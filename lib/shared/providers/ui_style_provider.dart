import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';
import 'package:my_nas/shared/widgets/liquid_glass/liquid_glass_service.dart';

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
  static const _hasUserSetKey = 'ui_style_user_set';

  /// 从存储加载
  Future<void> _loadFromStorage() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final value = box.get(_key) as String?;
      final hasUserSet = box.get(_hasUserSetKey) as bool? ?? false;

      if (value != null) {
        // 用户之前设置过，使用保存的值
        final style = _parseUIStyle(value);
        if (style != null) {
          state = style;
          return;
        }
      }

      // 首次安装或没有保存的设置
      if (!hasUserSet) {
        // 检测平台是否支持 Liquid Glass，如果支持则默认启用
        final defaultStyle = await _getDefaultStyleForPlatform();
        state = defaultStyle;
        // 保存默认值（但不标记为用户设置）
        await box.put(_key, defaultStyle.name);
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载UI风格失败，使用默认值');
    }
  }

  /// 根据平台获取默认风格
  Future<UIStyle> _getDefaultStyleForPlatform() async {
    if (kIsWeb) return UIStyle.classic;

    // iOS 26+ 支持 Liquid Glass
    if (Platform.isIOS) {
      final supported = await LiquidGlassService.instance.isSupported;
      if (supported) {
        return UIStyle.liquidClear;
      }
    }

    // macOS 26+ 也支持 (未来可以添加检测)
    // 目前 macOS 使用经典风格
    return UIStyle.classic;
  }

  /// 设置 UI 风格（用户主动设置）
  Future<void> setStyle(UIStyle style) async {
    state = style;
    await _saveToStorage(style, userSet: true);
  }

  /// 切换到下一个风格
  void cycleStyle() {
    final values = UIStyle.values;
    final nextIndex = (state.index + 1) % values.length;
    setStyle(values[nextIndex]);
  }

  /// 保存到存储
  Future<void> _saveToStorage(UIStyle style, {bool userSet = false}) async {
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_key, style.name);
      if (userSet) {
        // 标记用户主动设置过
        await box.put(_hasUserSetKey, true);
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存UI风格失败');
    }
  }

  /// 解析 UI 风格
  UIStyle? _parseUIStyle(String value) {
    // 处理旧版名称迁移：如果用户之前设置的是 'glass'，转换为 liquidClear
    if (value == 'glass') {
      return UIStyle.liquidClear;
    }
    for (final style in UIStyle.values) {
      if (style.name == value) {
        return style;
      }
    }
    return null;
  }
}
