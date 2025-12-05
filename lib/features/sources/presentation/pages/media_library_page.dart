import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/book/data/services/book_library_cache_service.dart';
import 'package:my_nas/features/book/presentation/pages/book_list_page.dart';
import 'package:my_nas/features/comic/data/services/comic_library_cache_service.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/data/services/music_library_cache_service.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/data/services/photo_library_cache_service.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/sources/presentation/widgets/folder_picker_sheet.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_library_cache_service.dart';
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
                      onPressed: () =>
                          _addPath(context, ref, sources, connections),
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
            ).showSnackBar(SnackBar(content: Text('已添加目录: $path')));
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
          style: TextStyle(color: path.isEnabled ? null : Colors.grey),
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
                    .togglePath(mediaType, path.id, enabled: !path.isEnabled);
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
                if (confirm ?? false) {
                  await ref
                      .read(mediaLibraryConfigProvider.notifier)
                      .removePath(mediaType, path.id);
                }
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'toggle',
              child: Row(
                children: [
                  Icon(
                    path.isEnabled ? Icons.visibility_off : Icons.visibility,
                  ),
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
  VideoScanProgress? _videoScanProgress;
  ScrapeStats? _scrapeStats;
  StreamSubscription<VideoScanProgress>? _progressSubscription;
  StreamSubscription<ScrapeStats>? _scrapeStatsSubscription;

  // 各媒体类型的数据库统计
  int? _musicCount;
  int? _photoCount;
  int? _bookCount;
  int? _comicCount;

  @override
  void initState() {
    super.initState();
    // 根据媒体类型初始化
    switch (widget.mediaType) {
      case MediaType.video:
        _progressSubscription = VideoScannerService().progressStream
            .listen((progress) {
              if (mounted) {
                setState(() => _videoScanProgress = progress);
              }
            });
        _scrapeStatsSubscription = VideoScannerService().scrapeStatsStream
            .listen((stats) {
              if (mounted) {
                setState(() => _scrapeStats = stats);
              }
            });
        _loadScrapeStats();
      case MediaType.music:
        _loadMusicStats();
      case MediaType.photo:
        _loadPhotoStats();
      case MediaType.book:
        _loadBookStats();
      case MediaType.comic:
        _loadComicStats();
      case MediaType.note:
        break;
    }
  }

  Future<void> _loadScrapeStats() async {
    try {
      final stats = await VideoScannerService().getScrapeStats();
      if (mounted) {
        setState(() => _scrapeStats = stats);
      }
    } on Exception {
      // 数据库未初始化时忽略错误
    }
  }

  Future<void> _loadMusicStats() async {
    try {
      final count = await MusicDatabaseService().getCount();
      if (mounted) {
        setState(() => _musicCount = count);
      }
    } on Exception {
      // 忽略错误
    }
  }

  Future<void> _loadPhotoStats() async {
    try {
      final count = await PhotoDatabaseService().getCount();
      if (mounted) {
        setState(() => _photoCount = count);
      }
    } on Exception {
      // 忽略错误
    }
  }

  Future<void> _loadBookStats() async {
    try {
      final count = await BookDatabaseService().getCount();
      if (mounted) {
        setState(() => _bookCount = count);
      }
    } on Exception {
      // 忽略错误
    }
  }

  Future<void> _loadComicStats() async {
    try {
      await ComicLibraryCacheService().init();
      final cache = ComicLibraryCacheService().getCache();
      if (mounted) {
        setState(() => _comicCount = cache?.comics.length ?? 0);
      }
    } on Exception {
      // 忽略错误
    }
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _scrapeStatsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 检查是否有已连接的源
    final hasConnectedSource = widget.paths.any((path) {
      final conn = widget.connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    });

    // 视频类型使用新的分区布局
    if (widget.mediaType == MediaType.video) {
      return _buildVideoScanSection(context, theme, isDark, hasConnectedSource);
    }

    // 其他媒体类型使用原有布局
    return _buildGenericScanSection(context, theme, isDark, hasConnectedSource);
  }

  /// 构建视频扫描区域（紧凑布局）
  Widget _buildVideoScanSection(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    bool hasConnectedSource,
  ) {
    final progress = _videoScanProgress;
    final stats = _scrapeStats;

    final isScanning = VideoScannerService().isScanning;
    final isScraping = VideoScannerService().isScraping;
    final isLoading = isScanning || isScraping;

    // 判断当前阶段
    final isScanningFiles = isScanning &&
        (progress?.phase == VideoScanPhase.scanning ||
            progress?.phase == VideoScanPhase.savingToDb);
    final isScrapingMeta = isScraping ||
        (progress?.phase == VideoScanPhase.scraping);

    // 统计信息
    final totalVideos = stats?.total ?? 0;
    final completedScrape = stats?.completed ?? 0;
    final failedScrape = stats?.failed ?? 0;
    final pendingScrape = stats?.pending ?? 0;

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
          // 标题行：视频库统计
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.video_library_rounded,
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
                      '视频库',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      totalVideos > 0
                          ? '共 $totalVideos 个视频'
                          : '暂无数据',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 刮削统计（简洁版）
          if (stats != null && stats.total > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _buildMiniStat(theme, '待刮削', pendingScrape, Colors.grey),
                const SizedBox(width: 16),
                _buildMiniStat(theme, '已完成', completedScrape, Colors.green),
                const SizedBox(width: 16),
                _buildMiniStat(theme, '失败', failedScrape, Colors.red),
              ],
            ),
          ],

          // 扫描/刮削进度
          if (isScanningFiles || isScrapingMeta) ...[
            const SizedBox(height: 12),
            _buildProgressRow(
              theme: theme,
              isDark: isDark,
              progress: isScanningFiles
                  ? (progress?.progress ?? 0.0)
                  : (stats != null && stats.total > 0
                      ? stats.processed / stats.total
                      : 0.0),
              description: isScanningFiles
                  ? (progress?.description ?? '正在扫描...')
                  : (progress?.currentFile != null
                      ? '正在刮削: ${progress!.currentFile}'
                      : '正在刮削元数据...'),
            ),
          ],

          const SizedBox(height: 12),

          // 操作按钮行
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isLoading || !hasConnectedSource
                      ? null
                      : _scanFilesOnly,
                  icon: SizedBox(
                    width: 18,
                    height: 18,
                    child: isScanning
                        ? const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          )
                        : const Icon(Icons.folder_open_rounded, size: 18),
                  ),
                  label: Text(isScanning ? '扫描中' : '扫描'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: isDark
                        ? Colors.grey[800]
                        : Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isLoading || !hasConnectedSource || totalVideos == 0
                      ? null
                      : _startScraping,
                  icon: SizedBox(
                    width: 18,
                    height: 18,
                    child: isScraping
                        ? const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          )
                        : const Icon(Icons.auto_fix_high_rounded, size: 18),
                  ),
                  label: Text(isScraping ? '刮削中' : '刮削'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: isDark
                        ? Colors.grey[800]
                        : Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (isScraping) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _stopScraping,
                  icon: const Icon(Icons.stop_rounded),
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.red,
                    backgroundColor: Colors.red.withValues(alpha: 0.1),
                  ),
                  tooltip: '停止刮削',
                ),
              ],
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
                      '请先连接至少一个源才能扫描',
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

  /// 构建迷你统计项
  Widget _buildMiniStat(ThemeData theme, String label, int value, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label $value',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

  /// 构建进度行
  Widget _buildProgressRow({
    required ThemeData theme,
    required bool isDark,
    required double progress,
    required String description,
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
              color: AppColors.primary,
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
                color: AppColors.primary,
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
          color: AppColors.primary,
        ),
      ],
    ],
  );

  /// 构建通用扫描区域（非视频类型）
  Widget _buildGenericScanSection(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    bool hasConnectedSource,
  ) {
    // 根据媒体类型获取状态和缓存信息
    final (isLoading, scanProgress, currentFolder, cacheInfo) =
        _getMediaState();

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
                child: Icon(icon, size: 20, color: AppColors.primary),
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isLoading || !hasConnectedSource
                  ? null
                  : _scanMedia,
              icon: Icon(
                isLoading ? Icons.hourglass_empty : Icons.refresh_rounded,
              ),
              label: Text(isLoading ? '扫描中...' : scanButtonText),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: isDark
                    ? Colors.grey[800]
                    : Colors.grey[300],
              ),
            ),
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
        // 使用 VideoScannerService 的进度
        final scannerIsScanning = VideoScannerService().isScanning;
        final progress = _videoScanProgress;
        final isLoading =
            scannerIsScanning ||
            (progress != null &&
                progress.phase != VideoScanPhase.completed &&
                progress.phase != VideoScanPhase.error);
        final scanProgress = progress?.progress ?? 0.0;
        final folder = progress?.description;
        final total = _scrapeStats?.total ?? 0;
        final statsInfo = total > 0 ? '共 $total 个视频' : '暂无数据';
        return (isLoading, scanProgress, folder, statsInfo);

      case MediaType.music:
        final state = ref.watch(musicListProvider);
        final isLoading = state is MusicListLoading;
        // 使用元数据提取进度（如果在提取元数据阶段）
        final progress = state is MusicListLoading
            ? (state.phase == MusicScanPhase.metadata
                  ? state.metadataProgress
                  : state.progress)
            : 0.0;
        final folder = state is MusicListLoading ? state.currentFolder : null;
        final count = _musicCount ?? 0;
        final statsInfo = count > 0 ? '共 $count 首音乐' : '暂无数据';
        return (isLoading, progress, folder, statsInfo);

      case MediaType.photo:
        final state = ref.watch(photoListProvider);
        final isLoading = state is PhotoListLoading;
        final progress = state is PhotoListLoading ? state.progress : 0.0;
        final folder = state is PhotoListLoading ? state.currentFolder : null;
        final count = _photoCount ?? 0;
        final statsInfo = count > 0 ? '共 $count 张照片' : '暂无数据';
        return (isLoading, progress, folder, statsInfo);

      case MediaType.comic:
        final state = ref.watch(comicListProvider);
        final isLoading = state is ComicListLoading;
        final progress = state is ComicListLoading ? state.progress : 0.0;
        final folder = state is ComicListLoading ? state.currentFolder : null;
        final count = _comicCount ?? 0;
        final statsInfo = count > 0 ? '共 $count 本漫画' : '暂无数据';
        return (isLoading, progress, folder, statsInfo);

      case MediaType.book:
        final state = ref.watch(bookListProvider);
        final isLoading = state is BookListLoading;
        final progress = state is BookListLoading ? state.progress : 0.0;
        final folder = state is BookListLoading ? state.currentFolder : null;
        final count = _bookCount ?? 0;
        final statsInfo = count > 0 ? '共 $count 本图书' : '暂无数据';
        return (isLoading, progress, folder, statsInfo);

      case MediaType.note:
        return (false, 0.0, null, '暂无数据');
    }
  }

  /// 获取媒体信息（图标、标题、按钮文字）
  (IconData, String, String) _getMediaInfo() {
    switch (widget.mediaType) {
      case MediaType.video:
        return (Icons.video_library_rounded, '视频库', '扫描视频');
      case MediaType.music:
        return (Icons.library_music_rounded, '音乐库', '扫描音乐');
      case MediaType.photo:
        return (Icons.photo_library_rounded, '照片库', '扫描照片');
      case MediaType.comic:
        return (Icons.collections_bookmark_rounded, '漫画库', '扫描漫画');
      case MediaType.book:
        return (Icons.library_books_rounded, '图书库', '扫描图书');
      case MediaType.note:
        return (Icons.note_rounded, '笔记库', '扫描笔记');
    }
  }

  /// 仅扫描文件（视频专用）
  Future<void> _scanFilesOnly() async {
    try {
      final count = await VideoScannerService().scanFilesOnly(
        paths: widget.paths,
        connections: widget.connections,
      );
      // 扫描完成后，通知 VideoListNotifier 重新加载
      await ref.read(videoListProvider.notifier).reloadFromCache();
      // 刷新刮削统计
      await _loadScrapeStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件扫描完成，共 $count 个视频')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e')),
        );
      }
    }
  }

  /// 开始刮削元数据（视频专用）
  Future<void> _startScraping() async {
    try {
      // 异步开始刮削，不阻塞 UI
      unawaited(VideoScannerService().scrapeMetadata(
        connections: widget.connections,
      ).then((_) async {
        // 刮削完成后刷新统计
        await _loadScrapeStats();
        // 通知 VideoListNotifier 重新加载
        await ref.read(videoListProvider.notifier).reloadFromCache();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('元数据刮削完成')),
          );
        }
      }));
      // 立即刷新状态
      setState(() {});
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刮削失败: $e')),
        );
      }
    }
  }

  /// 停止刮削（视频专用）
  void _stopScraping() {
    VideoScannerService().stopScraping();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在停止刮削...')),
    );
  }

  Future<void> _scanMedia() async {
    try {
      switch (widget.mediaType) {
        case MediaType.video:
          // 使用新的 VideoScannerService
          await VideoScannerService().scan(
            paths: widget.paths,
            connections: widget.connections,
          );
          // 扫描完成后，通知 VideoListNotifier 重新加载缓存
          await ref.read(videoListProvider.notifier).reloadFromCache();
          await _loadScrapeStats();
        case MediaType.music:
          await ref
              .read(musicListProvider.notifier)
              .loadMusic(forceRefresh: true);
          await _loadMusicStats();
        case MediaType.photo:
          await ref
              .read(photoListProvider.notifier)
              .loadPhotos(forceRefresh: true);
          await _loadPhotoStats();
        case MediaType.comic:
          await ref
              .read(comicListProvider.notifier)
              .loadComics(forceRefresh: true);
          await _loadComicStats();
        case MediaType.book:
          await ref
              .read(bookListProvider.notifier)
              .loadBooks(forceRefresh: true);
          await _loadBookStats();
        case MediaType.note:
          break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${widget.mediaType.displayName}扫描完成')),
        );
      }
    } finally {
      if (mounted) {}
    }
  }

  /// 清除缓存（保留方法以备将来使用）
  // ignore: unused_element
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清除'),
          ),
        ],
      ),
    );

    if (confirm ?? false) {
      switch (widget.mediaType) {
        case MediaType.video:
          // 同时清除 Hive 缓存和 SQLite 数据
          await VideoLibraryCacheService().clearCache();
          await VideoDatabaseService().clearAll();
          ref.invalidate(videoListProvider);
        case MediaType.music:
          // 同时清除 Hive 缓存和 SQLite 数据
          await MusicLibraryCacheService().clearCache();
          await MusicDatabaseService().clearAll();
          ref.invalidate(musicListProvider);
        case MediaType.photo:
          // 同时清除 Hive 缓存和 SQLite 数据
          await PhotoLibraryCacheService().clearCache();
          await PhotoDatabaseService().clear();
          ref.invalidate(photoListProvider);
        case MediaType.comic:
          // 漫画仅使用 FlutterSecureStorage
          await ComicLibraryCacheService().clearCache();
          ref.invalidate(comicListProvider);
        case MediaType.book:
          // 同时清除 Hive 缓存和 SQLite 数据
          await BookLibraryCacheService().clearCache();
          await BookDatabaseService().clear();
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
