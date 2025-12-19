import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/services/media_scan_progress_service.dart';
import 'package:my_nas/core/utils/logger.dart';
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

    // 分离移动端源和普通源
    final mobileSources = connectedSources.where((s) => s.type.isMobileSource).toList();
    final normalSources = connectedSources.where((s) => !s.type.isMobileSource).toList();

    // 如果有移动端源，显示源选择对话框
    if (mobileSources.isNotEmpty) {
      _showSourceSelectionDialog(
        context,
        ref,
        mobileSources,
        normalSources,
        connections,
        existingPaths,
      );
    } else {
      // 只有普通源，直接显示目录选择器
      _showFolderPicker(context, ref, normalSources, connections);
    }
  }

  /// 显示源选择对话框（移动端源 + 普通源）
  void _showSourceSelectionDialog(
    BuildContext context,
    WidgetRef ref,
    List<SourceEntity> mobileSources,
    List<SourceEntity> normalSources,
    Map<String, SourceConnection> connections,
    List<MediaLibraryPath> existingPaths,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择数据源',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),

            // 移动端源（直接添加，不需要选择目录）
            if (mobileSources.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '手机媒体',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
              ...mobileSources.map((source) {
                // 检查是否已添加
                final alreadyAdded = existingPaths.any((p) => p.sourceId == source.id);
                return ListTile(
                  leading: Icon(source.type.icon, color: source.type.themeColor),
                  title: Text(source.displayName),
                  subtitle: Text(source.type.description),
                  trailing: alreadyAdded
                      ? const Chip(label: Text('已添加'))
                      : const Icon(Icons.add),
                  enabled: !alreadyAdded,
                  onTap: alreadyAdded
                      ? null
                      : () => _addMobileSource(context, ref, source, connections),
                );
              }),
            ],

            // 普通源（需要选择目录）
            if (normalSources.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '远程存储',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('选择目录...'),
                subtitle: const Text('从 NAS 或网络存储选择'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _showFolderPicker(context, ref, normalSources, connections);
                },
              ),
            ],

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 添加移动端源到媒体库
  Future<void> _addMobileSource(
    BuildContext context,
    WidgetRef ref,
    SourceEntity source,
    Map<String, SourceConnection> connections,
  ) async {
    // 移动端源使用根路径 "/"
    final newPath = MediaLibraryPath(
      sourceId: source.id,
      path: '/',
      name: source.displayName,
    );

    await ref.read(mediaLibraryConfigProvider.notifier).addPath(mediaType, newPath);

    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加 ${source.displayName}，正在扫描...')),
      );

      // 添加后自动扫描该路径
      _autoScanPath(ref, mediaType, newPath, connections);
    }
  }

  /// 显示目录选择器
  void _showFolderPicker(
    BuildContext context,
    WidgetRef ref,
    List<SourceEntity> sources,
    Map<String, SourceConnection> connections,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FolderPickerSheet(
        sources: sources,
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
          // 扫描完成后自动触发后台刮削（使用最新连接状态）
          final currentConnections = ref.read(activeConnectionsProvider);
          final hasConnected = currentConnections.values
              .any((c) => c.status == SourceStatus.connected);
          logger.d(
            'VideoScan: 扫描完成，准备刮削 - '
            '连接数: ${currentConnections.length}, '
            '有可用连接: $hasConnected',
          );
          if (hasConnected) {
            unawaited(
              VideoScannerService().scrapeMetadata(connections: currentConnections),
            );
          } else {
            logger.w('VideoScan: 没有可用连接，跳过刮削');
          }
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
  // 扫描状态（所有媒体类型统一使用）
  bool _isScanning = false;
  double _scanProgress = 0;
  String? _scanDescription;
  int _scannedCount = 0;  // 扫描时的实时数量

  // 视频专用：刮削状态
  bool _isScraping = false;
  double _scrapeProgress = 0;

  // 统计信息
  int _itemCount = 0;
  int _scrapedCount = 0;  // 视频专用：已刮削数量
  int _pendingScrapeCount = 0;  // 视频专用：待刮削数量
  int _retryableCount = 0;  // 视频专用：可重试数量（失败+无TMDB）

  StreamSubscription<VideoScanProgress>? _videoProgressSub;
  StreamSubscription<ScrapeStats>? _scrapeStatsSub;
  StreamSubscription<MediaScanProgress>? _mediaScanProgressSub;

  @override
  void initState() {
    super.initState();
    _loadStats();

    if (widget.mediaType == MediaType.video) {
      // 视频类型：使用 VideoScannerService
      // 注意：刮削是全局的，所以使用全局状态
      _isScraping = VideoScannerService().isScraping;
      // 初始扫描状态：默认为 false，依赖 progressStream 更新
      _isScanning = false;

      if (_isScraping) {
        _loadInitialScrapeStats();
      }

      _videoProgressSub = VideoScannerService().progressStream.listen((progress) {
        if (mounted) {
          // 检查进度事件是否属于当前目录
          final isMyProgress = progress.sourceId == widget.path.sourceId &&
              progress.pathPrefix == widget.path.path;

          if (isMyProgress) {
            setState(() {
              _isScanning = progress.phase == VideoScanPhase.scanning ||
                  progress.phase == VideoScanPhase.savingToDb;
              _scanProgress = progress.progress;
              _scanDescription = progress.description;
              _scannedCount = progress.scannedCount;

              if (progress.phase == VideoScanPhase.completed ||
                  progress.phase == VideoScanPhase.error) {
                _isScanning = false;
              }
            });
          }
        }
      });
      _scrapeStatsSub = VideoScannerService().scrapeStatsStream.listen((globalStats) async {
        if (mounted) {
          final sourceId = widget.path.sourceId;
          final pathPrefix = widget.path.path;
          // 获取当前目录的刮削统计（而不是使用全局统计）
          final pathStats = await VideoScannerService().getScrapeStats(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );
          final retryable = await VideoScannerService().getRetryableCount(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );

          if (mounted) {
            setState(() {
              // 关键修复：当前目录的刮削状态应基于：
              // 1. 全局正在刮削 AND 当前目录有待刮削内容
              // 2. 或者当前目录正在被刮削中（scraping > 0）
              final isGlobalScraping = VideoScannerService().isScraping;
              _isScraping = isGlobalScraping && 
                  (pathStats.pending > 0 || pathStats.scraping > 0);
              _itemCount = pathStats.total;
              _scrapedCount = pathStats.completed;
              _pendingScrapeCount = pathStats.pending;
              _retryableCount = retryable;
              // 使用当前目录的进度
              _scrapeProgress = pathStats.progress;
            });
          }
        }
      });
    } else {
      // 其他媒体类型：使用 MediaScanProgressService
      final progressService = MediaScanProgressService();
      _isScanning = progressService.isScanning(
        widget.mediaType,
        widget.path.sourceId,
        widget.path.path,
      );

      _mediaScanProgressSub = progressService.progressStream.listen((progress) {
        if (mounted) {
          // 只处理属于当前目录和媒体类型的进度事件
          final isMyProgress = progress.mediaType == widget.mediaType &&
              progress.sourceId == widget.path.sourceId &&
              progress.pathPrefix == widget.path.path;

          if (isMyProgress) {
            setState(() {
              _isScanning = progress.phase == MediaScanPhase.scanning ||
                  progress.phase == MediaScanPhase.processing ||
                  progress.phase == MediaScanPhase.saving;
              _scanProgress = progress.progress;
              _scanDescription = progress.description;
              _scannedCount = progress.scannedCount;

              if (progress.phase == MediaScanPhase.completed ||
                  progress.phase == MediaScanPhase.error) {
                _isScanning = false;
                // 完成后重新加载统计
                _loadStats();
              }
            });
          }
        }
      });
    }
  }

  Future<void> _loadInitialScrapeStats() async {
    final sourceId = widget.path.sourceId;
    final pathPrefix = widget.path.path;

    // 获取当前目录的统计数据
    final pathStats = await VideoScannerService().getScrapeStats(
      sourceId: sourceId,
      pathPrefix: pathPrefix,
    );
    final retryable = await VideoScannerService().getRetryableCount(
      sourceId: sourceId,
      pathPrefix: pathPrefix,
    );

    if (mounted) {
      setState(() {
        _itemCount = pathStats.total;
        _scrapedCount = pathStats.completed;
        _pendingScrapeCount = pathStats.pending;
        _retryableCount = retryable;
        // 使用当前目录的进度（而非全局进度）
        _scrapeProgress = pathStats.progress;
        // 关键修复：只有当前目录有待刮削内容时才显示刮削中状态
        final isGlobalScraping = VideoScannerService().isScraping;
        _isScraping = isGlobalScraping && 
            (pathStats.pending > 0 || pathStats.scraping > 0);
      });
    }
  }

  @override
  void dispose() {
    _videoProgressSub?.cancel();
    _scrapeStatsSub?.cancel();
    _mediaScanProgressSub?.cancel();
    super.dispose();
  }

  /// 获取非视频类型的扫描进度信息（已废弃，现在使用 MediaScanProgressService）
  /// 保留用于兼容性，但不再监听 provider 状态
  /// 返回: (是否正在扫描, 进度, 描述, 已扫描数量)
  (bool isLoading, double progress, String? description, int scannedCount) _getOtherMediaScanState() => (_isScanning, _scanProgress, _scanDescription, _scannedCount);

  // 以下代码保留用于引用但不再使用
  // ignore: unused_element
  (bool, double, String?, int) _legacyGetOtherMediaScanState() {
    switch (widget.mediaType) {
      case MediaType.music:
        final state = ref.watch(musicListProvider);
        if (state is MusicListLoading) {
          final desc = state.currentFolder ??
              (state.phase == MusicScanPhase.metadata ? '提取元数据...' : '扫描文件...');
          return (true, state.metadataProgress > 0 ? state.metadataProgress : state.progress, desc, state.scannedCount);
        }
        return (false, 0, null, 0);
      case MediaType.photo:
        final state = ref.watch(photoListProvider);
        if (state is PhotoListLoading) {
          final desc = state.currentFolder ?? '扫描照片...';
          return (true, state.progress, desc, state.scannedCount);
        }
        return (false, 0, null, 0);
      case MediaType.book:
        final state = ref.watch(bookListProvider);
        if (state is BookListLoading) {
          final desc = state.currentFolder ?? '扫描书籍...';
          return (true, state.progress, desc, state.scannedCount);
        }
        return (false, 0, null, 0);
      case MediaType.comic:
        final state = ref.watch(comicListProvider);
        if (state is ComicListLoading) {
          final desc = state.currentFolder ?? '扫描漫画...';
          return (true, state.progress, desc, state.scannedCount);
        }
        return (false, 0, null, 0);
      default:
        return (false, 0, null, 0);
    }
  }

  /// 获取实时的媒体数量（扫描中使用扫描数量，否则使用数据库数量）
  int _getDisplayCount(bool isScanning, int scannedCount) {
    if (isScanning) {
      // 所有类型统一使用 _scannedCount
      if (_scannedCount > 0) return _scannedCount;
      if (scannedCount > 0) return scannedCount;
    }
    return _itemCount;
  }

  Future<void> _loadStats() async {
    try {
      final sourceId = widget.path.sourceId;
      final pathPrefix = widget.path.path;

      switch (widget.mediaType) {
        case MediaType.video:
          final stats = await VideoScannerService().getScrapeStats(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );
          final retryable = await VideoScannerService().getRetryableCount(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );
          if (mounted) {
            setState(() {
              _itemCount = stats.total;
              _scrapedCount = stats.completed;
              _pendingScrapeCount = stats.pending;
              _retryableCount = retryable;
            });
          }
        case MediaType.music:
          final count = await MusicDatabaseService().getCount(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );
          if (mounted) setState(() => _itemCount = count);
        case MediaType.photo:
          final count = await PhotoDatabaseService().getCount(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );
          if (mounted) setState(() => _itemCount = count);
        case MediaType.book:
          final count = await BookDatabaseService().getCount(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );
          if (mounted) setState(() => _itemCount = count);
        case MediaType.comic:
          final count = await ComicLibraryCacheService().getCount(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
          );
          if (mounted) setState(() => _itemCount = count);
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

    // 获取非视频类型的扫描进度
    final (otherIsScanning, otherProgress, otherDescription, otherScannedCount) =
        widget.mediaType != MediaType.video ? _getOtherMediaScanState() : (false, 0.0, null, 0);

    // 合并扫描状态：视频用 _isScanning，其他用 provider 状态
    final isCurrentlyScanning = widget.mediaType == MediaType.video ? _isScanning : otherIsScanning;
    final currentProgress = widget.mediaType == MediaType.video ? _scanProgress : otherProgress;
    final currentDescription = widget.mediaType == MediaType.video ? _scanDescription : otherDescription;

    // 获取显示的数量（扫描时实时更新）
    final displayCount = _getDisplayCount(isCurrentlyScanning, otherScannedCount);
    final isVideo = widget.mediaType == MediaType.video;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：图标、名称+数量、连接状态、更多按钮
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (widget.path.isEnabled ? _getMediaColor() : Colors.grey)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getMediaIcon(),
                    color: widget.path.isEnabled ? _getMediaColor() : Colors.grey,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 名称 + 数量
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.path.displayName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: widget.path.isEnabled ? null : Colors.grey,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (displayCount > 0 || isCurrentlyScanning) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isCurrentlyScanning ? AppColors.primary : _getMediaColor())
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isCurrentlyScanning && displayCount == 0
                                    ? '...'
                                    : '$displayCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isCurrentlyScanning ? AppColors.primary : _getMediaColor(),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.path.path,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // 连接状态指示
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isConnected ? Colors.green : Colors.grey)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConnected ? Icons.cloud_done : Icons.cloud_off,
                        size: 10,
                        color: isConnected ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        widget.source.displayName,
                        style: TextStyle(
                          fontSize: 9,
                          color: isConnected ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                // 更多按钮
                _buildMoreButton(context, isCurrentlyScanning),
              ],
            ),

            // 视频专用：刮削统计行（已刮削/待处理）
            if (isVideo && _itemCount > 0) ...[
              const SizedBox(height: 8),
              _buildVideoStatsRow(theme, isDark),
            ],

            // 扫描进度
            if (isCurrentlyScanning) ...[
              const SizedBox(height: 8),
              _buildProgressRow(
                theme: theme,
                isDark: isDark,
                progress: currentProgress,
                description: currentDescription ?? '正在扫描...',
                color: AppColors.primary,
              ),
            ],

            // 视频刮削进度
            if (isVideo && _isScraping) ...[
              const SizedBox(height: 6),
              _buildProgressRow(
                theme: theme,
                isDark: isDark,
                progress: _scrapeProgress,
                description: '正在刮削元数据...',
                color: Colors.orange,
              ),
            ],

            // 视频专用：刮削按钮（当有待刮削内容时显示）
            if (isVideo &&
                _pendingScrapeCount > 0 &&
                !_isScraping &&
                isConnected) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _startScraping,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: Text('刮削元数据 ($_pendingScrapeCount 待处理)', style: const TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],

            // 视频专用：重试按钮（当有失败或无TMDB数据的内容时显示）
            if (isVideo &&
                _retryableCount > 0 &&
                _pendingScrapeCount == 0 &&
                !_isScraping &&
                isConnected) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _retryScraping,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text('重试刮削 ($_retryableCount 失败/无数据)', style: const TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 视频专用：刮削统计行（更紧凑的样式）
  Widget _buildVideoStatsRow(ThemeData theme, bool isDark) => Row(
    children: [
      // 已刮削
      _buildCompactStatChip(
        icon: Icons.check_circle_outline,
        label: '已刮削',
        value: _scrapedCount,
        color: Colors.green,
        isDark: isDark,
      ),
      const SizedBox(width: 8),
      // 待处理
      _buildCompactStatChip(
        icon: Icons.pending_outlined,
        label: '待处理',
        value: _pendingScrapeCount,
        color: _pendingScrapeCount > 0 ? Colors.orange : Colors.grey,
        isDark: isDark,
      ),
    ],
  );

  Widget _buildCompactStatChip({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
    required bool isDark,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          '$label $value',
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
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
          // 圆形指示器：始终显示为不停转动的 loading 效果
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
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

  Widget _buildMoreButton(BuildContext context, bool isCurrentlyScanning) => PopupMenuButton<String>(
    onSelected: (value) => _handleMenuAction(value, context),
    itemBuilder: (context) {
      final isConnected = widget.connection?.status == SourceStatus.connected;
      final items = <PopupMenuEntry<String>>[
        // 扫描按钮
        PopupMenuItem(
          value: 'scan',
          enabled: isConnected && !isCurrentlyScanning,
          child: Row(
            children: [
              Icon(
                isCurrentlyScanning ? Icons.hourglass_empty : Icons.refresh_rounded,
                color: isConnected && !isCurrentlyScanning ? null : Colors.grey,
              ),
              const SizedBox(width: 12),
              Text(isCurrentlyScanning ? '扫描中...' : '扫描'),
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
    // 注意：不在这里设置 _isScanning = true
    // 因为进度会通过 progressStream 实时更新

    try {
      var count = 0;
      switch (widget.mediaType) {
        case MediaType.video:
          count = await VideoScannerService().scanFilesOnly(
            paths: [widget.path],
            connections: widget.connections,
          );
          if (!mounted) return;
          await ref.read(videoListProvider.notifier).reloadFromCache();
          await _loadStats();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('扫描完成，共 $count 个视频，开始刮削元数据...')),
            );
          }
          // 扫描完成后自动触发后台刮削（使用最新连接状态）
          if (!mounted) return;
          final currentConnections = ref.read(activeConnectionsProvider);
          if (currentConnections.values.any((c) => c.status == SourceStatus.connected)) {
            unawaited(VideoScannerService().scrapeMetadata(connections: currentConnections));
          }
        case MediaType.music:
          // 使用单目录扫描
          if (!mounted) return;
          count = await ref.read(musicListProvider.notifier).scanSinglePath(
            path: widget.path,
            connections: widget.connections,
          );
          await _loadStats();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('扫描完成，共 $count 首音乐')),
            );
          }
        case MediaType.photo:
          if (!mounted) return;
          count = await ref.read(photoListProvider.notifier).scanSinglePath(
            path: widget.path,
            connections: widget.connections,
          );
          await _loadStats();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('扫描完成，共 $count 张照片')),
            );
          }
        case MediaType.comic:
          if (!mounted) return;
          count = await ref.read(comicListProvider.notifier).scanSinglePath(
            path: widget.path,
            connections: widget.connections,
          );
          await _loadStats();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('扫描完成，共 $count 本漫画')),
            );
          }
        case MediaType.book:
          if (!mounted) return;
          count = await ref.read(bookListProvider.notifier).scanSinglePath(
            path: widget.path,
            connections: widget.connections,
          );
          await _loadStats();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('扫描完成，共 $count 本书')),
            );
          }
        case MediaType.note:
          break;
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e')),
        );
      }
    }
    // 不需要在 finally 中重置 _isScanning，因为它通过 progressStream 管理
  }

  Future<void> _startScraping() async {
    // 检查是否已在刮削中
    if (VideoScannerService().isScraping) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('刮削任务正在进行中...')),
      );
      return;
    }

    // 获取最新的连接状态（而不是使用可能过时的 widget.connections）
    final connections = ref.read(activeConnectionsProvider);

    // 检查是否有可用连接
    final hasConnected = connections.values.any((c) => c.status == SourceStatus.connected);
    if (!hasConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可用连接，请先连接源')),
        );
      }
      return;
    }

    setState(() => _isScraping = true);

    try {
      // 直接等待刮削完成（不使用 unawaited）
      await VideoScannerService().scrapeMetadata(
        connections: connections,
      );

      await _loadStats();
      await ref.read(videoListProvider.notifier).reloadFromCache();
      if (mounted) {
        setState(() => _isScraping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('元数据刮削完成')),
        );
      }
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

  /// 重试刮削失败和无 TMDB 数据的视频
  Future<void> _retryScraping() async {
    // 检查是否已在刮削中
    if (VideoScannerService().isScraping) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('刮削任务正在进行中...')),
      );
      return;
    }

    // 获取最新的连接状态（而不是使用可能过时的 widget.connections）
    final connections = ref.read(activeConnectionsProvider);

    // 检查是否有可用连接
    final hasConnected = connections.values.any((c) => c.status == SourceStatus.connected);
    if (!hasConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可用连接，请先连接源')),
        );
      }
      return;
    }

    setState(() => _isScraping = true);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开始重试刮削 $_retryableCount 个视频...')),
      );

      await VideoScannerService().retryScrapeFailedVideos(
        connections: connections,
      );

      if (!mounted) return;

      await _loadStats();
      await _loadInitialScrapeStats();
      await ref.read(videoListProvider.notifier).reloadFromCache();

      if (!mounted) return;

      setState(() => _isScraping = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('重试刮削完成')),
      );
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _isScraping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重试刮削失败: $e')),
        );
      }
    }
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
}
