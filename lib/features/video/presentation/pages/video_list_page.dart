import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/data/services/video_library_cache_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/data/services/video_scanner_service.dart';
import 'package:my_nas/features/video/domain/entities/tv_show_group.dart';
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

/// 优化后的视频列表状态 - 使用分类数据而非全量内存加载
class VideoListLoaded extends VideoListState {
  VideoListLoaded({
    required this.totalCount,
    this.movieCount = 0,
    this.tvShowCount = 0,
    this.tvShowGroupCount = 0,
    this.currentTab = VideoTab.all,
    this.searchQuery = '',
    this.isLoadingMetadata = false,
    this.fromCache = false,
    // 分类数据 - 从 SQLite 分页加载
    this.topRatedMovies = const [],
    this.recentVideos = const [],
    this.movies = const [],
    this.tvShowGroups = const {},
    // 电影系列数据
    this.movieCollections = const [],
    // 搜索结果
    this.searchResults = const [],
    // 用于快速查找的 Map（O(1) 查找）
    this.videoByKey = const {},
  });

  final int totalCount;
  final int movieCount;
  /// 剧集集数（单集数量）
  final int tvShowCount;
  /// 剧集分组数量（不同电视剧数量）
  final int tvShowGroupCount;
  final VideoTab currentTab;
  final String searchQuery;
  final bool isLoadingMetadata;
  final bool fromCache;

  // 分类数据 - 已从 SQLite 按评分排序
  final List<VideoMetadata> topRatedMovies;
  final List<VideoMetadata> recentVideos;
  final List<VideoMetadata> movies;
  /// 剧集分组（使用 TvShowGroup 按季组织）
  final Map<String, TvShowGroup> tvShowGroups;
  /// 电影系列
  final List<MovieCollection> movieCollections;

  // 搜索结果
  final List<VideoMetadata> searchResults;

  // 用于 O(1) 查找的 Map
  final Map<String, VideoMetadata> videoByKey;

  /// 根据当前分类获取过滤后的数据
  List<VideoMetadata> get filteredMetadata {
    if (searchQuery.isNotEmpty) return searchResults;

    switch (currentTab) {
      case VideoTab.all:
        // 返回所有视频（合并电影和剧集代表）
        final allVideos = <VideoMetadata>[...movies];
        for (final group in tvShowGroups.values) {
          allVideos.add(group.representative);
        }
        allVideos.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
        return allVideos;
      case VideoTab.movies:
        return movies;
      case VideoTab.tvShows:
        // 返回每个剧集的代表（第一季第一集）
        return tvShowGroups.values.map((g) => g.representative).toList();
      case VideoTab.recent:
        return recentVideos;
    }
  }

  /// 获取剧集分组列表（用于展示剧集卡片）
  List<TvShowGroup> get tvShowGroupList => tvShowGroups.values.toList();

  VideoListLoaded copyWith({
    int? totalCount,
    int? movieCount,
    int? tvShowCount,
    int? tvShowGroupCount,
    VideoTab? currentTab,
    String? searchQuery,
    bool? isLoadingMetadata,
    bool? fromCache,
    List<VideoMetadata>? topRatedMovies,
    List<VideoMetadata>? recentVideos,
    List<VideoMetadata>? movies,
    Map<String, TvShowGroup>? tvShowGroups,
    List<MovieCollection>? movieCollections,
    List<VideoMetadata>? searchResults,
    Map<String, VideoMetadata>? videoByKey,
  }) =>
      VideoListLoaded(
        totalCount: totalCount ?? this.totalCount,
        movieCount: movieCount ?? this.movieCount,
        tvShowCount: tvShowCount ?? this.tvShowCount,
        tvShowGroupCount: tvShowGroupCount ?? this.tvShowGroupCount,
        currentTab: currentTab ?? this.currentTab,
        searchQuery: searchQuery ?? this.searchQuery,
        isLoadingMetadata: isLoadingMetadata ?? this.isLoadingMetadata,
        fromCache: fromCache ?? this.fromCache,
        topRatedMovies: topRatedMovies ?? this.topRatedMovies,
        recentVideos: recentVideos ?? this.recentVideos,
        movies: movies ?? this.movies,
        tvShowGroups: tvShowGroups ?? this.tvShowGroups,
        movieCollections: movieCollections ?? this.movieCollections,
        searchResults: searchResults ?? this.searchResults,
        videoByKey: videoByKey ?? this.videoByKey,
      );
}

class VideoListError extends VideoListState {
  VideoListError(this.message);
  final String message;
}

class VideoListNotifier extends StateNotifier<VideoListState> {
  VideoListNotifier(this._ref) : super(VideoListLoading()) {
    // 使用 addPostFrameCallback 推迟初始化，确保导航动画不被阻塞
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _init();
    });

    // 监听刮削统计变化，实现渐进式更新
    _scrapeStatsSubscription = VideoScannerService().scrapeStatsStream.listen(
      _onScrapeStatsChanged,
    );

    // 监听连接状态变化，当有新连接时检查恢复刮削
    _connectionsSubscription = _ref.listen<Map<String, SourceConnection>>(
      activeConnectionsProvider,
      _onConnectionsChanged,
      fireImmediately: false,
    );
  }

  final Ref _ref;
  final VideoMetadataService _metadataService = VideoMetadataService();
  final VideoLibraryCacheService _cacheService = VideoLibraryCacheService();
  final VideoDatabaseService _db = VideoDatabaseService();

  StreamSubscription<ScrapeStats>? _scrapeStatsSubscription;
  ProviderSubscription<Map<String, SourceConnection>>? _connectionsSubscription;
  int _lastCompletedCount = 0;
  bool _hasCheckedResume = false;

  /// 获取启用的路径列表（用于 SQLite 过滤）
  List<({String sourceId, String path})>? _getEnabledPaths() {
    final config = _ref.read(mediaLibraryConfigProvider).valueOrNull;
    if (config == null) return null;

    final enabledPaths = config.getEnabledPathsForType(MediaType.video);
    if (enabledPaths.isEmpty) return null;

    return enabledPaths
        .map((p) => (sourceId: p.sourceId, path: p.path))
        .toList();
  }

  @override
  void dispose() {
    _scrapeStatsSubscription?.cancel();
    _connectionsSubscription?.close();
    super.dispose();
  }

  /// 连接状态变化时检查是否需要恢复刮削
  void _onConnectionsChanged(
    Map<String, SourceConnection>? previous,
    Map<String, SourceConnection> next,
  ) {
    // 只在首次有连接成功时检查恢复刮削
    if (_hasCheckedResume) return;

    final hasConnected = next.values.any((c) => c.status == SourceStatus.connected);
    if (hasConnected) {
      _hasCheckedResume = true;
      logger.d('VideoListNotifier: 检测到连接成功，检查是否有待恢复的刮削任务');
      VideoScannerService().checkAndResumeScraping(next);
    }
  }

  /// 刮削统计变化时刷新数据
  void _onScrapeStatsChanged(ScrapeStats stats) {
    // 当刮削全部完成时，强制刷新
    if (stats.isAllDone && _lastCompletedCount > 0) {
      _lastCompletedCount = 0; // 重置计数器
      _loadCategorizedData(silent: true);
      return;
    }

    // 只有当有新的刮削完成时才刷新
    if (stats.completed > _lastCompletedCount) {
      _lastCompletedCount = stats.completed;
      // 每刮削完成 10 个视频刷新一次，避免频繁刷新
      // 使用 silent: true 避免页面闪烁
      if (stats.completed % 10 == 0 || stats.pending == 0) {
        _loadCategorizedData(silent: true);
      }
    }
  }

  void _init() {
    logger.d('VideoListNotifier: 开始初始化...');

    // 关键优化：立即显示空状态UI，让用户立即看到界面
    // 用户不会看到黑屏或loading状态
    state = VideoListLoaded(totalCount: 0);

    // 在后台初始化服务并加载数据，不阻塞UI
    unawaited(_initAndLoadInBackground());
  }

  /// 后台初始化服务并加载数据
  Future<void> _initAndLoadInBackground() async {
    try {
      // 快速初始化服务（SQLite和Hive都是本地操作，应该很快）
      // 使用较短的超时，避免异常情况下长时间等待
      await Future.wait([
        _metadataService.init(),
        _cacheService.init(),
      ]).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          logger.w('VideoListNotifier: 服务初始化超时');
          return <void>[];
        },
      );

      logger.d('VideoListNotifier: 服务初始化完成，加载SQLite数据');

      // 从 SQLite 加载分类数据
      // SQLite是本地数据库，查询应该非常快
      await _loadCategorizedData(silent: true);
    } on Exception catch (e) {
      logger.e('VideoListNotifier: 后台初始化失败', e);
      // 保持空列表状态，让用户可以正常使用界面
    }
  }

  /// 从 SQLite 加载分类数据（高性能）
  ///
  /// [silent] 为 true 时不显示加载状态，避免页面闪烁（用于刮削进度更新）
  Future<void> _loadCategorizedData({bool silent = false}) async {
    // 非静默模式才显示加载状态
    if (!silent) {
      state = VideoListLoading(fromCache: true);
    }

    // 获取启用的路径（用于过滤停用文件夹的视频）
    final enabledPaths = _getEnabledPaths();

    // 并行查询各分类数据（使用 SQLite 索引，O(log N) 复杂度）
    // 首页只加载少量数据用于展示，查看全部页面支持分页懒加载
    // SQLite是本地数据库，查询应该非常快（<1秒），使用3秒超时作为保护
    List<Object?> results;
    try {
      results = await Future.wait([
        _db.getStats(enabledPaths: enabledPaths),
        _db.getTvShowGroupCount(enabledPaths: enabledPaths),
        // 减少首页加载量，加快初始显示速度
        _db.getTopRated(limit: 30, enabledPaths: enabledPaths),
        _db.getRecentlyUpdated(limit: 20, enabledPaths: enabledPaths),
        _db.getByCategory(MediaCategory.movie, limit: 30, enabledPaths: enabledPaths),
        _db.getTvShowGroupRepresentatives(limit: 30, enabledPaths: enabledPaths),
        _db.getMovieCollections(),
      ]).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          logger.w('VideoListNotifier: 数据库查询超时，显示空列表');
          // 返回空结果，避免阻塞
          return [
            <String, dynamic>{'total': 0, 'movies': 0, 'tvShows': 0},
            0,
            <VideoMetadata>[],
            <VideoMetadata>[],
            <VideoMetadata>[],
            <VideoMetadata>[],
            <MovieCollection>[],
          ];
        },
      );
    } on Exception catch (e) {
      logger.e('VideoListNotifier: 数据库查询失败', e);
      // 查询失败时保持当前状态
      return;
    }

    // 安全地转换结果类型，处理可能的null值
    final stats = (results[0] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final tvShowGroupCount = (results[1] as int?) ?? 0;
    final topRatedRaw = (results[2] as List<VideoMetadata>?) ?? <VideoMetadata>[];
    final recentRaw = (results[3] as List<VideoMetadata>?) ?? <VideoMetadata>[];
    final moviesList = (results[4] as List<VideoMetadata>?) ?? <VideoMetadata>[];
    final tvShowRepresentatives = (results[5] as List<VideoMetadata>?) ?? <VideoMetadata>[];
    final movieCollections = (results[6] as List<MovieCollection>?) ?? <MovieCollection>[];

    // 首页剧集直接使用代表性数据，不需要再分组
    // 但为了兼容性，仍然构建 TvShowGroup（用于高分推荐和最近添加的去重）
    final tvShowGroups = <String, TvShowGroup>{};
    for (final rep in tvShowRepresentatives) {
      final groupKey = rep.tmdbId != null ? 'tmdb_${rep.tmdbId}' : 'title_${rep.title?.toLowerCase()}';
      tvShowGroups[groupKey] = TvShowGroup(
        groupKey: groupKey,
        title: rep.title ?? rep.fileName,
        tmdbId: rep.tmdbId,
        posterUrl: rep.posterUrl,
        backdropUrl: rep.backdropUrl,
        rating: rep.rating,
        overview: rep.overview,
        year: rep.year,
        genres: rep.genres,
        seasonEpisodes: {rep.seasonNumber ?? 1: [rep]},
      );
    }

    // 对高分推荐进行去重：电影直接使用，剧集使用 TvShowGroup 的信息
    final topRated = _buildTopRatedWithGroups(topRatedRaw, tvShowGroups);

    // 对最近添加进行去重
    final recent = _buildRecentWithGroups(recentRaw, tvShowGroups);

    // 构建快速查找 Map
    final videoByKey = <String, VideoMetadata>{};
    for (final m in moviesList) {
      videoByKey[m.uniqueKey] = m;
    }
    for (final m in tvShowRepresentatives) {
      videoByKey[m.uniqueKey] = m;
    }

    state = VideoListLoaded(
      totalCount: stats['total'] as int? ?? 0,
      movieCount: stats['movies'] as int? ?? 0,
      tvShowCount: stats['tvShows'] as int? ?? 0,
      tvShowGroupCount: tvShowGroupCount,
      topRatedMovies: topRated,
      recentVideos: recent,
      movies: moviesList,
      tvShowGroups: tvShowGroups,
      movieCollections: movieCollections,
      videoByKey: videoByKey,
      fromCache: true,
    );

    logger.i('''
      VideoListNotifier: 数据加载完成，
      总计 ${stats['total']} 个视频，
      电影 ${stats['movies']} 个（首页加载 ${moviesList.length}），
      剧集 $tvShowGroupCount 部（首页加载 ${tvShowRepresentatives.length} 部），
      电影系列 ${movieCollections.length} 个，
      高分推荐 ${topRated.length} 个，
      最近添加 ${recent.length} 个'
      '''
    );
  }

  /// 重新加载数据（扫描完成后调用）
  Future<void> reloadFromCache() async {
    await _loadCategorizedData();
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
      if (query.isEmpty) {
        state = current.copyWith(searchQuery: '', searchResults: []);
      } else {
        // 使用 SQLite 搜索（带索引）
        _performSearch(query, current);
      }
    }
  }

  /// 执行搜索（使用 SQLite LIKE 查询）
  Future<void> _performSearch(String query, VideoListLoaded current) async {
    state = current.copyWith(searchQuery: query, isLoadingMetadata: true);

    final results = await _db.search(query, limit: 100);

    final newState = state;
    if (newState is VideoListLoaded && newState.searchQuery == query) {
      state = newState.copyWith(
        searchResults: results,
        isLoadingMetadata: false,
      );
    }
  }

  /// 构建高分推荐列表，剧集使用 TvShowGroup 的完整信息
  ///
  /// 对于剧集，会使用 TvShowGroup 的海报、评分等信息替换单集信息
  List<VideoMetadata> _buildTopRatedWithGroups(
    List<VideoMetadata> videos,
    Map<String, TvShowGroup> tvShowGroups,
    {int limit = 20}
  ) {
    final result = <VideoMetadata>[];
    final seenTvShows = <String>{};

    for (final video in videos) {
      if (result.length >= limit) break;

      // 电影直接添加
      if (video.category == MediaCategory.movie) {
        result.add(video);
        continue;
      }

      // 剧集需要去重并使用分组信息
      final groupKey = _getTvShowGroupKey(video);
      if (seenTvShows.contains(groupKey)) {
        continue;
      }
      seenTvShows.add(groupKey);

      // 使用 TvShowGroup 的信息构建代表元数据
      final group = tvShowGroups[groupKey];
      if (group != null) {
        // 使用分组的海报、评分等信息
        result.add(_buildGroupRepresentative(group));
      } else {
        result.add(video);
      }
    }

    return result;
  }

  /// 构建最近添加列表，剧集使用 TvShowGroup 的完整信息
  List<VideoMetadata> _buildRecentWithGroups(
    List<VideoMetadata> videos,
    Map<String, TvShowGroup> tvShowGroups,
    {int limit = 20}
  ) {
    final result = <VideoMetadata>[];
    final seenTvShows = <String>{};

    for (final video in videos) {
      if (result.length >= limit) break;

      // 电影直接添加
      if (video.category == MediaCategory.movie) {
        result.add(video);
        continue;
      }

      // 剧集需要去重
      final groupKey = _getTvShowGroupKey(video);
      if (seenTvShows.contains(groupKey)) {
        continue;
      }
      seenTvShows.add(groupKey);

      // 使用 TvShowGroup 的信息
      final group = tvShowGroups[groupKey];
      if (group != null) {
        result.add(_buildGroupRepresentative(group));
      } else {
        result.add(video);
      }
    }

    return result;
  }

  /// 从 TvShowGroup 构建代表性的 VideoMetadata
  /// 使用分组的标题、海报、评分等信息
  VideoMetadata _buildGroupRepresentative(TvShowGroup group) {
    final rep = group.representative;
    return VideoMetadata(
      sourceId: rep.sourceId,
      filePath: rep.filePath,
      fileName: rep.fileName,
      category: MediaCategory.tvShow,
      scrapeStatus: rep.scrapeStatus,
      tmdbId: group.tmdbId ?? rep.tmdbId,
      title: group.title, // 使用分组标题
      originalTitle: rep.originalTitle,
      year: group.year ?? rep.year,
      overview: group.overview ?? rep.overview, // 使用分组简介
      posterUrl: group.displayPosterUrl, // 使用分组海报
      backdropUrl: group.backdropUrl ?? rep.backdropUrl,
      rating: group.rating ?? rep.rating, // 使用分组评分
      runtime: rep.runtime,
      genres: group.genres ?? rep.genres,
      director: rep.director,
      cast: rep.cast,
      seasonNumber: rep.seasonNumber,
      episodeNumber: rep.episodeNumber,
      episodeTitle: rep.episodeTitle,
      lastUpdated: rep.lastUpdated,
      thumbnailUrl: rep.thumbnailUrl,
      generatedThumbnailUrl: rep.generatedThumbnailUrl,
      fileSize: rep.fileSize,
      fileModifiedTime: rep.fileModifiedTime,
    );
  }

  /// 获取剧集的分组键
  String _getTvShowGroupKey(VideoMetadata video) {
    // 优先使用 tmdbId
    if (video.tmdbId != null) {
      return 'tmdb_${video.tmdbId}';
    }
    // 否则使用标准化标题
    return _normalizeTitle(video.title ?? video.fileName);
  }

  /// 标准化标题（移除季集信息）
  String _normalizeTitle(String title) {
    var normalized = title.toLowerCase().trim();
    // 移除季集标记
    normalized = normalized.replaceAll(
      RegExp(r'[第\s]*(\d+|[一二三四五六七八九十]+)[季部期]'),
      '',
    );
    normalized = normalized.replaceAll(
      RegExp(r'season\s*\d+', caseSensitive: false),
      '',
    );
    normalized = normalized.replaceAll(RegExp(r's\d+', caseSensitive: false), '');
    normalized = normalized.replaceAll(RegExp(r'[\(\[\s]\d{4}[\)\]\s]?'), '');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return 'title_$normalized';
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

  // 刮削进度状态
  StreamSubscription<ScrapeStats>? _scrapeSubscription;
  ScrapeStats? _scrapeStats;

  @override
  void initState() {
    super.initState();
    _initScrapeListener();
  }

  void _initScrapeListener() {
    _scrapeSubscription = VideoScannerService().scrapeStatsStream.listen((stats) {
      if (mounted) {
        setState(() => _scrapeStats = stats);
      }
    });

    // 初始检查刮削状态
    _checkInitialScrapeState();
  }

  Future<void> _checkInitialScrapeState() async {
    if (VideoScannerService().isScraping) {
      final stats = await VideoScannerService().getScrapeStats();
      if (mounted) {
        setState(() => _scrapeStats = stats);
      }
    }
  }

  @override
  void dispose() {
    _scrapeSubscription?.cancel();
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
              final VideoListLoaded loaded => loaded.totalCount == 0
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
  ) => DecoratedBox(
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
    final videoCount = state is VideoListLoaded ? state.totalCount : 0;
    final movieCount = state is VideoListLoaded ? state.movieCount : 0;
    final tvShowCount = state is VideoListLoaded ? state.tvShowGroups.length : 0;

    // 判断是否正在刮削
    final isScraping = _scrapeStats != null && !_scrapeStats!.isAllDone && _scrapeStats!.total > 0;

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
              if (videoCount > 0 || isScraping)
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
                    // 刮削进度指示器
                    if (isScraping) ...[
                      const SizedBox(width: 12),
                      _buildScrapeProgressChip(isDark),
                    ],
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

  /// 刮削进度标签
  Widget _buildScrapeProgressChip(bool isDark) {
    final stats = _scrapeStats!;
    final progress = stats.progress;
    final percentage = (progress * 100).toInt();

    return Tooltip(
      message: '刮削进度: ${stats.processed}/${stats.total}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2,
              backgroundColor: isDark ? Colors.grey[700] : Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$percentage%',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
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
    final cacheService = VideoLibraryCacheService();
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

    // 获取剧集分组列表
    final tvShowGroups = state.tvShowGroupList;

    // 获取电影系列
    final movieCollections = state.movieCollections;

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
              totalCount: state.movieCount,
              onViewAll: state.movieCount > 10
                  ? () => _showMoviesPage(context, ref, '电影')
                  : null,
            ),
          ),

        // 剧集（纵向海报，显示季集统计）
        if (tvShowGroups.isNotEmpty)
          SliverToBoxAdapter(
            child: _TvShowRow(
              title: '剧集',
              groups: tvShowGroups,
              onGroupTap: (group) => _openVideoDetail(context, ref, group.representative),
              isDark: isDark,
              icon: Icons.live_tv_rounded,
              iconColor: AppColors.accent,
              totalCount: state.tvShowGroupCount,
              onViewAll: state.tvShowGroupCount > 10
                  ? () => _showTvShowsFullPage(context, ref, '剧集')
                  : null,
            ),
          ),

        // 电影系列（横向卡片，显示系列中电影数量）
        if (movieCollections.isNotEmpty)
          SliverToBoxAdapter(
            child: _MovieCollectionRow(
              title: '电影系列',
              collections: movieCollections,
              onCollectionTap: (collection) => _showCollectionPage(context, ref, collection),
              isDark: isDark,
              icon: Icons.collections_bookmark_rounded,
              iconColor: Colors.purple,
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

  /// 获取最近添加的视频（使用 SQLite 预加载的数据）
  List<VideoMetadata> _getRecentVideos(VideoListLoaded state, {int? limit}) {
    final recentVideos = state.recentVideos;
    return limit != null ? recentVideos.take(limit).toList() : recentVideos;
  }

  /// 显示分类页面（旧版，用于最近添加等）
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

  /// 显示电影全部页面（支持分页懒加载）
  void _showMoviesPage(BuildContext context, WidgetRef ref, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _MoviesPaginatedPage(
          title: title,
        ),
      ),
    );
  }

  /// 显示剧集全部页面（支持分页懒加载）
  void _showTvShowsFullPage(BuildContext context, WidgetRef ref, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _TvShowsPaginatedPage(
          title: title,
        ),
      ),
    );
  }

  /// 显示电影系列详情页面
  void _showCollectionPage(BuildContext context, WidgetRef ref, MovieCollection collection) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _MovieCollectionPage(
          collection: collection,
          onMovieTap: (movie) => _openVideoDetail(context, ref, movie),
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
        thumbnailUrl: metadata.displayPosterUrl,
      );

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      ref.invalidate(continueWatchingProvider);
    } on Exception catch (e) {
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
      error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
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

  /// 获取可用的海报 URL - 优先使用历史记录中的 thumbnailUrl
  String? _getDisplayPosterUrl() {
    // 检查历史记录中的 thumbnailUrl 是否可用
    if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty) {
      if (AdaptiveImage.isSupportedUrl(item.thumbnailUrl!)) {
        return item.thumbnailUrl;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posterUrl = _getDisplayPosterUrl();

    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playVideo(context, ref),
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
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
                        child: posterUrl != null
                            ? AdaptiveImage(
                                imageUrl: posterUrl,
                                placeholder: (_) => _buildThumbnailPlaceholder(),
                                errorWidget: (_, _) => _buildThumbnailPlaceholder(),
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
  }

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
          child: DecoratedBox(
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
                  if (video.thumbnailUrl != null &&
                      AdaptiveImage.isSupportedUrl(video.thumbnailUrl!))
                    AdaptiveImage(
                      imageUrl: video.thumbnailUrl!,
                      placeholder: (_) => _buildPlaceholder(),
                      errorWidget: (_, _) => _buildPlaceholder(),
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
    required this.isDark, this.width,
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
            transform: Matrix4.identity()..scaleByDouble(_isHovered ? 1.05 : 1.0, _isHovered ? 1.05 : 1.0, 1, 1),
            transformAlignment: Alignment.center,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 海报
                Expanded(
                  child: DecoratedBox(
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
                              placeholder: (_) => _buildPlaceholder(),
                              errorWidget: (_, _) => _buildPlaceholder(),
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

                          // 刮削状态指示器
                          if (widget.metadata.isPendingScrape ||
                              widget.metadata.isScraping)
                            Positioned(
                              top: 8,
                              left: widget.metadata.category ==
                                      MediaCategory.tvShow
                                  ? 50
                                  : 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[800]!.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 8,
                                      height: 8,
                                      child: widget.metadata.isScraping
                                          ? const CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: Colors.white,
                                            )
                                          : Icon(
                                              Icons.hourglass_empty,
                                              size: 8,
                                              color: Colors.grey[400],
                                            ),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      widget.metadata.isScraping ? '刮削中' : '待刮削',
                                      style: TextStyle(
                                        color: Colors.grey[300],
                                        fontSize: 8,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
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
    this.totalCount,
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
  /// 实际总数量（用于显示在"查看全部"按钮上，如果不传则使用 items.length）
  final int? totalCount;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final displayItems = items.take(maxCount).toList();
    // 始终显示"查看更多"卡片（只要有 onViewAll 回调）
    final showViewMore = onViewAll != null;
    // 使用真实总数（如果提供），否则使用 items.length
    final actualTotalCount = totalCount ?? items.length;
    final remainingCount = actualTotalCount > maxCount ? actualTotalCount - maxCount : 0;
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
                        '查看全部 ($actualTotalCount)',
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
                                if (widget.isDark) Colors.grey[850]! else Colors.grey[200]!,
                                if (widget.isDark) Colors.grey[900]! else Colors.grey[100]!,
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
                          if (widget.isDark) Colors.grey[850]! else Colors.grey[200]!,
                          if (widget.isDark) Colors.grey[900]! else Colors.grey[100]!,
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
    required this.metadata, required this.onTap, required this.isDark, super.key,
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
  late String? _posterUrl;
  late bool _hasPoster;

  @override
  void initState() {
    super.initState();
    _updatePosterUrl();
  }

  @override
  void didUpdateWidget(covariant _VerticalPosterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 metadata 变化时更新海报 URL
    if (oldWidget.metadata.displayPosterUrl != widget.metadata.displayPosterUrl) {
      _updatePosterUrl();
    }
  }

  void _updatePosterUrl() {
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
                                  placeholder: (_) => _buildPlaceholder(),
                                  errorWidget: (_, _) => _buildPlaceholder(),
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
  late String? _posterUrl;
  late bool _hasPoster;

  @override
  void initState() {
    super.initState();
    _updatePosterUrl();
  }

  @override
  void didUpdateWidget(covariant _HorizontalVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata.displayPosterUrl != widget.metadata.displayPosterUrl) {
      _updatePosterUrl();
    }
  }

  void _updatePosterUrl() {
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
            transform: Matrix4.identity()..scaleByDouble(_isHovered ? 1.03 : 1.0, _isHovered ? 1.03 : 1.0, 1, 1),
            transformAlignment: Alignment.center,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 视频缩略图（16:9 比例）
                Expanded(
                  child: DecoratedBox(
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
                                    placeholder: (_) => _buildPlaceholder(),
                                    errorWidget: (_, _) => _buildPlaceholder(),
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
        final genres = item.genres!.split(RegExp('[/,、]'))
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
  }) => GestureDetector(
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

  /// 空状态
  Widget _buildEmptyState(bool isDark) => Center(
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

/// 剧集行组件（显示季集统计）
class _TvShowRow extends StatelessWidget {
  const _TvShowRow({
    required this.title,
    required this.groups,
    required this.onGroupTap,
    required this.isDark,
    this.icon,
    this.iconColor,
    this.maxCount = 10,
    this.onViewAll,
    this.totalCount,
  });

  final String title;
  final List<TvShowGroup> groups;
  final void Function(TvShowGroup) onGroupTap;
  final bool isDark;
  final IconData? icon;
  final Color? iconColor;
  final int maxCount;
  final VoidCallback? onViewAll;
  /// 实际总数量（用于显示在"查看全部"按钮上，如果不传则使用 groups.length）
  final int? totalCount;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();

    final displayGroups = groups.take(maxCount).toList();
    final showViewMore = onViewAll != null;
    // 使用真实总数（如果提供），否则使用 groups.length
    final actualTotalCount = totalCount ?? groups.length;
    final remainingCount = actualTotalCount > maxCount ? actualTotalCount - maxCount : 0;
    final effectiveIconColor = iconColor ?? AppColors.primary;

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
                        '查看全部 ($actualTotalCount)',
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
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: displayGroups.length + (showViewMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (showViewMore && index == displayGroups.length) {
                return _ViewMoreCard(
                  onTap: onViewAll,
                  isDark: isDark,
                  remainingCount: remainingCount,
                  totalCount: groups.length,
                );
              }

              final group = displayGroups[index];
              return _TvShowPosterCard(
                group: group,
                onTap: () => onGroupTap(group),
                isDark: isDark,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 剧集海报卡片（显示季数和集数）
class _TvShowPosterCard extends StatefulWidget {
  const _TvShowPosterCard({
    required this.group,
    required this.onTap,
    required this.isDark,
    this.width = 130,
  });

  final TvShowGroup group;
  final VoidCallback onTap;
  final bool isDark;
  final double width;

  @override
  State<_TvShowPosterCard> createState() => _TvShowPosterCardState();
}

class _TvShowPosterCardState extends State<_TvShowPosterCard> {
  bool _isHovered = false;

  late String? _posterUrl;
  late bool _hasPoster;

  @override
  void initState() {
    super.initState();
    _updatePosterUrl();
  }

  @override
  void didUpdateWidget(covariant _TvShowPosterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.displayPosterUrl != widget.group.displayPosterUrl) {
      _updatePosterUrl();
    }
  }

  void _updatePosterUrl() {
    _posterUrl = widget.group.displayPosterUrl;
    _hasPoster = _posterUrl != null && _posterUrl!.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
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
                        // 海报图片
                        RepaintBoundary(
                          child: _hasPoster
                              ? AdaptiveImage(
                                  key: ValueKey(_posterUrl),
                                  imageUrl: _posterUrl!,
                                  placeholder: (_) => _buildPlaceholder(),
                                  errorWidget: (_, _) => _buildPlaceholder(),
                                )
                              : _buildPlaceholder(),
                        ),

                        // 渐变遮罩
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

                        // 评分徽章
                        if (widget.group.rating != null && widget.group.rating! > 0)
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
                                    widget.group.rating!.toStringAsFixed(1),
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

                        // 季集统计徽章（左上角）
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getSeasonEpisodeText(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        // 悬停边框
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
                  widget.group.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
                // 年份和季集信息
                Text(
                  _getSubtitleText(),
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

  String _getSeasonEpisodeText() {
    final seasonCount = widget.group.seasonCount;
    final episodeCount = widget.group.episodeCount;

    if (seasonCount > 1) {
      return '$seasonCount季 $episodeCount集';
    } else if (seasonCount == 1) {
      return '$episodeCount集';
    } else {
      return '$episodeCount集';
    }
  }

  String _getSubtitleText() {
    final parts = <String>[];
    if (widget.group.year != null) {
      parts.add('${widget.group.year}');
    }

    final seasonCount = widget.group.seasonCount;
    final episodeCount = widget.group.episodeCount;
    if (seasonCount > 1) {
      parts.add('$seasonCount季');
    }
    parts.add('$episodeCount集');

    return parts.join(' · ');
  }

  Widget _buildPlaceholder() => Container(
      color: widget.isDark ? Colors.grey[850] : Colors.grey[200],
      child: Center(
        child: Icon(
          Icons.live_tv_rounded,
          size: 40,
          color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );

  Color _getRatingColor() {
    final rating = widget.group.rating ?? 0;
    if (rating >= 8) return Colors.green;
    if (rating >= 6) return Colors.orange;
    return Colors.red;
  }
}

/// 剧集列表全页面
class _TvShowsFullPage extends ConsumerStatefulWidget {
  const _TvShowsFullPage({
    required this.title,
    required this.groups,
  });

  final String title;
  final List<TvShowGroup> groups;

  @override
  ConsumerState<_TvShowsFullPage> createState() => _TvShowsFullPageState();
}

class _TvShowsFullPageState extends ConsumerState<_TvShowsFullPage> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          childAspectRatio: 0.55,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
        itemCount: widget.groups.length,
        itemBuilder: (context, index) {
          final group = widget.groups[index];
          return _TvShowPosterCard(
            group: group,
            onTap: () => _openVideoDetail(context, group.representative),
            isDark: isDark,
          );
        },
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
  }
}

/// 电影分页页面（支持懒加载和筛选）
class _MoviesPaginatedPage extends ConsumerStatefulWidget {
  const _MoviesPaginatedPage({
    required this.title,
  });

  final String title;

  @override
  ConsumerState<_MoviesPaginatedPage> createState() => _MoviesPaginatedPageState();
}

class _MoviesPaginatedPageState extends ConsumerState<_MoviesPaginatedPage> {
  final List<VideoMetadata> _movies = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  static const int _pageSize = 50;

  // 筛选相关
  List<String> _availableGenres = [];
  List<int> _availableYears = [];
  String? _selectedGenre;
  int? _selectedYear;
  int _filteredCount = 0;
  bool _isLoadingFilters = true;

  // 排序相关
  VideoSortOption _sortOption = VideoSortOption.ratingDesc;

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _loadMore();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    try {
      final db = VideoDatabaseService();
      final genres = await db.getAvailableGenres(category: MediaCategory.movie);
      final years = await db.getAvailableYears(category: MediaCategory.movie);
      final count = await db.getFilteredCount(category: MediaCategory.movie);

      if (mounted) {
        setState(() {
          _availableGenres = genres;
          _availableYears = years;
          _filteredCount = count;
          _isLoadingFilters = false;
        });
      }
    } on Exception catch (e) {
      logger.e('VideoListPage: 加载筛选失败', e);
      if (mounted) {
        setState(() => _isLoadingFilters = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final db = VideoDatabaseService();
      final newMovies = await db.getFiltered(
        category: MediaCategory.movie,
        genre: _selectedGenre,
        year: _selectedYear,
        sortOption: _sortOption,
        offset: _offset,
      );

      if (!mounted) return;

      setState(() {
        _movies.addAll(newMovies);
        _offset += newMovies.length;
        _hasMore = newMovies.length >= _pageSize;
        _isLoading = false;
      });
    } on Exception catch (e) {
      logger.e('VideoListPage: 加载更多失败', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetAndReload() async {
    if (!mounted) return;
    setState(() {
      _movies.clear();
      _offset = 0;
      _hasMore = true;
    });

    // 更新筛选后的数量
    try {
      final db = VideoDatabaseService();
      final count = await db.getFilteredCount(
        category: MediaCategory.movie,
        genre: _selectedGenre,
        year: _selectedYear,
      );
      if (mounted) {
        setState(() => _filteredCount = count);
      }
    } on Exception catch (e) {
      logger.e('VideoListPage: 更新筛选后数量失败', e);
      // 忽略错误
    }

    await _loadMore();
  }

  void _showFilterSheet(BuildContext context, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterBottomSheet(
        isDark: isDark,
        availableGenres: _availableGenres,
        availableYears: _availableYears,
        selectedGenre: _selectedGenre,
        selectedYear: _selectedYear,
        onApply: (genre, year) {
          Navigator.of(context).pop();
          if (genre != _selectedGenre || year != _selectedYear) {
            setState(() {
              _selectedGenre = genre;
              _selectedYear = year;
            });
            _resetAndReload();
          }
        },
      ),
    );
  }

  bool get _hasFilters => _selectedGenre != null || _selectedYear != null;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          '${widget.title} ($_filteredCount)',
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
            tooltip: '排序',
            onPressed: () => _showSortMenu(context, isDark),
          ),
          // 筛选按钮
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  Icons.filter_list_rounded,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: _isLoadingFilters ? null : () => _showFilterSheet(context, isDark),
              ),
              if (_hasFilters)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 筛选标签
          if (_hasFilters)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_selectedGenre != null)
                    _FilterChip(
                      label: _selectedGenre!,
                      onRemove: () {
                        setState(() => _selectedGenre = null);
                        _resetAndReload();
                      },
                      isDark: isDark,
                    ),
                  if (_selectedYear != null)
                    _FilterChip(
                      label: '$_selectedYear年',
                      onRemove: () {
                        setState(() => _selectedYear = null);
                        _resetAndReload();
                      },
                      isDark: isDark,
                    ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedGenre = null;
                        _selectedYear = null;
                      });
                      _resetAndReload();
                    },
                    child: Text(
                      '清除全部',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 排序标签（当前排序不是默认时显示）
          if (_sortOption != VideoSortOption.ratingDesc)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.sort_rounded,
                    size: 14,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '按${_sortOption.displayName}排序',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          // 内容区域
          Expanded(
            child: _movies.isEmpty && _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _movies.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.movie_filter_outlined,
                              size: 64,
                              color: isDark ? Colors.white30 : Colors.black26,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '没有找到匹配的电影',
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 150,
                          childAspectRatio: 0.55,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: _movies.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _movies.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          final movie = _movies[index];
                          return _VerticalPosterCard(
                            metadata: movie,
                            onTap: () => _openVideoDetail(context, movie),
                            isDark: isDark,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showSortMenu(BuildContext context, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
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
            const Divider(height: 1),
            ...VideoSortOption.values.map((option) {
              final isSelected = option == _sortOption;
              return ListTile(
                leading: Icon(
                  option.icon,
                  color: isSelected ? Colors.blue : (isDark ? Colors.white70 : Colors.black54),
                ),
                title: Text(
                  option.displayName,
                  style: TextStyle(
                    color: isSelected ? Colors.blue : (isDark ? Colors.white : Colors.black87),
                    fontWeight: isSelected ? FontWeight.bold : null,
                  ),
                ),
                trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
                onTap: () {
                  Navigator.of(context).pop();
                  if (option != _sortOption) {
                    setState(() => _sortOption = option);
                    _resetAndReload();
                  }
                },
              );
            }),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
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
  }
}

/// 筛选标签
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onRemove,
    required this.isDark,
  });

  final String label;
  final VoidCallback onRemove;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white24 : Colors.black12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 16,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
}

/// 筛选底部弹窗
class _FilterBottomSheet extends StatefulWidget {
  const _FilterBottomSheet({
    required this.isDark,
    required this.availableGenres,
    required this.availableYears,
    required this.selectedGenre,
    required this.selectedYear,
    required this.onApply,
  });

  final bool isDark;
  final List<String> availableGenres;
  final List<int> availableYears;
  final String? selectedGenre;
  final int? selectedYear;
  final void Function(String? genre, int? year) onApply;

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  late String? _genre;
  late int? _year;

  @override
  void initState() {
    super.initState();
    _genre = widget.selectedGenre;
    _year = widget.selectedYear;
  }

  @override
  Widget build(BuildContext context) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1A1A2E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动条
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: widget.isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '筛选',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _genre = null;
                      _year = null;
                    });
                  },
                  child: const Text('重置'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 筛选内容
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 类型筛选
                  Text(
                    '类型',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: widget.isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.availableGenres.map((genre) {
                      final isSelected = _genre == genre;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _genre = isSelected ? null : genre;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.blue
                                : widget.isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.blue
                                  : widget.isDark
                                      ? Colors.white24
                                      : Colors.black12,
                            ),
                          ),
                          child: Text(
                            genre,
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected
                                  ? Colors.white
                                  : widget.isDark
                                      ? Colors.white
                                      : Colors.black87,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  // 年份筛选
                  Text(
                    '年份',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: widget.isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.availableYears.map((year) {
                      final isSelected = _year == year;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _year = isSelected ? null : year;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.blue
                                : widget.isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.blue
                                  : widget.isDark
                                      ? Colors.white24
                                      : Colors.black12,
                            ),
                          ),
                          child: Text(
                            '$year',
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected
                                  ? Colors.white
                                  : widget.isDark
                                      ? Colors.white
                                      : Colors.black87,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          // 底部按钮
          Container(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: widget.isDark ? const Color(0xFF1A1A2E) : Colors.white,
              border: Border(
                top: BorderSide(
                  color: widget.isDark ? Colors.white12 : Colors.black12,
                ),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => widget.onApply(_genre, _year),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '应用筛选',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
}

/// 剧集分页页面（支持懒加载和筛选）
class _TvShowsPaginatedPage extends ConsumerStatefulWidget {
  const _TvShowsPaginatedPage({
    required this.title,
  });

  final String title;

  @override
  ConsumerState<_TvShowsPaginatedPage> createState() => _TvShowsPaginatedPageState();
}

class _TvShowsPaginatedPageState extends ConsumerState<_TvShowsPaginatedPage> {
  final List<VideoMetadata> _tvShows = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  static const int _pageSize = 50;

  // 筛选相关
  List<String> _availableGenres = [];
  List<int> _availableYears = [];
  String? _selectedGenre;
  int? _selectedYear;
  int _filteredCount = 0;
  bool _isLoadingFilters = true;

  // 排序相关
  VideoSortOption _sortOption = VideoSortOption.ratingDesc;

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _loadMore();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    try {
      final db = VideoDatabaseService();
      final genres = await db.getAvailableGenres(category: MediaCategory.tvShow);
      final years = await db.getAvailableYears(category: MediaCategory.tvShow);
      final count = await db.getTvShowGroupCount();

      if (mounted) {
        setState(() {
          _availableGenres = genres;
          _availableYears = years;
          _filteredCount = count;
          _isLoadingFilters = false;
        });
      }
    } on Exception catch (e) {
      logger.e('TvShowsPaginatedPage: 加载筛选失败', e);
      if (mounted) {
        setState(() => _isLoadingFilters = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final db = VideoDatabaseService();
      final newTvShows = await db.getTvShowGroupRepresentativesFiltered(
        genre: _selectedGenre,
        year: _selectedYear,
        sortOption: _sortOption,
        offset: _offset,
      );

      if (!mounted) return;

      setState(() {
        _tvShows.addAll(newTvShows);
        _offset += newTvShows.length;
        _hasMore = newTvShows.length >= _pageSize;
        _isLoading = false;
      });
    } on Exception catch (e) {
      logger.e('TvShowsPaginatedPage: 加载更多失败', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetAndReload() async {
    if (!mounted) return;
    setState(() {
      _tvShows.clear();
      _offset = 0;
      _hasMore = true;
    });

    // 更新筛选后的数量
    try {
      final db = VideoDatabaseService();
      final count = await db.getTvShowGroupCountFiltered(
        genre: _selectedGenre,
        year: _selectedYear,
      );
      if (mounted) {
        setState(() => _filteredCount = count);
      }
    } on Exception catch (e) {
      logger.w('TvShowsPaginatedPage: 更新筛选后数量失败', e);
      // 忽略错误
    }

    await _loadMore();
  }

  void _showFilterSheet(BuildContext context, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterBottomSheet(
        isDark: isDark,
        availableGenres: _availableGenres,
        availableYears: _availableYears,
        selectedGenre: _selectedGenre,
        selectedYear: _selectedYear,
        onApply: (genre, year) {
          Navigator.of(context).pop();
          if (genre != _selectedGenre || year != _selectedYear) {
            setState(() {
              _selectedGenre = genre;
              _selectedYear = year;
            });
            _resetAndReload();
          }
        },
      ),
    );
  }

  void _showSortMenu(BuildContext context, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
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
            const Divider(height: 1),
            ...VideoSortOption.values.map((option) {
              final isSelected = option == _sortOption;
              return ListTile(
                leading: Icon(
                  option.icon,
                  color: isSelected ? Colors.blue : (isDark ? Colors.white70 : Colors.black54),
                ),
                title: Text(
                  option.displayName,
                  style: TextStyle(
                    color: isSelected ? Colors.blue : (isDark ? Colors.white : Colors.black87),
                    fontWeight: isSelected ? FontWeight.bold : null,
                  ),
                ),
                trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
                onTap: () {
                  Navigator.of(context).pop();
                  if (option != _sortOption) {
                    setState(() => _sortOption = option);
                    _resetAndReload();
                  }
                },
              );
            }),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  bool get _hasFilters => _selectedGenre != null || _selectedYear != null;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          '${widget.title} ($_filteredCount)',
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
            tooltip: '排序',
            onPressed: () => _showSortMenu(context, isDark),
          ),
          // 筛选按钮
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  Icons.filter_list_rounded,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: _isLoadingFilters ? null : () => _showFilterSheet(context, isDark),
              ),
              if (_hasFilters)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 筛选标签
          if (_hasFilters)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_selectedGenre != null)
                    _FilterChip(
                      label: _selectedGenre!,
                      onRemove: () {
                        setState(() => _selectedGenre = null);
                        _resetAndReload();
                      },
                      isDark: isDark,
                    ),
                  if (_selectedYear != null)
                    _FilterChip(
                      label: '$_selectedYear年',
                      onRemove: () {
                        setState(() => _selectedYear = null);
                        _resetAndReload();
                      },
                      isDark: isDark,
                    ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedGenre = null;
                        _selectedYear = null;
                      });
                      _resetAndReload();
                    },
                    child: Text(
                      '清除全部',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 内容区域
          Expanded(
            child: _tvShows.isEmpty && _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _tvShows.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.live_tv_outlined,
                              size: 64,
                              color: isDark ? Colors.white30 : Colors.black26,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '没有找到匹配的剧集',
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 150,
                          childAspectRatio: 0.55,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: _tvShows.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _tvShows.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          final tvShow = _tvShows[index];
                          return _VerticalPosterCard(
                            metadata: tvShow,
                            onTap: () => _openVideoDetail(context, tvShow),
                            isDark: isDark,
                          );
                        },
                      ),
          ),
        ],
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
  }
}

/// 电影系列行组件
class _MovieCollectionRow extends StatelessWidget {
  const _MovieCollectionRow({
    required this.title,
    required this.collections,
    required this.onCollectionTap,
    required this.isDark,
    this.icon,
    this.iconColor,
    this.maxCount = 10,
  });

  final String title;
  final List<MovieCollection> collections;
  final void Function(MovieCollection) onCollectionTap;
  final bool isDark;
  final IconData? icon;
  final Color? iconColor;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    if (collections.isEmpty) return const SizedBox.shrink();

    final displayItems = collections.take(maxCount).toList();
    final effectiveIconColor = iconColor ?? AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
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
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${collections.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 系列列表
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: displayItems.length,
            itemBuilder: (context, index) {
              final collection = displayItems[index];
              return _MovieCollectionCard(
                collection: collection,
                onTap: () => onCollectionTap(collection),
                isDark: isDark,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 电影系列卡片
class _MovieCollectionCard extends StatefulWidget {
  const _MovieCollectionCard({
    required this.collection,
    required this.onTap,
    required this.isDark,
  });

  final MovieCollection collection;
  final VoidCallback onTap;
  final bool isDark;

  @override
  State<_MovieCollectionCard> createState() => _MovieCollectionCardState();
}

class _MovieCollectionCardState extends State<_MovieCollectionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    final posterUrl = collection.posterUrl;
    final hasPoster = posterUrl != null && posterUrl.isNotEmpty;

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: Matrix4.identity()..scaleByDouble(_isHovered ? 1.02 : 1.0, _isHovered ? 1.02 : 1.0, 1, 1),
            transformAlignment: Alignment.center,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _isHovered ? 0.3 : 0.15),
                    blurRadius: _isHovered ? 16 : 8,
                    offset: Offset(0, _isHovered ? 8 : 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 背景图 - 显示多张海报叠加效果
                    _buildCollectionPosters(hasPoster, posterUrl),
                    // 渐变遮罩
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                            Colors.black.withValues(alpha: 0.9),
                          ],
                          stops: const [0.3, 0.7, 1.0],
                        ),
                      ),
                    ),
                    // 内容
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 系列名称
                          Text(
                            collection.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // 电影数量
                          Row(
                            children: [
                              Icon(
                                Icons.movie_rounded,
                                size: 14,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${collection.movieCount} 部电影',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        ],
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
        ),
      ),
    );
  }

  Widget _buildCollectionPosters(bool hasPoster, String? posterUrl) {
    final movies = widget.collection.movies;

    // 如果只有一个电影或没有海报，显示单张
    if (movies.length == 1 || !hasPoster) {
      if (hasPoster) {
        return AdaptiveImage(
          imageUrl: posterUrl!,
          placeholder: (_) => _buildPlaceholder(),
          errorWidget: (_, _) => _buildPlaceholder(),
        );
      }
      return _buildPlaceholder();
    }

    // 显示多张海报叠加效果（最多3张）
    final showPosters = movies.take(3).toList();
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景 - 最后一张（稍微右移和缩小）
        if (showPosters.length >= 3 && showPosters[2].posterUrl != null)
          Positioned(
            left: 20,
            right: -10,
            top: 5,
            bottom: 5,
            child: Transform.scale(
              scale: 0.85,
              child: Opacity(
                opacity: 0.4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AdaptiveImage(
                    imageUrl: showPosters[2].posterUrl!,
                  ),
                ),
              ),
            ),
          ),
        // 中间层
        if (showPosters.length >= 2 && showPosters[1].posterUrl != null)
          Positioned(
            left: 10,
            right: 0,
            top: 3,
            bottom: 3,
            child: Transform.scale(
              scale: 0.92,
              child: Opacity(
                opacity: 0.6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AdaptiveImage(
                    imageUrl: showPosters[1].posterUrl!,
                  ),
                ),
              ),
            ),
          ),
        // 前景 - 第一张
        if (showPosters.isNotEmpty && showPosters[0].posterUrl != null)
          AdaptiveImage(
            imageUrl: showPosters[0].posterUrl!,
            placeholder: (_) => _buildPlaceholder(),
            errorWidget: (_, _) => _buildPlaceholder(),
          ),
      ],
    );
  }

  Widget _buildPlaceholder() => Container(
      color: widget.isDark ? Colors.grey[850] : Colors.grey[200],
      child: Center(
        child: Icon(
          Icons.collections_bookmark_rounded,
          size: 40,
          color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );
}

/// 电影系列详情页面
class _MovieCollectionPage extends ConsumerWidget {
  const _MovieCollectionPage({
    required this.collection,
    required this.onMovieTap,
  });

  final MovieCollection collection;
  final void Function(VideoMetadata) onMovieTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final movies = collection.movies;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D1A) : Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // 顶部 AppBar 带背景图
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: isDark ? const Color(0xFF0D0D1A) : Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                collection.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: collection.backdropUrl != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        AdaptiveImage(
                          imageUrl: collection.backdropUrl!,
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                (isDark ? const Color(0xFF0D0D1A) : Colors.white).withValues(alpha: 0.8),
                                if (isDark) const Color(0xFF0D0D1A) else Colors.white,
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
          // 电影数量标签
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.movie_rounded,
                    size: 20,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${movies.length} 部电影',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 电影列表
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.55,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final movie = movies[index];
                  return _VerticalPosterCard(
                    metadata: movie,
                    onTap: () => onMovieTap(movie),
                    isDark: isDark,
                  );
                },
                childCount: movies.length,
              ),
            ),
          ),
          // 底部留白
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
    );
  }
}
