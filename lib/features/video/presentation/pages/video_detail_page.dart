import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/data/services/video_favorites_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/domain/utils/video_localization.dart';
import 'package:my_nas/features/video/presentation/pages/manual_scraper_page.dart';
import 'package:my_nas/features/video/presentation/pages/tmdb_preview_page.dart';
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
  /// 当前选中的视频版本（用于质量切换）
  late VideoMetadata _selectedMetadata;

  @override
  void initState() {
    super.initState();
    _selectedMetadata = widget.metadata;
  }

  bool get _isTvShow => _selectedMetadata.category == MediaCategory.tvShow;
  bool get _hasTmdbId => _selectedMetadata.tmdbId != null && _selectedMetadata.tmdbId! > 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 800;

    // 获取播放进度
    final progressAsync = ref.watch(videoProgressProvider(_selectedMetadata.filePath));
    final watchProgress = progressAsync.whenOrNull(data: (p) => p?.progressPercent);

    // 获取收藏状态
    final isFavoriteAsync = ref.watch(isFavoriteProvider(_selectedMetadata.filePath));
    final isFavorite = isFavoriteAsync.valueOrNull ?? false;

    // 获取已观看状态
    final isWatchedAsync = ref.watch(isWatchedProvider(_selectedMetadata.filePath));
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

    // 获取本地化标题
    final titleGetter = ref.watch(videoTitleGetterProvider);
    final localizedTitle = titleGetter(_selectedMetadata);

    // 获取本地化简介（如果没有从 TMDB 获取到的话）
    if (overview == null || overview!.isEmpty) {
      final overviewGetter = ref.watch(videoOverviewGetterProvider);
      overview = overviewGetter(_selectedMetadata);
    }

    return DetailHeroSection(
      metadata: _selectedMetadata,
      onPlay: _isPlaying ? () {} : _playVideo,
      onFavorite: _toggleFavorite,
      onToggleWatched: _toggleWatched,
      onScrape: _openManualScraper,
      isFavorite: isFavorite,
      isWatched: isWatched,
      watchProgress: watchProgress,
      backdropUrl: backdropUrl,
      tagline: tagline,
      displayTitle: localizedTitle,
      overview: overview,
      tmdbRating: tmdbRating,
      voteCount: voteCount,
      sourceId: widget.sourceId,
      // 电视剧详情页隐藏季集信息，因为这是剧的总览页，不是单集页
      // 无论是否有 TMDB，只要是电视剧且有 showDirectory，都隐藏
      hideEpisodeInfo: _isTvShow && (_hasTmdbId || _selectedMetadata.showDirectory != null),
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
          // 剧集选择器 (电视剧)
          if (_isTvShow) ...[
            if (_hasTmdbId)
              _buildEpisodeSection()
            else
              _buildLocalEpisodeSection(),
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

  /// 构建本地剧集选择器（无 TMDB 数据时使用）
  Widget _buildLocalEpisodeSection() {
    final showDirectory = _selectedMetadata.showDirectory;
    if (showDirectory == null || showDirectory.isEmpty) {
      return const SizedBox.shrink();
    }

    final localEpisodesAsync = ref.watch(localEpisodesByShowDirProvider(showDirectory));
    final allProgressAsync = ref.watch(allVideoProgressProvider);

    return localEpisodesAsync.when(
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (episodes) {
        if (episodes.isEmpty) {
          return const SizedBox.shrink();
        }

        final allProgress = allProgressAsync.valueOrNull ?? {};

        // 将进度转换为 Map<filePath, double>
        final episodeProgress = <String, double>{};
        for (final entry in allProgress.entries) {
          episodeProgress[entry.key] = entry.value.progressPercent;
        }

        return LocalEpisodeSelector(
          episodes: episodes,
          initialSeason: _selectedMetadata.seasonNumber,
          episodeProgress: episodeProgress,
          onEpisodePlay: _playLocalEpisode,
        );
      },
    );
  }

  /// 播放本地剧集（无 TMDB 数据）
  Future<void> _playLocalEpisode(VideoMetadata episode) async {
    setState(() => _isPlaying = true);

    try {
      final videoInfo = await _getVideoInfo(episode.filePath);
      if (videoInfo == null) return;

      if (!mounted) return;

      final videoItem = VideoItem(
        name: episode.displayTitle,
        path: episode.filePath,
        url: videoInfo.url,
        sourceId: widget.sourceId,
        size: videoInfo.size,
        thumbnailUrl: episode.displayPosterUrl,
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
                  // 标题行：系列名称 + 查看全部
                  Row(
                    children: [
                      Expanded(
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
                          ],
                        ),
                      ),
                      // 查看全部按钮
                      TextButton.icon(
                        onPressed: () => _openMovieCollectionPage(
                          collection,
                          widget.metadata.tmdbId!,
                          isDark,
                        ),
                        icon: Icon(
                          Icons.grid_view_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        label: Text(
                          '查看全部',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
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

  /// 打开电影系列完整列表页面
  void _openMovieCollectionPage(
    TmdbCollection collection,
    int currentMovieId,
    bool isDark,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MovieCollectionListPage(
          collection: collection,
          currentMovieId: currentMovieId,
          sourceId: widget.sourceId,
        ),
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

  Widget _buildFileInfoSection(bool isDark) {
    // 电视剧：显示剧集统计信息
    if (_isTvShow && _hasTmdbId) {
      return _buildTvShowFileInfo(isDark);
    }

    // 电视剧（无 TMDB）：显示基于 showDirectory 的剧集统计
    if (_isTvShow && _selectedMetadata.showDirectory != null) {
      return _buildLocalTvShowFileInfo(isDark);
    }

    // 电影：显示单个文件信息 + 质量选择器
    return Container(
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
          Row(
            children: [
              Text(
                '文件信息',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
              const Spacer(),
              // 质量选择器（仅电影）
              _buildQualitySelector(isDark),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('文件名', _selectedMetadata.fileName, isDark),
          _buildInfoRow('路径', _selectedMetadata.filePath, isDark),
          _buildInfoRow('来源', widget.sourceId, isDark),
          if (_selectedMetadata.resolution != null)
            _buildInfoRow('分辨率', _selectedMetadata.resolution!, isDark),
          if (_selectedMetadata.fileSizeText.isNotEmpty)
            _buildInfoRow('文件大小', _selectedMetadata.fileSizeText, isDark),
        ],
      ),
    );
  }

  /// 电视剧文件信息统计
  Widget _buildTvShowFileInfo(bool isDark) {
    final episodesAsync = ref.watch(relatedLocalVideosProvider(_selectedMetadata.tmdbId!));

    return Container(
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
            '本地剧集',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
          const SizedBox(height: 12),
          episodesAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, _) => Text(
              '加载失败',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
            data: (episodes) {
              if (episodes.isEmpty) {
                return Text(
                  '无本地剧集',
                  style: TextStyle(
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                );
              }

              // 统计信息
              final totalSize = episodes.fold<int>(0, (sum, e) => sum + (e.fileSize ?? 0));
              final totalSizeText = _formatFileSize(totalSize);
              final seasonNumbers = episodes
                  .where((e) => e.seasonNumber != null)
                  .map((e) => e.seasonNumber!)
                  .toSet()
                  .toList()
                ..sort();
              final showDirectory = episodes.first.showDirectory ?? '';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('剧集数量', '${episodes.length} 集', isDark),
                  if (seasonNumbers.isNotEmpty)
                    _buildInfoRow(
                      '季数',
                      seasonNumbers.length == 1
                          ? '第 ${seasonNumbers.first} 季'
                          : '${seasonNumbers.length} 季 (${seasonNumbers.first}-${seasonNumbers.last})',
                      isDark,
                    ),
                  _buildInfoRow('总大小', totalSizeText, isDark),
                  if (showDirectory.isNotEmpty)
                    _buildInfoRow('目录', showDirectory, isDark),
                  _buildInfoRow('来源', widget.sourceId, isDark),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 本地电视剧文件信息统计（无 TMDB 数据时使用）
  Widget _buildLocalTvShowFileInfo(bool isDark) {
    final showDirectory = _selectedMetadata.showDirectory!;
    final episodesAsync = ref.watch(localEpisodesByShowDirProvider(showDirectory));

    return Container(
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
            '本地剧集',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
          const SizedBox(height: 12),
          episodesAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, _) => Text(
              '加载失败',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
            data: (episodeMap) {
              // 统计信息
              var totalEpisodes = 0;
              var totalSize = 0;
              for (final seasonEpisodes in episodeMap.values) {
                for (final episode in seasonEpisodes.values) {
                  totalEpisodes++;
                  totalSize += episode.fileSize ?? 0;
                }
              }

              if (totalEpisodes == 0) {
                return Text(
                  '无本地剧集',
                  style: TextStyle(
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                );
              }

              final totalSizeText = _formatFileSize(totalSize);
              final seasonNumbers = episodeMap.keys.toList()..sort();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('剧集数量', '$totalEpisodes 集', isDark),
                  if (seasonNumbers.isNotEmpty)
                    _buildInfoRow(
                      '季数',
                      seasonNumbers.length == 1
                          ? '第 ${seasonNumbers.first} 季'
                          : '${seasonNumbers.length} 季 (${seasonNumbers.first}-${seasonNumbers.last})',
                      isDark,
                    ),
                  _buildInfoRow('总大小', totalSizeText, isDark),
                  _buildInfoRow('目录', showDirectory, isDark),
                  _buildInfoRow('来源', widget.sourceId, isDark),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    } else if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    } else if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

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
          onSecondaryTap: () {
            // 右键：返回到视频库主页（与长按相同）
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: '返回（长按/右键返回主页）',
          ),
        ),
      ),
    );

  /// 构建质量选择器
  ///
  /// 如果同一电影有多个质量版本，显示下拉选择器
  Widget _buildQualitySelector(bool isDark) {
    // 仅对有 TMDB ID 的电影显示质量选择器
    if (!_hasTmdbId || _isTvShow) {
      return const SizedBox.shrink();
    }

    final variantsAsync = ref.watch(relatedLocalVideosProvider(_selectedMetadata.tmdbId!));

    return variantsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (variants) {
        // 只有一个版本，不显示选择器
        if (variants.length <= 1) {
          return const SizedBox.shrink();
        }

        // 按分辨率排序（4K > 2160p > 1080p > 720p > 480p > 无）
        final sortedVariants = _sortByResolution(variants);

        return PopupMenuButton<VideoMetadata>(
          onSelected: (selected) {
            setState(() => _selectedMetadata = selected);
          },
          offset: const Offset(0, 40),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.hd_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  _selectedMetadata.resolution ?? '原始',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
          itemBuilder: (context) => sortedVariants.map((v) {
            final isSelected = v.filePath == _selectedMetadata.filePath;
            return PopupMenuItem<VideoMetadata>(
              value: v,
              child: Row(
                children: [
                  if (isSelected)
                    Icon(Icons.check_rounded, size: 18, color: AppColors.primary)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 8),
                  Text(
                    v.resolution ?? '原始',
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    v.fileSizeText,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// 按分辨率排序（高到低）
  List<VideoMetadata> _sortByResolution(List<VideoMetadata> variants) {
    const resolutionOrder = <String, int>{
      '4K': 0,
      '2160P': 1,
      '2160p': 1,
      '1080P': 2,
      '1080p': 2,
      '720P': 3,
      '720p': 3,
      '480P': 4,
      '480p': 4,
    };

    final sorted = List<VideoMetadata>.from(variants)
    ..sort((a, b) {
      final orderA = resolutionOrder[a.resolution] ?? 99;
      final orderB = resolutionOrder[b.resolution] ?? 99;
      return orderA.compareTo(orderB);
    });
    return sorted;
  }

  Future<void> _toggleFavorite() async {
    final favoritesNotifier = ref.read(favoritesProvider.notifier);
    final item = VideoFavoriteItem(
      videoPath: _selectedMetadata.filePath,
      videoName: _selectedMetadata.displayTitle,
      videoUrl: '', // URL 将在播放时获取
      thumbnailUrl: _selectedMetadata.displayPosterUrl,
      addedAt: DateTime.now(),
    );
    await favoritesNotifier.toggleFavorite(item);
  }

  Future<void> _toggleWatched() async {
    await toggleWatchedStatus(ref, widget.metadata.filePath);
  }

  /// 打开手动刮削页面
  Future<void> _openManualScraper() async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[widget.sourceId];
    final fileSystem = connection?.status == SourceStatus.connected
        ? connection!.adapter.fileSystem
        : null;

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ManualScraperPage(
          metadata: _selectedMetadata,
          fileSystem: fileSystem,
        ),
      ),
    );

    // 刮削成功后刷新详情页
    if ((result ?? false) && mounted) {
      // 重新加载元数据
      final metadataService = ref.read(videoMetadataServiceProvider);
      await metadataService.init();
      final updatedMetadata = await metadataService.getCachedAsync(
        widget.sourceId,
        _selectedMetadata.filePath,
      );
      if (updatedMetadata != null && mounted) {
        setState(() {
          _selectedMetadata = updatedMetadata;
        });
        // 刷新相关 Provider
        if (_selectedMetadata.tmdbId != null) {
          ref
            ..invalidate(movieDetailProvider(_selectedMetadata.tmdbId!))
            ..invalidate(tvDetailProvider(_selectedMetadata.tmdbId!));
        }
      }
    }
  }

  Future<void> _playVideo() async {
    setState(() => _isPlaying = true);

    try {
      final videoInfo = await _getVideoInfo(widget.metadata.filePath);
      if (videoInfo == null) return;

      if (!mounted) return;

      final videoItem = VideoItem(
        name: _selectedMetadata.displayTitle,
        path: _selectedMetadata.filePath,
        url: videoInfo.url,
        sourceId: widget.sourceId,
        size: videoInfo.size,
        thumbnailUrl: _selectedMetadata.displayPosterUrl,
      );

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      // 刷新播放历史
      ref..invalidate(continueWatchingProvider)
      ..invalidate(videoProgressProvider(_selectedMetadata.filePath));
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
      // 本地没有该影片，跳转到 TMDB 预览页面
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => TmdbPreviewPage(
            tmdbId: item.id,
            isMovie: item.isMovie,
            title: item.title,
            posterUrl: item.posterUrl,
            backdropUrl: item.backdropUrl,
          ),
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

/// 电影系列完整列表页面
class MovieCollectionListPage extends ConsumerWidget {
  const MovieCollectionListPage({
    required this.collection,
    required this.currentMovieId,
    required this.sourceId,
    super.key,
  });

  final TmdbCollection collection;
  final int currentMovieId;
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sortedParts = collection.sortedParts;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // 顶部 AppBar 带背景图
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                collection.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 4,
                      color: Colors.black54,
                    ),
                  ],
                ),
              ),
              background: collection.backdropUrl.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          collection.backdropUrl,
                          fit: BoxFit.cover,
                        ),
                        // 渐变遮罩
                        DecoratedBox(
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
                      ],
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[300],
                      ),
                    ),
            ),
          ),

          // 系列简介
          if (collection.overview.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  collection.overview,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            ),

          // 电影数量
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '共 ${sortedParts.length} 部电影',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
            ),
          ),

          // 电影网格
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                childAspectRatio: 0.55,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final part = sortedParts[index];
                  final isCurrentMovie = part.id == currentMovieId;

                  return _CollectionMovieGridItem(
                    part: part,
                    isCurrentMovie: isCurrentMovie,
                    sourceId: sourceId,
                    isDark: isDark,
                  );
                },
                childCount: sortedParts.length,
              ),
            ),
          ),

          // 底部留白
          const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
        ],
      ),
    );
  }
}

/// 电影系列网格项
class _CollectionMovieGridItem extends ConsumerWidget {
  const _CollectionMovieGridItem({
    required this.part,
    required this.isCurrentMovie,
    required this.sourceId,
    required this.isDark,
  });

  final TmdbCollectionPart part;
  final bool isCurrentMovie;
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 检查本地是否有该电影
    final localVideoAsync = ref.watch(localVideoByTmdbIdProvider(part.id));
    final localVideo = localVideoAsync.valueOrNull;
    final hasLocal = localVideo != null;

    return GestureDetector(
      onTap: () => _onTap(context, localVideo),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
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
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 海报图片
                    if (part.posterUrl.isNotEmpty)
                      Image.network(
                        part.posterUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _buildPlaceholder(),
                      )
                    else
                      _buildPlaceholder(),

                    // 当前电影标识
                    if (isCurrentMovie)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
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

                    // 本地可用标识
                    if (hasLocal && !isCurrentMovie)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),

                    // 评分
                    if (part.voteAverage > 0)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(6),
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
                                  fontSize: 11,
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
            const SizedBox(height: 8),

            // 标题
            Text(
              part.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),

            // 年份
            if (part.year != null)
              Text(
                '${part.year}',
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
    );
  }

  Widget _buildPlaceholder() => Container(
        color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[300],
        child: Center(
          child: Icon(
            Icons.movie_rounded,
            size: 40,
            color: isDark ? Colors.grey[600] : Colors.grey[500],
          ),
        ),
      );

  void _onTap(BuildContext context, VideoMetadata? localVideo) {
    if (isCurrentMovie) {
      Navigator.of(context).pop(); // 返回当前详情页
      return;
    }

    if (localVideo != null) {
      // 本地有该电影，跳转到详情页
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => VideoDetailPage(
            metadata: localVideo,
            sourceId: localVideo.sourceId,
          ),
        ),
      );
    } else {
      // 本地没有该电影，显示提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('本地未找到 "${part.title}"'),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
