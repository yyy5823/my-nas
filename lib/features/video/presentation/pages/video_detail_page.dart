import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_page.dart';
import 'package:my_nas/features/video/presentation/providers/video_detail_provider.dart';
import 'package:my_nas/features/video/data/services/video_favorites_service.dart';
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
  }) {
    // 获取 TMDB 详情以获取 tagline
    String? tagline;
    String? backdropUrl = widget.metadata.backdropUrl;

    if (_hasTmdbId) {
      if (_isTvShow) {
        final tvDetailAsync = ref.watch(tvDetailProvider(widget.metadata.tmdbId!));
        tvDetailAsync.whenData((detail) {
          if (detail != null) {
            tagline = detail.tagline;
            backdropUrl ??= detail.backdropUrl;
          }
        });
      } else {
        final movieDetailAsync = ref.watch(movieDetailProvider(widget.metadata.tmdbId!));
        movieDetailAsync.whenData((detail) {
          if (detail != null) {
            tagline = detail.tagline;
            backdropUrl ??= detail.backdropUrl;
          }
        });
      }
    }

    return DetailHeroSection(
      metadata: widget.metadata,
      onPlay: _isPlaying ? () {} : _playVideo,
      onFavorite: _toggleFavorite,
      isFavorite: isFavorite,
      watchProgress: watchProgress,
      backdropUrl: backdropUrl,
      tagline: tagline,
    );
  }

  Widget _buildMainContent(BuildContext context, bool isDark, bool isWide) {
    return Padding(
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

          // 简介
          if (widget.metadata.overview != null &&
              widget.metadata.overview!.isNotEmpty)
            _buildOverviewSection(isDark),

          // 演员阵容 (需要 TMDB ID)
          if (_hasTmdbId) ...[
            const SizedBox(height: 24),
            _buildCastSection(),
          ],

          // 详细信息
          const SizedBox(height: 24),
          _buildDetailInfoSection(isDark),

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
  }

  Widget _buildEpisodeSection() {
    final tvDetailAsync = ref.watch(tvDetailProvider(widget.metadata.tmdbId!));
    final localEpisodesAsync = ref.watch(localEpisodeFilesProvider(widget.metadata.tmdbId!));
    final allProgressAsync = ref.watch(allVideoProgressProvider);

    return tvDetailAsync.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
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

  Widget _buildOverviewSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '简介',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.metadata.overview!,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: isDark
                  ? AppColors.darkOnSurfaceVariant
                  : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCastSection() {
    if (_isTvShow) {
      final tvDetailAsync = ref.watch(tvDetailProvider(widget.metadata.tmdbId!));
      return tvDetailAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
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
        error: (_, __) => const SizedBox.shrink(),
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

  Widget _buildDetailInfoSection(bool isDark) {
    final items = <Widget>[];

    // 类型
    if (widget.metadata.genreList.isNotEmpty) {
      items.add(_buildInfoRow(
        '类型',
        widget.metadata.genreList.join(' / '),
        isDark,
      ));
    }

    // 导演
    if (widget.metadata.director != null) {
      items.add(_buildInfoRow('导演', widget.metadata.director!, isDark));
    }

    // 年份
    if (widget.metadata.year != null) {
      items.add(_buildInfoRow('年份', '${widget.metadata.year}', isDark));
    }

    // 时长
    if (widget.metadata.runtimeText.isNotEmpty) {
      items.add(_buildInfoRow('时长', widget.metadata.runtimeText, isDark));
    }

    // 从 TMDB 获取更多信息
    if (_hasTmdbId) {
      if (_isTvShow) {
        final tvDetailAsync = ref.watch(tvDetailProvider(widget.metadata.tmdbId!));
        tvDetailAsync.whenData((detail) {
          if (detail != null) {
            if (detail.networks.isNotEmpty) {
              items.add(_buildInfoRow(
                '播出平台',
                detail.networks.map((n) => n.name).join(', '),
                isDark,
              ));
            }
            if (detail.status.isNotEmpty) {
              items.add(_buildInfoRow('状态', _translateStatus(detail.status), isDark));
            }
          }
        });
      } else {
        final movieDetailAsync = ref.watch(movieDetailProvider(widget.metadata.tmdbId!));
        movieDetailAsync.whenData((detail) {
          if (detail != null) {
            if (detail.productionCompanies.isNotEmpty) {
              items.add(_buildInfoRow(
                '制作公司',
                detail.productionCompanies.take(3).map((c) => c.name).join(', '),
                isDark,
              ));
            }
            if (detail.status.isNotEmpty) {
              items.add(_buildInfoRow('状态', _translateStatus(detail.status), isDark));
            }
          }
        });
      }
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '详细信息',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppColors.darkOutline : Colors.grey[300]!,
              ),
            ),
            child: Column(children: items),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Padding(
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
  }

  Widget _buildRecommendationsSection() {
    return CombinedRecommendationsSection(
      tmdbId: widget.metadata.tmdbId!,
      isMovie: !_isTvShow,
      onItemTap: _onRecommendationTap,
    );
  }

  Widget _buildFileInfoSection(bool isDark) {
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
  }

  Widget _buildBackButton(BuildContext context, bool isDark) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 8,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'Released':
        return '已上映';
      case 'Returning Series':
        return '连载中';
      case 'Ended':
        return '已完结';
      case 'Canceled':
        return '已取消';
      case 'In Production':
        return '制作中';
      case 'Post Production':
        return '后期制作';
      case 'Planned':
        return '计划中';
      default:
        return status;
    }
  }

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

  Future<void> _playVideo() async {
    setState(() => _isPlaying = true);

    try {
      final url = await _getVideoUrl(widget.metadata.filePath);
      if (url == null) return;

      if (!mounted) return;

      final videoItem = VideoItem(
        name: widget.metadata.displayTitle,
        path: widget.metadata.filePath,
        url: url,
        size: 0,
        thumbnailUrl: widget.metadata.displayPosterUrl,
      );

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      // 刷新播放历史
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(videoProgressProvider(widget.metadata.filePath));
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
      final url = await _getVideoUrl(localFile.filePath);
      if (url == null) return;

      if (!mounted) return;

      final videoItem = VideoItem(
        name: '${localFile.displayTitle} - ${episode.name}',
        path: localFile.filePath,
        url: url,
        size: 0,
        thumbnailUrl: episode.stillUrl.isNotEmpty ? episode.stillUrl : localFile.displayPosterUrl,
      );

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      // 刷新播放历史
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(allVideoProgressProvider);
    } finally {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    }
  }

  Future<String?> _getVideoUrl(String filePath) async {
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

    return connection.adapter.fileSystem.getFileUrl(filePath);
  }

  void _onRecommendationTap(TmdbMediaItem item) {
    // TODO: 检查本地是否有该影片，如果有则跳转到详情页
    // 目前先显示一个提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.title} (${item.year ?? "未知年份"})'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
