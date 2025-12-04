import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/data/services/video_library_cache_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_detail_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_page.dart';
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/hero_banner.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';

/// 视频文件及其来源
class VideoFileWithSource {
  VideoFileWithSource({
    required this.file,
    required this.sourceId,
  });

  final FileItem file;
  final String sourceId;

  String get name => file.name;
  String get path => file.path;
  int get size => file.size;
  DateTime? get modifiedTime => file.modifiedTime;
  String? get thumbnailUrl => file.thumbnailUrl;
  String get displaySize => file.displaySize;

  VideoLibraryCacheEntry toCacheEntry() => VideoLibraryCacheEntry(
        sourceId: sourceId,
        filePath: path,
        fileName: name,
        thumbnailUrl: thumbnailUrl,
        size: size,
        modifiedTime: modifiedTime,
      );
}

/// 视频列表状态
final videoListProvider =
    StateNotifierProvider<VideoListNotifier, VideoListState>(VideoListNotifier.new);

/// 视频分类标签
enum VideoTab { all, movies, tvShows, recent }

sealed class VideoListState {}

class VideoListLoading extends VideoListState {
  VideoListLoading({
    this.progress = 0,
    this.currentFolder,
    this.fromCache = false,
    this.partialVideos = const [],
    this.scannedCount = 0,
  });
  final double progress;
  final String? currentFolder;
  final bool fromCache;
  final List<VideoFileWithSource> partialVideos;
  final int scannedCount;
}

class VideoListLoaded extends VideoListState {
  VideoListLoaded({
    required this.videos,
    this.currentTab = VideoTab.all,
    this.searchQuery = '',
    this.metadataMap = const {},
    this.isLoadingMetadata = false,
    this.metadataProgress = 0,
    this.fromCache = false,
  });

  final List<VideoFileWithSource> videos;
  final VideoTab currentTab;
  final String searchQuery;
  final Map<String, VideoMetadata> metadataMap;
  final bool isLoadingMetadata;
  final double metadataProgress;
  final bool fromCache;

  /// 根据当前分类过滤视频
  List<VideoMetadata> get filteredMetadata {
    var result = videos.map((v) {
      final key = '${v.sourceId}_${v.path}';
      return metadataMap[key] ??
          VideoMetadata(
            filePath: v.path,
            sourceId: v.sourceId,
            fileName: v.name,
            thumbnailUrl: v.thumbnailUrl,
          );
    }).toList();

    // 搜索过滤
    if (searchQuery.isNotEmpty) {
      result = result
          .where((m) =>
              m.displayTitle.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
    }

    // 分类过滤
    switch (currentTab) {
      case VideoTab.all:
        break;
      case VideoTab.movies:
        result = result.where((m) => m.category != MediaCategory.tvShow).toList();
      case VideoTab.tvShows:
        result = result.where((m) => m.category == MediaCategory.tvShow).toList();
      case VideoTab.recent:
        // 按最近修改时间排序
        result.sort((a, b) {
          final videoA = videos.firstWhere((v) => '${v.sourceId}_${v.path}' == a.uniqueKey,
              orElse: () => videos.first);
          final videoB = videos.firstWhere((v) => '${v.sourceId}_${v.path}' == b.uniqueKey,
              orElse: () => videos.first);
          return (videoB.modifiedTime ?? DateTime(1970))
              .compareTo(videoA.modifiedTime ?? DateTime(1970));
        });
        result = result.take(20).toList();
    }

    // 按评分排序（高评分优先）
    if (currentTab != VideoTab.recent) {
      result.sort((a, b) {
        final ratingA = a.rating ?? 0;
        final ratingB = b.rating ?? 0;
        if (ratingA != ratingB) return ratingB.compareTo(ratingA);
        return a.displayTitle.compareTo(b.displayTitle);
      });
    }

    return result;
  }

  /// 获取电影列表
  List<VideoMetadata> get movies => videos.map((v) {
        final key = '${v.sourceId}_${v.path}';
        return metadataMap[key] ??
            VideoMetadata(
              filePath: v.path,
              sourceId: v.sourceId,
              fileName: v.name,
              thumbnailUrl: v.thumbnailUrl,
            );
      }).where((m) => m.category != MediaCategory.tvShow).toList();

  /// 获取剧集列表（按剧集名分组）
  Map<String, List<VideoMetadata>> get tvShowGroups {
    final groups = <String, List<VideoMetadata>>{};
    for (final video in videos) {
      final key = '${video.sourceId}_${video.path}';
      final metadata = metadataMap[key];
      if (metadata?.category == MediaCategory.tvShow) {
        final showTitle = metadata!.title ?? metadata.fileName;
        groups.putIfAbsent(showTitle, () => []).add(metadata);
      }
    }
    // 按季集排序
    for (final episodes in groups.values) {
      episodes.sort((a, b) {
        final seasonA = a.seasonNumber ?? 0;
        final seasonB = b.seasonNumber ?? 0;
        if (seasonA != seasonB) return seasonA.compareTo(seasonB);
        return (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
      });
    }
    return groups;
  }

  /// 获取高分电影（评分 >= 7）
  List<VideoMetadata> get topRatedMovies => movies
        .where((m) => (m.rating ?? 0) >= 7)
        .toList()
      ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));

  VideoListLoaded copyWith({
    List<VideoFileWithSource>? videos,
    VideoTab? currentTab,
    String? searchQuery,
    Map<String, VideoMetadata>? metadataMap,
    bool? isLoadingMetadata,
    double? metadataProgress,
    bool? fromCache,
  }) =>
      VideoListLoaded(
        videos: videos ?? this.videos,
        currentTab: currentTab ?? this.currentTab,
        searchQuery: searchQuery ?? this.searchQuery,
        metadataMap: metadataMap ?? this.metadataMap,
        isLoadingMetadata: isLoadingMetadata ?? this.isLoadingMetadata,
        metadataProgress: metadataProgress ?? this.metadataProgress,
        fromCache: fromCache ?? this.fromCache,
      );
}

class VideoListError extends VideoListState {
  VideoListError(this.message);
  final String message;
}

class VideoListNotifier extends StateNotifier<VideoListState> {
  VideoListNotifier(Ref ref) : super(VideoListLoading()) {
    _init();
  }

  final VideoMetadataService _metadataService = VideoMetadataService.instance;
  final VideoLibraryCacheService _cacheService = VideoLibraryCacheService.instance;

  Future<void> _init() async {
    try {
      // 并行初始化服务
      await Future.wait([
        _metadataService.init(),
        _cacheService.init(),
      ]);

      // 从缓存加载视频数据（异步分批加载）
      // 使用 unawaited 让加载在后台进行，不阻塞
      _loadFromCache();
    } catch (e) {
      logger.e('VideoListNotifier: 初始化失败', e);
      state = VideoListLoaded(videos: [], fromCache: false);
    }
  }

  /// 从缓存加载视频数据（优化：分批加载元数据）
  Future<void> _loadFromCache() async {
    final cache = _cacheService.getCache();
    if (cache != null && cache.videos.isNotEmpty) {
      final videos = cache.videos.map((entry) => VideoFileWithSource(
          file: FileItem(
            name: entry.fileName,
            path: entry.filePath,
            size: entry.size,
            isDirectory: false,
            modifiedTime: entry.modifiedTime,
            thumbnailUrl: entry.thumbnailUrl,
          ),
          sourceId: entry.sourceId,
        )).toList();

      // 第一阶段：快速显示视频列表（无元数据）
      state = VideoListLoaded(
        videos: videos,
        metadataMap: const {},
        fromCache: true,
        isLoadingMetadata: true,
      );

      logger.i('VideoListNotifier: 快速加载了 ${videos.length} 个视频');

      // 第二阶段：异步分批加载元数据
      await _loadMetadataBatched(videos);
    } else {
      // 没有缓存，显示空状态
      state = VideoListLoaded(videos: [], fromCache: true);
      logger.i('VideoListNotifier: 无缓存数据');
    }
  }

  /// 分批加载元数据，优先加载首屏内容
  Future<void> _loadMetadataBatched(List<VideoFileWithSource> videos) async {
    final metadataMap = <String, VideoMetadata>{};

    // 第一阶段：优先加载首屏内容（前 30 个，覆盖推荐、最近添加、电影等首屏分类）
    const firstBatchSize = 30;
    final firstBatch = videos.take(firstBatchSize).toList();

    for (final video in firstBatch) {
      final cached = _metadataService.getCached(video.sourceId, video.path);
      if (cached != null) {
        metadataMap[cached.uniqueKey] = cached;
      }
    }

    // 立即更新首屏数据
    final current = state;
    if (current is VideoListLoaded) {
      state = current.copyWith(
        metadataMap: Map.from(metadataMap),
        metadataProgress: firstBatch.length / videos.length,
      );
    }

    logger.i('VideoListNotifier: 首屏元数据加载完成，共 ${metadataMap.length} 个');

    // 第二阶段：后台加载剩余内容
    if (videos.length > firstBatchSize) {
      await Future<void>.delayed(Duration.zero); // 让出执行权

      const batchSize = 100; // 后续批次可以更大
      final remainingVideos = videos.skip(firstBatchSize).toList();
      final totalBatches = (remainingVideos.length / batchSize).ceil();

      for (var batch = 0; batch < totalBatches; batch++) {
        final start = batch * batchSize;
        final end = (start + batchSize).clamp(0, remainingVideos.length);
        final batchVideos = remainingVideos.sublist(start, end);

        for (final video in batchVideos) {
          final cached = _metadataService.getCached(video.sourceId, video.path);
          if (cached != null) {
            metadataMap[cached.uniqueKey] = cached;
          }
        }

        // 更新状态
        final currentState = state;
        if (currentState is VideoListLoaded) {
          state = currentState.copyWith(
            metadataMap: Map.from(metadataMap),
            metadataProgress: (firstBatchSize + (batch + 1) * batchSize) / videos.length,
          );
        }

        // 让出执行权
        if (batch < totalBatches - 1) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    // 完成加载
    final finalState = state;
    if (finalState is VideoListLoaded) {
      state = finalState.copyWith(
        isLoadingMetadata: false,
        metadataProgress: 1.0,
      );
    }

    logger.i('VideoListNotifier: 全部元数据加载完成，共 ${metadataMap.length} 个');
  }

  /// 重新从缓存加载（扫描完成后调用）
  Future<void> reloadFromCache() async {
    await _loadFromCache();
  }

  void setTab(VideoTab tab) {
    final current = state;
    if (current is VideoListLoaded) {
      state = current.copyWith(currentTab: tab);
    }
  }

  void setSearchQuery(String query) {
    final current = state;
    if (current is VideoListLoaded) {
      state = current.copyWith(searchQuery: query);
    }
  }
}

class VideoListPage extends ConsumerStatefulWidget {
  const VideoListPage({super.key});

  @override
  ConsumerState<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends ConsumerState<VideoListPage> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 获取问候语
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 12) return '早上好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
      body: Column(
        children: [
          _buildHeader(context, ref, isDark, state),
          Expanded(
            child: switch (state) {
              VideoListLoading(
                :final progress,
                :final currentFolder,
                :final fromCache,
                :final partialVideos,
                :final scannedCount,
              ) =>
                _buildLoadingState(
                  context,
                  ref,
                  progress,
                  currentFolder,
                  fromCache,
                  partialVideos,
                  scannedCount,
                  isDark,
                ),
              VideoListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(videoListProvider.notifier).reloadFromCache(),
                ),
              VideoListLoaded loaded => loaded.videos.isEmpty
                  ? _buildEmptyState(context, ref, loaded, isDark)
                  : _buildVideoContent(context, ref, loaded, isDark),
            },
          ),
        ],
      ),
    );
  }

  /// 构建顶部区域（类似音乐模块的设计）
  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    VideoListState state,
  ) => Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF1A1A2E), const Color(0xFF0D0D0D)]
              : [AppColors.primary.withValues(alpha: 0.08), Colors.grey[50]!],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.appBarHorizontalPadding,
            AppSpacing.appBarVerticalPadding,
            AppSpacing.appBarHorizontalPadding,
            AppSpacing.lg,
          ),
          child: _showSearch
              ? _buildSearchBar(context, ref, isDark)
              : _buildGreetingHeader(context, ref, isDark, state),
        ),
      ),
    );

  /// 问候语头部
  Widget _buildGreetingHeader(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    VideoListState state,
  ) {
    final videoCount = state is VideoListLoaded ? state.videos.length : 0;
    final movieCount = state is VideoListLoaded ? state.movies.length : 0;
    final tvShowCount = state is VideoListLoaded ? state.tvShowGroups.length : 0;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getGreeting(),
                style: context.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              if (videoCount > 0)
                Row(
                  children: [
                    _buildStatChip(
                      icon: Icons.movie_rounded,
                      label: '$movieCount 电影',
                      color: AppColors.primary,
                      isDark: isDark,
                    ),
                    const SizedBox(width: 12),
                    _buildStatChip(
                      icon: Icons.live_tv_rounded,
                      label: '$tvShowCount 剧集',
                      color: AppColors.accent,
                      isDark: isDark,
                    ),
                  ],
                ),
            ],
          ),
        ),
        // 操作按钮（与音乐页面风格一致）
        IconButton(
          onPressed: () => setState(() => _showSearch = true),
          icon: Icon(
            Icons.search_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          tooltip: '搜索',
        ),
        IconButton(
          onPressed: () => _showSettingsMenu(context),
          icon: Icon(
            Icons.more_vert_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          tooltip: '更多',
        ),
      ],
    );
  }

  /// 搜索栏
  Widget _buildSearchBar(BuildContext context, WidgetRef ref, bool isDark) => Row(
      children: [
        IconButton(
          onPressed: () {
            setState(() => _showSearch = false);
            _searchController.clear();
            ref.read(videoListProvider.notifier).setSearchQuery('');
          },
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
        ),
        Expanded(
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: '搜索电影、剧集...',
              hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onChanged: (v) =>
                ref.read(videoListProvider.notifier).setSearchQuery(v),
          ),
        ),
        if (_searchController.text.isNotEmpty)
          IconButton(
            onPressed: () {
              _searchController.clear();
              ref.read(videoListProvider.notifier).setSearchQuery('');
            },
            icon: Icon(Icons.close, color: isDark ? Colors.grey[400] : Colors.grey[600]),
          ),
      ],
    );

  /// 统计标签
  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );

  /// 设置菜单
  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.settings_rounded),
              title: const Text('媒体库设置'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const MediaLibraryPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_rounded),
              title: const Text('连接源管理'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const SourcesPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(
    BuildContext context,
    WidgetRef ref,
    double progress,
    String? currentFolder,
    bool fromCache,
    List<VideoFileWithSource> partialVideos,
    int scannedCount,
    bool isDark,
  ) {
    // 如果有部分结果，显示带进度条的网格视图
    if (partialVideos.isNotEmpty && !fromCache) {
      return Column(
        children: [
          // 扫描进度条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.grey[100],
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress > 0 ? progress : null,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '正在扫描... 已找到 $scannedCount 个视频',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (currentFolder != null)
                        Text(
                          currentFolder,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (progress > 0)
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
          // 部分结果网格
          Expanded(
            child: _buildPartialResultsGrid(context, ref, partialVideos, isDark),
          ),
        ],
      );
    }

    // 没有部分结果时显示加载中心动画
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 4,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            fromCache ? '加载缓存...' : '扫描视频中...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : null,
            ),
          ),
          if (currentFolder != null) ...[
            const SizedBox(height: 8),
            Text(
              currentFolder,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPartialResultsGrid(
    BuildContext context,
    WidgetRef ref,
    List<VideoFileWithSource> videos,
    bool isDark,
  ) {
    final width = MediaQuery.of(context).size.width;
    // 横向视频卡片需要更少的列数
    final crossAxisCount = width > 1200 ? 5 : width > 900 ? 4 : width > 600 ? 3 : 2;

    // 使用横向比例，适合视频缩略图 (16:9 = 1.78，加上标题区域约 1.4)
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.4,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        return _PartialVideoCard(
          video: video,
          isDark: isDark,
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) {
    // 获取缓存信息
    final cacheService = VideoLibraryCacheService.instance;
    final cacheInfo = cacheService.getCacheInfo();

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
                Icons.video_library_rounded,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '视频库为空',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请在媒体库设置中配置视频目录并扫描',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // 缓存信息
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.storage_rounded,
                    size: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cacheInfo,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
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

  Widget _buildVideoContent(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) {
    // 如果有搜索，显示搜索结果
    if (state.searchQuery.isNotEmpty) {
      return _buildSearchResults(context, ref, state, isDark);
    }

    // 判断是否显示英雄横幅
    final showHeroBanner = state.topRatedMovies.isNotEmpty;

    // 判断设备类型
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    // 获取最近添加的视频（按修改时间排序）
    // 用于分类行显示，限制 10 个
    final recentVideos = _getRecentVideos(state, limit: 10);
    // 用于查看更多页面，不限制数量
    final allRecentVideos = _getRecentVideos(state);

    // 获取电影列表
    final movies = state.movies;

    // 获取剧集列表（每个剧集只取一个代表）
    final tvShows = state.tvShowGroups.entries
        .map((e) => e.value.first)
        .toList();

    // 高分推荐
    final topRated = state.topRatedMovies;

    return CustomScrollView(
      slivers: [
        // 英雄横幅（高分推荐轮播）
        if (showHeroBanner)
          SliverToBoxAdapter(
            child: isDesktop
                ? HeroBanner(
                    items: topRated.take(5).toList(),
                    height: 450,
                    onItemTap: (item) => _openVideoDetail(context, ref, item),
                    onPlayTap: (item) => _playVideo(context, ref, item),
                  )
                : CompactHeroBanner(
                    items: topRated.take(5).toList(),
                    height: 220,
                    onItemTap: (item) => _openVideoDetail(context, ref, item),
                  ),
          ),

        // 继续观看（横向卡片）
        _ContinueWatchingSection(isDark: isDark),

        // 最近添加（纵向海报）
        if (recentVideos.isNotEmpty)
          SliverToBoxAdapter(
            child: _CategoryRow(
              title: '最近添加',
              items: recentVideos,
              onItemTap: (m) => _openVideoDetail(context, ref, m),
              isDark: isDark,
              icon: Icons.schedule_rounded,
              iconColor: Colors.blue,
              maxCount: 10,
              onViewAll: allRecentVideos.length > 10
                  ? () => _showCategoryPage(context, '最近添加', allRecentVideos)
                  : null,
            ),
          ),

        // 电影（纵向海报）
        if (movies.isNotEmpty)
          SliverToBoxAdapter(
            child: _CategoryRow(
              title: '电影',
              items: movies,
              onItemTap: (m) => _openVideoDetail(context, ref, m),
              isDark: isDark,
              icon: Icons.movie_rounded,
              iconColor: AppColors.primary,
              maxCount: 10,
              onViewAll: movies.length > 10
                  ? () => _showCategoryPage(context, '电影', movies)
                  : null,
            ),
          ),

        // 剧集（纵向海报）
        if (tvShows.isNotEmpty)
          SliverToBoxAdapter(
            child: _CategoryRow(
              title: '剧集',
              items: tvShows,
              onItemTap: (m) => _openVideoDetail(context, ref, m),
              isDark: isDark,
              icon: Icons.live_tv_rounded,
              iconColor: AppColors.accent,
              maxCount: 10,
              onViewAll: tvShows.length > 10
                  ? () => _showCategoryPage(context, '剧集', tvShows)
                  : null,
            ),
          ),

        // 高分推荐（纵向海报）
        if (topRated.length > 5)
          SliverToBoxAdapter(
            child: _CategoryRow(
              title: '高分推荐',
              items: topRated.skip(5).toList(), // 跳过 Hero Banner 中已显示的
              onItemTap: (m) => _openVideoDetail(context, ref, m),
              isDark: isDark,
              icon: Icons.star_rounded,
              iconColor: Colors.amber,
              maxCount: 10,
              onViewAll: topRated.length > 15
                  ? () => _showCategoryPage(context, '高分推荐', topRated.skip(5).toList())
                  : null,
            ),
          ),

        // 底部留白
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  /// 获取最近添加的视频
  /// [limit] 为空时返回所有视频
  List<VideoMetadata> _getRecentVideos(VideoListLoaded state, {int? limit}) {
    final result = state.videos.map((v) {
      final key = '${v.sourceId}_${v.path}';
      return state.metadataMap[key] ??
          VideoMetadata(
            filePath: v.path,
            sourceId: v.sourceId,
            fileName: v.name,
            thumbnailUrl: v.thumbnailUrl,
          );
    }).toList();

    // 按最近修改时间排序
    result.sort((a, b) {
      final videoA = state.videos.firstWhere(
        (v) => '${v.sourceId}_${v.path}' == a.uniqueKey,
        orElse: () => state.videos.first,
      );
      final videoB = state.videos.firstWhere(
        (v) => '${v.sourceId}_${v.path}' == b.uniqueKey,
        orElse: () => state.videos.first,
      );
      return (videoB.modifiedTime ?? DateTime(1970))
          .compareTo(videoA.modifiedTime ?? DateTime(1970));
    });

    return limit != null ? result.take(limit).toList() : result;
  }

  /// 显示分类页面
  void _showCategoryPage(BuildContext context, String title, List<VideoMetadata> items) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _CategoryFullPage(
          title: title,
          items: items,
        ),
      ),
    );
  }

  /// 搜索结果页面
  Widget _buildSearchResults(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) {
    final results = state.filteredMetadata;

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '未找到 "${state.searchQuery}" 的相关结果',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '找到 ${results.length} 个结果',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _CategoryRow(
            title: '搜索结果',
            items: results,
            onItemTap: (m) => _openVideoDetail(context, ref, m),
            isDark: isDark,
            icon: Icons.search_rounded,
            iconColor: AppColors.primary,
            maxCount: results.length, // 显示所有结果
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  /// 直接播放视频
  Future<void> _playVideo(
    BuildContext context,
    WidgetRef ref,
    VideoMetadata metadata,
  ) async {
    // 获取连接
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[metadata.sourceId];
    if (connection == null) return;

    try {
      // 获取视频URL
      final url = await connection.adapter.fileSystem.getFileUrl(metadata.filePath);

      if (!context.mounted) return;

      final videoItem = VideoItem(
        name: metadata.displayTitle,
        path: metadata.filePath,
        url: url,
        sourceId: metadata.sourceId,
        size: 0,
        thumbnailUrl: metadata.displayPosterUrl,
      );

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      ref.invalidate(continueWatchingProvider);
    } catch (e) {
      logger.e('播放视频失败', e);
    }
  }

  Future<void> _openVideoDetail(
    BuildContext context,
    WidgetRef ref,
    VideoMetadata metadata,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoDetailPage(
          metadata: metadata,
          sourceId: metadata.sourceId,
        ),
      ),
    );
    ref.invalidate(continueWatchingProvider);
  }
}

/// 继续观看区域
class _ContinueWatchingSection extends ConsumerWidget {
  const _ContinueWatchingSection({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final continueWatchingAsync = ref.watch(continueWatchingProvider);

    return continueWatchingAsync.when(
      data: (items) {
        if (items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

        return SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.play_circle_rounded,
                        color: Colors.red,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '继续观看',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : null,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _ContinueWatchingCard(
                    item: items[index],
                    isDark: isDark,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

/// 继续观看卡片
class _ContinueWatchingCard extends ConsumerWidget {
  const _ContinueWatchingCard({
    required this.item,
    required this.isDark,
  });

  final VideoHistoryItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playVideo(context, ref),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 缩略图区域
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty
                            ? AdaptiveImage(
                                imageUrl: item.thumbnailUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_) => _buildThumbnailPlaceholder(),
                                errorWidget: (_, __) => _buildThumbnailPlaceholder(),
                              )
                            : _buildThumbnailPlaceholder(),
                      ),
                      // 进度条
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 3,
                          color: Colors.black45,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: item.progressPercent.clamp(0.0, 1.0),
                            child: Container(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 信息区域
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.videoName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : null,
                        ),
                      ),
                      if (item.lastPosition != null && item.duration != null)
                        Text(
                          '${_formatDuration(item.lastPosition!)} / ${_formatDuration(item.duration!)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

  Widget _buildThumbnailPlaceholder() => Container(
      color: isDark ? Colors.grey[800] : Colors.grey[200],
      child: const Center(
        child: Icon(
          Icons.play_circle_rounded,
          size: 40,
          color: Colors.white54,
        ),
      ),
    );

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _playVideo(BuildContext context, WidgetRef ref) async {
    final videoItem = VideoItem(
      name: item.videoName,
      path: item.videoPath,
      url: item.videoUrl,
      sourceId: item.sourceId,
      size: item.size,
      thumbnailUrl: item.thumbnailUrl,
      lastPosition: item.lastPosition,
    );

    if (!context.mounted) return;

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoPlayerPage(video: videoItem),
      ),
    );

    ref.invalidate(continueWatchingProvider);
  }
}

/// 扫描中的简化视频卡片（横向布局）
class _PartialVideoCard extends StatelessWidget {
  const _PartialVideoCard({
    required this.video,
    required this.isDark,
  });

  final VideoFileWithSource video;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 横向视频缩略图
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 缩略图或占位符
                  if (video.thumbnailUrl != null)
                    AdaptiveImage(
                      imageUrl: video.thumbnailUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_) => _buildPlaceholder(),
                      errorWidget: (_, __) => _buildPlaceholder(),
                    )
                  else
                    _buildPlaceholder(),
                  // 扫描中标记
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '扫描中',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          video.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : null,
          ),
        ),
      ],
    );

  Widget _buildPlaceholder() => Center(
      child: Icon(
        Icons.movie_rounded,
        size: 32,
        color: isDark ? Colors.grey[600] : Colors.grey[400],
      ),
    );
}

/// 海报卡片（带播放进度）
class _PosterCard extends ConsumerStatefulWidget {
  const _PosterCard({
    required this.metadata,
    required this.onTap,
    required this.isDark,
    this.width,
  });

  final VideoMetadata metadata;
  final VoidCallback onTap;
  final bool isDark;
  final double? width;

  @override
  ConsumerState<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends ConsumerState<_PosterCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final displayPoster = widget.metadata.displayPosterUrl;
    final hasPoster = displayPoster != null && displayPoster.isNotEmpty;

    // 获取播放进度
    final progressAsync = ref.watch(allVideoProgressProvider);
    final progress = progressAsync.valueOrNull?[widget.metadata.filePath];
    final hasProgress = progress != null && progress.progressPercent > 0.02 && progress.progressPercent < 0.98;

    return Container(
      width: widget.width,
      margin: widget.width != null ? const EdgeInsets.only(right: 12) : null,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: Matrix4.identity()..scale(_isHovered ? 1.05 : 1.0),
            transformAlignment: Alignment.center,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 海报
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: _isHovered ? 0.4 : 0.25),
                          blurRadius: _isHovered ? 20 : 10,
                          offset: Offset(0, _isHovered ? 10 : 5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 海报图片
                          if (hasPoster)
                            AdaptiveImage(
                              imageUrl: displayPoster,
                              fit: BoxFit.cover,
                              placeholder: (_) => _buildPlaceholder(),
                              errorWidget: (_, __) => _buildPlaceholder(),
                            )
                          else
                            _buildPlaceholder(),

                          // 渐变遮罩
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 60,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.8),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // 播放进度条
                          if (hasProgress)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress.progressPercent.clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.only(
                                        bottomLeft: const Radius.circular(12),
                                        bottomRight: progress.progressPercent > 0.95
                                            ? const Radius.circular(12)
                                            : Radius.zero,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // 评分徽章
                          if (widget.metadata.rating != null &&
                              widget.metadata.rating! > 0)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _getRatingColor(),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      widget.metadata.ratingText,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // 剧集标记
                          if (widget.metadata.category == MediaCategory.tvShow)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.metadata.seasonNumber != null
                                      ? 'S${widget.metadata.seasonNumber}'
                                      : '剧集',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),

                          // 继续观看标记
                          if (hasProgress)
                            Positioned(
                              bottom: 10,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${(progress.progressPercent * 100).toInt()}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // 悬停边框
                          if (_isHovered)
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 标题
                const SizedBox(height: 8),
                Text(
                  widget.metadata.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark ? Colors.white : null,
                  ),
                ),
                // 年份
                if (widget.metadata.year != null)
                  Text(
                    '${widget.metadata.year}',
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() => Container(
      color: widget.isDark ? Colors.grey[850] : Colors.grey[200],
      child: Center(
        child: Icon(
          widget.metadata.category == MediaCategory.tvShow
              ? Icons.live_tv_rounded
              : Icons.movie_rounded,
          size: 40,
          color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );

  Color _getRatingColor() {
    final rating = widget.metadata.rating ?? 0;
    if (rating >= 8) return Colors.green;
    if (rating >= 6) return Colors.orange;
    return Colors.red;
  }
}

/// 分类行组件（Netflix 风格，带查看更多）
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.title,
    required this.items,
    required this.onItemTap,
    required this.isDark,
    this.icon,
    this.iconColor,
    this.maxCount = 10,
    this.onViewAll,
    this.useVerticalPosters = true,
  });

  final String title;
  final List<VideoMetadata> items;
  final void Function(VideoMetadata) onItemTap;
  final bool isDark;
  final IconData? icon;
  final Color? iconColor;
  final int maxCount;
  final VoidCallback? onViewAll;
  final bool useVerticalPosters;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final displayItems = items.take(maxCount).toList();
    // 始终显示"查看更多"卡片（只要有 onViewAll 回调）
    final showViewMore = onViewAll != null;
    final remainingCount = items.length > maxCount ? items.length - maxCount : 0;
    final effectiveIconColor = iconColor ?? AppColors.primary;

    // 根据海报类型计算高度
    // 纵向海报: 宽130 * 1.5 = 195 高度 + 标题区域约 40
    // 横向视频卡: 高度约 160
    final rowHeight = useVerticalPosters ? 240.0 : 160.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: effectiveIconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: effectiveIconColor),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              // 标题栏的"查看全部"按钮
              if (showViewMore)
                TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '查看全部 (${items.length})',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // 内容滚动区域
        SizedBox(
          height: rowHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: displayItems.length + (showViewMore ? 1 : 0),
            itemBuilder: (context, index) {
              // 最后一个是"查看更多"卡片
              if (showViewMore && index == displayItems.length) {
                return _ViewMoreCard(
                  onTap: onViewAll,
                  isDark: isDark,
                  useVerticalStyle: useVerticalPosters,
                  remainingCount: remainingCount,
                  totalCount: items.length,
                );
              }

              final metadata = displayItems[index];
              if (useVerticalPosters) {
                return _VerticalPosterCard(
                  metadata: metadata,
                  onTap: () => onItemTap(metadata),
                  isDark: isDark,
                );
              } else {
                return _HorizontalVideoCard(
                  metadata: metadata,
                  onTap: () => onItemTap(metadata),
                  isDark: isDark,
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

/// 查看更多卡片
class _ViewMoreCard extends StatefulWidget {
  const _ViewMoreCard({
    required this.onTap,
    required this.isDark,
    this.useVerticalStyle = true,
    this.remainingCount = 0,
    this.totalCount = 0,
  });

  final VoidCallback? onTap;
  final bool isDark;
  final bool useVerticalStyle;
  final int remainingCount;
  final int totalCount;

  @override
  State<_ViewMoreCard> createState() => _ViewMoreCardState();
}

class _ViewMoreCardState extends State<_ViewMoreCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // 与 _VerticalPosterCard 保持一致的尺寸
    // 纵向: 宽130, 海报高195 (2:3比例), 横向: 220x124
    const verticalWidth = 130.0;
    const verticalPosterHeight = 195.0; // 130 * 1.5
    const horizontalWidth = 220.0;
    const horizontalHeight = 124.0;

    final width = widget.useVerticalStyle ? verticalWidth : horizontalWidth;
    final posterHeight = widget.useVerticalStyle ? verticalPosterHeight : horizontalHeight;

    if (widget.useVerticalStyle) {
      // 纵向样式：与 _VerticalPosterCard 结构完全一致
      return Container(
        width: width,
        margin: const EdgeInsets.only(right: 12),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _isHovered ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 海报区域 - 与 _VerticalPosterCard 的海报容器保持一致
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: width,
                    height: posterHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _isHovered
                            ? [
                                AppColors.primary.withValues(alpha: 0.3),
                                AppColors.primary.withValues(alpha: 0.1),
                              ]
                            : [
                                widget.isDark ? Colors.grey[850]! : Colors.grey[200]!,
                                widget.isDark ? Colors.grey[900]! : Colors.grey[100]!,
                              ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isHovered
                            ? AppColors.primary
                            : (widget.isDark ? Colors.grey[700]! : Colors.grey[300]!),
                        width: _isHovered ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: _isHovered ? 0.4 : 0.2),
                          blurRadius: _isHovered ? 16 : 8,
                          offset: Offset(0, _isHovered ? 8 : 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 图标
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _isHovered
                                ? AppColors.primary.withValues(alpha: 0.2)
                                : (widget.isDark ? Colors.grey[800] : Colors.grey[300]),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.grid_view_rounded,
                            color: _isHovered
                                ? AppColors.primary
                                : (widget.isDark ? Colors.grey[400] : Colors.grey[600]),
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 文字
                        Text(
                          '查看全部',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _isHovered
                                ? AppColors.primary
                                : (widget.isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // 数量
                        Text(
                          widget.remainingCount > 0
                              ? '还有 ${widget.remainingCount} 部'
                              : '共 ${widget.totalCount} 部',
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 标题区域 - 与 _VerticalPosterCard 保持一致的间距
                  const SizedBox(height: 8),
                  Text(
                    '更多内容',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: widget.isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  // 副标题 - 与 _VerticalPosterCard 的年份行对应
                  Text(
                    '共 ${widget.totalCount} 部',
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 横向样式保持原有实现
    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isHovered ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: width,
              height: posterHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isHovered
                      ? [
                          AppColors.primary.withValues(alpha: 0.3),
                          AppColors.primary.withValues(alpha: 0.1),
                        ]
                      : [
                          widget.isDark ? Colors.grey[850]! : Colors.grey[200]!,
                          widget.isDark ? Colors.grey[900]! : Colors.grey[100]!,
                        ],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isHovered
                      ? AppColors.primary
                      : (widget.isDark ? Colors.grey[700]! : Colors.grey[300]!),
                  width: _isHovered ? 2 : 1,
                ),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 图标
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _isHovered
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : (widget.isDark ? Colors.grey[800] : Colors.grey[300]),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.grid_view_rounded,
                      color: _isHovered
                          ? AppColors.primary
                          : (widget.isDark ? Colors.grey[400] : Colors.grey[600]),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 文字
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '查看全部',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _isHovered
                              ? AppColors.primary
                              : (widget.isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.remainingCount > 0
                            ? '还有 ${widget.remainingCount} 部'
                            : '共 ${widget.totalCount} 部',
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 懒加载海报卡片包装器
///
/// 使用 AutomaticKeepAliveClientMixin 保持已加载的卡片状态，
/// 滚动回来时不需要重新加载图片
class _LazyPosterCard extends ConsumerStatefulWidget {
  const _LazyPosterCard({
    super.key,
    required this.metadata,
    required this.onTap,
    required this.isDark,
    this.width = 130,
  });

  final VideoMetadata metadata;
  final VoidCallback onTap;
  final bool isDark;
  final double width;

  @override
  ConsumerState<_LazyPosterCard> createState() => _LazyPosterCardState();
}

class _LazyPosterCardState extends ConsumerState<_LazyPosterCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return _VerticalPosterCard(
      metadata: widget.metadata,
      onTap: widget.onTap,
      isDark: widget.isDark,
      width: widget.width,
    );
  }
}

/// 纵向海报卡片（2:3 比例，Netflix 风格）
class _VerticalPosterCard extends ConsumerStatefulWidget {
  const _VerticalPosterCard({
    required this.metadata,
    required this.onTap,
    required this.isDark,
    this.width = 130,
  });

  final VideoMetadata metadata;
  final VoidCallback onTap;
  final bool isDark;
  final double width;

  @override
  ConsumerState<_VerticalPosterCard> createState() => _VerticalPosterCardState();
}

class _VerticalPosterCardState extends ConsumerState<_VerticalPosterCard> {
  bool _isHovered = false;

  // 缓存图片 URL 避免重复计算
  late final String? _posterUrl;
  late final bool _hasPoster;

  @override
  void initState() {
    super.initState();
    _posterUrl = widget.metadata.displayPosterUrl;
    _hasPoster = _posterUrl != null && _posterUrl!.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    // 获取播放进度
    final progressAsync = ref.watch(allVideoProgressProvider);
    final progress = progressAsync.valueOrNull?[widget.metadata.filePath];
    final hasProgress = progress != null && progress.progressPercent > 0.02 && progress.progressPercent < 0.98;

    // 2:3 海报比例
    final posterHeight = widget.width * 1.5;

    return Container(
      width: widget.width,
      margin: const EdgeInsets.only(right: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isHovered ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 海报图片容器
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: widget.width,
                  height: posterHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: _isHovered ? 0.4 : 0.2),
                        blurRadius: _isHovered ? 16 : 8,
                        offset: Offset(0, _isHovered ? 8 : 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 海报图片 - 使用 RepaintBoundary 防止重绘
                        RepaintBoundary(
                          child: _hasPoster
                              ? AdaptiveImage(
                                  key: ValueKey(_posterUrl),
                                  imageUrl: _posterUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (_) => _buildPlaceholder(),
                                  errorWidget: (_, __) => _buildPlaceholder(),
                                )
                              : _buildPlaceholder(),
                        ),

                        // 渐变遮罩（底部）- 静态，不需要重建
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              height: 60,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.7),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 播放进度条
                        if (hasProgress)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(8),
                                    bottomRight: Radius.circular(8),
                                  ),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress.progressPercent.clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.only(
                                        bottomLeft: const Radius.circular(8),
                                        bottomRight: progress.progressPercent > 0.95
                                            ? const Radius.circular(8)
                                            : Radius.zero,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // 评分徽章
                        if (widget.metadata.rating != null && widget.metadata.rating! > 0)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getRatingColor(),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, size: 10, color: Colors.white),
                                  const SizedBox(width: 2),
                                  Text(
                                    widget.metadata.ratingText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // 剧集标记
                        if (widget.metadata.category == MediaCategory.tvShow)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.metadata.seasonNumber != null
                                    ? 'S${widget.metadata.seasonNumber}'
                                    : '剧集',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                        // 继续观看标记
                        if (hasProgress)
                          Positioned(
                            bottom: 8,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.play_arrow_rounded, size: 10, color: Colors.white),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${(progress.progressPercent * 100).toInt()}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // 悬停边框 - 使用 AnimatedOpacity 避免重建
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _isHovered ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 150),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 标题
                const SizedBox(height: 8),
                Text(
                  widget.metadata.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
                // 年份
                if (widget.metadata.year != null)
                  Text(
                    '${widget.metadata.year}',
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() => Container(
      color: widget.isDark ? Colors.grey[850] : Colors.grey[200],
      child: Center(
        child: Icon(
          widget.metadata.category == MediaCategory.tvShow
              ? Icons.live_tv_rounded
              : Icons.movie_rounded,
          size: 40,
          color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );

  Color _getRatingColor() {
    final rating = widget.metadata.rating ?? 0;
    if (rating >= 8) return Colors.green;
    if (rating >= 6) return Colors.orange;
    return Colors.red;
  }
}

/// 横向视频卡片（适合视频缩略图 16:9）
class _HorizontalVideoCard extends ConsumerStatefulWidget {
  const _HorizontalVideoCard({
    required this.metadata,
    required this.onTap,
    required this.isDark,
  });

  final VideoMetadata metadata;
  final VoidCallback onTap;
  final bool isDark;

  @override
  ConsumerState<_HorizontalVideoCard> createState() => _HorizontalVideoCardState();
}

class _HorizontalVideoCardState extends ConsumerState<_HorizontalVideoCard> {
  bool _isHovered = false;

  // 缓存图片 URL 避免重复计算
  late final String? _posterUrl;
  late final bool _hasPoster;

  @override
  void initState() {
    super.initState();
    _posterUrl = widget.metadata.displayPosterUrl;
    _hasPoster = _posterUrl != null && _posterUrl!.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {

    // 获取播放进度
    final progressAsync = ref.watch(allVideoProgressProvider);
    final progress = progressAsync.valueOrNull?[widget.metadata.filePath];
    final hasProgress = progress != null && progress.progressPercent > 0.02 && progress.progressPercent < 0.98;

    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: Matrix4.identity()..scale(_isHovered ? 1.03 : 1.0),
            transformAlignment: Alignment.center,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 视频缩略图（16:9 比例）
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: _isHovered ? 0.35 : 0.2),
                          blurRadius: _isHovered ? 12 : 6,
                          offset: Offset(0, _isHovered ? 6 : 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 缩略图 - 使用 RepaintBoundary 防止重绘
                          RepaintBoundary(
                            child: _hasPoster
                                ? AdaptiveImage(
                                    key: ValueKey(_posterUrl),
                                    imageUrl: _posterUrl!,
                                    fit: BoxFit.cover,
                                    placeholder: (_) => _buildPlaceholder(),
                                    errorWidget: (_, __) => _buildPlaceholder(),
                                  )
                                : _buildPlaceholder(),
                          ),

                          // 渐变遮罩（底部）
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.7),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 播放进度条
                          if (hasProgress)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(10),
                                    bottomRight: Radius.circular(10),
                                  ),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress.progressPercent.clamp(0.0, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.only(
                                        bottomLeft: const Radius.circular(10),
                                        bottomRight: progress.progressPercent > 0.95
                                            ? const Radius.circular(10)
                                            : Radius.zero,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // 时长或进度标签
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                hasProgress
                                    ? '${(progress.progressPercent * 100).toInt()}%'
                                    : (widget.metadata.runtime != null
                                        ? '${widget.metadata.runtime}分钟'
                                        : ''),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),

                          // 评分徽章
                          if (widget.metadata.rating != null && widget.metadata.rating! > 0)
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getRatingColor(),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded, size: 10, color: Colors.white),
                                    const SizedBox(width: 2),
                                    Text(
                                      widget.metadata.ratingText,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // 剧集标记
                          if (widget.metadata.category == MediaCategory.tvShow)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.metadata.seasonNumber != null
                                      ? 'S${widget.metadata.seasonNumber}'
                                      : '剧集',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),

                          // 悬停边框 - 使用 AnimatedOpacity 避免重建
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: _isHovered ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 150),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppColors.primary, width: 2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 标题和年份
                const SizedBox(height: 6),
                Text(
                  widget.metadata.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark ? Colors.white : null,
                  ),
                ),
                if (widget.metadata.year != null)
                  Text(
                    '${widget.metadata.year}',
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() => Container(
      color: widget.isDark ? Colors.grey[850] : Colors.grey[200],
      child: Center(
        child: Icon(
          widget.metadata.category == MediaCategory.tvShow
              ? Icons.live_tv_rounded
              : Icons.movie_rounded,
          size: 36,
          color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );

  Color _getRatingColor() {
    final rating = widget.metadata.rating ?? 0;
    if (rating >= 8) return Colors.green;
    if (rating >= 6) return Colors.orange;
    return Colors.red;
  }
}

/// 排序方式枚举
enum _SortType {
  rating, // 按评分
  year, // 按年份
  name, // 按名称
  recent, // 按添加时间
}

/// 分类全部页面（带排序筛选）
class _CategoryFullPage extends ConsumerStatefulWidget {
  const _CategoryFullPage({
    required this.title,
    required this.items,
  });

  final String title;
  final List<VideoMetadata> items;

  @override
  ConsumerState<_CategoryFullPage> createState() => _CategoryFullPageState();
}

class _CategoryFullPageState extends ConsumerState<_CategoryFullPage> {
  _SortType _sortType = _SortType.rating;
  bool _sortDescending = true;
  String? _selectedGenre;
  List<String> _availableGenres = [];

  @override
  void initState() {
    super.initState();
    _extractGenres();
  }

  /// 提取所有可用的类型标签
  void _extractGenres() {
    final genreSet = <String>{};
    for (final item in widget.items) {
      if (item.genres != null && item.genres!.isNotEmpty) {
        // 分割类型字符串（可能是 "动作 / 科幻" 格式）
        final genres = item.genres!.split(RegExp(r'[/,、]'))
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty);
        genreSet.addAll(genres);
      }
    }
    _availableGenres = genreSet.toList()..sort();
  }

  /// 获取排序和筛选后的列表
  List<VideoMetadata> get _sortedAndFilteredItems {
    var result = widget.items.toList();

    // 筛选
    if (_selectedGenre != null) {
      result = result.where((item) {
        if (item.genres == null) return false;
        return item.genres!.contains(_selectedGenre!);
      }).toList();
    }

    // 排序
    result.sort((a, b) {
      int comparison;
      switch (_sortType) {
        case _SortType.rating:
          comparison = (a.rating ?? 0).compareTo(b.rating ?? 0);
        case _SortType.year:
          comparison = (a.year ?? 0).compareTo(b.year ?? 0);
        case _SortType.name:
          comparison = a.displayTitle.compareTo(b.displayTitle);
        case _SortType.recent:
          // 默认顺序就是最近添加
          comparison = 0;
      }
      return _sortDescending ? -comparison : comparison;
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 600;

    // 计算网格列数
    final crossAxisCount = (width / 160).floor().clamp(2, 8);
    final filteredItems = _sortedAndFilteredItems;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        actions: [
          // 排序按钮
          IconButton(
            icon: Icon(
              Icons.sort_rounded,
              color: isDark ? Colors.white : Colors.black87,
            ),
            onPressed: () => _showSortOptions(context, isDark),
            tooltip: '排序',
          ),
          // 筛选按钮（如果有类型可选）
          if (_availableGenres.isNotEmpty)
            IconButton(
              icon: Badge(
                isLabelVisible: _selectedGenre != null,
                child: Icon(
                  Icons.filter_list_rounded,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              onPressed: () => _showFilterOptions(context, isDark),
              tooltip: '筛选',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${filteredItems.length} 部',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 排序和筛选状态栏
          _buildStatusBar(isDark, isWide),
          // 内容区域
          Expanded(
            child: filteredItems.isEmpty
                ? _buildEmptyState(isDark)
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    // 限制预加载区域，减少内存占用和初始加载时间
                    cacheExtent: 200,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: 0.55,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 12,
                    ),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final metadata = filteredItems[index];
                      return _LazyPosterCard(
                        key: ValueKey(metadata.uniqueKey),
                        metadata: metadata,
                        onTap: () => _openVideoDetail(context, metadata),
                        isDark: isDark,
                        width: (width - 32 - (crossAxisCount - 1) * 12) / crossAxisCount,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 构建状态栏（仅在有筛选条件时显示）
  Widget _buildStatusBar(bool isDark, bool isWide) {
    // 只有在有筛选条件时才显示状态栏
    if (_selectedGenre == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.grey[100],
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '筛选: ',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          // 筛选标签
          _buildChip(
            label: _selectedGenre!,
            icon: Icons.local_movies_rounded,
            isDark: isDark,
            isActive: true,
            onTap: () => setState(() => _selectedGenre = null),
            onClose: () => setState(() => _selectedGenre = null),
          ),
        ],
      ),
    );
  }

  /// 构建标签
  Widget _buildChip({
    required String label,
    required IconData icon,
    required bool isDark,
    bool isActive = false,
    VoidCallback? onTap,
    VoidCallback? onClose,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.2)
              : (isDark ? Colors.grey[800] : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? AppColors.primary
                : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive
                  ? AppColors.primary
                  : (isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive
                    ? AppColors.primary
                    : (isDark ? Colors.grey[300] : Colors.grey[700]),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClose,
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 空状态
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.filter_list_off_rounded,
            size: 64,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '没有符合筛选条件的内容',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _selectedGenre = null),
            child: const Text('清除筛选'),
          ),
        ],
      ),
    );
  }

  /// 显示排序选项
  void _showSortOptions(BuildContext context, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽指示器
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[600] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '排序方式',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            // 排序选项
            _buildSortOption(
              context,
              icon: Icons.star_rounded,
              label: '按评分',
              type: _SortType.rating,
              isDark: isDark,
            ),
            _buildSortOption(
              context,
              icon: Icons.calendar_today_rounded,
              label: '按年份',
              type: _SortType.year,
              isDark: isDark,
            ),
            _buildSortOption(
              context,
              icon: Icons.sort_by_alpha_rounded,
              label: '按名称',
              type: _SortType.name,
              isDark: isDark,
            ),
            _buildSortOption(
              context,
              icon: Icons.schedule_rounded,
              label: '按添加时间',
              type: _SortType.recent,
              isDark: isDark,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 构建排序选项
  Widget _buildSortOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required _SortType type,
    required bool isDark,
  }) {
    final isSelected = _sortType == type;

    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? AppColors.primary : (isDark ? Colors.grey[400] : Colors.grey[600]),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? AppColors.primary : (isDark ? Colors.white : Colors.black87),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 升序/降序切换
                IconButton(
                  icon: Icon(
                    _sortDescending ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                    color: AppColors.primary,
                  ),
                  onPressed: () {
                    setState(() => _sortDescending = !_sortDescending);
                    Navigator.pop(context);
                  },
                ),
                Icon(Icons.check_rounded, color: AppColors.primary),
              ],
            )
          : null,
      onTap: () {
        setState(() {
          if (_sortType == type) {
            _sortDescending = !_sortDescending;
          } else {
            _sortType = type;
            _sortDescending = true;
          }
        });
        Navigator.pop(context);
      },
    );
  }

  /// 显示筛选选项
  void _showFilterOptions(BuildContext context, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => SafeArea(
          child: Column(
            children: [
              // 拖拽指示器
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[600] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      '按类型筛选',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedGenre != null)
                      TextButton(
                        onPressed: () {
                          setState(() => _selectedGenre = null);
                          Navigator.pop(context);
                        },
                        child: const Text('清除'),
                      ),
                  ],
                ),
              ),
              // 类型列表
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _availableGenres.length,
                  itemBuilder: (context, index) {
                    final genre = _availableGenres[index];
                    final isSelected = _selectedGenre == genre;
                    final count = widget.items.where((item) =>
                        item.genres?.contains(genre) ?? false).length;

                    return ListTile(
                      leading: Icon(
                        Icons.local_movies_rounded,
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                      title: Text(
                        genre,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.primary
                              : (isDark ? Colors.white : Colors.black87),
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[800] : Colors.grey[200],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check_rounded, color: AppColors.primary),
                          ],
                        ],
                      ),
                      onTap: () {
                        setState(() {
                          _selectedGenre = isSelected ? null : genre;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openVideoDetail(BuildContext context, VideoMetadata metadata) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoDetailPage(
          metadata: metadata,
          sourceId: metadata.sourceId,
        ),
      ),
    );
    ref.invalidate(continueWatchingProvider);
  }
}
