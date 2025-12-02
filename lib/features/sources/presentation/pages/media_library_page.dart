import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/book/data/services/book_library_cache_service.dart';
import 'package:my_nas/features/book/presentation/pages/book_list_page.dart';
import 'package:my_nas/features/comic/data/services/comic_library_cache_service.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/music/data/services/music_library_cache_service.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/photo/data/services/photo_library_cache_service.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/sources/presentation/widgets/folder_picker_sheet.dart';
import 'package:my_nas/features/video/data/services/video_library_cache_service.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart';

class MediaLibraryPage extends ConsumerWidget {
  const MediaLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    // 宽屏使用固定 Tab，窄屏使用可滚动 Tab
    final useScrollableTab = screenWidth < 500;

    return DefaultTabController(
      length: MediaType.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('媒体库'),
          bottom: TabBar(
            isScrollable: useScrollableTab,
            tabAlignment: useScrollableTab ? TabAlignment.start : TabAlignment.fill,
            padding: useScrollableTab ? const EdgeInsets.symmetric(horizontal: 8) : EdgeInsets.zero,
            labelPadding: useScrollableTab
                ? const EdgeInsets.symmetric(horizontal: 12)
                : const EdgeInsets.symmetric(horizontal: 4),
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: isDark ? AppColors.darkOutline.withValues(alpha: 0.3) : null,
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.normal,
            ),
            tabs: MediaType.values.map((type) {
              return Tab(
                iconMargin: const EdgeInsets.only(bottom: 4),
                icon: Icon(_getMediaTypeIcon(type), size: 20),
                text: type.displayName,
              );
            }).toList(),
          ),
        ),
        body: TabBarView(
          children: MediaType.values.map((type) {
            return _MediaTypeTab(mediaType: type);
          }).toList(),
        ),
      ),
    );
  }

  IconData _getMediaTypeIcon(MediaType type) {
    return switch (type) {
      MediaType.video => Icons.movie_outlined,
      MediaType.music => Icons.music_note_outlined,
      MediaType.photo => Icons.photo_library_outlined,
      MediaType.comic => Icons.collections_outlined,
      MediaType.book => Icons.book_outlined,
      MediaType.note => Icons.note_outlined,
    };
  }
}

class _MediaTypeTab extends ConsumerWidget {
  const _MediaTypeTab({required this.mediaType});

  final MediaType mediaType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(mediaLibraryConfigProvider);
    final sourcesAsync = ref.watch(sourcesProvider);
    final connections = ref.watch(activeConnectionsProvider);

    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('加载失败: $e')),
      data: (config) {
        final paths = config.getPathsForType(mediaType);

        return sourcesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('加载失败: $e')),
          data: (sources) {
            if (sources.isEmpty) {
              return _buildNoSourcesState(context);
            }

            return Column(
              children: [
                // 所有媒体类型都显示扫描按钮和缓存信息（笔记除外）
                if (mediaType != MediaType.note)
                  _MediaScanSection(
                    mediaType: mediaType,
                    paths: paths,
                    connections: connections,
                  ),

                // 添加按钮
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _addPath(context, ref, sources, connections),
                      icon: const Icon(Icons.add),
                      label: Text('添加${mediaType.displayName}目录'),
                    ),
                  ),
                ),

                // 目录列表
                if (paths.isEmpty)
                  Expanded(child: _buildEmptyState(context))
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: paths.length,
                      itemBuilder: (context, index) {
                        final path = paths[index];
                        final source = sources.firstWhere(
                          (s) => s.id == path.sourceId,
                          orElse: () => SourceEntity(
                            name: '未知源',
                            type: SourceType.synology,
                            host: '',
                            username: '',
                          ),
                        );
                        final connection = connections[path.sourceId];

                        return _PathCard(
                          path: path,
                          source: source,
                          connection: connection,
                          mediaType: mediaType,
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildNoSourcesState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '尚未添加任何源',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '请先在设置中添加 NAS 或其他源',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getEmptyIcon(),
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '未配置${mediaType.displayName}目录',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '点击上方按钮添加目录',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getEmptyIcon() {
    return switch (mediaType) {
      MediaType.video => Icons.video_library_outlined,
      MediaType.music => Icons.library_music_outlined,
      MediaType.photo => Icons.photo_library_outlined,
      MediaType.comic => Icons.collections_bookmark_outlined,
      MediaType.book => Icons.library_books_outlined,
      MediaType.note => Icons.sticky_note_2_outlined,
    };
  }

  void _addPath(
    BuildContext context,
    WidgetRef ref,
    List<SourceEntity> sources,
    Map<String, SourceConnection> connections,
  ) {
    // 过滤出已连接的源
    final connectedSources = sources.where((s) {
      final conn = connections[s.id];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedSources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有已连接的源，请先连接一个源'),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FolderPickerSheet(
        sources: connectedSources,
        connections: connections,
        onSelect: (sourceId, path, name) async {
          final newPath = MediaLibraryPath(
            sourceId: sourceId,
            path: path,
            name: name,
          );
          await ref
              .read(mediaLibraryConfigProvider.notifier)
              .addPath(mediaType, newPath);
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已添加目录: $path')),
            );
          }
        },
      ),
    );
  }
}

class _PathCard extends ConsumerWidget {
  const _PathCard({
    required this.path,
    required this.source,
    required this.connection,
    required this.mediaType,
  });

  final MediaLibraryPath path;
  final SourceEntity source;
  final SourceConnection? connection;
  final MediaType mediaType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = connection?.status == SourceStatus.connected;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (path.isEnabled ? AppColors.primary : Colors.grey)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.folder,
            color: path.isEnabled ? AppColors.primary : Colors.grey,
          ),
        ),
        title: Text(
          path.displayName,
          style: TextStyle(
            color: path.isEnabled ? null : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              path.path,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Icon(
                  isConnected ? Icons.cloud_done : Icons.cloud_off,
                  size: 12,
                  color: isConnected ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  source.displayName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isConnected ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            switch (value) {
              case 'toggle':
                await ref
                    .read(mediaLibraryConfigProvider.notifier)
                    .togglePath(mediaType, path.id, !path.isEnabled);
                break;
              case 'delete':
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('删除目录'),
                    content: Text('确定要从媒体库中移除 "${path.displayName}" 吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref
                      .read(mediaLibraryConfigProvider.notifier)
                      .removePath(mediaType, path.id);
                }
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'toggle',
              child: Row(
                children: [
                  Icon(path.isEnabled ? Icons.visibility_off : Icons.visibility),
                  const SizedBox(width: 12),
                  Text(path.isEnabled ? '停用' : '启用'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 12),
                  Text('删除', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 视频扫描区域
class _MediaScanSection extends ConsumerStatefulWidget {
  const _MediaScanSection({
    required this.mediaType,
    required this.paths,
    required this.connections,
  });

  final MediaType mediaType;
  final List<MediaLibraryPath> paths;
  final Map<String, SourceConnection> connections;

  @override
  ConsumerState<_MediaScanSection> createState() => _MediaScanSectionState();
}

class _MediaScanSectionState extends ConsumerState<_MediaScanSection> {
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 检查是否有已连接的源
    final hasConnectedSource = widget.paths.any((path) {
      final conn = widget.connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    });

    // 根据媒体类型获取状态和缓存信息
    final (isLoading, scanProgress, currentFolder, cacheInfo) = _getMediaState();

    // 获取图标和标题
    final (icon, title, scanButtonText) = _getMediaInfo();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cacheInfo,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 扫描进度
          if (isLoading) ...[
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: scanProgress > 0 ? scanProgress : null,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    currentFolder ?? '正在扫描...',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (scanProgress > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: scanProgress,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                color: AppColors.primary,
              ),
            ],
            const SizedBox(height: 12),
          ],

          // 扫描按钮
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isLoading || !hasConnectedSource
                      ? null
                      : () => _scanMedia(),
                  icon: Icon(
                    isLoading ? Icons.hourglass_empty : Icons.refresh_rounded,
                  ),
                  label: Text(isLoading ? '扫描中...' : scanButtonText),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: isLoading
                    ? null
                    : () => _clearCache(),
                icon: const Icon(Icons.delete_outline),
                label: const Text('清除缓存'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ],
          ),

          // 未连接提示
          if (!hasConnectedSource && widget.paths.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.orange[700],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '请先连接至少一个源才能扫描${widget.mediaType.displayName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 获取媒体状态信息
  (bool, double, String?, String) _getMediaState() {
    switch (widget.mediaType) {
      case MediaType.video:
        final state = ref.watch(videoListProvider);
        final isLoading = state is VideoListLoading;
        final progress = state is VideoListLoading ? state.progress : 0.0;
        final folder = state is VideoListLoading ? state.currentFolder : null;
        final cacheInfo = VideoLibraryCacheService.instance.getCacheInfo();
        return (isLoading, progress, folder, cacheInfo);

      case MediaType.music:
        final state = ref.watch(musicListProvider);
        final isLoading = state is MusicListLoading;
        final progress = state is MusicListLoading ? state.progress : 0.0;
        final folder = state is MusicListLoading ? state.currentFolder : null;
        final cacheInfo = MusicLibraryCacheService.instance.getCacheInfo();
        return (isLoading, progress, folder, cacheInfo);

      case MediaType.photo:
        final state = ref.watch(photoListProvider);
        final isLoading = state is PhotoListLoading;
        final progress = state is PhotoListLoading ? state.progress : 0.0;
        final folder = state is PhotoListLoading ? state.currentFolder : null;
        final cacheInfo = PhotoLibraryCacheService.instance.getCacheInfo();
        return (isLoading, progress, folder, cacheInfo);

      case MediaType.comic:
        final state = ref.watch(comicListProvider);
        final isLoading = state is ComicListLoading;
        final progress = state is ComicListLoading ? state.progress : 0.0;
        final folder = state is ComicListLoading ? state.currentFolder : null;
        final cacheInfo = ComicLibraryCacheService.instance.getCacheInfo();
        return (isLoading, progress, folder, cacheInfo);

      case MediaType.book:
        final state = ref.watch(bookListProvider);
        final isLoading = state is BookListLoading;
        final progress = state is BookListLoading ? state.progress : 0.0;
        final folder = state is BookListLoading ? state.currentFolder : null;
        final cacheInfo = BookLibraryCacheService.instance.getCacheInfo();
        return (isLoading, progress, folder, cacheInfo);

      case MediaType.note:
        return (false, 0.0, null, '暂无缓存');
    }
  }

  /// 获取媒体信息（图标、标题、按钮文字）
  (IconData, String, String) _getMediaInfo() {
    switch (widget.mediaType) {
      case MediaType.video:
        return (Icons.video_library_rounded, '视频库缓存', '扫描视频');
      case MediaType.music:
        return (Icons.library_music_rounded, '音乐库缓存', '扫描音乐');
      case MediaType.photo:
        return (Icons.photo_library_rounded, '照片库缓存', '扫描照片');
      case MediaType.comic:
        return (Icons.collections_bookmark_rounded, '漫画库缓存', '扫描漫画');
      case MediaType.book:
        return (Icons.library_books_rounded, '图书库缓存', '扫描图书');
      case MediaType.note:
        return (Icons.note_rounded, '笔记库缓存', '扫描笔记');
    }
  }

  Future<void> _scanMedia() async {
    setState(() => _isScanning = true);
    try {
      switch (widget.mediaType) {
        case MediaType.video:
          await ref.read(videoListProvider.notifier).loadVideos(forceRefresh: true);
        case MediaType.music:
          await ref.read(musicListProvider.notifier).loadMusic(forceRefresh: true);
        case MediaType.photo:
          await ref.read(photoListProvider.notifier).loadPhotos(forceRefresh: true);
        case MediaType.comic:
          await ref.read(comicListProvider.notifier).loadComics(forceRefresh: true);
        case MediaType.book:
          await ref.read(bookListProvider.notifier).loadBooks(forceRefresh: true);
        case MediaType.note:
          break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.mediaType.displayName}扫描完成')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('清除${widget.mediaType.displayName}缓存'),
        content: Text('确定要清除${widget.mediaType.displayName}库缓存吗？下次需要重新扫描。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      switch (widget.mediaType) {
        case MediaType.video:
          await VideoLibraryCacheService.instance.clearCache();
          ref.invalidate(videoListProvider);
        case MediaType.music:
          await MusicLibraryCacheService.instance.clearCache();
          ref.invalidate(musicListProvider);
        case MediaType.photo:
          await PhotoLibraryCacheService.instance.clearCache();
          ref.invalidate(photoListProvider);
        case MediaType.comic:
          await ComicLibraryCacheService.instance.clearCache();
          ref.invalidate(comicListProvider);
        case MediaType.book:
          await BookLibraryCacheService.instance.clearCache();
          ref.invalidate(bookListProvider);
        case MediaType.note:
          break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.mediaType.displayName}缓存已清除')),
        );
      }
    }
  }
}
