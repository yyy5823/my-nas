import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/connection/presentation/providers/connection_provider.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/pages/music_player_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/mini_player.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/empty_widget.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';
import 'package:my_nas/shared/widgets/not_connected_widget.dart';

/// 音乐列表状态
final musicListProvider =
    StateNotifierProvider<MusicListNotifier, MusicListState>(
        (ref) => MusicListNotifier(ref));

sealed class MusicListState {}

class MusicListLoading extends MusicListState {}

class MusicListNotConnected extends MusicListState {}

class MusicListLoaded extends MusicListState {
  MusicListLoaded(this.tracks);
  final List<FileItem> tracks;
}

class MusicListError extends MusicListState {
  MusicListError(this.message);
  final String message;
}

class MusicListNotifier extends StateNotifier<MusicListState> {
  MusicListNotifier(this._ref) : super(MusicListLoading()) {
    loadMusic();
  }

  final Ref _ref;

  Future<void> loadMusic() async {
    state = MusicListLoading();

    final adapter = _ref.read(activeAdapterProvider);
    if (adapter == null) {
      state = MusicListNotConnected();
      return;
    }

    try {
      final shares = await adapter.fileSystem.listDirectory('/');
      final tracks = <FileItem>[];

      for (final share in shares) {
        if (share.isDirectory) {
          try {
            final files = await adapter.fileSystem.listDirectory(share.path);
            tracks.addAll(
              files.where((f) => f.type == FileType.audio),
            );
          } on Exception {
            // 忽略无法访问的目录
          }
        }
      }

      state = MusicListLoaded(tracks);
    } on Exception catch (e) {
      state = MusicListError(e.toString());
    }
  }
}

class MusicListPage extends ConsumerWidget {
  const MusicListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(musicListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          _buildAppBar(context, ref, isDark),
          Expanded(
            child: switch (state) {
              MusicListLoading() => const LoadingWidget(message: '扫描音乐中...'),
              MusicListNotConnected() => const NotConnectedWidget(
                  icon: Icons.library_music_outlined,
                  message: '连接到 NAS 后即可浏览和播放音乐',
                ),
              MusicListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(musicListProvider.notifier).loadMusic(),
                ),
              MusicListLoaded(:final tracks) when tracks.isEmpty => const EmptyWidget(
                  icon: Icons.library_music_outlined,
                  title: '暂无音乐',
                  message: '在 NAS 中添加音乐后将显示在这里',
                ),
              MusicListLoaded(:final tracks) => _buildMusicList(context, ref, tracks, isDark),
            },
          ),
          // 底部迷你播放器
          const MiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, WidgetRef ref, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withOpacity(0.2)
                : context.colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text(
                '音乐',
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : null,
                ),
              ),
              const Spacer(),
              _buildIconButton(
                icon: Icons.refresh_rounded,
                onTap: () => ref.read(musicListProvider.notifier).loadMusic(),
                isDark: isDark,
                tooltip: '刷新',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isDark ? AppColors.darkOnSurfaceVariant : null,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMusicList(
    BuildContext context,
    WidgetRef ref,
    List<FileItem> tracks,
    bool isDark,
  ) =>
      ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: tracks.length,
        itemBuilder: (context, index) => _MusicListTile(
          track: tracks[index],
          index: index,
          isDark: isDark,
        ),
      );
}

class _MusicListTile extends ConsumerWidget {
  const _MusicListTile({
    required this.track,
    required this.index,
    required this.isDark,
  });

  final FileItem track;
  final int index;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = currentMusic?.path == track.path;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isPlaying
            ? AppColors.fileAudio.withOpacity(isDark ? 0.15 : 0.1)
            : (isDark
                ? AppColors.darkSurfaceVariant.withOpacity(0.3)
                : context.colorScheme.surface),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPlaying
              ? AppColors.fileAudio.withOpacity(0.3)
              : (isDark
                  ? AppColors.darkOutline.withOpacity(0.2)
                  : context.colorScheme.outlineVariant.withOpacity(0.5)),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playTrack(context, ref),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // 专辑封面占位
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
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
                            : context.colorScheme.surfaceContainerHighest),
                  ),
                  child: Icon(
                    isPlaying ? Icons.equalizer_rounded : Icons.music_note_rounded,
                    color: isPlaying
                        ? Colors.white
                        : (isDark
                            ? AppColors.darkOnSurfaceVariant
                            : context.colorScheme.onSurfaceVariant),
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // 歌曲信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyLarge?.copyWith(
                          color: isPlaying
                              ? AppColors.fileAudio
                              : (isDark ? AppColors.darkOnSurface : null),
                          fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: (isDark
                                      ? AppColors.darkSurfaceElevated
                                      : context.colorScheme.surfaceContainerHighest)
                                  .withOpacity(isDark ? 1 : 0.8),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              track.displaySize,
                              style: context.textTheme.labelSmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 菜单按钮
                PopupMenuButton<String>(
                  onSelected: (value) => _handleMenuAction(context, ref, value),
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: isDark ? AppColors.darkOnSurfaceVariant : null,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: isDark ? AppColors.darkSurface : null,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'play_next',
                      child: Row(
                        children: [
                          Icon(
                            Icons.queue_play_next_rounded,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '下一首播放',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'add_to_queue',
                      child: Row(
                        children: [
                          Icon(
                            Icons.playlist_add_rounded,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '添加到播放列表',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'add_to_favorites',
                      child: Row(
                        children: [
                          Icon(
                            Icons.favorite_border_rounded,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '收藏',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playTrack(BuildContext context, WidgetRef ref) async {
    final adapter = ref.read(activeAdapterProvider);
    if (adapter == null) return;

    final url = await adapter.fileSystem.getFileUrl(track.path);
    final musicItem = MusicItem.fromFileItem(track, url);

    if (!context.mounted) return;

    await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const MusicPlayerPage(),
      ),
    );
  }

  Future<void> _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    final adapter = ref.read(activeAdapterProvider);
    if (adapter == null) return;

    final url = await adapter.fileSystem.getFileUrl(track.path);
    final musicItem = MusicItem.fromFileItem(track, url);

    switch (action) {
      case 'play_next':
        // 获取当前队列和索引
        final queue = ref.read(playQueueProvider);
        final playerState = ref.read(musicPlayerControllerProvider);

        if (queue.isEmpty) {
          // 如果队列为空，直接播放
          await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
        } else {
          // 插入到当前播放的下一个位置
          final insertIndex = playerState.currentIndex + 1;
          final newQueue = [...queue];
          newQueue.insert(insertIndex.clamp(0, newQueue.length), musicItem);
          ref.read(playQueueProvider.notifier).setQueue(newQueue);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已添加到下一首播放')),
            );
          }
        }

      case 'add_to_queue':
        ref.read(playQueueProvider.notifier).addToQueue(musicItem);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已添加到播放队列')),
          );
        }

      case 'add_to_favorites':
        final isFav = await ref.read(musicFavoritesProvider.notifier).toggleFavorite(musicItem);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(isFav ? '已添加到收藏' : '已取消收藏')),
          );
        }
    }
  }
}
