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

/// 跨平台玻璃效果配置
/// 根据不同平台调整模糊效果以获得最佳性能和视觉效果
abstract final class PlatformGlassConfig {
  /// 当前平台是否支持高性能模糊
  static bool get supportsHighQualityBlur {
    if (kIsWeb) return false;
    // iOS 和 macOS 原生支持高质量模糊
    if (Platform.isIOS || Platform.isMacOS) return true;
    // Android 12+ 和 Windows 11 也有较好支持
    // 这里简单地假设现代设备都支持
    return true;
  }

  /// 获取平台优化后的模糊强度
  static double getOptimizedBlurIntensity(double baseIntensity) {
    if (kIsWeb) return 0; // Web 不支持模糊

    if (Platform.isIOS || Platform.isMacOS) {
      // Apple 平台性能好，可以使用完整模糊
      return baseIntensity;
    }

    if (Platform.isAndroid) {
      // Android 降低一点模糊强度以保证性能
      return baseIntensity * 0.8;
    }

    if (Platform.isWindows || Platform.isLinux) {
      // 桌面平台可以使用完整模糊
      return baseIntensity;
    }

    return baseIntensity;
  }

  /// 获取平台特定的背景不透明度调整
  /// 某些平台可能需要更高的不透明度以确保可读性
  static double getAdjustedOpacity(double baseOpacity, {required bool isDark}) {
    if (kIsWeb) return 1.0; // Web 使用完全不透明

    if (Platform.isAndroid) {
      // Android 上稍微提高不透明度以补偿较低的模糊
      return (baseOpacity + 0.1).clamp(0.0, 1.0);
    }

    return baseOpacity;
  }

  /// 是否应该在此平台启用玻璃效果
  static bool shouldEnableGlass(UIStyle style) {
    if (kIsWeb) return false;
    return style.isGlass;
  }

  /// 获取平台优化后的 GlassStyle
  static GlassStyle getOptimizedStyle(
    GlassStyle style, {
    required bool isDark,
  }) {
    if (!style.needsBlur) return style;

    return GlassStyle(
      blurIntensity: getOptimizedBlurIntensity(style.blurIntensity),
      backgroundOpacity: getAdjustedOpacity(style.backgroundOpacity, isDark: isDark),
      tintOpacity: style.tintOpacity,
      borderOpacity: style.borderOpacity,
      enableBorderGlow: style.enableBorderGlow,
    );
  }
}
