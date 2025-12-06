import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/book/presentation/pages/book_list_page.dart';
import 'package:my_nas/features/comic/data/services/comic_library_cache_service.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/sources/presentation/widgets/folder_picker_sheet.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_scanner_service.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart';

class MediaLibraryPage extends ConsumerWidget {
  const MediaLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 判断是否为移动端
    final isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);

    // 移动端始终使用固定Tab（平均分割），桌面端根据屏幕宽度决定
    final useScrollableTab =
        !isMobile && MediaQuery.of(context).size.width < 500;

    return DefaultTabController(
      length: MediaType.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('媒体库'),
          bottom: TabBar(
            isScrollable: useScrollableTab,
            tabAlignment: useScrollableTab
                ? TabAlignment.start
                : TabAlignment.fill,
            padding: useScrollableTab
                ? const EdgeInsets.symmetric(horizontal: 8)
                : EdgeInsets.zero,
            labelPadding: useScrollableTab
                ? const EdgeInsets.symmetric(horizontal: 12)
                : const EdgeInsets.symmetric(horizontal: 4),
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.3)
                : null,
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.normal,
            ),
            tabs: MediaType.values
                .map(
                  (type) => Tab(
                    iconMargin: const EdgeInsets.only(bottom: 4),
                    icon: Icon(_getMediaTypeIcon(type), size: 20),
                    text: type.displayName,
                  ),
                )
                .toList(),
          ),
        ),
        body: TabBarView(
          children: MediaType.values
              .map((type) => _MediaTypeTab(mediaType: type))
              .toList(),
        ),
      ),
    );
  }

  IconData _getMediaTypeIcon(MediaType type) => switch (type) {
    MediaType.video => Icons.movie_outlined,
    MediaType.music => Icons.music_note_outlined,
    MediaType.photo => Icons.photo_library_outlined,
    MediaType.comic => Icons.collections_outlined,
    MediaType.book => Icons.book_outlined,
    MediaType.note => Icons.note_outlined,
  };
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
                // 添加按钮
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _addPath(context, ref, sources, connections, paths),
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
                          connections: connections,
                          mediaType: mediaType,
                          allPaths: paths,
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

  Widget _buildNoSourcesState(BuildContext context) => Center(
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
          Text('尚未添加任何源', style: Theme.of(context).textTheme.titleMedium),
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

  Widget _buildEmptyState(BuildContext context) => Center(
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

  IconData _getEmptyIcon() => switch (mediaType) {
    MediaType.video => Icons.video_library_outlined,
    MediaType.music => Icons.library_music_outlined,
    MediaType.photo => Icons.photo_library_outlined,
    MediaType.comic => Icons.collections_bookmark_outlined,
    MediaType.book => Icons.library_books_outlined,
    MediaType.note => Icons.sticky_note_2_outlined,
  };

  void _addPath(
    BuildContext context,
    WidgetRef ref,
    List<SourceEntity> sources,
    Map<String, SourceConnection> connections,
    List<MediaLibraryPath> existingPaths,
  ) {
    // 过滤出已连接的源
    final connectedSources = sources.where((s) {
      final conn = connections[s.id];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedSources.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有已连接的源，请先连接一个源')));
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
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('已添加目录: $path，正在扫描...')));

            // 添加后自动扫描该路径
            _autoScanPath(ref, mediaType, newPath, connections);
          }
        },
      ),
    );
  }

  /// 自动扫描新添加的路径
  void _autoScanPath(
    WidgetRef ref,
    MediaType type,
    MediaLibraryPath path,
    Map<String, SourceConnection> connections,
  ) {
    switch (type) {
      case MediaType.video:
        unawaited(VideoScannerService().scanFilesOnly(
          paths: [path],
          connections: connections,
        ).then((_) async {
          await ref.read(videoListProvider.notifier).reloadFromCache();
        }));
      case MediaType.music:
        unawaited(ref
            .read(musicListProvider.notifier)
            .loadMusic(forceRefresh: true));
      case MediaType.photo:
        unawaited(ref
            .read(photoListProvider.notifier)
            .loadPhotos(forceRefresh: true));
      case MediaType.comic:
        unawaited(ref
            .read(comicListProvider.notifier)
            .loadComics(forceRefresh: true));
      case MediaType.book:
        unawaited(ref
            .read(bookListProvider.notifier)
            .loadBooks(forceRefresh: true));
      case MediaType.note:
        break;
    }
  }
}

/// 路径卡片 - 显示扫描进度、统计信息和操作按钮
class _PathCard extends ConsumerStatefulWidget {
  const _PathCard({
    required this.path,
    required this.source,
    required this.connection,
    required this.connections,
    required this.mediaType,
    required this.allPaths,
  });

  final MediaLibraryPath path;
  final SourceEntity source;
  final SourceConnection? connection;
  final Map<String, SourceConnection> connections;
  final MediaType mediaType;
  final List<MediaLibraryPath> allPaths;

  @override
  ConsumerState<_PathCard> createState() => _PathCardState();
}

class _PathCardState extends ConsumerState<_PathCard> {
  // 扫描状态
  bool _isScanning = false;
  double _scanProgress = 0;
  String? _scanDescription;

  // 视频专用：刮削状态
  bool _isScraping = false;
  double _scrapeProgress = 0;

  // 统计信息
  int _itemCount = 0;
  int _scrapedCount = 0;  // 视频专用：已刮削数量
  int _pendingScrapeCount = 0;  // 视频专用：待刮削数量

  StreamSubscription<VideoScanProgress>? _videoProgressSub;
  StreamSubscription<ScrapeStats>? _scrapeStatsSub;

  @override
  void initState() {
    super.initState();
    _loadStats();

    if (widget.mediaType == MediaType.video) {
      _videoProgressSub = VideoScannerService().progressStream.listen((progress) {
        if (mounted) {
          setState(() {
            _isScanning = VideoScannerService().isScanning;
            _scanProgress = progress.progress;
            _scanDescription = progress.description;
          });
        }
      });
      _scrapeStatsSub = VideoScannerService().scrapeStatsStream.listen((stats) {
        if (mounted) {
          setState(() {
            _isScraping = VideoScannerService().isScraping;
            _itemCount = stats.total;
            _scrapedCount = stats.completed;
            _pendingScrapeCount = stats.pending;
            if (stats.total > 0) {
              _scrapeProgress = stats.processed / stats.total;
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _videoProgressSub?.cancel();
    _scrapeStatsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      switch (widget.mediaType) {
        case MediaType.video:
          final stats = await VideoScannerService().getScrapeStats();
          if (mounted) {
            setState(() {
              _itemCount = stats.total;
              _scrapedCount = stats.completed;
              _pendingScrapeCount = stats.pending;
            });
          }
        case MediaType.music:
          final count = await MusicDatabaseService().getCount();
          if (mounted) setState(() => _itemCount = count);
        case MediaType.photo:
          final count = await PhotoDatabaseService().getCount();
          if (mounted) setState(() => _itemCount = count);
        case MediaType.book:
          final count = await BookDatabaseService().getCount();
          if (mounted) setState(() => _itemCount = count);
        case MediaType.comic:
          await ComicLibraryCacheService().init();
          final cache = ComicLibraryCacheService().getCache();
          if (mounted) setState(() => _itemCount = cache?.comics.length ?? 0);
        case MediaType.note:
          break;
      }
    } on Exception {
      // 忽略错误
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.connection?.status == SourceStatus.connected;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：图标、名称、连接状态、更多按钮
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (widget.path.isEnabled ? _getMediaColor() : Colors.grey)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getMediaIcon(),
                    color: widget.path.isEnabled ? _getMediaColor() : Colors.grey,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.path.displayName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: widget.path.isEnabled ? null : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.path.path,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // 连接状态指示
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isConnected ? Colors.green : Colors.grey)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConnected ? Icons.cloud_done : Icons.cloud_off,
                        size: 12,
                        color: isConnected ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.source.displayName,
                        style: TextStyle(
                          fontSize: 10,
                          color: isConnected ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                // 更多按钮
                _buildMoreButton(context),
              ],
            ),

            // 统计信息行
            if (_itemCount > 0 || widget.mediaType == MediaType.video) ...[
              const SizedBox(height: 12),
              _buildStatsRow(theme, isDark),
            ],

            // 扫描进度
            if (_isScanning) ...[
              const SizedBox(height: 12),
              _buildProgressRow(
                theme: theme,
                isDark: isDark,
                progress: _scanProgress,
                description: _scanDescription ?? '正在扫描...',
                color: AppColors.primary,
              ),
            ],

            // 视频刮削进度
            if (widget.mediaType == MediaType.video && _isScraping) ...[
              const SizedBox(height: 8),
              _buildProgressRow(
                theme: theme,
                isDark: isDark,
                progress: _scrapeProgress,
                description: '正在刮削元数据...',
                color: Colors.orange,
              ),
            ],

            // 视频专用：刮削按钮（当有待刮削内容时显示）
            if (widget.mediaType == MediaType.video &&
                _pendingScrapeCount > 0 &&
                !_isScraping &&
                isConnected) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _startScraping,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: Text('刮削元数据 ($_pendingScrapeCount 待处理)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(ThemeData theme, bool isDark) {
    final isVideo = widget.mediaType == MediaType.video;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // 总数
          _buildStatItem(
            theme,
            icon: Icons.folder_open_rounded,
            label: _getCountLabel(),
            value: _itemCount,
            color: _getMediaColor(),
          ),

          // 视频专用：刮削统计
          if (isVideo && _itemCount > 0) ...[
            const SizedBox(width: 16),
            _buildStatItem(
              theme,
              icon: Icons.check_circle_outline,
              label: '已刮削',
              value: _scrapedCount,
              color: Colors.green,
            ),
            const SizedBox(width: 16),
            _buildStatItem(
              theme,
              icon: Icons.pending_outlined,
              label: '待处理',
              value: _pendingScrapeCount,
              color: _pendingScrapeCount > 0 ? Colors.orange : Colors.grey,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(
        '$label ',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      Text(
        '$value',
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    ],
  );

  Widget _buildProgressRow({
    required ThemeData theme,
    required bool isDark,
    required double progress,
    required String description,
    required Color color,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress > 0 ? progress : null,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              description,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (progress > 0)
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
      if (progress > 0) ...[
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
          color: color,
        ),
      ],
    ],
  );

  Widget _buildMoreButton(BuildContext context) => PopupMenuButton<String>(
    onSelected: (value) => _handleMenuAction(value, context),
    itemBuilder: (context) {
      final isConnected = widget.connection?.status == SourceStatus.connected;
      final items = <PopupMenuEntry<String>>[
        // 扫描按钮
        PopupMenuItem(
          value: 'scan',
          enabled: isConnected && !_isScanning,
          child: Row(
            children: [
              Icon(
                _isScanning ? Icons.hourglass_empty : Icons.refresh_rounded,
                color: isConnected && !_isScanning ? null : Colors.grey,
              ),
              const SizedBox(width: 12),
              Text(_isScanning ? '扫描中...' : '扫描'),
            ],
          ),
        ),
      ];

      // 视频专用：刮削按钮
      if (widget.mediaType == MediaType.video) {
        items.add(PopupMenuItem(
          value: 'scrape',
          enabled: isConnected && !_isScraping && _itemCount > 0,
          child: Row(
            children: [
              Icon(
                _isScraping ? Icons.hourglass_empty : Icons.auto_fix_high_rounded,
                color: isConnected && !_isScraping && _itemCount > 0
                    ? Colors.orange
                    : Colors.grey,
              ),
              const SizedBox(width: 12),
              Text(
                _isScraping ? '刮削中...' : '刮削元数据',
                style: TextStyle(
                  color: isConnected && !_isScraping && _itemCount > 0
                      ? Colors.orange
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ));

        // 停止刮削
        if (_isScraping) {
          items.add(const PopupMenuItem(
            value: 'stop_scrape',
            child: Row(
              children: [
                Icon(Icons.stop_rounded, color: Colors.red),
                SizedBox(width: 12),
                Text('停止刮削', style: TextStyle(color: Colors.red)),
              ],
            ),
          ));
        }
      }

      items.addAll([
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'toggle',
          child: Row(
            children: [
              Icon(widget.path.isEnabled ? Icons.visibility_off : Icons.visibility),
              const SizedBox(width: 12),
              Text(widget.path.isEnabled ? '停用' : '启用'),
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
      ]);

      return items;
    },
  );

  Future<void> _handleMenuAction(String value, BuildContext context) async {
    switch (value) {
      case 'scan':
        await _scanPath();
      case 'scrape':
        await _startScraping();
      case 'stop_scrape':
        _stopScraping();
      case 'toggle':
        await ref
            .read(mediaLibraryConfigProvider.notifier)
            .togglePath(widget.mediaType, widget.path.id, enabled: !widget.path.isEnabled);
      case 'delete':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除目录'),
            content: Text('确定要从媒体库中移除 "${widget.path.displayName}" 吗？'),
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
        if (confirm ?? false) {
          await ref
              .read(mediaLibraryConfigProvider.notifier)
              .removePath(widget.mediaType, widget.path.id);
        }
    }
  }

  Future<void> _scanPath() async {
    setState(() => _isScanning = true);

    try {
      switch (widget.mediaType) {
        case MediaType.video:
          final count = await VideoScannerService().scanFilesOnly(
            paths: [widget.path],
            connections: widget.connections,
          );
          await ref.read(videoListProvider.notifier).reloadFromCache();
          await _loadStats();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('扫描完成，共 $count 个视频')),
            );
          }
        case MediaType.music:
          await ref.read(musicListProvider.notifier).loadMusic(forceRefresh: true);
          await _loadStats();
        case MediaType.photo:
          await ref.read(photoListProvider.notifier).loadPhotos(forceRefresh: true);
          await _loadStats();
        case MediaType.comic:
          await ref.read(comicListProvider.notifier).loadComics(forceRefresh: true);
          await _loadStats();
        case MediaType.book:
          await ref.read(bookListProvider.notifier).loadBooks(forceRefresh: true);
          await _loadStats();
        case MediaType.note:
          break;
      }

      if (mounted && widget.mediaType != MediaType.video) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.mediaType.displayName}扫描完成')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _startScraping() async {
    setState(() => _isScraping = true);

    try {
      unawaited(VideoScannerService().scrapeMetadata(
        connections: widget.connections,
      ).then((_) async {
        await _loadStats();
        await ref.read(videoListProvider.notifier).reloadFromCache();
        if (mounted) {
          setState(() => _isScraping = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('元数据刮削完成')),
          );
        }
      }));
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isScraping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刮削失败: $e')),
        );
      }
    }
  }

  void _stopScraping() {
    VideoScannerService().stopScraping();
    setState(() => _isScraping = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在停止刮削...')),
    );
  }

  Color _getMediaColor() => switch (widget.mediaType) {
    MediaType.video => AppColors.fileVideo,
    MediaType.music => AppColors.fileAudio,
    MediaType.photo => AppColors.fileImage,
    MediaType.comic => AppColors.accent,
    MediaType.book => AppColors.tertiary,
    MediaType.note => AppColors.secondary,
  };

  IconData _getMediaIcon() => switch (widget.mediaType) {
    MediaType.video => Icons.video_library_rounded,
    MediaType.music => Icons.library_music_rounded,
    MediaType.photo => Icons.photo_library_rounded,
    MediaType.comic => Icons.collections_bookmark_rounded,
    MediaType.book => Icons.library_books_rounded,
    MediaType.note => Icons.note_rounded,
  };

  String _getCountLabel() => switch (widget.mediaType) {
    MediaType.video => '视频',
    MediaType.music => '音乐',
    MediaType.photo => '照片',
    MediaType.comic => '漫画',
    MediaType.book => '图书',
    MediaType.note => '笔记',
  };
}
