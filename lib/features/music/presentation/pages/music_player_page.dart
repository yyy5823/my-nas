import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/music_player_controls.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              // TODO: 处理菜单操作
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'add_to_playlist',
                child: Row(
                  children: [
                    Icon(Icons.playlist_add),
                    SizedBox(width: 12),
                    Text('添加到播放列表'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share),
                    SizedBox(width: 12),
                    Text('分享'),
                  ],
                ),
              ),
            ],
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
