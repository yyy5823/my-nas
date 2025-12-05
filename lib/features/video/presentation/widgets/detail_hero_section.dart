import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';

/// 详情页 Hero 区域组件
class DetailHeroSection extends StatelessWidget {
  const DetailHeroSection({
    required this.metadata,
    required this.onPlay,
    this.onFavorite,
    this.isFavorite = false,
    this.watchProgress,
    this.backdropUrl,
    this.tagline,
    super.key,
  });

  final VideoMetadata metadata;
  final VoidCallback onPlay;
  final VoidCallback? onFavorite;
  final bool isFavorite;
  final double? watchProgress;
  final String? backdropUrl;
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = size.width > 800;
    final heroHeight = isWide ? 450.0 : 350.0;

    final displayBackdrop = backdropUrl ?? metadata.backdropUrl;
    final displayPoster = metadata.displayPosterUrl;
    final hasBackdrop = displayBackdrop != null && displayBackdrop.isNotEmpty;
    final hasPoster = displayPoster != null && displayPoster.isNotEmpty;

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景图
          if (hasBackdrop)
            AdaptiveImage(
              imageUrl: displayBackdrop,
              fit: BoxFit.cover,
              placeholder: (_) => _buildBackdropPlaceholder(isDark),
              errorWidget: (_, __) => _buildBackdropPlaceholder(isDark),
            )
          else
            _buildBackdropPlaceholder(isDark),

          // 渐变遮罩
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.3),
                  isDark
                      ? AppColors.darkBackground.withValues(alpha: 0.9)
                      : Colors.black.withValues(alpha: 0.7),
                  isDark ? AppColors.darkBackground : Colors.black,
                ],
                stops: const [0.0, 0.4, 0.7, 1.0],
              ),
            ),
          ),

          // 左侧渐变 (宽屏模式)
          if (isWide)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    isDark
                        ? AppColors.darkBackground.withValues(alpha: 0.8)
                        : Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5],
                ),
              ),
            ),

          // 内容区域
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 48 : 16,
                vertical: 16,
              ),
              child: isWide
                  ? _buildWideLayout(isDark, hasPoster, displayPoster)
                  : _buildNarrowLayout(isDark, hasPoster, displayPoster),
            ),
          ),
        ],
      ),
    );
  }

  /// 宽屏布局 (海报在左，信息在右)
  Widget _buildWideLayout(bool isDark, bool hasPoster, String? displayPoster) => Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 海报
        if (hasPoster)
          Container(
            width: 200,
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AdaptiveImage(
                imageUrl: displayPoster!,
                fit: BoxFit.cover,
                placeholder: (_) => _buildPosterPlaceholder(isDark),
                errorWidget: (_, __) => _buildPosterPlaceholder(isDark),
              ),
            ),
          ),
        if (hasPoster) const SizedBox(width: 32),
        // 信息区域
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitleSection(isDark, large: true),
              const SizedBox(height: 8),
              _buildMetadataRow(isDark),
              if (tagline != null && tagline!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildTagline(isDark),
              ],
              const SizedBox(height: 20),
              _buildActionButtons(isDark, large: true),
            ],
          ),
        ),
      ],
    );

  /// 窄屏布局 (垂直排列)
  Widget _buildNarrowLayout(bool isDark, bool hasPoster, String? displayPoster) => Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 海报和标题横向排列
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 小海报
            if (hasPoster)
              Container(
                width: 100,
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AdaptiveImage(
                    imageUrl: displayPoster!,
                    fit: BoxFit.cover,
                    placeholder: (_) => _buildPosterPlaceholder(isDark),
                    errorWidget: (_, __) => _buildPosterPlaceholder(isDark),
                  ),
                ),
              ),
            if (hasPoster) const SizedBox(width: 16),
            // 标题和元数据
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildTitleSection(isDark, large: false),
                  const SizedBox(height: 6),
                  _buildMetadataRow(isDark),
                ],
              ),
            ),
          ],
        ),
        if (tagline != null && tagline!.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildTagline(isDark),
        ],
        const SizedBox(height: 16),
        _buildActionButtons(isDark, large: false),
      ],
    );

  Widget _buildTitleSection(bool isDark, {bool large = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 主标题
        Text(
          metadata.displayTitle,
          style: TextStyle(
            fontSize: large ? 32 : 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.2,
            shadows: [
              Shadow(
                offset: const Offset(0, 2),
                blurRadius: 4,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
        // 原标题 (如果不同)
        if (metadata.originalTitle != null &&
            metadata.originalTitle != metadata.title &&
            metadata.originalTitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              metadata.originalTitle!,
              style: TextStyle(
                fontSize: large ? 16 : 13,
                color: Colors.white.withValues(alpha: 0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );

  Widget _buildMetadataRow(bool isDark) {
    final items = <Widget>[];

    // 评分
    if (metadata.rating != null && metadata.rating! > 0) {
      items.add(_buildMetadataChip(
        icon: Icons.star_rounded,
        iconColor: Colors.amber,
        text: metadata.ratingText,
      ));
    }

    // 年份
    if (metadata.year != null) {
      items.add(_buildMetadataChip(text: '${metadata.year}'));
    }

    // 时长
    if (metadata.runtime != null && metadata.runtime! > 0) {
      items.add(_buildMetadataChip(text: _formatRuntime(metadata.runtime!)));
    }

    // 类型
    if (metadata.genres != null && metadata.genres!.isNotEmpty) {
      items.add(_buildMetadataChip(text: metadata.genres!));
    }

    // 剧集信息
    if (metadata.category == MediaCategory.tvShow) {
      if (metadata.seasonNumber != null && metadata.episodeNumber != null) {
        items.add(_buildMetadataChip(
          text: 'S${metadata.seasonNumber} E${metadata.episodeNumber}',
          backgroundColor: AppColors.accent.withValues(alpha: 0.3),
        ));
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items,
    );
  }

  Widget _buildMetadataChip({
    String? text,
    IconData? icon,
    Color? iconColor,
    Color? backgroundColor,
  }) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor ?? Colors.white),
            const SizedBox(width: 4),
          ],
          if (text != null)
            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );

  Widget _buildTagline(bool isDark) => Text(
      '"$tagline"',
      style: TextStyle(
        fontSize: 14,
        fontStyle: FontStyle.italic,
        color: Colors.white.withValues(alpha: 0.8),
      ),
    );

  Widget _buildActionButtons(bool isDark, {bool large = false}) {
    final buttonHeight = large ? 48.0 : 42.0;
    final fontSize = large ? 15.0 : 14.0;

    return Row(
      children: [
        // 播放按钮
        Expanded(
          flex: 2,
          child: SizedBox(
            height: buttonHeight,
            child: ElevatedButton.icon(
              onPressed: onPlay,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 4,
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 24),
              label: Text(
                watchProgress != null && watchProgress! > 0.05
                    ? '继续播放'
                    : '播放',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        // 播放进度指示
        if (watchProgress != null && watchProgress! > 0.05) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${(watchProgress! * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        // 收藏按钮
        if (onFavorite != null) ...[
          const SizedBox(width: 12),
          SizedBox(
            height: buttonHeight,
            width: buttonHeight,
            child: IconButton.filled(
              onPressed: onFavorite,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                foregroundColor: Colors.white,
              ),
              icon: Icon(
                isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFavorite ? Colors.red : Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBackdropPlaceholder(bool isDark) => Container(
      color: isDark ? AppColors.darkSurface : Colors.grey[800],
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          size: 80,
          color: isDark ? Colors.grey[700] : Colors.grey[600],
        ),
      ),
    );

  Widget _buildPosterPlaceholder(bool isDark) => Container(
      color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[700],
      child: Center(
        child: Icon(
          metadata.category == MediaCategory.tvShow
              ? Icons.live_tv_rounded
              : Icons.movie_rounded,
          size: 40,
          color: isDark ? Colors.grey[600] : Colors.grey[500],
        ),
      ),
    );

  String _formatRuntime(int minutes) {
    if (minutes < 60) {
      return '${minutes}分钟';
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }
}
