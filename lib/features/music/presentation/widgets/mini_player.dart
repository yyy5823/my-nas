import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/music/presentation/pages/music_player_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// 底部迷你播放器 - 现代化设计
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final playerNotifier = ref.read(musicPlayerControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (currentMusic == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => MusicPlayerPage.open(context),
      onVerticalDragEnd: (details) {
        // 向上滑动打开全屏播放器
        if (details.primaryVelocity != null && details.primaryVelocity! < -200) {
          MusicPlayerPage.open(context);
        }
      },
      child: Container(
        height: 72,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark
              ? Colors.grey[900]!.withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.95),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.15),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Stack(
              children: [
                // 进度条背景
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildProgressBar(playerState, isDark),
                ),
                // 内容
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 14),
                  child: Row(
                    children: [
                      // 封面
                      _buildCover(currentMusic.coverData, currentMusic.coverUrl, isDark),
                      const SizedBox(width: 12),
                      // 歌曲信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              currentMusic.displayTitle,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              currentMusic.displayArtist,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // 控制按钮
                      _buildControlButtons(ref, playerState, playerNotifier, isDark),
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

  Widget _buildProgressBar(MusicPlayerState playerState, bool isDark) => SizedBox(
      height: 3,
      child: LinearProgressIndicator(
        value: playerState.progress.clamp(0.0, 1.0),
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.05),
        valueColor: AlwaysStoppedAnimation(AppColors.primary),
      ),
    );

  Widget _buildCover(List<int>? coverData, String? coverUrl, bool isDark) {
    Widget coverImage;

    if (coverData != null && coverData.isNotEmpty) {
      coverImage = Image.memory(
        Uint8List.fromList(coverData),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildCoverPlaceholder(isDark),
      );
    } else if (coverUrl != null) {
      coverImage = Image.network(
        coverUrl,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildCoverPlaceholder(isDark),
      );
    } else {
      coverImage = _buildCoverPlaceholder(isDark);
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: coverImage,
      ),
    );
  }

  Widget _buildCoverPlaceholder(bool isDark) => Container(
      color: isDark ? Colors.grey[800] : Colors.grey[200],
      child: Icon(
        Icons.music_note_rounded,
        color: isDark ? Colors.grey[600] : Colors.grey[400],
        size: 24,
      ),
    );

  Widget _buildControlButtons(
    WidgetRef ref,
    MusicPlayerState playerState,
    MusicPlayerNotifier playerNotifier,
    bool isDark,
  ) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 上一曲
        _buildControlButton(
          onPressed: playerNotifier.playPrevious,
          icon: Icons.skip_previous_rounded,
          size: 24,
          isDark: isDark,
        ),
        const SizedBox(width: 4),
        // 播放/暂停
        _buildPlayPauseButton(playerState, playerNotifier),
        const SizedBox(width: 4),
        // 下一曲
        _buildControlButton(
          onPressed: playerNotifier.playNext,
          icon: Icons.skip_next_rounded,
          size: 24,
          isDark: isDark,
        ),
      ],
    );

  Widget _buildControlButton({
    required VoidCallback onPressed,
    required IconData icon,
    required double size,
    required bool isDark,
  }) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: size,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ),
    );

  Widget _buildPlayPauseButton(
    MusicPlayerState playerState,
    MusicPlayerNotifier playerNotifier,
  ) => GestureDetector(
      onTap: playerNotifier.playOrPause,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.secondary],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: playerState.isBuffering
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(
                playerState.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 26,
                color: Colors.white,
              ),
      ),
    );
}
