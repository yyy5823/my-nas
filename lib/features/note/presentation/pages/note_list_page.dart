import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/network/http_client.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/note/data/services/markdown_parser.dart';
import 'package:my_nas/features/note/domain/entities/note_item.dart';
import 'package:my_nas/features/note/presentation/widgets/note_tree_widget.dart';
import 'package:my_nas/features/note/presentation/widgets/task_list_widget.dart';
import 'package:my_nas/features/reading/presentation/pages/reading_page.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/empty_widget.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/media_setup_widget.dart';

/// 笔记页面状态
final notePageProvider =
    StateNotifierProvider<NotePageNotifier, NotePageState>(
        (ref) => NotePageNotifier(ref));

sealed class NotePageState {}

class NotePageLoading extends NotePageState {
  NotePageLoading({this.message});
  final String? message;
}

class NotePageNotConnected extends NotePageState {}

class NotePageLoaded extends NotePageState {
  NotePageLoaded({
    required this.treeNodes,
    this.selectedNode,
    this.content,
    this.tasks = const [],
    this.isEditing = false,
    this.hasChanges = false,
    this.isLoadingContent = false,
    this.livePreview = true,
  });

  final List<NoteTreeNode> treeNodes;
  final NoteTreeNode? selectedNode;
  final String? content;
  final List<TaskItem> tasks;
  final bool isEditing;
  final bool hasChanges;
  final bool isLoadingContent;
  final bool livePreview; // 实时预览模式

  /// 当前选中的文件是否是任务文件
  bool get isTaskFile => selectedNode?.isTaskFile ?? false;

  NotePageLoaded copyWith({
    List<NoteTreeNode>? treeNodes,
    NoteTreeNode? selectedNode,
    String? content,
    List<TaskItem>? tasks,
    bool? isEditing,
    bool? hasChanges,
    bool? isLoadingContent,
    bool? livePreview,
    bool clearSelection = false,
  }) {
    return NotePageLoaded(
      treeNodes: treeNodes ?? this.treeNodes,
      selectedNode: clearSelection ? null : (selectedNode ?? this.selectedNode),
      content: clearSelection ? null : (content ?? this.content),
      tasks: tasks ?? this.tasks,
      isEditing: isEditing ?? this.isEditing,
      hasChanges: hasChanges ?? this.hasChanges,
      isLoadingContent: isLoadingContent ?? this.isLoadingContent,
      livePreview: livePreview ?? this.livePreview,
    );
  }
}

class NotePageError extends NotePageState {
  NotePageError(this.message);
  final String message;
}

class NotePageNotifier extends StateNotifier<NotePageState> {
  NotePageNotifier(this._ref) : super(NotePageLoading()) {
    loadTree();

    // 监听连接状态变化，自动刷新
    _ref.listen<Map<String, SourceConnection>>(activeConnectionsProvider,
        (previous, next) {
      final prevConnected = previous?.values
              .where((c) => c.status == SourceStatus.connected)
              .length ??
          0;
      final nextConnected =
          next.values.where((c) => c.status == SourceStatus.connected).length;

      if (nextConnected > prevConnected && state is NotePageNotConnected) {
        loadTree();
      }
    });
  }

  final Ref _ref;

  /// 加载目录树
  Future<void> loadTree() async {
    state = NotePageLoading(message: '加载目录结构...');

    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    // 等待配置加载完成
    MediaLibraryConfig? config = configAsync.valueOrNull;
    if (config == null) {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final updated = _ref.read(mediaLibraryConfigProvider);
        config = updated.valueOrNull;
        if (config != null) break;

        if (updated.hasError) {
          state = NotePageError('加载媒体库配置失败');
          return;
        }
      }

      if (config == null) {
        state = NotePageLoaded(treeNodes: []);
        return;
      }
    }

    // 获取已启用的笔记路径
    final notePaths = config.getEnabledPathsForType(MediaType.note);

    if (notePaths.isEmpty) {
      state = NotePageLoaded(treeNodes: []);
      return;
    }

    // 过滤出已连接的路径
    final connectedPaths = notePaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      state = NotePageNotConnected();
      return;
    }

    try {
      final rootNodes = <NoteTreeNode>[];

      for (final mediaPath in connectedPaths) {
        final connection = connections[mediaPath.sourceId];
        if (connection == null) continue;

        // 创建根节点
        final rootNode = NoteTreeNode(
          name: mediaPath.displayName,
          path: mediaPath.path,
          type: NoteTreeNodeType.folder,
          sourceId: mediaPath.sourceId,
          isExpanded: true,
        );

        // 加载一级子目录
        final children = await _loadFolderChildren(
          connection.adapter.fileSystem,
          mediaPath.path,
          mediaPath.sourceId,
        );

        rootNodes.add(rootNode.copyWith(children: children));
      }

      state = NotePageLoaded(treeNodes: rootNodes);
    } on Exception catch (e) {
      state = NotePageError(e.toString());
    }
  }

  /// 加载文件夹子节点
  Future<List<NoteTreeNode>> _loadFolderChildren(
    NasFileSystem fs,
    String path,
    String sourceId,
  ) async {
    try {
      final items = await fs.listDirectory(path);
      final nodes = <NoteTreeNode>[];

      // 先排序：文件夹在前，文件在后，各自按名称排序
      final folders = items.where((i) => i.isDirectory).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      final files = items.where((i) => !i.isDirectory && _isNoteFile(i.name)).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      for (final item in folders) {
        // 跳过隐藏文件夹
        if (item.name.startsWith('.') ||
            item.name.startsWith('@') ||
            item.name == '#recycle') {
          continue;
        }

        nodes.add(NoteTreeNode(
          name: item.name,
          path: item.path,
          type: NoteTreeNodeType.folder,
          sourceId: sourceId,
        ));
      }

      for (final item in files) {
        // 跳过隐藏文件
        if (item.name.startsWith('.')) continue;

        // 不在此处获取URL，等用户点击时再获取
        nodes.add(NoteTreeNode(
          name: item.name,
          path: item.path,
          type: NoteTreeNodeType.file,
          sourceId: sourceId,
          fileItem: item,
        ));
      }

      return nodes;
    } on Exception catch (e) {
      logger.w('加载文件夹失败: $path - $e');
      return [];
    }
  }

  bool _isNoteFile(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.md') ||
        lower.endsWith('.markdown') ||
        lower.endsWith('.txt');
  }

  /// 切换文件夹展开状态
  Future<void> toggleFolder(NoteTreeNode node) async {
    final current = state;
    if (current is! NotePageLoaded) return;

    // 递归更新节点的展开状态
    List<NoteTreeNode> updateNode(List<NoteTreeNode> nodes, String targetPath, bool expanded, List<NoteTreeNode>? newChildren) {
      return nodes.map((n) {
        if (n.path == targetPath) {
          return n.copyWith(
            isExpanded: expanded,
            children: newChildren ?? n.children,
          );
        }
        if (n.children.isNotEmpty) {
          return n.copyWith(
            children: updateNode(n.children, targetPath, expanded, newChildren),
          );
        }
        return n;
      }).toList();
    }

    if (!node.isExpanded && node.children.isEmpty) {
      // 需要加载子节点
      final connection = _ref.read(activeConnectionsProvider)[node.sourceId];
      if (connection == null) return;

      final children = await _loadFolderChildren(
        connection.adapter.fileSystem,
        node.path,
        node.sourceId,
      );

      final newTree = updateNode(current.treeNodes, node.path, true, children);
      state = current.copyWith(treeNodes: newTree);
    } else {
      // 只切换展开状态
      final newTree = updateNode(current.treeNodes, node.path, !node.isExpanded, null);
      state = current.copyWith(treeNodes: newTree);
    }
  }

  /// 选中文件并加载内容
  Future<void> selectFile(NoteTreeNode node) async {
    final current = state;
    if (current is! NotePageLoaded) return;
    if (node.type != NoteTreeNodeType.file) return;

    // 先更新选中状态，显示加载中
    state = current.copyWith(
      selectedNode: node,
      content: null,
      tasks: [],
      isLoadingContent: true,
      hasChanges: false,
      isEditing: false,
    );

    // 加载文件内容
    try {
      // 获取文件URL（懒加载）
      String? url = node.url;
      if (url == null) {
        // URL未缓存，需要获取
        final connections = _ref.read(activeConnectionsProvider);
        final connection = connections[node.sourceId];
        if (connection == null || connection.status != SourceStatus.connected) {
          throw Exception('连接已断开');
        }
        url = await connection.adapter.fileSystem.getFileUrl(node.path);
      }

      String content;
      final uri = Uri.parse(url);

      // 检查是否为本地文件 (file:// 协议)
      if (uri.scheme == 'file') {
        // 本地文件直接读取
        final file = File(uri.toFilePath());
        if (!await file.exists()) {
          throw Exception('文件不存在');
        }
        final bytes = await file.readAsBytes();
        try {
          content = utf8.decode(bytes);
        } on FormatException {
          content = String.fromCharCodes(bytes);
        }
      } else {
        // 远程文件通过 HTTP 获取
        final response = await InsecureHttpClient.get(uri);
        if (response.statusCode != 200) {
          throw Exception('加载失败: ${response.statusCode}');
        }
        try {
          content = utf8.decode(response.bodyBytes);
        } on FormatException {
          content = String.fromCharCodes(response.bodyBytes);
        }
      }

      // 只有任务文件才解析任务
      final tasks = node.isTaskFile ? MarkdownParser.parseTasks(content) : <TaskItem>[];

      state = (state as NotePageLoaded).copyWith(
        content: content,
        tasks: tasks,
        isLoadingContent: false,
      );
    } on Exception catch (e) {
      state = (state as NotePageLoaded).copyWith(
        content: '加载失败: $e',
        isLoadingContent: false,
      );
    }
  }

  /// 进入编辑模式
  void setEditing(bool editing) {
    final current = state;
    if (current is NotePageLoaded) {
      state = current.copyWith(isEditing: editing);
    }
  }

  /// 切换实时预览模式
  void toggleLivePreview() {
    final current = state;
    if (current is NotePageLoaded) {
      state = current.copyWith(livePreview: !current.livePreview);
    }
  }

  /// 更新内容
  void updateContent(String content) {
    final current = state;
    if (current is NotePageLoaded) {
      final tasks = current.isTaskFile
          ? MarkdownParser.parseTasks(content)
          : <TaskItem>[];
      state = current.copyWith(
        content: content,
        tasks: tasks,
        hasChanges: true,
      );
    }
  }

  /// 切换任务状态
  void toggleTask(int index) {
    final current = state;
    if (current is! NotePageLoaded) return;
    if (index >= current.tasks.length) return;

    final task = current.tasks[index];
    final newStatus =
        task.isCompleted ? TaskStatus.pending : TaskStatus.completed;
    final newTasks = [...current.tasks];
    newTasks[index] = task.copyWith(status: newStatus);

    // 更新 Markdown 内容中对应的任务状态
    final newContent =
        _updateTaskInContent(current.content ?? '', index, newStatus);

    state = current.copyWith(
      tasks: newTasks,
      content: newContent,
      hasChanges: true,
    );
  }

  String _updateTaskInContent(
      String content, int taskIndex, TaskStatus newStatus) {
    final lines = content.split('\n');
    var currentTaskIndex = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (RegExp(r'^[-*+]\s*\[([ xX/\-])\]').hasMatch(line.trim())) {
        if (currentTaskIndex == taskIndex) {
          final statusChar = switch (newStatus) {
            TaskStatus.completed => 'x',
            TaskStatus.inProgress => '/',
            TaskStatus.cancelled => '-',
            TaskStatus.pending => ' ',
          };
          lines[i] = line.replaceFirstMapped(
            RegExp(r'\[([ xX/\-])\]'),
            (m) => '[$statusChar]',
          );
          break;
        }
        currentTaskIndex++;
      }
    }

    return lines.join('\n');
  }
}

class NoteListPage extends ConsumerStatefulWidget {
  const NoteListPage({super.key});

  @override
  ConsumerState<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends ConsumerState<NoteListPage> {
  final TextEditingController _editController = TextEditingController();
  final ScrollController _previewScrollController = ScrollController();

  // 侧边栏宽度
  double _sidebarWidth = 280;
  static const double _minSidebarWidth = 200;
  static const double _maxSidebarWidth = 400;

  // 侧边栏是否收起
  bool _isSidebarCollapsed = false;

  @override
  void dispose() {
    _editController.dispose();
    _previewScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notePageProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          // 统一的顶部头部
          _buildAppBar(context, ref, isDark, state),
          // 主内容区
          Expanded(
            child: switch (state) {
              NotePageLoading(:final message) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      if (message != null) ...[
                        const SizedBox(height: 16),
                        Text(message),
                      ],
                    ],
                  ),
                ),
              NotePageNotConnected() => const MediaSetupWidget(
                  mediaType: MediaType.note,
                  icon: Icons.note_outlined,
                ),
              NotePageError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(notePageProvider.notifier).loadTree(),
                ),
              NotePageLoaded(:final treeNodes) when treeNodes.isEmpty =>
                _buildEmptyState(context, ref, isDark),
              NotePageLoaded() => _buildMainLayout(context, state, isDark),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.note_alt_rounded,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '笔记库为空',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请在媒体库设置中配置笔记目录并扫描',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const MediaLibraryPage()),
              ),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('媒体库设置'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
              ),
              icon: const Icon(Icons.cloud_rounded),
              label: const Text('连接管理'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    NotePageState state,
  ) {
    // 统计笔记数量
    int noteCount = 0;
    if (state is NotePageLoaded) {
      noteCount = _countNotes(state.treeNodes);
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text(
                '笔记',
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : null,
                ),
              ),
              if (noteCount > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$noteCount',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Spacer(),
              _buildIconButton(
                icon: Icons.refresh_rounded,
                onTap: () => ref.read(notePageProvider.notifier).loadTree(),
                isDark: isDark,
                tooltip: '刷新',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 递归统计笔记文件数量
  int _countNotes(List<NoteTreeNode> nodes) {
    int count = 0;
    for (final node in nodes) {
      if (node.type == NoteTreeNodeType.file) {
        count++;
      }
      if (node.children.isNotEmpty) {
        count += _countNotes(node.children);
      }
    }
    return count;
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: isDark ? AppColors.darkOnSurfaceVariant : null,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainLayout(
      BuildContext context, NotePageLoaded state, bool isDark) {
    return Row(
      children: [
        // 左侧目录树（可收起）
        if (!_isSidebarCollapsed) ...[
          _buildSidebar(context, state, isDark),
          // 可拖动分隔线
          _buildResizeHandle(isDark),
        ],
        // 展开按钮（当侧边栏收起时显示）
        if (_isSidebarCollapsed)
          _buildExpandButton(isDark),
        // 右侧内容区
        Expanded(
          child: _buildContentArea(context, state, isDark),
        ),
      ],
    );
  }

  Widget _buildSidebar(
      BuildContext context, NotePageLoaded state, bool isDark) {
    return Container(
      width: _sidebarWidth,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        children: [
          // 标题栏
          _buildSidebarHeader(context, isDark),
          // 目录树
          Expanded(
            child: NoteTreeWidget(
              nodes: state.treeNodes,
              selectedPath: state.selectedNode?.path,
              onNodeSelected: (node) =>
                  ref.read(notePageProvider.notifier).selectFile(node),
              onFolderToggle: (node) =>
                  ref.read(notePageProvider.notifier).toggleFolder(node),
              onFolderLoad: (node) =>
                  ref.read(notePageProvider.notifier).toggleFolder(node),
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(
              Icons.folder_rounded,
              size: 20,
              color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              '笔记',
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : null,
              ),
            ),
            const Spacer(),
            // 收起按钮
            IconButton(
              onPressed: () => setState(() => _isSidebarCollapsed = true),
              icon: Icon(
                Icons.chevron_left_rounded,
                size: 20,
                color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey,
              ),
              tooltip: '收起侧边栏',
            ),
            IconButton(
              onPressed: () => ref.read(notePageProvider.notifier).loadTree(),
              icon: Icon(
                Icons.refresh_rounded,
                size: 20,
                color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey,
              ),
              tooltip: '刷新',
              splashRadius: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandButton(bool isDark) {
    return Container(
      width: 48,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.grey[100],
        border: Border(
          right: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          IconButton(
            onPressed: () => setState(() => _isSidebarCollapsed = false),
            icon: Icon(
              Icons.chevron_right_rounded,
              color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[700],
            ),
            tooltip: '展开侧边栏',
          ),
        ],
      ),
    );
  }

  Widget _buildResizeHandle(bool isDark) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _sidebarWidth += details.delta.dx;
          _sidebarWidth = _sidebarWidth.clamp(_minSidebarWidth, _maxSidebarWidth);
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 4,
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
        ),
      ),
    );
  }

  Widget _buildContentArea(
      BuildContext context, NotePageLoaded state, bool isDark) {
    if (state.selectedNode == null) {
      return _buildEmptyContent(context, isDark);
    }

    if (state.isLoadingContent) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return Column(
      children: [
        // 顶部工具栏
        _buildContentHeader(context, state, isDark),
        // 内容区
        Expanded(
          child: state.isEditing
              ? (state.livePreview
                  ? _buildSplitView(context, state, isDark)
                  : _buildEditorOnly(context, state, isDark))
              : _buildPreview(context, state, isDark),
        ),
      ],
    );
  }

  Widget _buildEmptyContent(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.article_outlined,
            size: 64,
            color: isDark
                ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                : Colors.grey.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '选择一个笔记开始阅读',
            style: context.textTheme.bodyLarge?.copyWith(
              color: isDark
                  ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.5)
                  : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentHeader(
      BuildContext context, NotePageLoaded state, bool isDark) {
    final node = state.selectedNode!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // 文件图标
            Icon(
              node.isTaskFile ? Icons.checklist_rounded : Icons.article_outlined,
              size: 20,
              color: node.isTaskFile ? Colors.orange : AppColors.primary,
            ),
            const SizedBox(width: 8),
            // 文件名
            Expanded(
              child: Text(
                node.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkOnSurface : null,
                ),
              ),
            ),
            // 任务文件标记
            if (node.isTaskFile && state.tasks.isNotEmpty) ...[
              _buildTaskProgress(state, isDark),
              const SizedBox(width: 12),
            ],
            // 编辑/预览切换
            _buildModeToggle(state, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskProgress(NotePageLoaded state, bool isDark) {
    final completed = state.tasks.where((t) => t.isCompleted).length;
    final total = state.tasks.length;
    final progress = total > 0 ? completed / total : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: completed == total
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              color: completed == total ? Colors.green : Colors.orange,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$completed / $total',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: completed == total ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle(NotePageLoaded state, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 模式切换按钮组
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModeButton(
                icon: Icons.visibility_rounded,
                label: '预览',
                isSelected: !state.isEditing,
                onTap: () =>
                    ref.read(notePageProvider.notifier).setEditing(false),
                isDark: isDark,
              ),
              _buildModeButton(
                icon: Icons.edit_rounded,
                label: '编辑',
                isSelected: state.isEditing,
                onTap: () =>
                    ref.read(notePageProvider.notifier).setEditing(true),
                isDark: isDark,
              ),
            ],
          ),
        ),
        // 实时预览切换（仅在编辑模式显示）
        if (state.isEditing) ...[
          const SizedBox(width: 8),
          _buildLivePreviewToggle(state, isDark),
        ],
      ],
    );
  }

  /// 实时预览切换按钮
  Widget _buildLivePreviewToggle(NotePageLoaded state, bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(notePageProvider.notifier).toggleLivePreview(),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: state.livePreview
                ? AppColors.primary.withValues(alpha: 0.15)
                : (isDark
                    ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                    : Colors.grey.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.vertical_split_rounded,
                size: 16,
                color: state.livePreview
                    ? AppColors.primary
                    : (isDark ? AppColors.darkOnSurfaceVariant : Colors.grey),
              ),
              const SizedBox(width: 4),
              Text(
                '分屏',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      state.livePreview ? FontWeight.w600 : FontWeight.normal,
                  color: state.livePreview
                      ? AppColors.primary
                      : (isDark ? AppColors.darkOnSurfaceVariant : Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkOnSurfaceVariant : Colors.grey),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkOnSurfaceVariant : Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context, NotePageLoaded state, bool isDark) {
    // 如果是任务文件，显示任务列表视图
    if (state.isTaskFile && state.tasks.isNotEmpty) {
      return _buildTaskFilePreview(context, state, isDark);
    }

    // 普通 Markdown 预览
    return SingleChildScrollView(
      controller: _previewScrollController,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: _MarkdownPreview(
        content: state.content ?? '',
        isDark: isDark,
      ),
    );
  }

  Widget _buildTaskFilePreview(
      BuildContext context, NotePageLoaded state, bool isDark) {
    return Column(
      children: [
        // 任务列表
        Expanded(
          child: TaskListWidget(
            tasks: state.tasks,
            onToggle: (index) =>
                ref.read(notePageProvider.notifier).toggleTask(index),
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  /// 分屏视图：左边编辑器，右边实时预览
  Widget _buildSplitView(
      BuildContext context, NotePageLoaded state, bool isDark) {
    // 初始化编辑器内容
    if (_editController.text != state.content && !state.hasChanges) {
      _editController.text = state.content ?? '';
    }

    return Column(
      children: [
        // 工具栏
        _buildEditorToolbar(context, isDark),
        // 分屏内容区
        Expanded(
          child: Row(
            children: [
              // 左侧：编辑区域
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: isDark
                            ? AppColors.darkOutline.withValues(alpha: 0.3)
                            : Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: TextField(
                    controller: _editController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: isDark ? AppColors.darkOnSurface : null,
                      height: 1.6,
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.all(AppSpacing.md),
                      border: InputBorder.none,
                      hintText: '开始编写 Markdown...',
                      hintStyle: TextStyle(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.5)
                            : null,
                      ),
                    ),
                    onChanged: (value) =>
                        ref.read(notePageProvider.notifier).updateContent(value),
                  ),
                ),
              ),
              // 右侧：实时预览
              Expanded(
                child: Container(
                  color: isDark
                      ? AppColors.darkBackground
                      : Colors.grey.withValues(alpha: 0.05),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 预览标题栏
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                              : Colors.grey.withValues(alpha: 0.1),
                          border: Border(
                            bottom: BorderSide(
                              color: isDark
                                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                                  : Colors.grey.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.preview_rounded,
                              size: 16,
                              color: isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '实时预览',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 预览内容
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: _MarkdownPreview(
                            content: _editController.text,
                            isDark: isDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 纯编辑视图（无预览）
  Widget _buildEditorOnly(
      BuildContext context, NotePageLoaded state, bool isDark) {
    // 初始化编辑器内容
    if (_editController.text != state.content && !state.hasChanges) {
      _editController.text = state.content ?? '';
    }

    return Column(
      children: [
        // 工具栏
        _buildEditorToolbar(context, isDark),
        // 编辑区域
        Expanded(
          child: TextField(
            controller: _editController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: isDark ? AppColors.darkOnSurface : null,
              height: 1.6,
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.all(AppSpacing.md),
              border: InputBorder.none,
              hintText: '开始编写...',
              hintStyle: TextStyle(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.5)
                    : null,
              ),
            ),
            onChanged: (value) =>
                ref.read(notePageProvider.notifier).updateContent(value),
          ),
        ),
      ],
    );
  }

  Widget _buildEditorToolbar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant
            : context.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : context.colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildToolButton(
            icon: Icons.format_bold_rounded,
            tooltip: '粗体',
            onTap: () => _insertMarkdown('**', '**'),
          ),
          _buildToolButton(
            icon: Icons.format_italic_rounded,
            tooltip: '斜体',
            onTap: () => _insertMarkdown('*', '*'),
          ),
          _buildToolButton(
            icon: Icons.strikethrough_s_rounded,
            tooltip: '删除线',
            onTap: () => _insertMarkdown('~~', '~~'),
          ),
          const VerticalDivider(width: 16),
          _buildToolButton(
            icon: Icons.title_rounded,
            tooltip: '标题',
            onTap: () => _insertMarkdown('## ', ''),
          ),
          _buildToolButton(
            icon: Icons.format_list_bulleted_rounded,
            tooltip: '列表',
            onTap: () => _insertMarkdown('- ', ''),
          ),
          _buildToolButton(
            icon: Icons.check_box_outlined,
            tooltip: '任务',
            onTap: () => _insertMarkdown('- [ ] ', ''),
          ),
          const VerticalDivider(width: 16),
          _buildToolButton(
            icon: Icons.code_rounded,
            tooltip: '代码',
            onTap: () => _insertMarkdown('`', '`'),
          ),
          _buildToolButton(
            icon: Icons.link_rounded,
            tooltip: '链接',
            onTap: () => _insertMarkdown('[', '](url)'),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      splashRadius: 20,
    );
  }

  void _insertMarkdown(String prefix, String suffix) {
    final text = _editController.text;
    final selection = _editController.selection;

    if (selection.isValid) {
      final selectedText = text.substring(selection.start, selection.end);
      final newText = '$prefix$selectedText$suffix';
      _editController.value = TextEditingValue(
        text: text.replaceRange(selection.start, selection.end, newText),
        selection: TextSelection.collapsed(
          offset: selection.start + prefix.length + selectedText.length,
        ),
      );
    } else {
      final offset = _editController.selection.baseOffset;
      _editController.value = TextEditingValue(
        text:
            text.substring(0, offset) + prefix + suffix + text.substring(offset),
        selection: TextSelection.collapsed(offset: offset + prefix.length),
      );
    }

    ref.read(notePageProvider.notifier).updateContent(_editController.text);
  }
}

/// 简单的 Markdown 预览组件
class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({
    required this.content,
    required this.isDark,
  });

  final String content;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      widgets.add(_buildLine(context, line));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildLine(BuildContext context, String line) {
    final trimmed = line.trim();

    // 空行
    if (trimmed.isEmpty) {
      return const SizedBox(height: 8);
    }

    // 标题
    if (trimmed.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 16),
        child: Text(
          trimmed.substring(2),
          style: context.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkOnSurface : null,
          ),
        ),
      );
    }
    if (trimmed.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 14),
        child: Text(
          trimmed.substring(3),
          style: context.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkOnSurface : null,
          ),
        ),
      );
    }
    if (trimmed.startsWith('### ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 12),
        child: Text(
          trimmed.substring(4),
          style: context.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkOnSurface : null,
          ),
        ),
      );
    }

    // 任务项
    final taskMatch =
        RegExp(r'^[-*+]\s*\[([ xX/\-])\]\s*(.+)$').firstMatch(trimmed);
    if (taskMatch != null) {
      final isCompleted = taskMatch.group(1)!.toLowerCase() == 'x';
      final taskContent = taskMatch.group(2)!;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isCompleted
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 20,
              color: isCompleted
                  ? Colors.green
                  : (isDark ? AppColors.darkOnSurfaceVariant : null),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                taskContent,
                style: context.textTheme.bodyMedium?.copyWith(
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                  color: isCompleted
                      ? (isDark ? AppColors.darkOnSurfaceVariant : Colors.grey)
                      : (isDark ? AppColors.darkOnSurface : null),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 列表项
    if (trimmed.startsWith('- ') ||
        trimmed.startsWith('* ') ||
        trimmed.startsWith('+ ')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '•  ',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurface : null,
                fontWeight: FontWeight.bold,
              ),
            ),
            Expanded(
              child: _buildRichText(context, trimmed.substring(2)),
            ),
          ],
        ),
      );
    }

    // 代码块
    if (trimmed.startsWith('```')) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          trimmed.substring(3),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: isDark ? AppColors.darkOnSurface : null,
          ),
        ),
      );
    }

    // 引用
    if (trimmed.startsWith('> ')) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: AppColors.primary,
              width: 4,
            ),
          ),
          color: isDark
              ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
              : Colors.grey.shade50,
        ),
        child: Text(
          trimmed.substring(2),
          style: context.textTheme.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: isDark ? AppColors.darkOnSurfaceVariant : null,
          ),
        ),
      );
    }

    // 普通段落
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _buildRichText(context, line),
    );
  }

  Widget _buildRichText(BuildContext context, String text) {
    return Text(
      _stripMarkdown(text),
      style: context.textTheme.bodyMedium?.copyWith(
        color: isDark ? AppColors.darkOnSurface : null,
        height: 1.6,
      ),
    );
  }

  String _stripMarkdown(String text) {
    return text
        .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'\*(.+?)\*'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'`(.+?)`'), (m) => m.group(1)!)
        .replaceAllMapped(RegExp(r'\[(.+?)\]\(.+?\)'), (m) => m.group(1)!);
  }
}

/// 笔记列表内容组件（供阅读页面复用）
class NoteListContent extends ConsumerStatefulWidget {
  const NoteListContent({super.key});

  @override
  ConsumerState<NoteListContent> createState() => _NoteListContentState();
}

class _NoteListContentState extends ConsumerState<NoteListContent> {
  final TextEditingController _editController = TextEditingController();
  final ScrollController _previewScrollController = ScrollController();

  double _sidebarWidth = 280;
  static const double _minSidebarWidth = 200;
  static const double _maxSidebarWidth = 400;

  // 侧边栏是否收起
  bool _isSidebarCollapsed = false;

  @override
  void dispose() {
    _editController.dispose();
    _previewScrollController.dispose();
    super.dispose();
  }

  /// 递归统计笔记文件数量
  int _countNotes(List<NoteTreeNode> nodes) {
    int count = 0;
    for (final node in nodes) {
      if (node.type == NoteTreeNodeType.file) {
        count++;
      }
      if (node.children.isNotEmpty) {
        count += _countNotes(node.children);
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notePageProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return switch (state) {
      NotePageLoading(:final message) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(message),
              ],
            ],
          ),
        ),
      NotePageNotConnected() => const MediaSetupWidget(
          mediaType: MediaType.note,
          icon: Icons.note_outlined,
        ),
      NotePageError(:final message) => AppErrorWidget(
          message: message,
          onRetry: () => ref.read(notePageProvider.notifier).loadTree(),
        ),
      NotePageLoaded(:final treeNodes) when treeNodes.isEmpty =>
        const EmptyWidget(
          icon: Icons.note_outlined,
          title: '暂无笔记',
          message: '在配置的目录中添加 Markdown 文件后将显示在这里',
        ),
      NotePageLoaded() => _buildMainLayout(context, state, isDark),
    };
  }

  Widget _buildMainLayout(
      BuildContext context, NotePageLoaded state, bool isDark) {
    return Row(
      children: [
        // 左侧目录树（可收起）
        if (!_isSidebarCollapsed) ...[
          _buildSidebar(context, state, isDark),
          // 可拖动分隔线
          _buildResizeHandle(isDark),
        ],
        // 展开按钮（当侧边栏收起时显示）
        if (_isSidebarCollapsed)
          _buildExpandButton(isDark),
        // 右侧内容区
        Expanded(
          child: _buildContentArea(context, state, isDark),
        ),
      ],
    );
  }

  Widget _buildSidebar(
      BuildContext context, NotePageLoaded state, bool isDark) {
    return Container(
      width: _sidebarWidth,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        children: [
          // 标题栏
          _buildSidebarHeader(context, isDark),
          // 目录树
          Expanded(
            child: NoteTreeWidget(
              nodes: state.treeNodes,
              selectedPath: state.selectedNode?.path,
              onNodeSelected: (node) =>
                  ref.read(notePageProvider.notifier).selectFile(node),
              onFolderToggle: (node) =>
                  ref.read(notePageProvider.notifier).toggleFolder(node),
              onFolderLoad: (node) =>
                  ref.read(notePageProvider.notifier).toggleFolder(node),
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_outlined,
            size: 20,
            color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Text(
            '笔记目录',
            style: context.textTheme.titleSmall?.copyWith(
              color: isDark ? AppColors.darkOnSurface : null,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // 收起按钮
          IconButton(
            onPressed: () => setState(() => _isSidebarCollapsed = true),
            icon: Icon(
              Icons.chevron_left_rounded,
              color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600],
            ),
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: '收起侧边栏',
          ),
        ],
      ),
    );
  }

  Widget _buildExpandButton(bool isDark) {
    return Container(
      width: 40,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          IconButton(
            onPressed: () => setState(() => _isSidebarCollapsed = false),
            icon: Icon(
              Icons.chevron_right_rounded,
              color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600],
            ),
            iconSize: 20,
            tooltip: '展开侧边栏',
          ),
        ],
      ),
    );
  }

  Widget _buildResizeHandle(bool isDark) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _sidebarWidth += details.delta.dx;
          _sidebarWidth = _sidebarWidth.clamp(_minSidebarWidth, _maxSidebarWidth);
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 4,
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
        ),
      ),
    );
  }

  Widget _buildContentArea(
      BuildContext context, NotePageLoaded state, bool isDark) {
    if (state.selectedNode == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.article_outlined,
              size: 64,
              color: isDark
                  ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '选择一个笔记开始阅读',
              style: context.textTheme.bodyLarge?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.5)
                    : Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    if (state.isLoadingContent) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    // 显示内容
    return SingleChildScrollView(
      controller: _previewScrollController,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: _SimpleMarkdownPreview(
        content: state.content ?? '',
        isDark: isDark,
      ),
    );
  }
}

/// 简易 Markdown 预览（供 NoteListContent 使用）
class _SimpleMarkdownPreview extends StatelessWidget {
  const _SimpleMarkdownPreview({
    required this.content,
    required this.isDark,
  });

  final String content;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      // 标题
      if (trimmed.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 16),
          child: Text(
            trimmed.substring(2),
            style: context.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : null,
            ),
          ),
        ));
      } else if (trimmed.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 14),
          child: Text(
            trimmed.substring(3),
            style: context.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : null,
            ),
          ),
        ));
      } else if (trimmed.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 12),
          child: Text(
            trimmed.substring(4),
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : null,
            ),
          ),
        ));
      } else {
        // 普通段落
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            line,
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurface : null,
              height: 1.6,
            ),
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}
