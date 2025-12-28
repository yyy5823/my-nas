import 'dart:ui';

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
}
