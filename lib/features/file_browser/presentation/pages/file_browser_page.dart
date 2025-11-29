import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/connection/presentation/providers/connection_provider.dart';
import 'package:my_nas/features/file_browser/presentation/providers/file_browser_provider.dart';
import 'package:my_nas/features/file_browser/presentation/widgets/file_item_widget.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/providers/download_provider.dart';
import 'package:my_nas/shared/services/download_service.dart';
import 'package:my_nas/shared/widgets/download_manager_sheet.dart';
import 'package:my_nas/shared/widgets/empty_widget.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';

class FileBrowserPage extends ConsumerStatefulWidget {
  const FileBrowserPage({super.key});

  @override
  ConsumerState<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends ConsumerState<FileBrowserPage> {
  @override
  void initState() {
    super.initState();
    // 初次加载根目录
    Future.microtask(
      () => ref.read(fileListProvider.notifier).loadDirectory('/'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileState = ref.watch(fileListProvider);
    final currentPath = ref.watch(currentPathProvider);
    final viewMode = ref.watch(viewModeProvider);
    final isGridView = viewMode == ViewMode.grid;

    return Scaffold(
      appBar: AppBar(
        leading: currentPath != '/'
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    ref.read(fileListProvider.notifier).navigateUp(),
                tooltip: '返回上级',
              )
            : null,
        title: const Text('文件'),
        actions: [
          IconButton(
            icon: Icon(isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              ref.read(viewModeProvider.notifier).state =
                  isGridView ? ViewMode.list : ViewMode.grid;
            },
            tooltip: isGridView ? '列表视图' : '网格视图',
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => _showSortOptions(context),
            tooltip: '排序',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => showDownloadManager(context),
            tooltip: '下载管理',
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showMoreOptions(context),
            tooltip: '更多',
          ),
        ],
      ),
      body: Column(
        children: [
          // Breadcrumb
          _buildBreadcrumb(currentPath),
          const Divider(height: 1),

          // File list
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(fileListProvider.notifier).refresh(),
              child: _buildContent(fileState, isGridView),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateOptions(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBreadcrumb(String currentPath) {
    final parts = currentPath.split('/').where((p) => p.isNotEmpty).toList();

    return Container(
      height: 48,
      padding: AppSpacing.paddingHorizontalLg,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _BreadcrumbItem(
            label: '根目录',
            isFirst: true,
            onTap: () => ref.read(fileListProvider.notifier).loadDirectory('/'),
          ),
          for (var i = 0; i < parts.length; i++)
            _BreadcrumbItem(
              label: parts[i],
              onTap: () {
                final newPath = '/${parts.sublist(0, i + 1).join('/')}';
                ref.read(fileListProvider.notifier).loadDirectory(newPath);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildContent(FileListState state, bool isGridView) => switch (state) {
        FileListLoading() => const LoadingWidget(message: '加载中...'),
        FileListError(:final message) => AppErrorWidget(
            message: message,
            onRetry: () => ref.read(fileListProvider.notifier).refresh(),
          ),
        FileListLoaded(:final files) when files.isEmpty => const EmptyWidget(
            icon: Icons.folder_open_outlined,
            title: '文件夹为空',
            message: '此文件夹中没有文件或子文件夹',
          ),
        FileListLoaded(:final files) =>
          isGridView ? _buildGrid(files) : _buildList(files),
      };

  Widget _buildList(List<FileItem> files) => ListView.builder(
        padding: AppSpacing.paddingVerticalSm,
        itemCount: files.length,
        itemBuilder: (context, index) => FileItemWidget(
          file: files[index],
          onTap: () => _handleFileTap(files[index]),
          onLongPress: () => _showFileOptions(context, files[index]),
        ),
      );

  Widget _buildGrid(List<FileItem> files) => GridView.builder(
        padding: AppSpacing.paddingMd,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: context.isDesktop ? 160 : 120,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 0.85,
        ),
        itemCount: files.length,
        itemBuilder: (context, index) => FileItemWidget(
          file: files[index],
          isGridView: true,
          onTap: () => _handleFileTap(files[index]),
          onLongPress: () => _showFileOptions(context, files[index]),
        ),
      );

  void _handleFileTap(FileItem file) {
    if (file.isDirectory) {
      ref.read(fileListProvider.notifier).loadDirectory(file.path);
    } else {
      // TODO: 打开文件预览或播放
      _showFileOptions(context, file);
    }
  }

  void _showSortOptions(BuildContext context) {
    final sortMode = ref.read(sortModeProvider);
    final ascending = ref.read(sortAscendingProvider);

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '排序方式',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final mode in SortMode.values)
              ListTile(
                leading: Icon(
                  sortMode == mode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(_getSortModeName(mode)),
                onTap: () {
                  ref.read(sortModeProvider.notifier).state = mode;
                  ref.read(fileListProvider.notifier).refresh();
                  Navigator.pop(context);
                },
              ),
            const Divider(),
            SwitchListTile(
              title: const Text('升序排列'),
              value: ascending,
              onChanged: (v) {
                ref.read(sortAscendingProvider.notifier).state = v;
                ref.read(fileListProvider.notifier).refresh();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _getSortModeName(SortMode mode) => switch (mode) {
        SortMode.name => '名称',
        SortMode.size => '大小',
        SortMode.date => '修改日期',
        SortMode.type => '类型',
      };

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新'),
              onTap: () {
                Navigator.pop(context);
                ref.read(fileListProvider.notifier).refresh();
              },
            ),
            ListTile(
              leading: const Icon(Icons.select_all),
              title: const Text('多选'),
              onTap: () {
                Navigator.pop(context);
                // TODO: 实现多选模式
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('新建文件夹'),
              onTap: () {
                Navigator.pop(context);
                _showCreateFolderDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('上传文件'),
              onTap: () {
                Navigator.pop(context);
                // TODO: 实现文件上传
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showCreateFolderDialog() {
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '文件夹名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref
                    .read(fileListProvider.notifier)
                    .createFolder(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showFileOptions(BuildContext context, FileItem file) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    file.isDirectory ? Icons.folder : Icons.insert_drive_file,
                    size: 40,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          style: context.textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!file.isDirectory)
                          Text(
                            file.displaySize,
                            style: context.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            if (!file.isDirectory) ...[
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('下载'),
                onTap: () {
                  Navigator.pop(context);
                  _downloadFile(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('分享'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: 实现分享
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(file);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: context.colorScheme.error),
              title: Text('删除', style: TextStyle(color: context.colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirm(file);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(FileItem file) {
    final controller = TextEditingController(text: file.name);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '新名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty &&
                  controller.text != file.name) {
                ref
                    .read(fileListProvider.notifier)
                    .rename(file.path, controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(FileItem file) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${file.name}" 吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(fileListProvider.notifier).delete(file.path);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: context.colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadFile(FileItem file) async {
    final adapter = ref.read(activeAdapterProvider);
    if (adapter == null) return;

    try {
      // 获取文件下载 URL
      final url = await adapter.fileSystem.getFileUrl(file.path);

      // 创建下载任务
      final service = ref.read(downloadServiceProvider);
      final task = await service.addTask(url: url, fileName: file.name);

      // 开始下载
      await service.startDownload(task.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('开始下载: ${file.name}'),
          action: SnackBarAction(
            label: '查看',
            onPressed: () => showDownloadManager(context),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('下载失败: $e'),
          backgroundColor: context.colorScheme.error,
        ),
      );
    }
  }
}

class _BreadcrumbItem extends StatelessWidget {
  const _BreadcrumbItem({
    required this.label,
    required this.onTap,
    this.isFirst = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isFirst;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isFirst)
            Icon(
              Icons.chevron_right,
              size: 20,
              color: context.colorScheme.onSurfaceVariant,
            ),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(label),
          ),
        ],
      );
}
