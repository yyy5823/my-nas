import 'dart:io';

import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';

/// 最近播放区域 - 水平滚动展示
class RecentTracksSection extends StatelessWidget {
  const RecentTracksSection({
    required this.tracks,
    required this.isDark,
    required this.onTrackTap,
    required this.onMoreTap,
    this.isDesktop = false,
    this.title = '最近播放',
    super.key,
  });

  final List<MusicFileWithSource> tracks;
  final bool isDark;
  final bool isDesktop;
  final String title;
  final void Function(MusicFileWithSource track) onTrackTap;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayTracks = tracks.take(isDesktop ? 10 : 8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: isDesktop ? 18 : 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              TextButton(
                onPressed: onMoreTap,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '查看全部',
                      style: TextStyle(
                        fontSize: isDesktop ? 14 : 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_rounded, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 水平滚动列表
        SizedBox(
          height: isDesktop ? 200 : 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
            itemCount: displayTracks.length,
            itemBuilder: (context, index) {
              final track = displayTracks[index];
              return Padding(
                padding: EdgeInsets.only(
                  right: index == displayTracks.length - 1 ? 0 : 12,
                ),
                child: _TrackCard(
                  track: track,
                  isDark: isDark,
                  isDesktop: isDesktop,
                  onTap: () => onTrackTap(track),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.track,
    required this.isDark,
    required this.onTap,
    this.isDesktop = false,
  });

  final MusicFileWithSource track;
  final bool isDark;
  final bool isDesktop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cardWidth = isDesktop ? 150.0 : 130.0;
    final coverSize = isDesktop ? 150.0 : 130.0;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面
            _buildCover(coverSize),
            const SizedBox(height: 8),
            // 歌曲信息
            Text(
              track.displayTitle,
              style: TextStyle(
                fontSize: isDesktop ? 14 : 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              track.displayArtist,
              style: TextStyle(
                fontSize: isDesktop ? 12 : 11,
                color: isDark ? Colors.white60 : Colors.black45,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(double size) {
    Widget coverImage;
    if (track.coverPath != null && track.coverPath!.isNotEmpty) {
      coverImage = Image.file(
        File(track.coverPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildDefaultCover(),
      );
    } else {
      coverImage = _buildDefaultCover();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            coverImage,
            // 播放悬浮按钮
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultCover() => Container(
      color: isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.black.withValues(alpha: 0.05),
      child: Icon(
        Icons.music_note_rounded,
        color: isDark ? Colors.white30 : Colors.black26,
        size: 48,
      ),
    );
}

/// 热门歌曲区域 - 列表形式展示
class PopularTracksSection extends StatelessWidget {
  const PopularTracksSection({
    required this.tracks,
    required this.isDark,
    required this.onTrackTap,
    required this.onMoreTap,
    this.isDesktop = false,
    this.title = '热门歌曲',
    this.maxItems = 5,
    super.key,
  });

  final List<MusicFileWithSource> tracks;
  final bool isDark;
  final bool isDesktop;
  final String title;
  final int maxItems;
  final void Function(MusicFileWithSource track) onTrackTap;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayTracks = tracks.take(maxItems).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: isDesktop ? 18 : 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              TextButton(
                onPressed: onMoreTap,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '查看全部',
                      style: TextStyle(
                        fontSize: isDesktop ? 14 : 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_rounded, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 歌曲列表
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
          child: Column(
            children: List.generate(displayTracks.length, (index) {
              final track = displayTracks[index];
              return _PopularTrackItem(
                track: track,
                index: index + 1,
                isDark: isDark,
                isDesktop: isDesktop,
                onTap: () => onTrackTap(track),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _PopularTrackItem extends StatelessWidget {
  const _PopularTrackItem({
    required this.track,
    required this.index,
    required this.isDark,
    required this.onTap,
    this.isDesktop = false,
  });

  final MusicFileWithSource track;
  final int index;
  final bool isDark;
  final bool isDesktop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              // 排名
              SizedBox(
                width: 28,
                child: Text(
                  '$index',
                  style: TextStyle(
                    fontSize: isDesktop ? 16 : 14,
                    fontWeight: FontWeight.bold,
                    color: index <= 3
                        ? AppColors.primary
                        : (isDark ? Colors.white38 : Colors.black38),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),
              // 封面
              _buildCover(),
              const SizedBox(width: 12),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.displayTitle,
                      style: TextStyle(
                        fontSize: isDesktop ? 14 : 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.displayArtist,
                      style: TextStyle(
                        fontSize: isDesktop ? 12 : 11,
                        color: isDark ? Colors.white60 : Colors.black45,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 时长
              if (track.duration != null)
                Text(
                  _formatDuration(track.duration!),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              const SizedBox(width: 8),
              // 更多按钮
              Icon(
                Icons.more_vert_rounded,
                color: isDark ? Colors.white30 : Colors.black26,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );

  Widget _buildCover() {
    Widget coverImage;
    if (track.coverPath != null && track.coverPath!.isNotEmpty) {
      coverImage = Image.file(
        File(track.coverPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildDefaultCover(),
      );
    } else {
      coverImage = _buildDefaultCover();
    }

    return Container(
      width: isDesktop ? 48 : 44,
      height: isDesktop ? 48 : 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: coverImage,
      ),
    );
  }

  Widget _buildDefaultCover() => Container(
      color: isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.black.withValues(alpha: 0.05),
      child: Icon(
        Icons.music_note_rounded,
        color: isDark ? Colors.white30 : Colors.black26,
        size: 24,
      ),
    );

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}
