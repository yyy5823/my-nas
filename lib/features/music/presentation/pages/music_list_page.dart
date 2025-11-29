import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/connection/presentation/providers/connection_provider.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/pages/music_player_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/mini_player.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/empty_widget.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';

/// 音乐列表状态
final musicListProvider =
    StateNotifierProvider<MusicListNotifier, MusicListState>((ref) =>
        MusicListNotifier(ref));

sealed class MusicListState {}

class MusicListLoading extends MusicListState {}

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
      state = MusicListError('未连接到 NAS');
      return;
    }

    try {
      // 递归扫描音乐文件 (简化版，只扫描根目录下一层)
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(musicListProvider.notifier).loadMusic(),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: switch (state) {
              MusicListLoading() => const LoadingWidget(message: '扫描音乐中...'),
              MusicListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () =>
                      ref.read(musicListProvider.notifier).loadMusic(),
                ),
              MusicListLoaded(:final tracks) when tracks.isEmpty =>
                const EmptyWidget(
                  icon: Icons.library_music_outlined,
                  title: '暂无音乐',
                  message: '在 NAS 中添加音乐后将显示在这里',
                ),
              MusicListLoaded(:final tracks) =>
                _buildMusicList(context, ref, tracks),
            },
          ),
          // 底部迷你播放器
          const MiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildMusicList(
    BuildContext context,
    WidgetRef ref,
    List<FileItem> tracks,
  ) =>
      ListView.builder(
        padding: AppSpacing.paddingSm,
        itemCount: tracks.length,
        itemBuilder: (context, index) =>
            _MusicListTile(track: tracks[index], index: index),
      );
}

class _MusicListTile extends ConsumerWidget {
  const _MusicListTile({
    required this.track,
    required this.index,
  });

  final FileItem track;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = currentMusic?.path == track.path;

    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: AppRadius.borderRadiusSm,
          color: isPlaying
              ? context.colorScheme.primary.withValues(alpha: 0.1)
              : context.colorScheme.surfaceContainerHighest,
        ),
        child: Center(
          child: Icon(
            isPlaying ? Icons.equalizer : Icons.music_note,
            color: isPlaying
                ? context.colorScheme.primary
                : context.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(
        track.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isPlaying ? context.colorScheme.primary : null,
          fontWeight: isPlaying ? FontWeight.bold : null,
        ),
      ),
      subtitle: Text(
        track.displaySize,
        style: context.textTheme.bodySmall?.copyWith(
          color: context.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) => _handleMenuAction(context, ref, value),
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'play_next',
            child: Row(
              children: [
                Icon(Icons.queue_play_next),
                SizedBox(width: 12),
                Text('下一首播放'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'add_to_queue',
            child: Row(
              children: [
                Icon(Icons.playlist_add),
                SizedBox(width: 12),
                Text('添加到播放列表'),
              ],
            ),
          ),
        ],
      ),
      onTap: () => _playTrack(context, ref),
    );
  }

  Future<void> _playTrack(BuildContext context, WidgetRef ref) async {
    final adapter = ref.read(activeAdapterProvider);
    if (adapter == null) return;

    // 获取音乐 URL
    final url = await adapter.fileSystem.getFileUrl(track.path);

    // 创建音乐项
    final musicItem = MusicItem.fromFileItem(track, url);

    if (!context.mounted) return;

    // 播放
    await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);

    // 导航到播放器页面
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const MusicPlayerPage(),
      ),
    );
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) {
    // TODO: 实现菜单操作
  }
}
