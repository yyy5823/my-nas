import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';

/// UI 风格枚举
/// - classic: 经典不透明风格
/// - liquidClear: 液态玻璃 - 清澈模式（更透明）
/// - liquidTinted: 液态玻璃 - 染色模式（更高对比度）
enum UIStyle {
  classic('经典', Icons.square_rounded),
  liquidClear('玻璃 · 清澈', Icons.blur_on),
  liquidTinted('玻璃 · 染色', Icons.blur_circular);

  const UIStyle(this.label, this.icon);

  final String label;
  final IconData icon;

  /// 是否为玻璃风格
  bool get isGlass => this != classic;

  /// 是否为染色模式
  bool get isTinted => this == liquidTinted;
}

/// 玻璃效果样式配置
class GlassStyle {
  const GlassStyle({
    required this.blurIntensity,
    required this.backgroundOpacity,
    required this.tintOpacity,
    required this.borderOpacity,
    required this.enableBorderGlow,
  });

  /// 经典模式（无模糊，完全不透明）
  static const GlassStyle classic = GlassStyle(
    blurIntensity: 0,
    backgroundOpacity: 1.0,
    tintOpacity: 0,
    borderOpacity: 0.1,
    enableBorderGlow: false,
  );

  /// 模糊强度 (0-30)
  final double blurIntensity;

  /// 背景不透明度 (0.0-1.0)
  final double backgroundOpacity;

  /// 染色不透明度 (0.0-1.0)
  final double tintOpacity;

  /// 边框不透明度 (0.0-1.0)
  final double borderOpacity;

  /// 是否启用边框光晕
  final bool enableBorderGlow;

  /// 是否需要模糊效果
  bool get needsBlur => blurIntensity > 0;

  /// 获取模糊滤镜
  ImageFilter? get blurFilter => needsBlur
      ? ImageFilter.blur(sigmaX: blurIntensity, sigmaY: blurIntensity)
      : null;
}

/// 玻璃主题工具类
/// 根据 UIStyle 和当前主题模式获取合适的玻璃样式
abstract final class GlassTheme {
  static GlassStyle getStyle(UIStyle style, {required bool isDark}) => switch (style) {
      UIStyle.classic => GlassStyle.classic,
      UIStyle.liquidClear => isDark
          ? const GlassStyle(
              blurIntensity: 25,
              backgroundOpacity: 0.5,
              tintOpacity: 0.1,
              borderOpacity: 0.2,
              enableBorderGlow: true,
            )
          : const GlassStyle(
              blurIntensity: 20,
              backgroundOpacity: 0.6,
              tintOpacity: 0.05,
              borderOpacity: 0.15,
              enableBorderGlow: true,
            ),
      UIStyle.liquidTinted => isDark
          ? const GlassStyle(
              blurIntensity: 30,
              backgroundOpacity: 0.75,
              tintOpacity: 0.15,
              borderOpacity: 0.25,
              enableBorderGlow: true,
            )
          : const GlassStyle(
              blurIntensity: 25,
              backgroundOpacity: 0.85,
              tintOpacity: 0.1,
              borderOpacity: 0.2,
              enableBorderGlow: true,
            ),
    };

  /// 获取玻璃效果的背景颜色
  static Color getBackgroundColor(
    GlassStyle style, {
    required bool isDark,
    Color? tintColor,
  }) {
    if (!style.needsBlur) {
      // Classic 模式 - 使用实色背景（使用 AppColors 保持一致性）
      return isDark ? AppColors.darkSurface : AppColors.lightSurface;
    }

    // 玻璃模式 - 使用半透明背景
    final baseColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final tint = tintColor ?? (isDark ? Colors.white : Colors.black);

    // 混合基础色和染色
    return Color.lerp(
      baseColor.withValues(alpha: style.backgroundOpacity),
      tint.withValues(alpha: style.tintOpacity),
      style.tintOpacity,
    )!;
  }

  /// 获取玻璃效果的边框颜色
  static Color getBorderColor(GlassStyle style, {required bool isDark}) {
    if (!style.enableBorderGlow) {
      return isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.black.withValues(alpha: 0.05);
    }

    return isDark
        ? Colors.white.withValues(alpha: style.borderOpacity)
        : Colors.black.withValues(alpha: style.borderOpacity * 0.5);
  }

  /// 获取玻璃效果的阴影
  static List<BoxShadow>? getGlowShadows(
    GlassStyle style, {
    required bool isDark,
    Color? glowColor,
  }) {
    if (!style.enableBorderGlow) return null;

    final color = glowColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.08));

    return [
      BoxShadow(
        color: color,
        blurRadius: 20,
        spreadRadius: -5,
      ),
    ];
  }

  /// 获取导航栏专用的玻璃样式（更高不透明度确保可读性）
  static GlassStyle getNavBarStyle(UIStyle style, {required bool isDark}) {
    final baseStyle = getStyle(style, isDark: isDark);
    if (!baseStyle.needsBlur) return baseStyle;

    // 导航栏使用更高的不透明度
    return GlassStyle(
      blurIntensity: baseStyle.blurIntensity,
      backgroundOpacity: (baseStyle.backgroundOpacity + 0.15).clamp(0.0, 0.95),
      tintOpacity: baseStyle.tintOpacity,
      borderOpacity: baseStyle.borderOpacity,
      enableBorderGlow: baseStyle.enableBorderGlow,
    );
  }
}

/// 平台模糊支持级别
enum BlurSupportLevel {
  /// 完全支持 - 可以使用高质量模糊
  full,

  /// 部分支持 - 需要降低模糊强度以保证性能
  partial,

  /// 不支持 - 使用不透明背景替代
  none,
}

/// 跨平台玻璃效果配置
/// 根据不同平台调整模糊效果以获得最佳性能和视觉效果
///
/// 注意：所有平台统一使用 Flutter 的 BackdropFilter 实现真正的毛玻璃效果
/// 原生 UIVisualEffectView/NSVisualEffectView 无法模糊 Flutter 渲染层的内容
abstract final class PlatformGlassConfig {
  /// 获取当前平台的模糊支持级别
  static BlurSupportLevel get blurSupportLevel {
    if (kIsWeb) return BlurSupportLevel.none;

    if (Platform.isIOS || Platform.isMacOS) {
      // Apple 平台 GPU 性能优异，完全支持
      return BlurSupportLevel.full;
    }

    if (Platform.isAndroid) {
      // Android 需要根据设备性能决定
      // 保守起见使用部分支持，降低模糊强度
      return BlurSupportLevel.partial;
    }

    if (Platform.isWindows) {
      // Windows 桌面性能通常足够，但某些集成显卡可能有问题
      // 使用部分支持以确保兼容性
      return BlurSupportLevel.partial;
    }

    if (Platform.isLinux) {
      // Linux 桌面性能差异较大
      return BlurSupportLevel.partial;
    }

    return BlurSupportLevel.partial;
  }

  /// 当前平台是否支持高性能模糊
  static bool get supportsHighQualityBlur {
    return blurSupportLevel == BlurSupportLevel.full;
  }

  /// 当前平台是否支持模糊效果
  static bool get supportsBlur {
    return blurSupportLevel != BlurSupportLevel.none;
  }

  /// 获取平台优化后的模糊强度
  static double getOptimizedBlurIntensity(double baseIntensity) {
    return switch (blurSupportLevel) {
      BlurSupportLevel.full => baseIntensity,
      BlurSupportLevel.partial => _getPartialBlurIntensity(baseIntensity),
      BlurSupportLevel.none => 0,
    };
  }

  /// 部分支持平台的模糊强度计算
  static double _getPartialBlurIntensity(double baseIntensity) {
    if (kIsWeb) return 0;

    if (Platform.isAndroid) {
      // Android: 降低到 60% 以保证流畅度
      // 高模糊值在低端设备上可能导致卡顿
      return baseIntensity * 0.6;
    }

    if (Platform.isWindows) {
      // Windows: 降低到 70%
      // 某些集成显卡对高斯模糊性能较差
      return baseIntensity * 0.7;
    }

    if (Platform.isLinux) {
      // Linux: 降低到 60%
      return baseIntensity * 0.6;
    }

    return baseIntensity * 0.7;
  }

  /// 获取平台特定的背景不透明度调整
  /// 模糊强度降低时需要提高不透明度以保持可读性
  static double getAdjustedOpacity(double baseOpacity, {required bool isDark}) {
    return switch (blurSupportLevel) {
      BlurSupportLevel.full => baseOpacity,
      BlurSupportLevel.partial => _getPartialOpacity(baseOpacity, isDark: isDark),
      BlurSupportLevel.none => 1.0,
    };
  }

  /// 部分支持平台的不透明度计算
  static double _getPartialOpacity(double baseOpacity, {required bool isDark}) {
    if (kIsWeb) return 1.0;

    // 模糊强度降低时，提高背景不透明度以补偿
    // 公式：降低的模糊比例 * 补偿系数 + 原始不透明度
    double opacityBoost;

    if (Platform.isAndroid) {
      // Android 模糊降到 60%，补偿 0.15
      opacityBoost = 0.15;
    } else if (Platform.isWindows) {
      // Windows 模糊降到 70%，补偿 0.1
      opacityBoost = 0.1;
    } else {
      opacityBoost = 0.12;
    }

    return (baseOpacity + opacityBoost).clamp(0.0, 0.95);
  }

  /// 是否应该在此平台启用玻璃效果
  static bool shouldEnableGlass(UIStyle style) {
    if (!style.isGlass) return false;
    // 只有完全不支持模糊的平台才禁用玻璃效果
    return blurSupportLevel != BlurSupportLevel.none;
  }

  /// 是否应该使用原生模糊实现
  /// 注意：始终返回 false，因为原生实现无法模糊 Flutter 内容
  /// 保留此方法以保持 API 兼容性
  static bool shouldUseNativeBlur(UIStyle style) {
    // 不再使用原生模糊，统一使用 Flutter BackdropFilter
    // 原生 UIVisualEffectView/NSVisualEffectView 只能模糊窗口背景
    // 无法模糊 Flutter 渲染层的内容（如列表、文字等）
    return false;
  }

  /// 获取原生模糊样式名称（已弃用，保留以兼容）
  @Deprecated('不再使用原生模糊，请使用 Flutter BackdropFilter')
  static String getNativeBlurStyle(UIStyle style, {required bool isDark}) {
    return 'systemMaterial';
  }

  /// 获取平台优化后的 GlassStyle
  static GlassStyle getOptimizedStyle(
    GlassStyle style, {
    required bool isDark,
  }) {
    if (!style.needsBlur) return style;

    // 如果平台完全不支持模糊，返回经典样式
    if (blurSupportLevel == BlurSupportLevel.none) {
      return GlassStyle.classic;
    }

    return GlassStyle(
      blurIntensity: getOptimizedBlurIntensity(style.blurIntensity),
      backgroundOpacity: getAdjustedOpacity(style.backgroundOpacity, isDark: isDark),
      tintOpacity: style.tintOpacity,
      borderOpacity: style.borderOpacity,
      enableBorderGlow: style.enableBorderGlow,
    );
  }
}
