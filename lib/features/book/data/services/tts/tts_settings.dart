import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/utils/logger.dart';

/// TTS 引擎类型
enum TTSEngine {
  /// 系统 TTS（离线）
  system,
  /// Edge TTS（在线高品质）
  edge,
}

/// TTS 设置
@immutable
class TTSSettings {
  const TTSSettings({
    this.engine = TTSEngine.system,
    this.speechRate = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.selectedVoiceId,
    this.selectedEdgeVoiceId,
    this.autoScrollFollow = true,
    this.highlightEnabled = true,
    this.autoPlayNextChapter = true,
  });

  factory TTSSettings.fromJson(Map<String, dynamic> json) => TTSSettings(
        engine: TTSEngine.values.firstWhere(
          (e) => e.name == json['engine'],
          orElse: () => TTSEngine.system,
        ),
        speechRate: (json['speechRate'] as num?)?.toDouble() ?? 1.0,
        pitch: (json['pitch'] as num?)?.toDouble() ?? 1.0,
        volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
        selectedVoiceId: json['selectedVoiceId'] as String?,
        selectedEdgeVoiceId: json['selectedEdgeVoiceId'] as String?,
        autoScrollFollow: json['autoScrollFollow'] as bool? ?? true,
        highlightEnabled: json['highlightEnabled'] as bool? ?? true,
        autoPlayNextChapter: json['autoPlayNextChapter'] as bool? ?? true,
      );

  /// TTS 引擎
  final TTSEngine engine;

  /// 语速 (0.5 - 2.0)
  final double speechRate;

  /// 音调 (0.5 - 2.0)
  final double pitch;

  /// 音量 (0.0 - 1.0)
  final double volume;

  /// 系统 TTS 选中的音色 ID
  final String? selectedVoiceId;

  /// Edge TTS 选中的音色 ID
  final String? selectedEdgeVoiceId;

  /// 自动滚动跟随
  final bool autoScrollFollow;

  /// 启用高亮
  final bool highlightEnabled;

  /// 自动播放下一章
  final bool autoPlayNextChapter;

  /// 是否使用在线引擎
  bool get isOnlineEngine => engine == TTSEngine.edge;

  TTSSettings copyWith({
    TTSEngine? engine,
    double? speechRate,
    double? pitch,
    double? volume,
    String? selectedVoiceId,
    String? selectedEdgeVoiceId,
    bool? autoScrollFollow,
    bool? highlightEnabled,
    bool? autoPlayNextChapter,
  }) =>
      TTSSettings(
        engine: engine ?? this.engine,
        speechRate: speechRate ?? this.speechRate,
        pitch: pitch ?? this.pitch,
        volume: volume ?? this.volume,
        selectedVoiceId: selectedVoiceId ?? this.selectedVoiceId,
        selectedEdgeVoiceId: selectedEdgeVoiceId ?? this.selectedEdgeVoiceId,
        autoScrollFollow: autoScrollFollow ?? this.autoScrollFollow,
        highlightEnabled: highlightEnabled ?? this.highlightEnabled,
        autoPlayNextChapter: autoPlayNextChapter ?? this.autoPlayNextChapter,
      );

  /// 清除选中音色
  TTSSettings clearVoice() => TTSSettings(
        engine: engine,
        speechRate: speechRate,
        pitch: pitch,
        volume: volume,
        selectedVoiceId: null,
        selectedEdgeVoiceId: null,
        autoScrollFollow: autoScrollFollow,
        highlightEnabled: highlightEnabled,
        autoPlayNextChapter: autoPlayNextChapter,
      );

  Map<String, dynamic> toJson() => {
        'engine': engine.name,
        'speechRate': speechRate,
        'pitch': pitch,
        'volume': volume,
        'selectedVoiceId': selectedVoiceId,
        'selectedEdgeVoiceId': selectedEdgeVoiceId,
        'autoScrollFollow': autoScrollFollow,
        'highlightEnabled': highlightEnabled,
        'autoPlayNextChapter': autoPlayNextChapter,
      };
}


/// TTS 设置持久化服务
class TTSSettingsService {
  factory TTSSettingsService() => _instance ??= TTSSettingsService._();
  TTSSettingsService._();

  static TTSSettingsService? _instance;

  static const String _boxName = 'tts_settings';
  static const String _settingsKey = 'settings';

  Box<String>? _box;

  /// 初始化
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    try {
      _box = await Hive.openBox<String>(_boxName);
      logger.i('TTSSettingsService: 初始化完成');
    } on Exception catch (e) {
      logger.e('TTSSettingsService: 初始化失败', e);
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox<String>(_boxName);
    }
  }

  /// 获取设置
  TTSSettings getSettings() {
    if (_box == null) return const TTSSettings();
    final jsonStr = _box!.get(_settingsKey);
    if (jsonStr == null) return const TTSSettings();
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return TTSSettings.fromJson(json);
    } on Exception catch (e) {
      logger.w('TTSSettingsService: 解析设置失败', e);
      return const TTSSettings();
    }
  }

  /// 保存设置
  Future<void> saveSettings(TTSSettings settings) async {
    if (_box == null) await init();
    try {
      await _box!.put(_settingsKey, jsonEncode(settings.toJson()));
      logger.d('TTSSettingsService: 保存设置成功');
    } on Exception catch (e) {
      logger.e('TTSSettingsService: 保存设置失败', e);
    }
  }
}
