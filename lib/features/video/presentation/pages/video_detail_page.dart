import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/data/services/video_favorites_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_page.dart';
import 'package:my_nas/features/video/presentation/providers/video_detail_provider.dart';
import 'package:my_nas/features/video/presentation/providers/video_favorites_provider.dart';
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/cast_section.dart';
import 'package:my_nas/features/video/presentation/widgets/detail_hero_section.dart';
import 'package:my_nas/features/video/presentation/widgets/episode_selector.dart';
import 'package:my_nas/features/video/presentation/widgets/recommendations_section.dart';

/// 视频详情页面
class VideoDetailPage extends ConsumerStatefulWidget {
  const VideoDetailPage({
    required this.metadata,
    required this.sourceId,
    super.key,
  });

  final VideoMetadata metadata;
  final String sourceId;

  @override
  ConsumerState<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends ConsumerState<VideoDetailPage> {
  bool _isPlaying = false;

  bool get _isTvShow => widget.metadata.category == MediaCategory.tvShow;
  bool get _hasTmdbId => widget.metadata.tmdbId != null && widget.metadata.tmdbId! > 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 800;

    // 获取播放进度
    final progressAsync = ref.watch(videoProgressProvider(widget.metadata.filePath));
    final watchProgress = progressAsync.whenOrNull(data: (p) => p?.progressPercent);

    // 获取收藏状态
    final isFavoriteAsync = ref.watch(isFavoriteProvider(widget.metadata.filePath));
    final isFavorite = isFavoriteAsync.valueOrNull ?? false;

    // 获取已观看状态
    final isWatchedAsync = ref.watch(isWatchedProvider(widget.metadata.filePath));
    final isWatched = isWatchedAsync.valueOrNull ?? false;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[100],
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Hero 区域
              SliverToBoxAdapter(
                child: _buildHeroSection(
                  isDark,
                  watchProgress: watchProgress,
                  isFavorite: isFavorite,
                  isWatched: isWatched,
                ),
              ),

              // 内容区域
              SliverToBoxAdapter(
                child: _buildMainContent(context, isDark, isWide),
              ),
            ],
          ),

          // 返回按钮
          _buildBackButton(context, isDark),
        ],
      ),
    );
  }

  Widget _buildHeroSection(
    bool isDark, {
    double? watchProgress,
    bool isFavorite = false,
    bool isWatched = false,
  }) {
    // 获取 TMDB 详情以获取 tagline、评分等
    String? tagline;
    String? overview;
    double? tmdbRating;
    int? voteCount;
    var backdropUrl = widget.metadata.backdropUrl;

    if (_hasTmdbId) {
      if (_isTvShow) {
        final _ = ref.watch(tvDetailProvider(widget.metadata.tmdbId!))
        ..whenData((detail) {
          if (detail != null) {
            tagline = detail.tagline;
            overview = detail.overview;
            tmdbRating = detail.voteAverage;
            voteCount = detail.voteCount;
            backdropUrl ??= detail.backdropUrl;
          }
        });
      } else {
        final _ = ref.watch(movieDetailProvider(widget.metadata.tmdbId!))
        ..whenData((detail) {
          if (detail != null) {
            tagline = detail.tagline;
            overview = detail.overview;
            tmdbRating = detail.voteAverage;
            voteCount = detail.voteCount;
            backdropUrl ??= detail.backdropUrl;
          }
        });
      }
    }

    // 使用 metadata 的简介作为后备
    overview ??= widget.metadata.overview;

    return DetailHeroSection(
      metadata: widget.metadata,
      onPlay: _isPlaying ? () {} : _playVideo,
      onFavorite: _toggleFavorite,
      onToggleWatched: _toggleWatched,
      isFavorite: isFavorite,
      isWatched: isWatched,
      watchProgress: watchProgress,
      backdropUrl: backdropUrl,
      tagline: tagline,
      overview: overview,
      tmdbRating: tmdbRating,
      voteCount: voteCount,
    );
  }

  Widget _buildMainContent(BuildContext context, bool isDark, bool isWide) => Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 24 : 0,
        vertical: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 剧集选择器 (仅电视剧且有 TMDB ID)
          if (_isTvShow && _hasTmdbId) ...[
            _buildEpisodeSection(),
            const SizedBox(height: 24),
          ],

          // 注意：简介已移至 Banner 区域，不再单独显示

          // 演员阵容 (需要 TMDB ID)
          if (_hasTmdbId) ...[
            _buildCastSection(),
          ],

          // 电影系列 (仅电影且有 TMDB ID)
          if (!_isTvShow && _hasTmdbId) ...[
            const SizedBox(height: 24),
            _buildMovieCollectionSection(isDark),
          ],

          // 注意：详细信息已移至 Banner 区域的元数据标签中

          // 推荐内容 (需要 TMDB ID)
          if (_hasTmdbId) ...[
            const SizedBox(height: 24),
            _buildRecommendationsSection(),
          ],

          // 文件信息
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildFileInfoSection(isDark),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );

  Widget _buildEpisodeSection() {
    final tvDetailAsync = ref.watch(tvDetailProvider(widget.metadata.tmdbId!));
    final localEpisodesAsync = ref.watch(localEpisodeFilesProvider(widget.metadata.tmdbId!));
    final allProgressAsync = ref.watch(allVideoProgressProvider);

    return tvDetailAsync.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (tvDetail) {
        if (tvDetail == null || tvDetail.seasons.isEmpty) {
          return const SizedBox.shrink();
        }

        final localEpisodes = localEpisodesAsync.valueOrNull ?? {};
        final allProgress = allProgressAsync.valueOrNull ?? {};

        // 将进度转换为 Map<filePath, double>
        final episodeProgress = <String, double>{};
        for (final entry in allProgress.entries) {
          episodeProgress[entry.key] = entry.value.progressPercent;
        }

        return EpisodeSelector(
          tvId: widget.metadata.tmdbId!,
          seasons: tvDetail.seasons,
          initialSeason: widget.metadata.seasonNumber,
          localEpisodes: localEpisodes,
          episodeProgress: episodeProgress,
          onEpisodePlay: _playEpisode,
        );
      },
    );
  }

  Widget _buildCastSection() {
    if (_isTvShow) {
      final tvDetailAsync = ref.watch(tvDetailProvider(widget.metadata.tmdbId!));
      return tvDetailAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (tvDetail) {
          if (tvDetail == null || tvDetail.cast.isEmpty) {
            return const SizedBox.shrink();
          }
          return CastAndCrewSection(
            cast: tvDetail.cast,
            crew: tvDetail.crew,
          );
        },
      );
    } else {
      final movieDetailAsync = ref.watch(movieDetailProvider(widget.metadata.tmdbId!));
      return movieDetailAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (movieDetail) {
          if (movieDetail == null || movieDetail.cast.isEmpty) {
            return const SizedBox.shrink();
          }
          return CastAndCrewSection(
            cast: movieDetail.cast,
            crew: movieDetail.crew,
          );
        },
      );
    }
  }

  /// 电影系列/合集区域
  Widget _buildMovieCollectionSection(bool isDark) {
    final movieDetailAsync = ref.watch(movieDetailProvider(widget.metadata.tmdbId!));

    return movieDetailAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (movieDetail) {
        if (movieDetail == null || movieDetail.belongsToCollection == null) {
          return const SizedBox.shrink();
        }

        final collectionInfo = movieDetail.belongsToCollection!;
        final collectionAsync = ref.watch(movieCollectionProvider(collectionInfo.id));

        return collectionAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  collectionInfo.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                ),
                const SizedBox(height: 12),
                const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (collection) {
            if (collection == null || collection.parts.isEmpty) {
              return const SizedBox.shrink();
            }

            final sortedParts = collection.sortedParts;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '共 ${sortedParts.length} 部电影',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: sortedParts.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final part = sortedParts[index];
                        final isCurrentMovie = part.id == widget.metadata.tmdbId;

                        return _buildCollectionMovieCard(
                          part,
                          isDark,
                          isCurrentMovie: isCurrentMovie,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCollectionMovieCard(
    TmdbCollectionPart part,
    bool isDark, {
    bool isCurrentMovie = false,
  }) => GestureDetector(
      onTap: isCurrentMovie ? null : () => _onCollectionMovieTap(part),
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: isCurrentMovie
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 海报
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (part.posterUrl.isNotEmpty) Image.network(
                            part.posterUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _buildPosterPlaceholder(isDark),
                          ) else _buildPosterPlaceholder(isDark),
                    // 当前电影标识
                    if (isCurrentMovie)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '当前',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    // 评分
                    if (part.voteAverage > 0)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 12,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                part.ratingText,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
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
            const SizedBox(height: 6),
            // 标题
            Text(
              part.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
            // 年份
            if (part.year != null)
              Text(
                '${part.year}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );

  Widget _buildPosterPlaceholder(bool isDark) => Container(
      color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[300],
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          size: 40,
          color: isDark ? Colors.grey[600] : Colors.grey[500],
        ),
      ),
    );

  void _onCollectionMovieTap(TmdbCollectionPart part) {
    // TODO: 检查本地是否有该电影，如果有则跳转到详情页
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${part.title} (${part.year ?? "未知年份"})'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
          ),
        ],
      ),
    );

  Widget _buildRecommendationsSection() => CombinedRecommendationsSection(
      tmdbId: widget.metadata.tmdbId!,
      isMovie: !_isTvShow,
      onItemTap: _onRecommendationTap,
    );

  Widget _buildFileInfoSection(bool isDark) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkOutline : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '文件信息',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
          const SizedBox(height: 12),
          _buildInfoRow('文件名', widget.metadata.fileName, isDark),
          _buildInfoRow('路径', widget.metadata.filePath, isDark),
          _buildInfoRow('来源', widget.sourceId, isDark),
        ],
      ),
    );

  Widget _buildBackButton(BuildContext context, bool isDark) => Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: GestureDetector(
          onLongPress: () {
            // 长按：返回到视频库主页（弹出所有详情页）
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: '返回（长按返回主页）',
          ),
        ),
      ),
    );

  Future<void> _toggleFavorite() async {
    final favoritesNotifier = ref.read(favoritesProvider.notifier);
    final item = VideoFavoriteItem(
      videoPath: widget.metadata.filePath,
      videoName: widget.metadata.displayTitle,
      videoUrl: '', // URL 将在播放时获取
      thumbnailUrl: widget.metadata.displayPosterUrl,
      addedAt: DateTime.now(),
    );
    await favoritesNotifier.toggleFavorite(item);
  }

  Future<void> _toggleWatched() async {
    await toggleWatchedStatus(ref, widget.metadata.filePath);
  }

  Future<void> _playVideo() async {
    setState(() => _isPlaying = true);

    try {
      final videoInfo = await _getVideoInfo(widget.metadata.filePath);
      if (videoInfo == null) return;

      if (!mounted) return;

      final videoItem = VideoItem(
        name: widget.metadata.displayTitle,
        path: widget.metadata.filePath,
        url: videoInfo.url,
        sourceId: widget.sourceId,
        size: videoInfo.size,
        thumbnailUrl: widget.metadata.displayPosterUrl,
      );

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      // 刷新播放历史
      ref..invalidate(continueWatchingProvider)
      ..invalidate(videoProgressProvider(widget.metadata.filePath));
    } finally {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    }
  }

  Future<void> _playEpisode(TmdbEpisode episode, VideoMetadata? localFile) async {
    if (localFile == null) return;

    setState(() => _isPlaying = true);

    try {
      final videoInfo = await _getVideoInfo(localFile.filePath);
      if (videoInfo == null) return;

      if (!mounted) return;

      final videoItem = VideoItem(
        name: '${localFile.displayTitle} - ${episode.name}',
        path: localFile.filePath,
        url: videoInfo.url,
        sourceId: widget.sourceId,
        size: videoInfo.size,
        thumbnailUrl: episode.stillUrl.isNotEmpty ? episode.stillUrl : localFile.displayPosterUrl,
      );

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      // 刷新播放历史
      ref..invalidate(continueWatchingProvider)
      ..invalidate(allVideoProgressProvider);
    } finally {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    }
  }

  /// 获取视频信息（URL 和文件大小）
  Future<_VideoPlayInfo?> _getVideoInfo(String filePath) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[widget.sourceId];

    if (connection == null || connection.status != SourceStatus.connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: Colors.white),
                SizedBox(width: 12),
                Text('未连接到 NAS，请先在设置中连接'),
              ],
            ),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    }

    try {
      final fileSystem = connection.adapter.fileSystem;

      // 获取文件信息以获得大小
      final fileInfo = await fileSystem.getFileInfo(filePath);
      final url = await fileSystem.getFileUrl(filePath);

      return _VideoPlayInfo(url: url, size: fileInfo.size);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('获取视频信息失败: $e')),
              ],
            ),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _onRecommendationTap(TmdbMediaItem item) async {
    // 检查本地是否有该影片
    final metadataService = ref.read(videoMetadataServiceProvider);
    await metadataService.init();
    final localVideo = await metadataService.getFirstByTmdbId(item.id);

    if (!mounted) return;

    if (localVideo != null) {
      // 本地有该影片，跳转到详情页
      // 使用 pushReplacement 避免详情页嵌套过深
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => VideoDetailPage(
            metadata: localVideo,
            sourceId: localVideo.sourceId,
          ),
        ),
      );
    } else {
      // 本地没有该影片，显示提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('本地未找到 "${item.title}" (${item.year ?? "未知年份"})'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

/// 视频播放信息
class _VideoPlayInfo {
  const _VideoPlayInfo({
    required this.url,
    required this.size,
  });

  final String url;
  final int size;
}
