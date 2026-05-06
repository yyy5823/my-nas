import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/lyric_service.dart';
import 'package:my_nas/features/music/data/services/lyrics_translation_service.dart';
import 'package:my_nas/features/music/data/services/music_metadata_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_settings_provider.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';

/// 当前歌词
final currentLyricProvider = StateNotifierProvider<LyricNotifier, LyricState>(LyricNotifier.new);

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
  }) => LyricState(
      lyricData: lyricData ?? this.lyricData,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
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

    // 监听翻译开关 / 目标语言变化 → 即时重翻当前歌词
    _ref.listen<MusicSettings>(musicSettingsProvider, (prev, next) {
      final toggled = prev?.lyricsTranslateEnabled !=
          next.lyricsTranslateEnabled;
      final langChanged =
          prev?.lyricsTranslateLang != next.lyricsTranslateLang;
      if (toggled || langChanged) {
        AppError.fireAndForget(
          retranslate(),
          action: 'lyric.retranslateOnSettingsChange',
        );
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
  /// 优先从 .lrc 文件加载，如果没有则尝试从音频文件提取嵌入歌词
  Future<void> loadLyrics(MusicItem music) async {
    state = state.copyWith(isLoading: true);

    try {
      // 首先检查是否有已提取的嵌入歌词
      if (music.lyrics != null && music.lyrics!.isNotEmpty) {
        final lyricData = LyricService().parseLyrics(music.lyrics!);
        state = state.copyWith(
          lyricData: lyricData,
          isLoading: false,
        );
        return;
      }

      // 获取连接
      final connections = _ref.read(activeConnectionsProvider);
      final connection = connections[music.sourceId];

      if (connection == null || connection.status != SourceStatus.connected) {
        state = state.copyWith(
          isLoading: false,
          lyricData: LyricData.empty,
        );
        return;
      }

      // 尝试从同目录的 .lrc 文件加载
      var lyricData = await LyricService().loadLyrics(
        musicPath: music.path,
        musicName: music.name,
        fileSystem: connection.adapter.fileSystem,
      );

      // 如果没有 .lrc 文件，尝试从音频文件提取嵌入歌词
      if (lyricData.isEmpty) {
        logger.d('LyricNotifier: 未找到 .lrc 文件，尝试从音频提取嵌入歌词');
        lyricData = await _extractEmbeddedLyrics(music, connection);
      }

      state = state.copyWith(
        lyricData: lyricData,
        isLoading: false,
      );

      // 异步触发翻译（不阻塞首屏歌词渲染）
      AppError.fireAndForget(
        _translateIfEnabled(),
        action: 'lyricNotifier.translate',
      );
    } on Exception catch (e) {
      logger.e('LyricNotifier: 加载歌词失败', e);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        lyricData: LyricData.empty,
      );
    }
  }

  /// 从音频文件提取嵌入歌词
  Future<LyricData> _extractEmbeddedLyrics(MusicItem music, SourceConnection connection) async {
    try {
      // 从 NAS 提取元数据（不跳过歌词）
      final metadata = await MusicMetadataService().extractFromNasFile(
        connection.adapter.fileSystem,
        music.path,
      );

      if (metadata != null && metadata.hasLyrics) {
        logger.i('LyricNotifier: 从音频文件提取到嵌入歌词');
        return LyricService().parseLyrics(metadata.lyrics!);
      }
    } on Exception catch (e) {
      logger.w('LyricNotifier: 从音频提取嵌入歌词失败', e);
    }
    return LyricData.empty;
  }

  /// 清除歌词
  void clear() {
    state = const LyricState();
  }

  /// 若开启翻译开关，调 LyricsTranslationService 把每行 text 翻译后回填
  Future<void> _translateIfEnabled() async {
    final settings = _ref.read(musicSettingsProvider);
    if (!settings.lyricsTranslateEnabled) return;
    final data = state.lyricData;
    if (data.isEmpty) return;
    final texts = data.lines.map((l) => l.text).toList();
    final results = await LyricsTranslationService.instance.translateBatch(
      texts: texts,
      targetLang: settings.lyricsTranslateLang,
    );
    final translated = data.lines.map((l) {
      final t = results[l.text];
      if (t == null || t.trim().isEmpty || t == l.text) return l;
      return l.copyWith(translation: t);
    }).toList();
    state = state.copyWith(
      lyricData: LyricData(
        lines: translated,
        title: data.title,
        artist: data.artist,
        album: data.album,
      ),
    );
  }

  /// 用户切换翻译开关后，重新翻译当前歌词
  Future<void> retranslate() => _translateIfEnabled();
}
