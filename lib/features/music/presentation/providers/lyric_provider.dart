import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/music/data/services/lyric_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';

/// 当前歌词
final currentLyricProvider = StateNotifierProvider<LyricNotifier, LyricState>((ref) {
  return LyricNotifier(ref);
});

/// 歌词状态
class LyricState {
  const LyricState({
    this.lyricData = LyricData.empty,
    this.isLoading = false,
    this.error,
  });

  final LyricData lyricData;
  final bool isLoading;
  final String? error;

  LyricState copyWith({
    LyricData? lyricData,
    bool? isLoading,
    String? error,
  }) {
    return LyricState(
      lyricData: lyricData ?? this.lyricData,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 歌词管理器
class LyricNotifier extends StateNotifier<LyricState> {
  LyricNotifier(this._ref) : super(const LyricState()) {
    // 监听当前音乐变化
    _ref.listen<MusicItem?>(currentMusicProvider, (previous, next) {
      if (next != null && next != previous) {
        loadLyrics(next);
      } else if (next == null) {
        state = const LyricState();
      }
    });

    // 初始化时检查是否已有音乐在播放
    final currentMusic = _ref.read(currentMusicProvider);
    if (currentMusic != null) {
      loadLyrics(currentMusic);
    }
  }

  final Ref _ref;

  /// 加载歌词
  Future<void> loadLyrics(MusicItem music) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // 首先检查是否有嵌入的歌词（从 ID3 标签提取）
      if (music.lyrics != null && music.lyrics!.isNotEmpty) {
        final lyricData = LyricService.instance.parseLyrics(music.lyrics!);
        state = state.copyWith(
          lyricData: lyricData,
          isLoading: false,
        );
        return;
      }

      // 尝试从同目录的 .lrc 文件加载
      final connections = _ref.read(activeConnectionsProvider);
      final connection = connections[music.sourceId];

      if (connection == null || connection.status != SourceStatus.connected) {
        state = state.copyWith(
          isLoading: false,
          lyricData: LyricData.empty,
        );
        return;
      }

      final lyricData = await LyricService.instance.loadLyrics(
        musicPath: music.path,
        musicName: music.name,
        fileSystem: connection.adapter.fileSystem,
      );

      state = state.copyWith(
        lyricData: lyricData,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        lyricData: LyricData.empty,
      );
    }
  }

  /// 清除歌词
  void clear() {
    state = const LyricState();
  }
}
