import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 10 段均衡器频率（Hz），按 ISO 标准
const List<int> kEqBands = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

/// 单段增益范围（dB）
const double kEqMinGain = -12.0;
const double kEqMaxGain = 12.0;

/// 预设
class EqualizerPreset {
  const EqualizerPreset(this.id, this.name, this.gains);
  final String id;
  final String name;
  final List<double> gains; // 10 段
}

const List<EqualizerPreset> kEqPresets = [
  EqualizerPreset('flat', '平直', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  EqualizerPreset('pop', '流行', [-1, 1, 3, 5, 3, 1, -1, -1, 1, 3]),
  EqualizerPreset('rock', '摇滚', [5, 3, 1, -1, -2, 1, 3, 5, 5, 5]),
  EqualizerPreset('jazz', '爵士', [4, 3, 1, 2, -2, -2, 0, 1, 2, 3]),
  EqualizerPreset('classical', '古典', [5, 4, 3, 2, -2, -2, 0, 2, 3, 4]),
  EqualizerPreset('bass', '重低音', [7, 6, 5, 3, 1, 0, 0, 0, 0, 0]),
  EqualizerPreset('treble', '高音', [0, 0, 0, 0, 0, 1, 3, 5, 6, 7]),
  EqualizerPreset('vocal', '人声', [-2, -3, -3, 1, 4, 4, 3, 1, 0, -2]),
];

/// 当前生效的均衡器状态。变更后调用 [AudioEffectsService.apply] 推到播放引擎。
class EqualizerState {
  EqualizerState({
    this.enabled = false,
    this.presetId = 'flat',
    List<double>? gains,
  }) : gains = gains ?? List<double>.filled(10, 0);

  factory EqualizerState.fromMap(Map<dynamic, dynamic> m) {
    final raw = (m['gains'] as List?)?.cast<num>() ?? const [];
    final gains = List<double>.generate(
      10,
      (i) => i < raw.length ? raw[i].toDouble() : 0.0,
    );
    return EqualizerState(
      enabled: (m['enabled'] as bool?) ?? false,
      presetId: (m['presetId'] as String?) ?? 'flat',
      gains: gains,
    );
  }

  bool enabled;
  String presetId;
  List<double> gains; // 长度始终 10

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'presetId': presetId,
        'gains': gains,
      };

  EqualizerState copy() => EqualizerState(
        enabled: enabled,
        presetId: presetId,
        gains: List<double>.from(gains),
      );
}

/// 把均衡器状态转换为 mpv `af` 滤镜字符串。
///
/// 格式：`equalizer=f=31:width_type=q:w=1:g=g0,equalizer=f=62:...`
///
/// 当全部 gain ≈ 0 或 enabled=false 时返回空字符串（让调用方关掉 af）。
String buildMpvEqualizerFilter(EqualizerState state) {
  if (!state.enabled) return '';
  final hasNonZero = state.gains.any((g) => g.abs() > 0.05);
  if (!hasNonZero) return '';
  final parts = <String>[];
  for (var i = 0; i < kEqBands.length && i < state.gains.length; i++) {
    final f = kEqBands[i];
    final g = state.gains[i].clamp(kEqMinGain, kEqMaxGain);
    parts.add('equalizer=f=$f:width_type=q:w=1:g=${g.toStringAsFixed(2)}');
  }
  return parts.join(',');
}

/// 均衡器服务：持久化 + 通知。播放引擎适配在各 handler 内部完成（订阅 onChange）。
class AudioEffectsService {
  AudioEffectsService._();
  static final AudioEffectsService instance = AudioEffectsService._();

  static const _boxName = 'audio_effects';
  static const _stateKey = 'equalizer';

  Box<Map<dynamic, dynamic>>? _box;
  EqualizerState _state = EqualizerState();
  bool _initialized = false;

  final StreamController<EqualizerState> _onChange =
      StreamController<EqualizerState>.broadcast();

  /// 当前状态。返回拷贝以避免外部修改。
  EqualizerState get state => _state.copy();

  /// 状态变化广播流。播放引擎应订阅并即时应用。
  Stream<EqualizerState> get onChange => _onChange.stream;

  Future<void> init() async {
    if (_initialized) return;
    try {
      _box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
      final raw = _box!.get(_stateKey);
      if (raw != null) {
        _state = EqualizerState.fromMap(raw);
      }
      _initialized = true;
      logger.i('AudioEffectsService: init enabled=${_state.enabled} preset=${_state.presetId}');
    } on Exception catch (e, st) {
      logger.e('AudioEffectsService: init failed', e, st);
    }
  }

  Future<void> setEnabled({required bool enabled}) async {
    _state.enabled = enabled;
    await _save();
    _onChange.add(_state.copy());
  }

  Future<void> applyPreset(String presetId) async {
    final p = kEqPresets.firstWhere(
      (p) => p.id == presetId,
      orElse: () => kEqPresets.first,
    );
    _state
      ..presetId = p.id
      ..gains = List<double>.from(p.gains);
    await _save();
    _onChange.add(_state.copy());
  }

  Future<void> setBandGain(int bandIndex, double gainDb) async {
    if (bandIndex < 0 || bandIndex >= 10) return;
    final clamped = gainDb.clamp(kEqMinGain, kEqMaxGain);
    if ((_state.gains[bandIndex] - clamped).abs() < 0.01) return;
    _state
      ..gains[bandIndex] = clamped
      ..presetId = 'custom';
    await _save();
    _onChange.add(_state.copy());
  }

  Future<void> resetFlat() async {
    _state
      ..presetId = 'flat'
      ..gains = List<double>.filled(10, 0);
    await _save();
    _onChange.add(_state.copy());
  }

  Future<void> _save() async {
    if (_box == null) return;
    await _box!.put(_stateKey, _state.toMap());
  }
}
