import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// 底部迷你播放器
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final playerNotifier = ref.read(musicPlayerControllerProvider.notifier);

    if (currentMusic == null) return const SizedBox.shrink();

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: context.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: context.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 进度条
          LinearProgressIndicator(
            value: playerState.progress.clamp(0.0, 1.0),
            minHeight: 2,
            backgroundColor: context.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(context.colorScheme.primary),
          ),
          // 播放器内容
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  // 封面
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.borderRadiusSm,
                      color: context.colorScheme.surfaceContainerHighest,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildCoverImage(context, currentMusic.coverData, currentMusic.coverUrl),
                  ),
                  const SizedBox(width: 12),
                  // 歌曲信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          currentMusic.displayTitle,
                          style: context.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentMusic.displayArtist,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // 控制按钮
                  IconButton(
                    onPressed: playerNotifier.playPrevious,
                    icon: const Icon(Icons.skip_previous),
                    iconSize: 28,
                  ),
                  IconButton(
                    onPressed: playerNotifier.playOrPause,
                    icon: Icon(
                      playerState.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                    ),
                    iconSize: 40,
                    color: context.colorScheme.primary,
                  ),
                  IconButton(
                    onPressed: playerNotifier.playNext,
                    icon: const Icon(Icons.skip_next),
                    iconSize: 28,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImage(BuildContext context, List<int>? coverData, String? coverUrl) {
    // 优先使用嵌入的封面图片
    if (coverData != null && coverData.isNotEmpty) {
      return Image.memory(
        Uint8List.fromList(coverData),
        fit: BoxFit.cover,
        gaplessPlayback: true, // 防止闪烁
        errorBuilder: (_, _, _) => _buildCoverPlaceholder(context),
      );
    }
    // 其次使用 URL 封面
    if (coverUrl != null) {
      return Image.network(
        coverUrl,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildCoverPlaceholder(context),
      );
    }
    return _buildCoverPlaceholder(context);
  }

  Widget _buildCoverPlaceholder(BuildContext context) => Center(
        child: Icon(
          Icons.music_note,
          color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      );
}
