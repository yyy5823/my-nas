import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/pages/music_player_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// Hero 播放卡片 - 展示当前播放或最近播放的歌曲
class HeroPlayerCard extends ConsumerWidget {
  const HeroPlayerCard({
    required this.isDark,
    this.isDesktop = false,
    this.onShuffleTap,
    this.onQueueTap,
    super.key,
  });

  final bool isDark;
  final bool isDesktop;
  final VoidCallback? onShuffleTap;
  final VoidCallback? onQueueTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    // 只监听 isPlaying 状态，避免因 position 高频更新导致卡片闪烁
    final isPlaying = ref.watch(
      musicPlayerControllerProvider.select((state) => state.isPlaying),
    );

    // 如果没有当前播放，显示欢迎卡片
    if (currentMusic == null) {
      return _buildWelcomeCard(context);
    }

    return GestureDetector(
      onTap: () => MusicPlayerPage.open(context),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
        height: isDesktop ? 200 : 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景封面（模糊）
              _buildBlurredBackground(currentMusic),
              // 渐变遮罩
              _buildGradientOverlay(),
              // 内容
              _buildContent(context, ref, currentMusic, isPlaying),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(BuildContext context) => Container(
      margin: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
      height: isDesktop ? 200 : 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.7),
            AppColors.secondary,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 装饰性音符图案
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(
              Icons.music_note_rounded,
              size: 150,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          Positioned(
            left: -30,
            top: -30,
            child: Icon(
              Icons.album_rounded,
              size: 100,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          // 内容
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                // 左侧文字内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.play_circle_filled_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '开始探索你的音乐',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '选择一首歌曲开始播放',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                // 右侧随机播放按钮
                if (onShuffleTap != null)
                  GestureDetector(
                    onTap: onShuffleTap,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shuffle_rounded,
                            color: AppColors.primary,
                            size: 28,
                          ),
                          SizedBox(height: 2),
                          Text(
                            '随机',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

  Widget _buildBlurredBackground(MusicItem currentMusic) {
    final coverData = currentMusic.coverData;
    final coverUrl = currentMusic.coverUrl;

    Widget? coverImage;

    if (coverData != null && coverData.isNotEmpty) {
      coverImage = Image.memory(
        Uint8List.fromList(coverData),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildDefaultBackground(),
      );
    } else if (coverUrl != null && coverUrl.isNotEmpty) {
      // 支持 file:// URL 和网络 URL
      if (coverUrl.startsWith('file://')) {
        final filePath = coverUrl.substring(7); // 移除 'file://' 前缀
        coverImage = Image.file(
          File(filePath),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildDefaultBackground(),
        );
      } else {
        coverImage = Image.network(
          coverUrl,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildDefaultBackground(),
        );
      }
    }

    if (coverImage != null) {
      return ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: coverImage,
      );
    }
    return _buildDefaultBackground();
  }

  Widget _buildDefaultBackground() => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.7),
            AppColors.secondary,
          ],
        ),
      ),
    );

  Widget _buildGradientOverlay() => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.3),
            Colors.black.withValues(alpha: 0.7),
          ],
        ),
      ),
    );

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    MusicItem currentMusic,
    bool isPlaying,
  ) => Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // 封面
          _buildCover(currentMusic),
          const SizedBox(width: 16),
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isPlaying ? '正在播放' : '继续播放',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 歌曲名
                Text(
                  currentMusic.displayTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // 艺术家
                Text(
                  currentMusic.displayArtist,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // 随机播放按钮
          if (onShuffleTap != null) ...[
            _buildShuffleButton(),
            const SizedBox(width: 12),
          ],
          // 播放按钮
          _buildPlayButton(context, ref, isPlaying),
        ],
      ),
    );

  Widget _buildShuffleButton() => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onShuffleTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.shuffle_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );

  Widget _buildCover(MusicItem currentMusic) {
    Widget coverImage;
    final coverData = currentMusic.coverData;
    final coverUrl = currentMusic.coverUrl;

    if (coverData != null && coverData.isNotEmpty) {
      coverImage = Image.memory(
        Uint8List.fromList(coverData),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildDefaultCover(),
      );
    } else if (coverUrl != null && coverUrl.isNotEmpty) {
      // 支持 file:// URL 和网络 URL
      if (coverUrl.startsWith('file://')) {
        final filePath = coverUrl.substring(7); // 移除 'file://' 前缀
        coverImage = Image.file(
          File(filePath),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildDefaultCover(),
        );
      } else {
        coverImage = Image.network(
          coverUrl,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildDefaultCover(),
        );
      }
    } else {
      coverImage = _buildDefaultCover();
    }

    return Hero(
      tag: 'music_cover',
      child: Container(
        width: isDesktop ? 140 : 120,
        height: isDesktop ? 140 : 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: coverImage,
        ),
      ),
    );
  }

  Widget _buildDefaultCover() => ColoredBox(
      color: AppColors.primary.withValues(alpha: 0.3),
      child: const Icon(
        Icons.music_note_rounded,
        color: Colors.white,
        size: 48,
      ),
    );

  Widget _buildPlayButton(BuildContext context, WidgetRef ref, bool isPlaying) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (isPlaying) {
          ref.read(musicPlayerControllerProvider.notifier).pause();
        } else {
          ref.read(musicPlayerControllerProvider.notifier).resume();
        }
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: AppColors.primary,
          size: 32,
        ),
      ),
    );
}
