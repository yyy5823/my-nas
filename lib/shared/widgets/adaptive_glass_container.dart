import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/ui_style.dart';

/// 自适应玻璃容器 - 根据平台自动选择最佳模糊实现
///
/// - iOS/macOS: 使用原生 UIVisualEffectView/NSVisualEffectView
/// - Android/Windows/Linux: 使用 Flutter BackdropFilter
/// - Web: 使用不透明背景（不支持模糊）
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
    // 经典模式直接返回普通容器
    if (!uiStyle.isGlass) {
      return _buildClassicContainer();
    }

    // Apple 平台使用原生实现
    if (PlatformGlassConfig.shouldUseNativeBlur(uiStyle)) {
      return _buildNativeBlurContainer();
    }

    // 其他平台使用 Flutter 实现
    return _buildFlutterBlurContainer();
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

  /// Apple 平台 - 原生模糊实现
  Widget _buildNativeBlurContainer() {
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);
    final nativeStyle = PlatformGlassConfig.getNativeBlurStyle(uiStyle, isDark: isDark);

    final creationParams = <String, dynamic>{
      'style': nativeStyle,
      'material': nativeStyle,
      'isDark': isDark,
      'cornerRadius': cornerRadius,
      'enableBorder': enableBorder,
      'borderOpacity': glassStyle.borderOpacity,
      'enableVibrancy': false,
      'blendingMode': 'behindWindow',
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(cornerRadius),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // 原生模糊背景
          Positioned.fill(
            child: _buildPlatformView(creationParams),
          ),
          // Flutter 子组件
          Padding(
            padding: padding,
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformView(Map<String, dynamic> creationParams) {
    const viewType = 'com.kkape.mynas/native_blur_view';

    if (Platform.isIOS) {
      return UiKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    } else if (Platform.isMacOS) {
      return AppKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }

    return const SizedBox.shrink();
  }

  /// 其他平台 - Flutter BackdropFilter 实现
  Widget _buildFlutterBlurContainer() {
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
/// 特点:
/// - 更高的背景不透明度确保可读性
/// - 支持安全区域
/// - 底部边框
class AdaptiveGlassNavBar extends StatelessWidget {
  const AdaptiveGlassNavBar({
    required this.child,
    required this.uiStyle,
    required this.isDark,
    this.height,
    super.key,
  });

  final Widget child;
  final UIStyle uiStyle;
  final bool isDark;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (!uiStyle.isGlass) {
      return _buildClassicNavBar(context);
    }

    if (PlatformGlassConfig.shouldUseNativeBlur(uiStyle)) {
      return _buildNativeNavBar(context);
    }

    return _buildFlutterNavBar(context);
  }

  Widget _buildClassicNavBar(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border(
          top: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : AppColors.lightOutline.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: child,
    );
  }

  Widget _buildNativeNavBar(BuildContext context) {
    final nativeStyle = uiStyle == UIStyle.liquidClear ? 'systemChromeMaterial' : 'systemMaterial';

    final creationParams = <String, dynamic>{
      'style': nativeStyle,
      'material': Platform.isMacOS ? 'headerView' : nativeStyle,
      'isDark': isDark,
      'cornerRadius': 0.0,
      'enableBorder': false,
      'borderOpacity': 0.0,
      'enableVibrancy': false,
      'blendingMode': 'behindWindow',
    };

    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: _buildPlatformView(creationParams),
        ),
        // 顶部边框
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 0.5,
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        SizedBox(
          height: height,
          child: child,
        ),
      ],
    );
  }

  Widget _buildPlatformView(Map<String, dynamic> creationParams) {
    const viewType = 'com.kkape.mynas/native_blur_view';

    if (Platform.isIOS) {
      return UiKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    } else if (Platform.isMacOS) {
      return AppKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildFlutterNavBar(BuildContext context) {
    final glassStyle = GlassTheme.getNavBarStyle(uiStyle, isDark: isDark);
    final optimizedStyle = PlatformGlassConfig.getOptimizedStyle(glassStyle, isDark: isDark);
    final bgColor = GlassTheme.getBackgroundColor(optimizedStyle, isDark: isDark);

    Widget navBar = Container(
      height: height,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: child,
    );

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
