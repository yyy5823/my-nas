import 'dart:ui';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/file_browser/presentation/providers/file_browser_provider.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/file_browser/presentation/widgets/file_item_widget.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/providers/download_provider.dart';
import 'package:my_nas/shared/widgets/download_manager_sheet.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connectedSources = ref.watch(connectedSourcesProvider);
    final selectedSourceId = ref.watch(selectedSourceIdProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          // 自定义 AppBar
          _buildAppBar(context, currentPath, isGridView, isDark),
          // 源选择器（只有多个已连接源时显示）
          if (connectedSources.length > 1) _buildSourceSelector(connectedSources, selectedSourceId, isDark),
          // 面包屑导航
          _buildBreadcrumb(currentPath, isDark),
          // 文件列表
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(fileListProvider.notifier).refresh(),
              color: AppColors.primary,
              backgroundColor: isDark ? AppColors.darkSurface : null,
              child: _buildContent(fileState, isGridView, isDark),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFab(isDark),
    );
  }

  Widget _buildAppBar(BuildContext context, String currentPath, bool isGridView, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withOpacity(0.2)
                : context.colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // 返回按钮
              if (currentPath != '/')
                _buildIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => ref.read(fileListProvider.notifier).navigateUp(),
                  isDark: isDark,
                  tooltip: '返回上级',
                )
              else
                const SizedBox(width: 40),
              const SizedBox(width: 8),
              // 标题
              Expanded(
                child: Text(
                  '文件',
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : null,
                  ),
                ),
              ),
              // 操作按钮
              _buildIconButton(
                icon: isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                onTap: () {
                  ref.read(viewModeProvider.notifier).state =
                      isGridView ? ViewMode.list : ViewMode.grid;
                },
                isDark: isDark,
                tooltip: isGridView ? '列表视图' : '网格视图',
              ),
              _buildIconButton(
                icon: Icons.sort_rounded,
                onTap: () => _showSortOptions(context, isDark),
                isDark: isDark,
                tooltip: '排序',
              ),
              _buildIconButton(
                icon: Icons.download_rounded,
                onTap: () => showDownloadManager(context),
                isDark: isDark,
                tooltip: '下载管理',
              ),
              _buildIconButton(
                icon: Icons.more_vert_rounded,
                onTap: () => _showMoreOptions(context, isDark),
                isDark: isDark,
                tooltip: '更多',
              ),
            ],
          ),
        ),
      ),
    );
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

  Widget _buildSourceSelector(
    List<(SourceEntity, SourceConnection)> connectedSources,
    String? selectedSourceId,
    bool isDark,
  ) {
    // 查找当前选中的源
    final selectedSource = connectedSources.firstWhere(
      (item) => item.$1.id == selectedSourceId,
      orElse: () => connectedSources.first,
    );

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withOpacity(0.3)
            : AppColors.lightSurfaceVariant.withOpacity(0.6),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withOpacity(0.1)
                : AppColors.lightOutline.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getSourceIcon(selectedSource.$1.type),
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PopupMenuButton<String>(
              initialValue: selectedSourceId,
              onSelected: (sourceId) {
                ref.read(selectedSourceIdProvider.notifier).state = sourceId;
                ref.read(currentPathProvider.notifier).state = '/';
                ref.read(fileListProvider.notifier).loadDirectory('/');
              },
              offset: const Offset(0, 44),
              itemBuilder: (context) => connectedSources.map((item) {
                final (source, _) = item;
                return PopupMenuItem<String>(
                  value: source.id,
                  child: Row(
                    children: [
                      Icon(
                        _getSourceIcon(source.type),
                        size: 18,
                        color: source.id == selectedSourceId
                            ? AppColors.primary
                            : (isDark ? AppColors.darkOnSurfaceVariant : null),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              source.name,
                              style: TextStyle(
                                fontWeight: source.id == selectedSourceId
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: source.id == selectedSourceId
                                    ? AppColors.primary
                                    : null,
                              ),
                            ),
                            Text(
                              source.host,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : AppColors.lightOnSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (source.id == selectedSourceId)
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                    ],
                  ),
                );
              }).toList(),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          selectedSource.$1.name,
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          selectedSource.$1.host,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.unfold_more_rounded,
                    size: 20,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getSourceIcon(SourceType type) => switch (type) {
        SourceType.synology => Icons.storage_rounded,
        SourceType.qnap => Icons.storage_rounded,
        SourceType.webdav => Icons.cloud_rounded,
        SourceType.smb => Icons.lan_rounded,
        _ => Icons.dns_rounded,
      };

  Widget _buildBreadcrumb(String currentPath, bool isDark) {
    final parts = currentPath.split('/').where((p) => p.isNotEmpty).toList();

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withOpacity(0.2)
            : AppColors.lightSurfaceVariant.withOpacity(0.5),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          _buildBreadcrumbItem(
            context: context,
            label: '根目录',
            icon: Icons.home_rounded,
            isFirst: true,
            isDark: isDark,
            onTap: () => ref.read(fileListProvider.notifier).loadDirectory('/'),
          ),
          for (var i = 0; i < parts.length; i++)
            _buildBreadcrumbItem(
              context: context,
              label: parts[i],
              isDark: isDark,
              onTap: () {
                final newPath = '/${parts.sublist(0, i + 1).join('/')}';
                ref.read(fileListProvider.notifier).loadDirectory(newPath);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbItem({
    required BuildContext context,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
    IconData? icon,
    bool isFirst = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isFirst)
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(FileListState state, bool isGridView, bool isDark) => switch (state) {
        FileListLoading() => const LoadingWidget(message: '加载中...'),
        FileListNotConnected() => _buildNotConnectedPrompt(isDark),
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
          isGridView ? _buildGrid(files, isDark) : _buildList(files, isDark),
      };

  Widget _buildNotConnectedPrompt(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '未连接到 NAS',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请先在设置中配置并连接到 NAS 服务器',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          '添加连接',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<FileItem> files, bool isDark) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: files.length,
        itemBuilder: (context, index) => FileItemWidget(
          file: files[index],
          onTap: () => _handleFileTap(files[index]),
          onLongPress: () => _showFileOptions(context, files[index], isDark),
        ),
      );

  Widget _buildGrid(List<FileItem> files, bool isDark) => GridView.builder(
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
          onLongPress: () => _showFileOptions(context, files[index], isDark),
        ),
      );

  Widget _buildFab(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: AppColors.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showCreateOptions(context, isDark),
          borderRadius: BorderRadius.circular(18),
          child: const SizedBox(
            width: 60,
            height: 60,
            child: Icon(
              Icons.add_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }

  void _handleFileTap(FileItem file) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (file.isDirectory) {
      ref.read(fileListProvider.notifier).loadDirectory(file.path);
    } else {
      _showFileOptions(context, file, isDark);
    }
  }

  void _showSortOptions(BuildContext context, bool isDark) {
    final sortMode = ref.read(sortModeProvider);
    final ascending = ref.read(sortAscendingProvider);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildBottomSheet(
        context,
        isDark,
        title: '排序方式',
        children: [
          for (final mode in SortMode.values)
            _buildOptionTile(
              context,
              isDark,
              icon: _getSortModeIcon(mode),
              title: _getSortModeName(mode),
              isSelected: sortMode == mode,
              onTap: () {
                ref.read(sortModeProvider.notifier).state = mode;
                ref.read(fileListProvider.notifier).refresh();
                Navigator.pop(context);
              },
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Divider(
              color: isDark
                  ? AppColors.darkOutline.withOpacity(0.2)
                  : AppColors.lightOutline.withOpacity(0.3),
            ),
          ),
          _buildSwitchTile(
            context,
            isDark,
            title: '升序排列',
            value: ascending,
            onChanged: (v) {
              ref.read(sortAscendingProvider.notifier).state = v;
              ref.read(fileListProvider.notifier).refresh();
            },
          ),
        ],
      ),
    );
  }

  IconData _getSortModeIcon(SortMode mode) => switch (mode) {
        SortMode.name => Icons.sort_by_alpha_rounded,
        SortMode.size => Icons.straighten_rounded,
        SortMode.date => Icons.schedule_rounded,
        SortMode.type => Icons.category_rounded,
      };

  String _getSortModeName(SortMode mode) => switch (mode) {
        SortMode.name => '名称',
        SortMode.size => '大小',
        SortMode.date => '修改日期',
        SortMode.type => '类型',
      };

  void _showMoreOptions(BuildContext context, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildBottomSheet(
        context,
        isDark,
        title: '更多选项',
        children: [
          _buildActionTile(
            context,
            isDark,
            icon: Icons.refresh_rounded,
            iconColor: AppColors.info,
            title: '刷新',
            onTap: () {
              Navigator.pop(context);
              ref.read(fileListProvider.notifier).refresh();
            },
          ),
          _buildActionTile(
            context,
            isDark,
            icon: Icons.select_all_rounded,
            iconColor: AppColors.secondary,
            title: '多选',
            onTap: () {
              Navigator.pop(context);
              // TODO: 实现多选模式
            },
          ),
        ],
      ),
    );
  }

  void _showCreateOptions(BuildContext context, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildBottomSheet(
        context,
        isDark,
        title: '新建',
        children: [
          _buildActionTile(
            context,
            isDark,
            icon: Icons.create_new_folder_rounded,
            iconColor: AppColors.fileFolder,
            title: '新建文件夹',
            onTap: () {
              Navigator.pop(context);
              _showCreateFolderDialog(isDark);
            },
          ),
          _buildActionTile(
            context,
            isDark,
            icon: Icons.upload_file_rounded,
            iconColor: AppColors.primary,
            title: '上传文件',
            onTap: () {
              Navigator.pop(context);
              _pickAndUploadFiles();
            },
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog(bool isDark) {
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '新建文件夹',
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: isDark ? AppColors.darkOnSurface : null),
          decoration: InputDecoration(
            hintText: '文件夹名称',
            hintStyle: TextStyle(
              color: isDark ? AppColors.darkOnSurfaceVariant : null,
            ),
            filled: true,
            fillColor: isDark
                ? AppColors.darkSurfaceVariant.withOpacity(0.5)
                : AppColors.lightSurfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : null,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (controller.text.isNotEmpty) {
                    ref.read(fileListProvider.notifier).createFolder(controller.text);
                    Navigator.pop(context);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text(
                    '创建',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFileOptions(BuildContext context, FileItem file, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildBottomSheet(
        context,
        isDark,
        title: '',
        children: [
          // 文件信息头部
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Row(
              children: [
                _buildFileIcon(file, isDark),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkOnSurface : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!file.isDirectory)
                        Text(
                          file.displaySize,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Divider(
              color: isDark
                  ? AppColors.darkOutline.withOpacity(0.2)
                  : AppColors.lightOutline.withOpacity(0.3),
            ),
          ),
          if (!file.isDirectory) ...[
            _buildActionTile(
              context,
              isDark,
              icon: Icons.download_rounded,
              iconColor: AppColors.primary,
              title: '下载',
              onTap: () {
                Navigator.pop(context);
                _downloadFile(file);
              },
            ),
            _buildActionTile(
              context,
              isDark,
              icon: Icons.share_rounded,
              iconColor: AppColors.accent,
              title: '分享',
              onTap: () {
                Navigator.pop(context);
                // TODO: 实现分享
              },
            ),
          ],
          _buildActionTile(
            context,
            isDark,
            icon: Icons.content_copy_rounded,
            iconColor: AppColors.info,
            title: '复制到...',
            onTap: () {
              Navigator.pop(context);
              _showDestinationPicker(file, isDark, isCopy: true);
            },
          ),
          _buildActionTile(
            context,
            isDark,
            icon: Icons.drive_file_move_rounded,
            iconColor: AppColors.accent,
            title: '移动到...',
            onTap: () {
              Navigator.pop(context);
              _showDestinationPicker(file, isDark, isCopy: false);
            },
          ),
          _buildActionTile(
            context,
            isDark,
            icon: Icons.edit_rounded,
            iconColor: AppColors.secondary,
            title: '重命名',
            onTap: () {
              Navigator.pop(context);
              _showRenameDialog(file, isDark);
            },
          ),
          _buildActionTile(
            context,
            isDark,
            icon: Icons.delete_rounded,
            iconColor: AppColors.error,
            title: '删除',
            titleColor: AppColors.error,
            onTap: () {
              Navigator.pop(context);
              _showDeleteConfirm(file, isDark);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFileIcon(FileItem file, bool isDark) {
    final color = _getFileColor(file);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        _getFileIcon(file),
        color: color,
        size: 26,
      ),
    );
  }

  IconData _getFileIcon(FileItem file) => switch (file.type) {
        FileType.folder => Icons.folder_rounded,
        FileType.image => Icons.image_rounded,
        FileType.video => Icons.play_circle_rounded,
        FileType.audio => Icons.music_note_rounded,
        FileType.document => Icons.description_rounded,
        FileType.archive => Icons.folder_zip_rounded,
        FileType.code => Icons.code_rounded,
        FileType.text => Icons.article_rounded,
        FileType.pdf => Icons.picture_as_pdf_rounded,
        FileType.epub || FileType.comic => Icons.menu_book_rounded,
        FileType.other => Icons.insert_drive_file_rounded,
      };

  Color _getFileColor(FileItem file) => switch (file.type) {
        FileType.folder => AppColors.fileFolder,
        FileType.image => AppColors.fileImage,
        FileType.video => AppColors.fileVideo,
        FileType.audio => AppColors.fileAudio,
        FileType.document => AppColors.fileDocument,
        FileType.archive => AppColors.fileArchive,
        FileType.code => AppColors.fileCode,
        FileType.pdf => AppColors.error,
        FileType.epub || FileType.comic => AppColors.accent,
        FileType.text => AppColors.fileDocument,
        FileType.other => AppColors.fileOther,
      };

  void _showRenameDialog(FileItem file, bool isDark) {
    final controller = TextEditingController(text: file.name);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '重命名',
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: isDark ? AppColors.darkOnSurface : null),
          decoration: InputDecoration(
            hintText: '新名称',
            hintStyle: TextStyle(
              color: isDark ? AppColors.darkOnSurfaceVariant : null,
            ),
            filled: true,
            fillColor: isDark
                ? AppColors.darkSurfaceVariant.withOpacity(0.5)
                : AppColors.lightSurfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : null,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (controller.text.isNotEmpty && controller.text != file.name) {
                    ref.read(fileListProvider.notifier).rename(file.path, controller.text);
                    Navigator.pop(context);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text(
                    '确定',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(FileItem file, bool isDark) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '确认删除',
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          '确定要删除 "${file.name}" 吗？此操作无法撤销。',
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurfaceVariant : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : null,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.error, AppColors.errorDark],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  ref.read(fileListProvider.notifier).delete(file.path);
                  Navigator.pop(context);
                },
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text(
                    '删除',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadFile(FileItem file) async {
    final connection = ref.read(selectedSourceConnectionProvider);
    if (connection == null || !connection.adapter.isConnected) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    try {
      final url = await connection.adapter.fileSystem.getFileUrl(file.path);
      final service = ref.read(downloadServiceProvider);
      final task = await service.addTask(url: url, fileName: file.name);
      await service.startDownload(task.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('开始下载: ${file.name}'),
          backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
          action: SnackBarAction(
            label: '查看',
            textColor: AppColors.primary,
            onPressed: () => showDownloadManager(context),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('下载失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _pickAndUploadFiles() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    try {
      final result = await fp.FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: fp.FileType.any,
      );

      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        if (file.path == null) continue;

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在上传: ${file.name}'),
            backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
            duration: const Duration(seconds: 1),
          ),
        );

        await ref.read(fileListProvider.notifier).uploadFile(
              file.path!,
              fileName: file.name,
            );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('上传完成: ${result.files.length} 个文件'),
          backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('上传失败: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showDestinationPicker(FileItem file, bool isDark, {required bool isCopy}) {
    String selectedPath = '/';

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: isDark ? AppColors.darkSurface : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            isCopy ? '复制到' : '移动到',
            style: TextStyle(
              color: isDark ? AppColors.darkOnSurface : null,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: _DestinationBrowser(
              initialPath: selectedPath,
              isDark: isDark,
              onPathChanged: (path) => setState(() => selectedPath = path),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                '取消',
                style: TextStyle(
                  color: isDark ? AppColors.darkOnSurfaceVariant : null,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      if (isCopy) {
                        await ref.read(fileListProvider.notifier).copyTo(file.path, selectedPath);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已复制到 $selectedPath'),
                            backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
                          ),
                        );
                      } else {
                        await ref.read(fileListProvider.notifier).moveTo(file.path, selectedPath);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已移动到 $selectedPath'),
                            backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
                          ),
                        );
                      }
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('操作失败: $e'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Text(
                      isCopy ? '复制到此处' : '移动到此处',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSheet(
    BuildContext context,
    bool isDark, {
    required String title,
    required List<Widget> children,
  }) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurface.withOpacity(0.95)
                : AppColors.lightSurface.withOpacity(0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: isDark ? AppColors.glassStroke : AppColors.lightOutline.withOpacity(0.2),
              ),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant.withOpacity(0.3)
                        : AppColors.lightOnSurfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (title.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      title,
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                  ),
                ...children,
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.15)
                      : (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant)
                          .withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: context.textTheme.bodyLarge?.copyWith(
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryGradient,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    bool isDark, {
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant)
                  .withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              value ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              title,
              style: context.textTheme.bodyLarge?.copyWith(
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                title,
                style: context.textTheme.bodyLarge?.copyWith(
                  color: titleColor ??
                      (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 目录选择器组件
class _DestinationBrowser extends ConsumerStatefulWidget {
  const _DestinationBrowser({
    required this.initialPath,
    required this.isDark,
    required this.onPathChanged,
  });

  final String initialPath;
  final bool isDark;
  final ValueChanged<String> onPathChanged;

  @override
  ConsumerState<_DestinationBrowser> createState() => _DestinationBrowserState();
}

class _DestinationBrowserState extends ConsumerState<_DestinationBrowser> {
  late String _currentPath;
  List<FileItem>? _directories;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadDirectories();
  }

  Future<void> _loadDirectories() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final connection = ref.read(selectedSourceConnectionProvider);
      if (connection == null || !connection.adapter.isConnected) {
        setState(() {
          _error = '未连接';
          _isLoading = false;
        });
        return;
      }

      final files = await connection.adapter.fileSystem.listDirectory(_currentPath);
      final dirs = files.where((FileItem f) => f.isDirectory).toList();

      setState(() {
        _directories = dirs;
        _isLoading = false;
      });

      widget.onPathChanged(_currentPath);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _navigateTo(String path) {
    _currentPath = path;
    _loadDirectories();
  }

  void _navigateUp() {
    if (_currentPath == '/' || _currentPath.isEmpty) return;
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return;
    parts.removeLast();
    _navigateTo(parts.isEmpty ? '/' : '/${parts.join('/')}');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 当前路径和返回按钮
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.isDark
                ? AppColors.darkSurfaceVariant.withOpacity(0.5)
                : AppColors.lightSurfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (_currentPath != '/')
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  onPressed: _navigateUp,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  color: widget.isDark ? AppColors.darkOnSurface : null,
                ),
              Expanded(
                child: Text(
                  _currentPath == '/' ? '根目录' : _currentPath,
                  style: TextStyle(
                    color: widget.isDark ? AppColors.darkOnSurface : null,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 目录列表
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: widget.isDark ? AppColors.darkOnSurfaceVariant : null,
                        ),
                      ),
                    )
                  : _directories == null || _directories!.isEmpty
                      ? Center(
                          child: Text(
                            '没有子文件夹',
                            style: TextStyle(
                              color: widget.isDark ? AppColors.darkOnSurfaceVariant : null,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _directories!.length,
                          itemBuilder: (context, index) {
                            final dir = _directories![index];
                            return ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.fileFolder.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.folder_rounded,
                                  color: AppColors.fileFolder,
                                  size: 22,
                                ),
                              ),
                              title: Text(
                                dir.name,
                                style: TextStyle(
                                  color: widget.isDark ? AppColors.darkOnSurface : null,
                                ),
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: widget.isDark ? AppColors.darkOnSurfaceVariant : null,
                              ),
                              onTap: () => _navigateTo(dir.path),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
