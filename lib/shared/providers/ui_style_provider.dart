import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// UI 风格 Provider
final uiStyleProvider = StateNotifierProvider<UIStyleNotifier, UIStyle>(
  (ref) => UIStyleNotifier(),
);

/// UI 风格状态管理
class UIStyleNotifier extends StateNotifier<UIStyle> {
  UIStyleNotifier() : super(UIStyle.classic) {
    _loadFromStorage();
  }

  static const _key = 'ui_style';

  /// 从存储加载
  Future<void> _loadFromStorage() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final value = box.get(_key) as String?;
      if (value != null) {
        final style = _parseUIStyle(value);
        if (style != null) {
          state = style;
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载UI风格失败，使用默认值');
    }
  }

  /// 设置 UI 风格
  Future<void> setStyle(UIStyle style) async {
    state = style;
    await _saveToStorage(style);
  }

  /// 切换到下一个风格
  void cycleStyle() {
    final values = UIStyle.values;
    final nextIndex = (state.index + 1) % values.length;
    setStyle(values[nextIndex]);
  }

  /// 保存到存储
  Future<void> _saveToStorage(UIStyle style) async {
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_key, style.name);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存UI风格失败');
    }
  }

  /// 解析 UI 风格
  UIStyle? _parseUIStyle(String value) {
    for (final style in UIStyle.values) {
      if (style.name == value) {
        return style;
      }
    }
    return null;
  }
}
