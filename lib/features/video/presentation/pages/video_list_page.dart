import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
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
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/animated_list_item.dart';
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
    StateNotifierProvider<VideoListNotifier, VideoListState>((ref) {
  return VideoListNotifier(ref);
});

/// 视频分类标签
enum VideoTab { all, movies, tvShows, recent }

sealed class VideoListState {}

class VideoListLoading extends VideoListState {
  VideoListLoading({this.progress = 0, this.currentFolder, this.fromCache = false});
  final double progress;
  final String? currentFolder;
  final bool fromCache;
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
  List<VideoMetadata> get topRatedMovies {
    return movies
        .where((m) => (m.rating ?? 0) >= 7)
        .toList()
      ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
  }

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
  VideoListNotifier(this._ref) : super(VideoListLoading()) {
    _init();
  }

  final Ref _ref;
  final VideoMetadataService _metadataService = VideoMetadataService.instance;
  final VideoLibraryCacheService _cacheService = VideoLibraryCacheService.instance;

  Future<void> _init() async {
    try {
      await _metadataService.init();
      await _cacheService.init();

      // 立即尝试从缓存加载，不等待连接
      await _loadFromCacheImmediately();

      // 监听连接状态变化，当有新连接时自动刷新
      _ref.listen<Map<String, SourceConnection>>(activeConnectionsProvider, (previous, next) {
        final prevConnected = previous?.values.where((c) => c.status == SourceStatus.connected).length ?? 0;
        final nextConnected = next.values.where((c) => c.status == SourceStatus.connected).length;

        // 当连接数增加时，自动刷新视频列表
        if (nextConnected > prevConnected) {
          final currentState = state;
          // 如果当前是空列表或者是从缓存加载的，尝试重新扫描
          if (currentState is VideoListLoaded &&
              (currentState.videos.isEmpty || currentState.fromCache)) {
            logger.i('VideoListNotifier: 检测到新连接，自动刷新视频列表');
            loadVideos();
          }
        }
      });
    } catch (e) {
      logger.e('VideoListNotifier: 初始化失败', e);
      // 初始化失败，显示空列表
      state = VideoListLoaded(videos: [], fromCache: false);
    }
  }

  /// 立即从缓存加载视频数据，不检查连接状态
  Future<void> _loadFromCacheImmediately() async {
    final cache = _cacheService.getCache();
    if (cache != null && cache.videos.isNotEmpty) {
      state = VideoListLoading(fromCache: true, currentFolder: '加载缓存...');

      final videos = cache.videos.map((entry) {
        return VideoFileWithSource(
          file: FileItem(
            name: entry.fileName,
            path: entry.filePath,
            size: entry.size,
            isDirectory: false,
            modifiedTime: entry.modifiedTime,
            thumbnailUrl: entry.thumbnailUrl,
          ),
          sourceId: entry.sourceId,
        );
      }).toList();

      // 加载缓存的元数据
      final metadataMap = <String, VideoMetadata>{};
      for (final video in videos) {
        final cached = _metadataService.getCached(video.sourceId, video.path);
        if (cached != null) {
          metadataMap[cached.uniqueKey] = cached;
        }
      }

      state = VideoListLoaded(
        videos: videos,
        metadataMap: metadataMap,
        fromCache: true,
      );

      // 后台加载缺失的元数据
      _loadMissingMetadata(videos);

      logger.i('从缓存加载了 ${videos.length} 个视频');
    } else {
      // 没有缓存，显示空状态并提示用户刷新
      state = VideoListLoaded(videos: [], fromCache: true);
    }
  }

  /// 加载视频（优先使用缓存）
  Future<void> loadVideos({bool forceRefresh = false, int maxDepth = 3}) async {
    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    // 等待配置加载
    MediaLibraryConfig? config = configAsync.valueOrNull;
    if (config == null) {
      state = VideoListLoading(currentFolder: '正在加载配置...');
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final updated = _ref.read(mediaLibraryConfigProvider);
        config = updated.valueOrNull;
        if (config != null) break;
        if (updated.hasError) {
          state = VideoListError('加载媒体库配置失败');
          return;
        }
      }
      if (config == null) {
        state = VideoListLoaded(videos: []);
        return;
      }
    }

    final videoPaths = config.getEnabledPathsForType(MediaType.video);
    if (videoPaths.isEmpty) {
      state = VideoListLoaded(videos: []);
      return;
    }

    final connectedPaths = videoPaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      // 没有已连接的源，保持当前缓存状态并提示
      logger.w('没有已连接的源，无法扫描视频');
      // 保持当前状态，如果是空的则显示空列表
      if (state is! VideoListLoaded || (state as VideoListLoaded).videos.isEmpty) {
        state = VideoListLoaded(videos: [], fromCache: true);
      }
      return;
    }

    final sourceIds = connectedPaths.map((p) => p.sourceId).toList();

    // 尝试使用缓存
    if (!forceRefresh && _cacheService.isCacheValid(sourceIds)) {
      final cache = _cacheService.getCache();
      if (cache != null) {
        state = VideoListLoading(fromCache: true, currentFolder: '加载缓存...');

        final videos = cache.videos.map((entry) {
          return VideoFileWithSource(
            file: FileItem(
              name: entry.fileName,
              path: entry.filePath,
              size: entry.size,
              isDirectory: false,
              modifiedTime: entry.modifiedTime,
              thumbnailUrl: entry.thumbnailUrl,
            ),
            sourceId: entry.sourceId,
          );
        }).toList();

        // 加载缓存的元数据
        final metadataMap = <String, VideoMetadata>{};
        for (final video in videos) {
          final cached = _metadataService.getCached(video.sourceId, video.path);
          if (cached != null) {
            metadataMap[cached.uniqueKey] = cached;
          }
        }

        state = VideoListLoaded(
          videos: videos,
          metadataMap: metadataMap,
          fromCache: true,
        );

        // 后台加载缺失的元数据
        _loadMissingMetadata(videos);

        logger.i('从缓存加载了 ${videos.length} 个视频');
        return;
      }
    }

    // 扫描文件系统
    state = VideoListLoading();
    final videos = <VideoFileWithSource>[];
    var scannedFolders = 0;
    final totalFolders = connectedPaths.length;

    for (final mediaPath in connectedPaths) {
      final connection = connections[mediaPath.sourceId];
      if (connection == null) continue;

      state = VideoListLoading(
        progress: scannedFolders / totalFolders,
        currentFolder: mediaPath.displayName,
      );

      try {
        await _scanFolderRecursively(
          connection.adapter.fileSystem,
          mediaPath.path,
          videos,
          sourceId: mediaPath.sourceId,
          currentDepth: 0,
          maxDepth: maxDepth,
        );
      } on Exception catch (e) {
        logger.w('扫描文件夹失败: ${mediaPath.path} - $e');
      }

      scannedFolders++;
    }

    logger.i('视频扫描完成，共找到 ${videos.length} 个视频');

    // 保存到缓存
    final cacheEntries = videos.map((v) => v.toCacheEntry()).toList();
    await _cacheService.saveCache(VideoLibraryCache(
      videos: cacheEntries,
      lastUpdated: DateTime.now(),
      sourceIds: sourceIds,
    ));

    // 加载元数据
    final metadataMap = <String, VideoMetadata>{};
    for (final video in videos) {
      final cached = _metadataService.getCached(video.sourceId, video.path);
      if (cached != null) {
        metadataMap[cached.uniqueKey] = cached;
      }
    }

    state = VideoListLoaded(videos: videos, metadataMap: metadataMap);

    // 后台加载缺失的元数据
    _loadMissingMetadata(videos);
  }

  Future<void> _scanFolderRecursively(
    NasFileSystem fileSystem,
    String path,
    List<VideoFileWithSource> videos, {
    required String sourceId,
    required int currentDepth,
    required int maxDepth,
  }) async {
    if (currentDepth > maxDepth) return;

    try {
      final files = await fileSystem.listDirectory(path);

      for (final file in files) {
        if (file.type == FileType.video) {
          videos.add(VideoFileWithSource(file: file, sourceId: sourceId));
        } else if (file.isDirectory && currentDepth < maxDepth) {
          if (file.name.startsWith('.') ||
              file.name.startsWith('@') ||
              file.name == '#recycle') {
            continue;
          }

          await _scanFolderRecursively(
            fileSystem,
            file.path,
            videos,
            sourceId: sourceId,
            currentDepth: currentDepth + 1,
            maxDepth: maxDepth,
          );
        }
      }
    } on Exception catch (e) {
      logger.w('扫描子文件夹失败: $path - $e');
    }
  }

  Future<void> _loadMissingMetadata(List<VideoFileWithSource> videos) async {
    final current = state;
    if (current is! VideoListLoaded) return;

    final missingVideos = videos.where((v) {
      final key = '${v.sourceId}_${v.path}';
      return !current.metadataMap.containsKey(key);
    }).toList();

    if (missingVideos.isEmpty) return;

    state = current.copyWith(isLoadingMetadata: true, metadataProgress: 0);

    final updatedMap = Map<String, VideoMetadata>.from(current.metadataMap);
    final total = missingVideos.length;

    for (var i = 0; i < missingVideos.length; i++) {
      final video = missingVideos[i];

      try {
        final metadata = await _metadataService.getOrFetch(
          sourceId: video.sourceId,
          filePath: video.path,
          fileName: video.name,
        );
        updatedMap[metadata.uniqueKey] = metadata;

        if ((i + 1) % 5 == 0 || i == missingVideos.length - 1) {
          final currentState = state;
          if (currentState is VideoListLoaded) {
            state = currentState.copyWith(
              metadataMap: Map.from(updatedMap),
              metadataProgress: (i + 1) / total,
            );
          }
        }
      } on Exception catch (e) {
        logger.w('获取元数据失败: ${video.name} - $e');
      }

      if (i < missingVideos.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    final finalState = state;
    if (finalState is VideoListLoaded) {
      state = finalState.copyWith(isLoadingMetadata: false);
    }
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

  /// 强制刷新（从源重新扫描）
  Future<void> forceRefresh() async {
    await _cacheService.clearCache();
    await loadVideos(forceRefresh: true);
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : null,
      body: switch (state) {
        VideoListLoading(:final progress, :final currentFolder, :final fromCache) =>
          _buildLoadingState(progress, currentFolder, fromCache, isDark),
        VideoListError(:final message) => AppErrorWidget(
            message: message,
            onRetry: () => ref.read(videoListProvider.notifier).loadVideos(),
          ),
        VideoListLoaded loaded => loaded.videos.isEmpty
            ? _buildEmptyState(context, ref, loaded, isDark)
            : _buildNetflixStyleContent(context, ref, loaded, isDark),
      },
    );
  }

  Widget _buildLoadingState(
    double progress,
    String? currentFolder,
    bool fromCache,
    bool isDark,
  ) {
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

  Widget _buildNetflixStyleContent(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) {
    return CustomScrollView(
      slivers: [
        // 顶部导航栏
        _buildAppBar(context, ref, state, isDark),

        // 继续观看
        _ContinueWatchingSection(isDark: isDark),

        // 分类标签
        SliverToBoxAdapter(
          child: _buildTabBar(context, ref, state, isDark),
        ),

        // 元数据加载进度
        if (state.isLoadingMetadata)
          SliverToBoxAdapter(
            child: _buildMetadataProgress(state, isDark),
          ),

        // 内容区域
        ..._buildContentSections(context, ref, state, isDark),

        // 底部留白
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) {
    return SliverAppBar(
      floating: true,
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.white,
      elevation: 0,
      title: _showSearch
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '搜索视频...',
                hintStyle: TextStyle(color: isDark ? Colors.grey[500] : null),
                border: InputBorder.none,
              ),
              style: TextStyle(color: isDark ? Colors.white : null),
              onChanged: (v) =>
                  ref.read(videoListProvider.notifier).setSearchQuery(v),
            )
          : Row(
              children: [
                Text(
                  '视频库',
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : null,
                  ),
                ),
                if (state.fromCache)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '缓存',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
      actions: [
        IconButton(
          onPressed: () {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchController.clear();
                ref.read(videoListProvider.notifier).setSearchQuery('');
              }
            });
          },
          icon: Icon(
            _showSearch ? Icons.close : Icons.search_rounded,
            color: isDark ? Colors.white : null,
          ),
        ),
        IconButton(
          onPressed: () => ref.read(videoListProvider.notifier).forceRefresh(),
          icon: Icon(
            Icons.refresh_rounded,
            color: isDark ? Colors.white : null,
          ),
          tooltip: '刷新',
        ),
      ],
    );
  }

  Widget _buildTabBar(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: VideoTab.values.map((tab) {
          final isSelected = state.currentTab == tab;
          final label = switch (tab) {
            VideoTab.all => '全部',
            VideoTab.movies => '电影',
            VideoTab.tvShows => '剧集',
            VideoTab.recent => '最近',
          };

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => ref.read(videoListProvider.notifier).setTab(tab),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? Colors.grey[800] : Colors.grey[200]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.grey[300] : Colors.grey[700]),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMetadataProgress(VideoListLoaded state, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: state.metadataProgress > 0 ? state.metadataProgress : null,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '正在获取影片信息... ${(state.metadataProgress * 100).toInt()}%',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildContentSections(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) {
    if (state.searchQuery.isNotEmpty) {
      // 搜索结果
      return [
        _buildPosterGrid(
          context,
          ref,
          state.filteredMetadata,
          '搜索结果',
          isDark,
        ),
      ];
    }

    switch (state.currentTab) {
      case VideoTab.all:
        return _buildAllContent(context, ref, state, isDark);
      case VideoTab.movies:
        return [
          _buildPosterGrid(context, ref, state.movies, '电影', isDark),
        ];
      case VideoTab.tvShows:
        return _buildTvShowsContent(context, ref, state, isDark);
      case VideoTab.recent:
        return [
          _buildPosterGrid(context, ref, state.filteredMetadata, '最近添加', isDark),
        ];
    }
  }

  List<Widget> _buildAllContent(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) {
    final sections = <Widget>[];

    // 高分推荐
    final topRated = state.topRatedMovies.take(10).toList();
    if (topRated.isNotEmpty) {
      sections.add(_buildHorizontalSection(
        context,
        ref,
        topRated,
        '高分推荐',
        Icons.star_rounded,
        Colors.amber,
        isDark,
      ));
    }

    // 电影
    final movies = state.movies.take(15).toList();
    if (movies.isNotEmpty) {
      sections.add(_buildHorizontalSection(
        context,
        ref,
        movies,
        '电影',
        Icons.movie_rounded,
        AppColors.primary,
        isDark,
      ));
    }

    // 剧集
    final tvShowGroups = state.tvShowGroups;
    if (tvShowGroups.isNotEmpty) {
      final tvShows = tvShowGroups.entries
          .map((e) => e.value.first)
          .take(15)
          .toList();
      sections.add(_buildHorizontalSection(
        context,
        ref,
        tvShows,
        '剧集',
        Icons.live_tv_rounded,
        AppColors.accent,
        isDark,
      ));
    }

    return sections;
  }

  List<Widget> _buildTvShowsContent(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) {
    final sections = <Widget>[];
    final tvShowGroups = state.tvShowGroups;

    // 按剧集分组展示
    for (final entry in tvShowGroups.entries.take(10)) {
      sections.add(_buildHorizontalSection(
        context,
        ref,
        entry.value,
        entry.key,
        Icons.live_tv_rounded,
        AppColors.accent,
        isDark,
        showSeeAll: entry.value.length > 6,
      ));
    }

    return sections;
  }

  Widget _buildHorizontalSection(
    BuildContext context,
    WidgetRef ref,
    List<VideoMetadata> items,
    String title,
    IconData icon,
    Color iconColor,
    bool isDark, {
    bool showSeeAll = false,
  }) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : null,
                  ),
                ),
                const Spacer(),
                if (showSeeAll)
                  TextButton(
                    onPressed: () {},
                    child: Text(
                      '查看全部',
                      style: TextStyle(color: AppColors.primary, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
          // 海报横向滚动
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final metadata = items[index];
                return AnimatedListItem(
                  index: index,
                  slideOffset: 0,
                  delay: const Duration(milliseconds: 40),
                  child: _PosterCard(
                    metadata: metadata,
                    onTap: () => _openVideoDetail(context, ref, metadata),
                    isDark: isDark,
                    width: 120,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPosterGrid(
    BuildContext context,
    WidgetRef ref,
    List<VideoMetadata> items,
    String title,
    bool isDark,
  ) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 1200 ? 7 : width > 900 ? 6 : width > 600 ? 5 : 3;

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.65,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final metadata = items[index];
            return AnimatedGridItem(
              index: index,
              delay: const Duration(milliseconds: 30),
              child: _PosterCard(
                metadata: metadata,
                onTap: () => _openVideoDetail(context, ref, metadata),
                isDark: isDark,
              ),
            );
          },
          childCount: items.length,
        ),
      ),
    );
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
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
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
                        child: Container(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_rounded,
                              size: 40,
                              color: Colors.white54,
                            ),
                          ),
                        ),
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
      size: item.size,
      thumbnailUrl: item.thumbnailUrl,
      lastPosition: item.lastPosition,
    );

    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoPlayerPage(video: videoItem),
      ),
    );

    ref.invalidate(continueWatchingProvider);
  }
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
                            CachedNetworkImage(
                              imageUrl: displayPoster,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _buildPlaceholder(),
                              errorWidget: (_, __, ___) => _buildPlaceholder(),
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

  Widget _buildPlaceholder() {
    return Container(
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
  }

  Color _getRatingColor() {
    final rating = widget.metadata.rating ?? 0;
    if (rating >= 8) return Colors.green;
    if (rating >= 6) return Colors.orange;
    return Colors.red;
  }
}

/// 缓存信息条
class _CacheInfoBar extends ConsumerWidget {
  const _CacheInfoBar({
    required this.state,
    required this.isDark,
  });

  final VideoListLoaded state;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheService = VideoLibraryCacheService.instance;
    final cache = cacheService.getCache();

    if (cache == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final videoCount = state.videos.length;
    final movieCount = state.movies.length;
    final tvShowCount = state.tvShowGroups.length;

    // 计算缓存时间
    final cacheAge = DateTime.now().difference(cache.lastUpdated);
    final ageText = cacheAge.inHours < 1
        ? '${cacheAge.inMinutes} 分钟前'
        : cacheAge.inHours < 24
            ? '${cacheAge.inHours} 小时前'
            : '${cacheAge.inDays} 天前';

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // 视频统计
            _buildStatItem(
              icon: Icons.video_library_rounded,
              label: '视频',
              count: videoCount,
              color: AppColors.primary,
            ),
            const SizedBox(width: 16),
            _buildStatItem(
              icon: Icons.movie_rounded,
              label: '电影',
              count: movieCount,
              color: Colors.orange,
            ),
            const SizedBox(width: 16),
            _buildStatItem(
              icon: Icons.live_tv_rounded,
              label: '剧集',
              count: tvShowCount,
              color: AppColors.accent,
            ),
            const Spacer(),
            // 更新时间
            Row(
              children: [
                Icon(
                  Icons.update_rounded,
                  size: 14,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  ageText,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            // 刷新按钮
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => ref.read(videoListProvider.notifier).forceRefresh(),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.grey[500] : Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
