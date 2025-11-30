import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/presentation/providers/playlist_provider.dart';

/// 显示播放列表
void showPlaylistSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const PlaylistSheet(),
  );
}

class PlaylistSheet extends ConsumerWidget {
  const PlaylistSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final playlist = ref.watch(playlistProvider);
    final playlistNotifier = ref.read(playlistProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
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
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.playlist_play_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '播放列表',
                          style: context.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${playlist.length} 个视频',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 循环模式
                  IconButton(
                    onPressed: playlistNotifier.toggleRepeatMode,
                    icon: Icon(
                      _getRepeatIcon(playlist.repeatMode),
                      color: playlist.repeatMode != RepeatMode.none
                          ? AppColors.primary
                          : null,
                    ),
                    tooltip: _getRepeatTooltip(playlist.repeatMode),
                  ),
                  // 随机播放
                  IconButton(
                    onPressed: playlistNotifier.toggleShuffle,
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color: playlist.shuffleEnabled ? AppColors.primary : null,
                    ),
                    tooltip: playlist.shuffleEnabled ? '关闭随机' : '随机播放',
                  ),
                  // 清空列表
                  if (playlist.items.isNotEmpty)
                    IconButton(
                      onPressed: () {
                        showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('清空播放列表'),
                            content: const Text('确定要清空播放列表吗？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('确定'),
                              ),
                            ],
                          ),
                        ).then((confirmed) {
                          if (confirmed == true) {
                            playlistNotifier.clearPlaylist();
                          }
                        });
                      },
                      icon: const Icon(Icons.clear_all_rounded),
                      tooltip: '清空列表',
                    ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 播放列表内容
            Expanded(
              child: playlist.isEmpty
                  ? _buildEmptyState(context, isDark)
                  : ReorderableListView.builder(
                      scrollController: scrollController,
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      itemCount: playlist.items.length,
                      onReorder: playlistNotifier.moveItem,
                      itemBuilder: (context, index) {
                        final item = playlist.items[index];
                        final isPlaying = index == playlist.currentIndex;

                        return _PlaylistItem(
                          key: ValueKey(item.path),
                          item: item,
                          index: index,
                          isPlaying: isPlaying,
                          isDark: isDark,
                          onTap: () {
                            playlistNotifier.playAt(index);
                            Navigator.pop(context);
                          },
                          onRemove: () {
                            playlistNotifier.removeFromPlaylist(index);
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
              Icons.queue_music_rounded,
              size: 64,
              color: isDark
                  ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.5)
                  : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '播放列表为空',
              style: context.textTheme.titleMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '从视频列表中选择视频播放',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.7)
                    : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );

  IconData _getRepeatIcon(RepeatMode mode) => switch (mode) {
        RepeatMode.none => Icons.repeat_rounded,
        RepeatMode.all => Icons.repeat_rounded,
        RepeatMode.one => Icons.repeat_one_rounded,
      };

  String _getRepeatTooltip(RepeatMode mode) => switch (mode) {
        RepeatMode.none => '列表循环',
        RepeatMode.all => '单曲循环',
        RepeatMode.one => '关闭循环',
      };
}

class _PlaylistItem extends StatelessWidget {
  const _PlaylistItem({
    required super.key,
    required this.item,
    required this.index,
    required this.isPlaying,
    required this.isDark,
    required this.onTap,
    required this.onRemove,
  });

  final VideoItem item;
  final int index;
  final bool isPlaying;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Dismissible(
        key: ValueKey('dismiss_${item.path}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onRemove(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: Colors.red,
          child: const Icon(Icons.delete_rounded, color: Colors.white),
        ),
        child: ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPlaying
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : (isDark
                      ? AppColors.darkSurfaceVariant
                      : AppColors.lightSurfaceVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: isPlaying
                  ? const Icon(
                      Icons.play_arrow_rounded,
                      color: AppColors.primary,
                    )
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
          title: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
              color: isPlaying ? AppColors.primary : null,
            ),
          ),
          subtitle: Text(
            _formatSize(item.size),
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? AppColors.darkOnSurfaceVariant
                  : AppColors.lightOnSurfaceVariant,
            ),
          ),
          trailing: ReorderableDragStartListener(
            index: index,
            child: const Icon(Icons.drag_handle_rounded),
          ),
          onTap: onTap,
        ),
      );

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
