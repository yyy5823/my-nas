import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/capability/playback_capability_service.dart';
import 'package:my_nas/features/video/domain/entities/audio_capability.dart';
import 'package:my_nas/features/video/domain/entities/hdr_capability.dart';

/// HDR 和音频设置状态
class HdrAudioSettingsState {
  const HdrAudioSettingsState({
    required this.settings,
    this.hdrCapability,
    this.audioCapability,
    this.isLoading = false,
  });

  /// 用户设置
  final HdrAudioSettings settings;

  /// 检测到的 HDR 能力（可能为 null，表示未检测）
  final HdrCapability? hdrCapability;

  /// 检测到的音频能力（可能为 null，表示未检测）
  final AudioPassthroughCapability? audioCapability;

  /// 是否正在检测能力
  final bool isLoading;

  /// 复制
  HdrAudioSettingsState copyWith({
    HdrAudioSettings? settings,
    HdrCapability? hdrCapability,
    AudioPassthroughCapability? audioCapability,
    bool? isLoading,
  }) =>
      HdrAudioSettingsState(
        settings: settings ?? this.settings,
        hdrCapability: hdrCapability ?? this.hdrCapability,
        audioCapability: audioCapability ?? this.audioCapability,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// HDR 和音频设置 Provider
final hdrAudioSettingsProvider =
    StateNotifierProvider<HdrAudioSettingsNotifier, HdrAudioSettingsState>(
  (ref) => HdrAudioSettingsNotifier(),
);

/// HDR 和音频设置管理器
class HdrAudioSettingsNotifier extends StateNotifier<HdrAudioSettingsState> {
  HdrAudioSettingsNotifier()
      : super(const HdrAudioSettingsState(
          settings: HdrAudioSettings(),
        )) {
    _loadSettings();
  }

  static const _boxName = 'hdr_audio_settings';
  static const _settingsKey = 'settings';

  Box<dynamic>? _box;

  final _capabilityService = PlaybackCapabilityService();

  /// 加载设置
  Future<void> _loadSettings() async {
    try {
      if (Hive.isBoxOpen(_boxName)) {
        _box = Hive.box<dynamic>(_boxName);
      } else {
        _box = await Hive.openBox<dynamic>(_boxName);
      }
      final map = _box!.get(_settingsKey) as Map<dynamic, dynamic>?;
      final settings = HdrAudioSettings.fromMap(map);

      state = state.copyWith(settings: settings);
      logger.d('HdrAudioSettingsNotifier: 加载设置完成');

      // 异步检测设备能力
      await detectCapabilities();
    } catch (e, st) {
      AppError.ignore(e, st, '加载 HDR/音频设置失败');
    }
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    try {
      await _box?.put(_settingsKey, state.settings.toMap());
    } catch (e, st) {
      AppError.ignore(e, st, '保存 HDR/音频设置失败');
    }
  }

  /// 检测设备能力
  Future<void> detectCapabilities({bool forceRefresh = false}) async {
    state = state.copyWith(isLoading: true);

    try {
      final hdrCap = await _capabilityService.getHdrCapability(
        forceRefresh: forceRefresh,
      );
      final audioCap = await _capabilityService.getAudioCapability(
        forceRefresh: forceRefresh,
      );

      state = state.copyWith(
        hdrCapability: hdrCap,
        audioCapability: audioCap,
        isLoading: false,
      );

      logger.i('HdrAudioSettingsNotifier: 设备能力检测完成 - HDR: $hdrCap, Audio: $audioCap');
    } catch (e, st) {
      AppError.ignore(e, st, '设备能力检测失败');
      state = state.copyWith(isLoading: false);
    }
  }

  /// 设置 HDR 模式
  void setHdrMode(HdrMode mode) {
    state = state.copyWith(
      settings: state.settings.copyWith(hdrMode: mode),
    );
    _saveSettings();
    logger.d('HdrAudioSettingsNotifier: HDR 模式设置为 $mode');
  }

  /// 设置色调映射算法
  void setToneMappingMode(ToneMappingMode mode) {
    state = state.copyWith(
      settings: state.settings.copyWith(toneMappingMode: mode),
    );
    _saveSettings();
    logger.d('HdrAudioSettingsNotifier: 色调映射设置为 $mode');
  }

  /// 设置音频直通模式
  void setAudioPassthroughMode(AudioPassthroughMode mode) {
    state = state.copyWith(
      settings: state.settings.copyWith(audioPassthroughMode: mode),
    );
    _saveSettings();
    logger.d('HdrAudioSettingsNotifier: 音频直通设置为 $mode');
  }

  /// 设置启用的直通编码
  void setEnabledPassthroughCodecs(List<AudioCodec>? codecs) {
    state = state.copyWith(
      settings: state.settings.copyWith(enabledPassthroughCodecs: codecs),
    );
    _saveSettings();
    logger.d('HdrAudioSettingsNotifier: 直通编码设置为 $codecs');
  }

  /// 获取当前设置
  HdrAudioSettings get settings => state.settings;

  /// 获取 HDR 能力
  HdrCapability? get hdrCapability => state.hdrCapability;

  /// 获取音频能力
  AudioPassthroughCapability? get audioCapability => state.audioCapability;
}
