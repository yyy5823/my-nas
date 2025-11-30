import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_page.dart';
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 800;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[100],
      body: CustomScrollView(
        slivers: [
          // 顶部背景和海报
          SliverToBoxAdapter(
            child: _buildHeader(context, isDark, isWide),
          ),

          // 内容区域
          SliverToBoxAdapter(
            child: _buildContent(context, isDark, isWide),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, bool isWide) {
    final hasBackdrop = widget.metadata.backdropUrl != null &&
        widget.metadata.backdropUrl!.isNotEmpty;
    final hasPoster = widget.metadata.posterUrl != null &&
        widget.metadata.posterUrl!.isNotEmpty;

    return Stack(
      children: [
        // 背景图
        if (hasBackdrop)
          SizedBox(
            height: isWide ? 400 : 300,
            width: double.infinity,
            child: CachedNetworkImage(
              imageUrl: widget.metadata.backdropUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[300],
              ),
              errorWidget: (_, __, ___) => Container(
                color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[300],
              ),
            ),
          )
        else
          Container(
            height: isWide ? 400 : 300,
            color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[300],
          ),

        // 渐变遮罩
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  (isDark ? AppColors.darkBackground : Colors.grey[100]!)
                      .withValues(alpha: 0.3),
                  (isDark ? AppColors.darkBackground : Colors.grey[100]!)
                      .withValues(alpha: 0.9),
                  isDark ? AppColors.darkBackground : Colors.grey[100]!,
                ],
                stops: const [0.0, 0.4, 0.7, 1.0],
              ),
            ),
          ),
        ),

        // 返回按钮
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
            ),
          ),
        ),

        // 海报和标题（横向布局）
        if (isWide)
          Positioned(
            bottom: 0,
            left: 40,
            right: 40,
            child: Row(
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
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: widget.metadata.posterUrl!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                const SizedBox(width: 24),
                // 标题信息
                Expanded(
                  child: _buildTitleSection(context, isDark),
                ),
              ],
            ),
          )
        else
          Positioned(
            bottom: 0,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // 海报
                    if (hasPoster)
                      Container(
                        width: 120,
                        height: 180,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: widget.metadata.posterUrl!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    const SizedBox(width: 16),
                    // 标题信息
                    Expanded(
                      child: _buildTitleSection(context, isDark),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTitleSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 分类标签
        if (widget.metadata.category != MediaCategory.unknown)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: widget.metadata.category == MediaCategory.tvShow
                  ? AppColors.accent.withValues(alpha: 0.9)
                  : AppColors.primary.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.metadata.category == MediaCategory.tvShow ? '电视剧' : '电影',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

        // 标题
        Text(
          widget.metadata.displayTitle,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.darkOnSurface : Colors.black87,
          ),
        ),

        // 原始标题
        if (widget.metadata.originalTitle != null &&
            widget.metadata.originalTitle != widget.metadata.title)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.metadata.originalTitle!,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppColors.darkOnSurfaceVariant : Colors.black54,
              ),
            ),
          ),

        const SizedBox(height: 12),

        // 元数据行
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            // 年份
            if (widget.metadata.year != null)
              _buildMetaChip(
                Icons.calendar_today_rounded,
                '${widget.metadata.year}',
                isDark,
              ),

            // 评分
            if (widget.metadata.rating != null && widget.metadata.rating! > 0)
              _buildRatingChip(widget.metadata.rating!, isDark),

            // 时长
            if (widget.metadata.runtimeText.isNotEmpty)
              _buildMetaChip(
                Icons.schedule_rounded,
                widget.metadata.runtimeText,
                isDark,
              ),

            // 季/集
            if (widget.metadata.category == MediaCategory.tvShow) ...[
              if (widget.metadata.seasonNumber != null)
                _buildMetaChip(
                  Icons.folder_rounded,
                  '第 ${widget.metadata.seasonNumber} 季',
                  isDark,
                ),
              if (widget.metadata.episodeNumber != null)
                _buildMetaChip(
                  Icons.play_circle_outline_rounded,
                  '第 ${widget.metadata.episodeNumber} 集',
                  isDark,
                ),
            ],
          ],
        ),

        const SizedBox(height: 16),

        // 播放按钮
        ElevatedButton.icon(
          onPressed: _isPlaying ? null : _playVideo,
          icon: _isPlaying
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.play_arrow_rounded),
          label: Text(_isPlaying ? '正在加载...' : '播放'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetaChip(IconData icon, String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? AppColors.darkOnSurfaceVariant : Colors.black54,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.darkOnSurface : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingChip(double rating, bool isDark) {
    Color ratingColor;
    if (rating >= 8) {
      ratingColor = Colors.green;
    } else if (rating >= 6) {
      ratingColor = Colors.orange;
    } else {
      ratingColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ratingColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            size: 16,
            color: ratingColor,
          ),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: ratingColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isDark, bool isWide) {
    return Padding(
      padding: EdgeInsets.all(isWide ? 40 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 剧集标题
          if (widget.metadata.episodeTitle != null) ...[
            Text(
              '本集: ${widget.metadata.episodeTitle}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkOnSurface : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 简介
          if (widget.metadata.overview != null &&
              widget.metadata.overview!.isNotEmpty) ...[
            Text(
              '简介',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.metadata.overview!,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: isDark ? AppColors.darkOnSurfaceVariant : Colors.black54,
              ),
            ),
            const SizedBox(height: 24),
          ],

          // 类型
          if (widget.metadata.genreList.isNotEmpty) ...[
            Text(
              '类型',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.metadata.genreList.map((genre) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceElevated
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkOutline.withValues(alpha: 0.3)
                          : Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    genre,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.darkOnSurface : Colors.black87,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // 导演
          if (widget.metadata.director != null) ...[
            Text(
              '导演',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.metadata.director!,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppColors.darkOnSurfaceVariant : Colors.black54,
              ),
            ),
            const SizedBox(height: 24),
          ],

          // 演员
          if (widget.metadata.castList.isNotEmpty) ...[
            Text(
              '演员',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.metadata.castList.map((actor) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceElevated
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkOutline.withValues(alpha: 0.3)
                          : Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    actor,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.darkOnSurface : Colors.black87,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // 文件信息
          _buildFileInfo(context, isDark),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildFileInfo(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.2),
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
              color: isDark ? AppColors.darkOnSurface : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _buildFileInfoRow('文件名', widget.metadata.fileName, isDark),
          _buildFileInfoRow('路径', widget.metadata.filePath, isDark),
          _buildFileInfoRow('来源', widget.sourceId, isDark),
        ],
      ),
    );
  }

  Widget _buildFileInfoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkOnSurfaceVariant : Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkOnSurface : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _playVideo() async {
    setState(() => _isPlaying = true);

    try {
      final connections = ref.read(activeConnectionsProvider);
      final connection = connections[widget.sourceId];

      // 检查连接状态
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
        return;
      }

      final url = await connection.adapter.fileSystem.getFileUrl(
        widget.metadata.filePath,
      );

      if (!mounted) return;

      final videoItem = VideoItem(
        name: widget.metadata.displayTitle,
        path: widget.metadata.filePath,
        url: url,
        size: 0,
      );

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      // 刷新继续观看列表
      ref.invalidate(continueWatchingProvider);
    } finally {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    }
  }
}
