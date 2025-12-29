import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/ui_style.dart';

/// 自适应玻璃容器 - 使用 Flutter BackdropFilter 实现真正的毛玻璃效果
///
/// 所有平台统一使用 Flutter BackdropFilter，可以正确模糊 Flutter 渲染的内容。
/// 针对不同平台会自动调整模糊强度和背景不透明度以优化性能：
/// - iOS/macOS: 完整模糊效果
/// - Android/Windows/Linux: 降低模糊强度，提高背景不透明度以补偿
/// - Web: 不支持模糊，使用不透明背景
///
/// 使用示例:
/// ```dart
/// AdaptiveGlassContainer(
///   uiStyle: uiStyle,
///   isDark: isDark,
///   cornerRadius: 20,
///   child: YourContent(),
/// )
/// ```
class AdaptiveGlassContainer extends StatelessWidget {
  const AdaptiveGlassContainer({
    required this.child,
    required this.uiStyle,
    required this.isDark,
    this.cornerRadius = 20,
    this.enableBorder = true,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// 子组件
  final Widget child;

  /// UI 风格
  final UIStyle uiStyle;

  /// 是否为深色模式
  final bool isDark;

  /// 圆角半径
  final double cornerRadius;

  /// 是否显示边框
  final bool enableBorder;

  /// 内边距
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    // 经典模式或不支持玻璃效果的平台
    if (!PlatformGlassConfig.shouldEnableGlass(uiStyle)) {
      return _buildClassicContainer();
    }

    // 所有支持的平台统一使用 Flutter BackdropFilter
    return _buildBlurContainer();
  }

  /// 经典模式 - 不透明背景
  Widget _buildClassicContainer() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3) : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(cornerRadius),
        border: enableBorder
            ? Border.all(
                color: isDark
                    ? AppColors.darkOutline.withValues(alpha: 0.2)
                    : AppColors.lightOutline.withValues(alpha: 0.3),
              )
            : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cornerRadius),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }

  /// Flutter BackdropFilter 实现 - 真正的毛玻璃效果
  Widget _buildBlurContainer() {
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);
    final optimizedStyle = PlatformGlassConfig.getOptimizedStyle(glassStyle, isDark: isDark);

    final bgColor = GlassTheme.getBackgroundColor(optimizedStyle, isDark: isDark);
    final borderColor = GlassTheme.getBorderColor(optimizedStyle, isDark: isDark);

    Widget container = DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(cornerRadius),
        border: enableBorder ? Border.all(color: borderColor) : null,
        boxShadow: GlassTheme.getGlowShadows(optimizedStyle, isDark: isDark),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cornerRadius),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );

    // 添加模糊效果
    if (optimizedStyle.needsBlur) {
      container = ClipRRect(
        borderRadius: BorderRadius.circular(cornerRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: optimizedStyle.blurIntensity,
            sigmaY: optimizedStyle.blurIntensity,
          ),
          child: container,
        ),
      );
    }

    return container;
  }
}

/// 自适应玻璃导航栏容器 - 专为导航栏优化的玻璃效果
///
/// 使用 Flutter BackdropFilter 实现真正的毛玻璃效果，
/// 可以正确模糊导航栏后面的 Flutter 内容（如列表、文字等）。
///
/// 特点:
/// - 真正的毛玻璃模糊效果
/// - 更高的背景不透明度确保可读性
/// - 支持安全区域
/// - 顶部/底部边框
class AdaptiveGlassNavBar extends StatelessWidget {
  const AdaptiveGlassNavBar({
    required this.child,
    required this.uiStyle,
    required this.isDark,
    this.height,
    this.isTop = false,
    super.key,
  });

  final Widget child;
  final UIStyle uiStyle;
  final bool isDark;
  final double? height;

  /// 是否为顶部导航栏（影响边框位置）
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    // 经典模式或不支持玻璃效果的平台
    if (!PlatformGlassConfig.shouldEnableGlass(uiStyle)) {
      return _buildClassicNavBar();
    }

    // 所有支持的平台统一使用 Flutter BackdropFilter
    return _buildBlurNavBar();
  }

  Widget _buildClassicNavBar() {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border(
          top: isTop
              ? BorderSide.none
              : BorderSide(
                  color: isDark
                      ? AppColors.darkOutline.withValues(alpha: 0.2)
                      : AppColors.lightOutline.withValues(alpha: 0.3),
                ),
          bottom: isTop
              ? BorderSide(
                  color: isDark
                      ? AppColors.darkOutline.withValues(alpha: 0.2)
                      : AppColors.lightOutline.withValues(alpha: 0.3),
                )
              : BorderSide.none,
        ),
      ),
      child: child,
    );
  }

  Widget _buildBlurNavBar() {
    final glassStyle = GlassTheme.getNavBarStyle(uiStyle, isDark: isDark);
    final optimizedStyle = PlatformGlassConfig.getOptimizedStyle(glassStyle, isDark: isDark);
    final bgColor = GlassTheme.getBackgroundColor(optimizedStyle, isDark: isDark);

    // 边框颜色
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);

    Widget navBar = Container(
      height: height,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: isTop ? BorderSide.none : BorderSide(color: borderColor, width: 0.5),
          bottom: isTop ? BorderSide(color: borderColor, width: 0.5) : BorderSide.none,
        ),
      ),
      child: child,
    );

    // 添加模糊效果
    if (optimizedStyle.needsBlur) {
      navBar = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: optimizedStyle.blurIntensity,
            sigmaY: optimizedStyle.blurIntensity,
          ),
          child: navBar,
        ),
      );
    }

    return navBar;
  }
}
