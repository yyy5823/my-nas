import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/logger.dart';
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
  });

  factory MusicSettings.fromMap(Map<dynamic, dynamic> map) => MusicSettings(
        volume: (map['volume'] as num?)?.toDouble() ?? 1.0,
        playMode: PlayMode.values[map['playMode'] as int? ?? 0],
        crossfadeDuration: map['crossfadeDuration'] as int? ?? 0,
        autoPlayOnConnect: map['autoPlayOnConnect'] as bool? ?? false,
        showLyrics: map['showLyrics'] as bool? ?? true,
        gaplessPlayback: map['gaplessPlayback'] as bool? ?? true,
      );

  final double volume;
  final PlayMode playMode;
  final int crossfadeDuration; // 淡入淡出秒数 (0 表示关闭)
  final bool autoPlayOnConnect; // 连接后自动播放
  final bool showLyrics; // 显示歌词
  final bool gaplessPlayback; // 无缝播放

  MusicSettings copyWith({
    double? volume,
    PlayMode? playMode,
    int? crossfadeDuration,
    bool? autoPlayOnConnect,
    bool? showLyrics,
    bool? gaplessPlayback,
  }) =>
      MusicSettings(
        volume: volume ?? this.volume,
        playMode: playMode ?? this.playMode,
        crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
        autoPlayOnConnect: autoPlayOnConnect ?? this.autoPlayOnConnect,
        showLyrics: showLyrics ?? this.showLyrics,
        gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
      );

  Map<String, dynamic> toMap() => {
        'volume': volume,
        'playMode': playMode.index,
        'crossfadeDuration': crossfadeDuration,
        'autoPlayOnConnect': autoPlayOnConnect,
        'showLyrics': showLyrics,
        'gaplessPlayback': gaplessPlayback,
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
      logger.i('MusicSettingsNotifier: 加载设置成功');
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
    // 同步到播放器
    unawaited(_ref.read(musicPlayerControllerProvider.notifier).player.setVolume(clampedVolume));
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
