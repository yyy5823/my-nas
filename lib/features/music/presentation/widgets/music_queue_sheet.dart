import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// 显示播放队列
void showMusicQueueSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const MusicQueueSheet(),
  );
}

class MusicQueueSheet extends ConsumerWidget {
  const MusicQueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final queue = ref.watch(playQueueProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final currentMusic = ref.watch(currentMusicProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 拖拽指示器
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkOutline.withValues(alpha: 0.3)
                    : AppColors.lightOutline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 标题栏
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.fileAudio.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.queue_music_rounded,
                      color: AppColors.fileAudio,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '播放队列',
                          style: context.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${queue.length} 首歌曲',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 清空队列
                  if (queue.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        ref.read(playQueueProvider.notifier).clear();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.clear_all_rounded, size: 18),
                      label: const Text('清空'),
                    ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 队列列表
            Expanded(
              child: queue.isEmpty
                  ? _buildEmptyState(context, isDark)
                  : ReorderableListView.builder(
                      scrollController: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      itemCount: queue.length,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex--;
                        ref.read(playQueueProvider.notifier).reorder(oldIndex, newIndex);
                        // 更新当前索引
                        if (oldIndex == playerState.currentIndex) {
                          ref.read(musicPlayerControllerProvider.notifier)
                              .updateCurrentIndex(newIndex);
                        } else if (oldIndex < playerState.currentIndex &&
                            newIndex >= playerState.currentIndex) {
                          ref.read(musicPlayerControllerProvider.notifier)
                              .updateCurrentIndex(playerState.currentIndex - 1);
                        } else if (oldIndex > playerState.currentIndex &&
                            newIndex <= playerState.currentIndex) {
                          ref.read(musicPlayerControllerProvider.notifier)
                              .updateCurrentIndex(playerState.currentIndex + 1);
                        }
                      },
                      itemBuilder: (context, index) {
                        final track = queue[index];
                        final isPlaying = currentMusic?.path == track.path;
                        return _QueueItem(
                          key: ValueKey(track.path),
                          track: track,
                          index: index,
                          isPlaying: isPlaying,
                          isDark: isDark,
                          onTap: () {
                            ref.read(musicPlayerControllerProvider.notifier).playAt(index);
                          },
                          onRemove: () {
                            ref.read(playQueueProvider.notifier).removeFromQueue(index);
                            // 更新当前索引
                            if (index < playerState.currentIndex) {
                              ref.read(musicPlayerControllerProvider.notifier)
                                  .updateCurrentIndex(playerState.currentIndex - 1);
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.queue_music_outlined,
              size: 64,
              color: isDark
                  ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.5)
                  : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '播放队列为空',
              style: context.textTheme.titleMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '从音乐列表中添加歌曲',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.7)
                    : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({
    required this.track,
    required this.index,
    required this.isPlaying,
    required this.isDark,
    required this.onTap,
    required this.onRemove,
    super.key,
  });

  final MusicItem track;
  final int index;
  final bool isPlaying;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Dismissible(
        key: ValueKey('dismiss_${track.path}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onRemove(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: Colors.red,
          child: const Icon(Icons.delete_rounded, color: Colors.white),
        ),
        child: Material(
          color: Colors.transparent,
          child: ListTile(
            onTap: onTap,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: isPlaying
                    ? const LinearGradient(
                        colors: [AppColors.fileAudio, AppColors.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isPlaying
                    ? null
                    : (isDark
                        ? AppColors.darkSurfaceElevated
                        : AppColors.lightSurfaceVariant),
              ),
              child: Icon(
                isPlaying ? Icons.equalizer_rounded : Icons.music_note_rounded,
                color: isPlaying
                    ? Colors.white
                    : (isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant),
                size: 20,
              ),
            ),
            title: Text(
              track.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                color: isPlaying
                    ? AppColors.fileAudio
                    : (isDark ? AppColors.darkOnSurface : null),
              ),
            ),
            subtitle: Text(
              track.displayArtist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.durationText,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_handle_rounded,
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
