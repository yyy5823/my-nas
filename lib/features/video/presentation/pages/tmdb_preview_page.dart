import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/presentation/pages/video_detail_page.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';

/// TMDB 预览页面 - 用于展示本地不存在的 TMDB 内容
class TmdbPreviewPage extends ConsumerStatefulWidget {
  const TmdbPreviewPage({
    required this.tmdbId,
    required this.isMovie,
    required this.title,
    this.posterUrl,
    this.backdropUrl,
    super.key,
  });

  final int tmdbId;
  final bool isMovie;
  final String title;
  final String? posterUrl;
  final String? backdropUrl;

  @override
  ConsumerState<TmdbPreviewPage> createState() => _TmdbPreviewPageState();
}

class _TmdbPreviewPageState extends ConsumerState<TmdbPreviewPage> {
  final TmdbService _tmdbService = TmdbService();
  bool _isLoading = true;
  Object? _detail; // TmdbMovieDetail or TmdbTvDetail
  List<TmdbMediaItem> _similarItems = [];
  List<TmdbMediaItem> _recommendedItems = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      if (widget.isMovie) {
        final detail = await _tmdbService.getMovieDetail(widget.tmdbId);
        final similar = await _tmdbService.getSimilarMovies(widget.tmdbId);
        final recommended = await _tmdbService.getMovieRecommendations(widget.tmdbId);
        if (mounted) {
          setState(() {
            _detail = detail;
            _similarItems = similar.results;
            _recommendedItems = recommended.results;
            _isLoading = false;
          });
        }
      } else {
        final detail = await _tmdbService.getTvDetail(widget.tmdbId);
        final similar = await _tmdbService.getSimilarTvShows(widget.tmdbId);
        final recommended = await _tmdbService.getTvRecommendations(widget.tmdbId);
        if (mounted) {
          setState(() {
            _detail = detail;
            _similarItems = similar.results;
            _recommendedItems = recommended.results;
            _isLoading = false;
          });
        }
      }
    } on Exception catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backdropUrl = widget.backdropUrl ?? _getBackdropUrl();
    final posterUrl = widget.posterUrl ?? _getPosterUrl();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // 顶部背景
                SliverAppBar(
                  expandedHeight: 300,
                  pinned: true,
                  backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (backdropUrl != null && backdropUrl.isNotEmpty)
                          AdaptiveImage(
                            imageUrl: backdropUrl,
                            fit: BoxFit.cover,
                          ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                (isDark ? const Color(0xFF0D0D0D) : Colors.grey[50]!),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 内容
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 海报
                            if (posterUrl != null && posterUrl.isNotEmpty)
                              Container(
                                width: 100,
                                height: 150,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: AdaptiveImage(
                                    imageUrl: posterUrl,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 16),
                            // 标题和信息
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getTitle(),
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildMetaInfo(isDark),
                                  const SizedBox(height: 12),
                                  // 本地不可用标签
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.cloud_outlined, size: 16, color: Colors.orange[700]),
                                        const SizedBox(width: 6),
                                        Text(
                                          '本地不可用',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // 简介
                        if (_getOverview().isNotEmpty) ...[
                          Text(
                            '简介',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getOverview(),
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.grey[300] : Colors.grey[700],
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        // 推荐内容
                        if (_recommendedItems.isNotEmpty)
                          _buildMediaSection('推荐内容', _recommendedItems, isDark),
                        // 相似内容
                        if (_similarItems.isNotEmpty)
                          _buildMediaSection('相似内容', _similarItems, isDark),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMetaInfo(bool isDark) {
    final items = <String>[];

    if (_detail is TmdbMovieDetail) {
      final movie = _detail! as TmdbMovieDetail;
      if (movie.year != null) items.add('${movie.year}');
      if (movie.runtime != null) items.add('${movie.runtime}分钟');
      if (movie.voteAverage > 0) items.add('⭐ ${movie.voteAverage.toStringAsFixed(1)}');
    } else if (_detail is TmdbTvDetail) {
      final tv = _detail! as TmdbTvDetail;
      if (tv.year != null) items.add('${tv.year}');
      items.add('${tv.numberOfSeasons}季');
      if (tv.voteAverage > 0) items.add('⭐ ${tv.voteAverage.toStringAsFixed(1)}');
    }

    return Wrap(
      spacing: 12,
      children: items.map((item) => Text(
        item,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      )).toList(),
    );
  }

  Widget _buildMediaSection(String title, List<TmdbMediaItem> items, bool isDark) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: EdgeInsets.only(right: index < items.length - 1 ? 12 : 0),
                child: _TmdbMediaCard(
                  item: item,
                  isMovie: widget.isMovie,
                  isDark: isDark,
                  onTap: () => _onMediaItemTap(item),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );

  Future<void> _onMediaItemTap(TmdbMediaItem item) async {
    // 检查本地是否存在
    final db = VideoDatabaseService();
    final localVideo = await db.getFirstByTmdbId(item.id);

    if (!mounted) return;

    if (localVideo != null) {
      // 本地存在 - 跳转到 VideoDetailPage
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoDetailPage(
            metadata: localVideo,
            sourceId: localVideo.sourceId,
          ),
        ),
      );
    } else {
      // 本地不存在 - 跳转到 TmdbPreviewPage
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => TmdbPreviewPage(
            tmdbId: item.id,
            isMovie: widget.isMovie,
            title: item.title,
            posterUrl: item.posterUrl,
            backdropUrl: item.backdropUrl,
          ),
        ),
      );
    }
  }

  String _getTitle() {
    if (_detail is TmdbMovieDetail) {
      return (_detail! as TmdbMovieDetail).title;
    } else if (_detail is TmdbTvDetail) {
      return (_detail! as TmdbTvDetail).name;
    }
    return widget.title;
  }

  String _getOverview() {
    if (_detail is TmdbMovieDetail) {
      return (_detail! as TmdbMovieDetail).overview;
    } else if (_detail is TmdbTvDetail) {
      return (_detail! as TmdbTvDetail).overview;
    }
    return '';
  }

  String? _getPosterUrl() {
    if (_detail is TmdbMovieDetail) {
      return (_detail! as TmdbMovieDetail).posterUrl;
    } else if (_detail is TmdbTvDetail) {
      return (_detail! as TmdbTvDetail).posterUrl;
    }
    return null;
  }

  String? _getBackdropUrl() {
    if (_detail is TmdbMovieDetail) {
      return (_detail! as TmdbMovieDetail).backdropUrl;
    } else if (_detail is TmdbTvDetail) {
      return (_detail! as TmdbTvDetail).backdropUrl;
    }
    return null;
  }
}

/// TMDB 媒体卡片
class _TmdbMediaCard extends StatelessWidget {
  const _TmdbMediaCard({
    required this.item,
    required this.isMovie,
    required this.isDark,
    required this.onTap,
  });

  final TmdbMediaItem item;
  final bool isMovie;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPoster = item.posterUrl.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 海报
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: hasPoster
                      ? AdaptiveImage(
                          imageUrl: item.posterUrl,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: isDark ? Colors.grey[850] : Colors.grey[200],
                          child: Icon(
                            isMovie ? Icons.movie : Icons.tv,
                            color: isDark ? Colors.grey[600] : Colors.grey[400],
                            size: 32,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 标题
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
