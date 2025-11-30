import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/music_player_controls.dart';
import 'package:my_nas/features/music/presentation/widgets/music_queue_sheet.dart';
import 'package:my_nas/features/music/presentation/widgets/music_settings_sheet.dart';

class MusicPlayerPage extends ConsumerWidget {
  const MusicPlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final playerNotifier = ref.read(musicPlayerControllerProvider.notifier);

    if (currentMusic == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('正在播放'),
        ),
        body: const Center(
          child: Text('未选择音乐'),
        ),
      );
    }

    // 检查是否已收藏
    final isFavoriteAsync = ref.watch(isMusicFavoriteProvider(currentMusic.path));

    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        centerTitle: true,
        actions: [
          // 收藏按钮
          isFavoriteAsync.when(
            data: (isFavorite) => IconButton(
              onPressed: () async {
                final result = await ref
                    .read(musicFavoritesProvider.notifier)
                    .toggleFavorite(currentMusic);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result ? '已添加到收藏' : '已取消收藏')),
                  );
                }
              },
              icon: Icon(
                isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFavorite ? AppColors.fileAudio : null,
              ),
              tooltip: isFavorite ? '取消收藏' : '收藏',
            ),
            loading: () => const SizedBox(
              width: 48,
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
            error: (_, __) => IconButton(
              onPressed: null,
              icon: const Icon(Icons.favorite_border_rounded),
            ),
          ),
          // 队列按钮
          IconButton(
            onPressed: () => showMusicQueueSheet(context),
            icon: const Icon(Icons.queue_music_rounded),
            tooltip: '播放队列',
          ),
          // 设置按钮
          IconButton(
            onPressed: () => showMusicSettingsSheet(context),
            icon: const Icon(Icons.settings_rounded),
            tooltip: '播放设置',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            children: [
              const Spacer(),
              // 封面
              _buildCover(context),
              const SizedBox(height: 32),
              // 歌曲信息
              _buildTrackInfo(context, currentMusic.name, currentMusic.displayArtist),
              const SizedBox(height: 32),
              // 播放控制
              MusicPlayerControls(
                state: playerState,
                onPlayPause: playerNotifier.playOrPause,
                onNext: playerNotifier.playNext,
                onPrevious: playerNotifier.playPrevious,
                onSeek: playerNotifier.seek,
                onVolumeChange: playerNotifier.setVolume,
                onTogglePlayMode: playerNotifier.togglePlayMode,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final currentMusic = ProviderScope.containerOf(context).read(currentMusicProvider);

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          borderRadius: AppRadius.borderRadiusLg,
          color: context.colorScheme.surfaceContainerHighest,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: currentMusic?.coverUrl != null
            ? Image.network(
                currentMusic!.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildCoverPlaceholder(context),
              )
            : _buildCoverPlaceholder(context),
      ),
    );
  }

  Widget _buildCoverPlaceholder(BuildContext context) => Center(
        child: Icon(
          Icons.album,
          size: 120,
          color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
        ),
      );

  Widget _buildTrackInfo(BuildContext context, String title, String artist) =>
      Column(
        children: [
          Text(
            title,
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            artist,
            style: context.textTheme.bodyLarge?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
}
