import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler_interface.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// 音乐播放设置
class MusicSettings {
  const MusicSettings({
    this.volume = 1.0,
    this.playMode = PlayMode.loop,
    this.crossfadeDuration = 0,
    this.autoPlayOnConnect = false,
    this.showLyrics = true,
    this.gaplessPlayback = true,
    this.dynamicIslandEnabled = true, // 默认开启，不在 UI 上显示开关
    this.playerEngine = MusicPlayerEngine.justAudio, // 播放引擎
    this.lyricsFontScale = 1.0, // 歌词字号缩放（pinch 持久化）
    this.lyricsTranslateEnabled = false, // 启用歌词翻译
    this.lyricsTranslateLang = 'zh-CN', // 翻译目标语言（BCP-47）
  });

  factory MusicSettings.fromMap(Map<dynamic, dynamic> map) => MusicSettings(
        volume: (map['volume'] as num?)?.toDouble() ?? 1.0,
        playMode: PlayMode.values[map['playMode'] as int? ?? 0],
        crossfadeDuration: map['crossfadeDuration'] as int? ?? 0,
        autoPlayOnConnect: map['autoPlayOnConnect'] as bool? ?? false,
        showLyrics: map['showLyrics'] as bool? ?? true,
        gaplessPlayback: map['gaplessPlayback'] as bool? ?? true,
        dynamicIslandEnabled: map['dynamicIslandEnabled'] as bool? ?? true,
        playerEngine: MusicPlayerEngine.values[map['playerEngine'] as int? ?? 0],
        lyricsFontScale:
            (map['lyricsFontScale'] as num?)?.toDouble() ?? 1.0,
        lyricsTranslateEnabled:
            map['lyricsTranslateEnabled'] as bool? ?? false,
        lyricsTranslateLang:
            (map['lyricsTranslateLang'] as String?) ?? 'zh-CN',
      );

  final double volume;
  final PlayMode playMode;
  final int crossfadeDuration; // 淡入淡出秒数 (0 表示关闭)
  final bool autoPlayOnConnect; // 连接后自动播放
  final bool showLyrics; // 显示歌词
  final bool gaplessPlayback; // 无缝播放
  final bool dynamicIslandEnabled; // Android 灵动岛悬浮窗（默认开启，不在 UI 显示）
  final MusicPlayerEngine playerEngine; // 播放引擎
  final double lyricsFontScale; // 歌词字号缩放 (0.7 - 1.8)
  final bool lyricsTranslateEnabled;
  final String lyricsTranslateLang; // BCP-47

  /// 歌词字号缩放范围
  static const double minLyricsFontScale = 0.7;
  static const double maxLyricsFontScale = 1.8;

  /// 是否使用 media_kit 引擎
  bool get useMediaKitEngine => playerEngine == MusicPlayerEngine.mediaKit;

  MusicSettings copyWith({
    double? volume,
    PlayMode? playMode,
    int? crossfadeDuration,
    bool? autoPlayOnConnect,
    bool? showLyrics,
    bool? gaplessPlayback,
    bool? dynamicIslandEnabled,
    MusicPlayerEngine? playerEngine,
    double? lyricsFontScale,
    bool? lyricsTranslateEnabled,
    String? lyricsTranslateLang,
  }) =>
      MusicSettings(
        volume: volume ?? this.volume,
        playMode: playMode ?? this.playMode,
        crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
        autoPlayOnConnect: autoPlayOnConnect ?? this.autoPlayOnConnect,
        showLyrics: showLyrics ?? this.showLyrics,
        gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
        dynamicIslandEnabled: dynamicIslandEnabled ?? this.dynamicIslandEnabled,
        playerEngine: playerEngine ?? this.playerEngine,
        lyricsFontScale: lyricsFontScale ?? this.lyricsFontScale,
        lyricsTranslateEnabled:
            lyricsTranslateEnabled ?? this.lyricsTranslateEnabled,
        lyricsTranslateLang:
            lyricsTranslateLang ?? this.lyricsTranslateLang,
      );

  Map<String, dynamic> toMap() => {
        'volume': volume,
        'playMode': playMode.index,
        'crossfadeDuration': crossfadeDuration,
        'autoPlayOnConnect': autoPlayOnConnect,
        'showLyrics': showLyrics,
        'gaplessPlayback': gaplessPlayback,
        'dynamicIslandEnabled': dynamicIslandEnabled,
        'playerEngine': playerEngine.index,
        'lyricsFontScale': lyricsFontScale,
        'lyricsTranslateEnabled': lyricsTranslateEnabled,
        'lyricsTranslateLang': lyricsTranslateLang,
      };
}

/// 音乐设置管理
class MusicSettingsNotifier extends StateNotifier<MusicSettings> {
  MusicSettingsNotifier(this._ref) : super(const MusicSettings()) {
    _load();
  }

  final Ref _ref;
  static const _boxName = 'music_settings';
  static const _settingsKey = 'settings';

  Box<Map<dynamic, dynamic>>? _box;
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;

    try {
      _box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
      _initialized = true;
    } on Exception catch (e) {
      logger.e('MusicSettingsNotifier: 初始化失败', e);
    }
  }

  Future<void> _load() async {
    await _init();
    if (_box == null) return;

    final data = _box!.get(_settingsKey);
    if (data != null) {
      state = MusicSettings.fromMap(data);
      logger.i('MusicSettingsNotifier: 加载设置成功, playMode=${state.playMode}');
      // 同步播放模式到播放器
      _ref.read(musicPlayerControllerProvider.notifier).setPlayMode(state.playMode);
    }
  }

  Future<void> _save() async {
    await _init();
    if (_box == null) return;

    await _box!.put(_settingsKey, state.toMap());
  }

  /// 设置音量
  Future<void> setVolume(double volume) async {
    final clampedVolume = volume.clamp(0.0, 1.0);
    state = state.copyWith(volume: clampedVolume);
    await _save();
    // 同步到播放器（使用 setVolumeInternal 方法，避免循环调用）
    AppError.fireAndForget(
      _ref.read(musicPlayerControllerProvider.notifier).setVolumeInternal(clampedVolume),
      action: 'musicSettings.syncVolumeToPlayer',
    );
  }

  /// 设置播放模式
  Future<void> setPlayMode(PlayMode mode) async {
    state = state.copyWith(playMode: mode);
    await _save();
    // 同步到播放器
    _ref.read(musicPlayerControllerProvider.notifier).setPlayMode(mode);
  }

  /// 设置淡入淡出时长
  Future<void> setCrossfadeDuration(int seconds) async {
    state = state.copyWith(crossfadeDuration: seconds.clamp(0, 12));
    await _save();
  }

  /// 设置连接后自动播放
  Future<void> setAutoPlayOnConnect({required bool enabled}) async {
    state = state.copyWith(autoPlayOnConnect: enabled);
    await _save();
  }

  /// 设置显示歌词
  Future<void> setShowLyrics({required bool enabled}) async {
    state = state.copyWith(showLyrics: enabled);
    await _save();
  }

  /// 设置无缝播放
  Future<void> setGaplessPlayback({required bool enabled}) async {
    state = state.copyWith(gaplessPlayback: enabled);
    await _save();
  }

  /// 设置 Android 灵动岛悬浮窗（功能保留，不在 UI 上显示开关）
  Future<void> setDynamicIslandEnabled({required bool enabled}) async {
    state = state.copyWith(dynamicIslandEnabled: enabled);
    await _save();
    // 同步到播放器
    await _ref.read(musicPlayerControllerProvider.notifier).setDynamicIslandEnabled(enabled: enabled);
  }

  /// 设置播放引擎
  ///
  /// 注意：更改引擎需要重启应用才能生效
  /// - [MusicPlayerEngine.justAudio] - 平台原生解码器（默认，灵动岛稳定）
  /// - [MusicPlayerEngine.mediaKit] - FFmpeg 解码器（支持 AC3/DTS 等高级格式）
  Future<void> setPlayerEngine(MusicPlayerEngine engine) async {
    state = state.copyWith(playerEngine: engine);
    await _save();
    logger.i('MusicSettingsNotifier: 播放引擎已更改为 $engine，需要重启应用生效');
  }

  /// 启用 / 禁用歌词翻译
  Future<void> setLyricsTranslateEnabled({required bool enabled}) async {
    state = state.copyWith(lyricsTranslateEnabled: enabled);
    await _save();
  }

  /// 设置翻译目标语言（BCP-47）
  Future<void> setLyricsTranslateLang(String lang) async {
    state = state.copyWith(lyricsTranslateLang: lang);
    await _save();
  }

  /// 设置歌词字号缩放（0.7 - 1.8）
  Future<void> setLyricsFontScale(double scale) async {
    final clamped = scale.clamp(
      MusicSettings.minLyricsFontScale,
      MusicSettings.maxLyricsFontScale,
    );
    if ((state.lyricsFontScale - clamped).abs() < 0.001) return;
    state = state.copyWith(lyricsFontScale: clamped);
    await _save();
  }

  /// 重置设置
  Future<void> reset() async {
    state = const MusicSettings();
    await _save();
  }
}

/// 音乐设置 provider
final musicSettingsProvider =
    StateNotifierProvider<MusicSettingsNotifier, MusicSettings>(MusicSettingsNotifier.new);

/// 可用的淡入淡出时长选项
const availableCrossfadeDurations = [0, 2, 4, 6, 8, 10, 12];
