import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

/// 字幕样式状态
class SubtitleStyle {
  const SubtitleStyle({
    this.fontSize = 24.0,
    this.fontColor = Colors.white,
    this.backgroundColor = Colors.black54,
    this.position = SubtitlePosition.bottom,
    this.fontWeight = FontWeight.normal,
    this.hasOutline = true,
    this.outlineColor = Colors.black,
    this.outlineWidth = 2.0,
  });

  /// 从 Map 创建
  factory SubtitleStyle.fromMap(Map<dynamic, dynamic> map) => SubtitleStyle(
        fontSize: (map['fontSize'] as num?)?.toDouble() ?? 24.0,
        fontColor: Color(map['fontColor'] as int? ?? 0xFFFFFFFF),
        backgroundColor: Color(map['backgroundColor'] as int? ?? 0x8A000000),
        position: SubtitlePosition.values[map['position'] as int? ?? 0],
        fontWeight: FontWeight.values[map['fontWeight'] as int? ?? 3],
        hasOutline: map['hasOutline'] as bool? ?? true,
        outlineColor: Color(map['outlineColor'] as int? ?? 0xFF000000),
        outlineWidth: (map['outlineWidth'] as num?)?.toDouble() ?? 2.0,
      );

  final double fontSize;
  final Color fontColor;
  final Color backgroundColor;
  final SubtitlePosition position;
  final FontWeight fontWeight;
  final bool hasOutline;
  final Color outlineColor;
  final double outlineWidth;

  SubtitleStyle copyWith({
    double? fontSize,
    Color? fontColor,
    Color? backgroundColor,
    SubtitlePosition? position,
    FontWeight? fontWeight,
    bool? hasOutline,
    Color? outlineColor,
    double? outlineWidth,
  }) =>
      SubtitleStyle(
        fontSize: fontSize ?? this.fontSize,
        fontColor: fontColor ?? this.fontColor,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        position: position ?? this.position,
        fontWeight: fontWeight ?? this.fontWeight,
        hasOutline: hasOutline ?? this.hasOutline,
        outlineColor: outlineColor ?? this.outlineColor,
        outlineWidth: outlineWidth ?? this.outlineWidth,
      );

  /// 转换为 Map
  Map<String, dynamic> toMap() => {
        'fontSize': fontSize,
        'fontColor': fontColor.toARGB32(),
        'backgroundColor': backgroundColor.toARGB32(),
        'position': position.index,
        'fontWeight': FontWeight.values.indexOf(fontWeight),
        'hasOutline': hasOutline,
        'outlineColor': outlineColor.toARGB32(),
        'outlineWidth': outlineWidth,
      };
}

/// 字幕位置
enum SubtitlePosition {
  top,
  center,
  bottom,
}

/// 字幕样式管理
class SubtitleStyleNotifier extends StateNotifier<SubtitleStyle> {
  SubtitleStyleNotifier() : super(const SubtitleStyle()) {
    _loadFromStorage();
  }

  static const _boxName = 'video_settings';
  static const _key = 'subtitle_style';

  Future<void> _loadFromStorage() async {
    try {
      final box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
      final data = box.get(_key);
      if (data != null) {
        state = SubtitleStyle.fromMap(data);
      }
    } on Exception catch (_) {
      // 使用默认值
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
      await box.put(_key, state.toMap());
    } on Exception catch (_) {
      // 忽略保存错误
    }
  }

  /// 设置字体大小
  void setFontSize(double size) {
    state = state.copyWith(fontSize: size.clamp(12.0, 48.0));
    _saveToStorage();
  }

  /// 设置字体颜色
  void setFontColor(Color color) {
    state = state.copyWith(fontColor: color);
    _saveToStorage();
  }

  /// 设置背景颜色
  void setBackgroundColor(Color color) {
    state = state.copyWith(backgroundColor: color);
    _saveToStorage();
  }

  /// 设置位置
  void setPosition(SubtitlePosition position) {
    state = state.copyWith(position: position);
    _saveToStorage();
  }

  /// 设置字体粗细
  void setFontWeight(FontWeight weight) {
    state = state.copyWith(fontWeight: weight);
    _saveToStorage();
  }

  /// 设置是否显示描边
  void setHasOutline(bool hasOutline) {
    state = state.copyWith(hasOutline: hasOutline);
    _saveToStorage();
  }

  /// 设置描边颜色
  void setOutlineColor(Color color) {
    state = state.copyWith(outlineColor: color);
    _saveToStorage();
  }

  /// 设置描边宽度
  void setOutlineWidth(double width) {
    state = state.copyWith(outlineWidth: width.clamp(0.5, 5.0));
    _saveToStorage();
  }

  /// 重置为默认
  void reset() {
    state = const SubtitleStyle();
    _saveToStorage();
  }
}

/// 字幕样式 provider
final subtitleStyleProvider =
    StateNotifierProvider<SubtitleStyleNotifier, SubtitleStyle>((ref) => SubtitleStyleNotifier());

/// 预设字幕颜色
const subtitleColors = [
  Colors.white,
  Colors.yellow,
  Colors.cyan,
  Colors.green,
  Colors.orange,
  Colors.pink,
  Colors.red,
  Colors.purple,
];

/// 预设背景颜色
final subtitleBackgrounds = [
  Colors.black.withValues(alpha: 0.6),
  Colors.black.withValues(alpha: 0.4),
  Colors.black.withValues(alpha: 0.2),
  Colors.transparent,
  Colors.blue.withValues(alpha: 0.5),
  Colors.purple.withValues(alpha: 0.5),
];

/// 可用字体大小
const subtitleFontSizes = [16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0];

extension ColorToInt on Color {
  int toARGB32() =>
      ((a * 255.0).round().clamp(0, 255) << 24) |
      ((r * 255.0).round().clamp(0, 255) << 16) |
      ((g * 255.0).round().clamp(0, 255) << 8) |
      (b * 255.0).round().clamp(0, 255);
}
