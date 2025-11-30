import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';

/// 海报墙组件
class PosterWall extends StatelessWidget {
  const PosterWall({
    required this.items,
    required this.onItemTap,
    this.onItemLongPress,
    this.crossAxisCount,
    this.childAspectRatio = 0.67,
    this.padding = const EdgeInsets.all(16),
    this.spacing = 12,
    super.key,
  });

  final List<VideoMetadata> items;
  final void Function(VideoMetadata item) onItemTap;
  final void Function(VideoMetadata item)? onItemLongPress;
  final int? crossAxisCount;
  final double childAspectRatio;
  final EdgeInsets padding;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final count = crossAxisCount ?? (width > 1200 ? 6 : width > 800 ? 5 : width > 600 ? 4 : 3);

    return GridView.builder(
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: count,
        childAspectRatio: childAspectRatio,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => PosterCard(
        metadata: items[index],
        onTap: () => onItemTap(items[index]),
        onLongPress: onItemLongPress != null ? () => onItemLongPress!(items[index]) : null,
      ),
    );
  }
}

/// 海报墙 Sliver 版本
class SliverPosterWall extends StatelessWidget {
  const SliverPosterWall({
    required this.items,
    required this.onItemTap,
    this.onItemLongPress,
    this.crossAxisCount,
    this.childAspectRatio = 0.67,
    this.padding = const EdgeInsets.all(16),
    this.spacing = 12,
    super.key,
  });

  final List<VideoMetadata> items;
  final void Function(VideoMetadata item) onItemTap;
  final void Function(VideoMetadata item)? onItemLongPress;
  final int? crossAxisCount;
  final double childAspectRatio;
  final EdgeInsets padding;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final count = crossAxisCount ?? (width > 1200 ? 6 : width > 800 ? 5 : width > 600 ? 4 : 3);

    return SliverPadding(
      padding: padding,
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: count,
          childAspectRatio: childAspectRatio,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => PosterCard(
            metadata: items[index],
            onTap: () => onItemTap(items[index]),
            onLongPress: onItemLongPress != null ? () => onItemLongPress!(items[index]) : null,
          ),
          childCount: items.length,
        ),
      ),
    );
  }
}

/// 海报卡片
class PosterCard extends StatefulWidget {
  const PosterCard({
    required this.metadata,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final VideoMetadata metadata;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayPoster = widget.metadata.displayPosterUrl;
    final hasPoster = displayPoster != null && displayPoster.isNotEmpty;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _isHovered ? 0.3 : 0.2),
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
                  // 海报图片或占位符（优先使用 TMDB 海报，没有则使用内置缩略图）
                  if (hasPoster)
                    CachedNetworkImage(
                      imageUrl: displayPoster,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _buildPlaceholder(isDark),
                      errorWidget: (_, __, ___) => _buildPlaceholder(isDark),
                    )
                  else
                    _buildPlaceholder(isDark),

                  // 渐变遮罩和信息
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 标题
                          Text(
                            widget.metadata.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // 年份和评分
                          Row(
                            children: [
                              if (widget.metadata.year != null) ...[
                                Text(
                                  '${widget.metadata.year}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 10,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (widget.metadata.rating != null && widget.metadata.rating! > 0)
                                _buildRatingBadge(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 电视剧标记
                  if (widget.metadata.category == MediaCategory.tvShow)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

                  // 悬停效果
                  if (_isHovered)
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.8),
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
    );
  }

  Widget _buildPlaceholder(bool isDark) {
    return Container(
      color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[200],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.metadata.category == MediaCategory.tvShow
                ? Icons.live_tv_rounded
                : Icons.movie_rounded,
            size: 40,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              widget.metadata.displayTitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: _getRatingColor(),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.star_rounded,
            size: 10,
            color: Colors.white,
          ),
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
    );
  }

  Color _getRatingColor() {
    final rating = widget.metadata.rating ?? 0;
    if (rating >= 8) return Colors.green;
    if (rating >= 6) return Colors.orange;
    return Colors.red;
  }
}

/// 横向滚动海报行
class PosterRow extends StatelessWidget {
  const PosterRow({
    required this.title,
    required this.items,
    required this.onItemTap,
    this.onSeeAllTap,
    this.itemWidth = 120,
    this.itemHeight = 180,
    super.key,
  });

  final String title;
  final List<VideoMetadata> items;
  final void Function(VideoMetadata item) onItemTap;
  final VoidCallback? onSeeAllTap;
  final double itemWidth;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkOnSurface : null,
                    ),
              ),
              const Spacer(),
              if (onSeeAllTap != null)
                TextButton(
                  onPressed: onSeeAllTap,
                  child: Text(
                    '查看全部',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // 海报列表
        SizedBox(
          height: itemHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final metadata = items[index];
              final displayPoster = metadata.displayPosterUrl;
              final hasPoster = displayPoster != null && displayPoster.isNotEmpty;

              return Padding(
                padding: EdgeInsets.only(right: index < items.length - 1 ? 12 : 0),
                child: GestureDetector(
                  onTap: () => onItemTap(metadata),
                  child: SizedBox(
                    width: itemWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 海报
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: hasPoster
                                  ? CachedNetworkImage(
                                      imageUrl: displayPoster,
                                      fit: BoxFit.cover,
                                      width: itemWidth,
                                      placeholder: (_, __) => _buildMiniPlaceholder(isDark, metadata),
                                      errorWidget: (_, __, ___) => _buildMiniPlaceholder(isDark, metadata),
                                    )
                                  : _buildMiniPlaceholder(isDark, metadata),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // 标题
                        Text(
                          metadata.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMiniPlaceholder(bool isDark, VideoMetadata metadata) {
    return Container(
      color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[200],
      child: Center(
        child: Icon(
          metadata.category == MediaCategory.tvShow
              ? Icons.live_tv_rounded
              : Icons.movie_rounded,
          size: 32,
          color: isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );
  }
}
