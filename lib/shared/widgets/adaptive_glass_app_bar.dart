import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';

/// 自适应玻璃顶栏 - 根据平台和 UI 风格自动选择最佳实现
///
/// iOS 26+: 使用原生 UIVisualEffectView (Liquid Glass)
/// iOS 13-25/macOS: 使用原生模糊效果
/// Android/Windows/Linux: 使用 Flutter BackdropFilter
/// 经典模式: 使用不透明背景
///
/// 使用示例:
/// ```dart
/// AdaptiveGlassAppBar(
///   title: Text('标题'),
///   leading: BackButton(),
///   actions: [IconButton(...)],
///   backgroundColor: Colors.blue.withOpacity(0.1), // 可选染色
/// )
/// ```
class AdaptiveGlassAppBar extends ConsumerWidget {
  const AdaptiveGlassAppBar({
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.backgroundColor,
    this.elevation = 0,
    this.toolbarHeight,
    this.expandedHeight,
    this.flexibleSpace,
    this.pinned = true,
    this.floating = false,
    this.snap = false,
    this.forceClassic = false,
    this.centerTitle,
    this.titleSpacing,
    this.automaticallyImplyLeading = true,
    super.key,
  });

  /// 标题组件
  final Widget? title;

  /// 左侧组件（通常是返回按钮）
  final Widget? leading;

  /// 右侧操作按钮列表
  final List<Widget>? actions;

  /// 底部组件（如 TabBar）
  final PreferredSizeWidget? bottom;

  /// 背景颜色/染色（玻璃模式下会作为染色层）
  final Color? backgroundColor;

  /// 阴影高度
  final double elevation;

  /// 工具栏高度
  final double? toolbarHeight;

  /// 展开高度（用于 SliverAppBar）
  final double? expandedHeight;

  /// 弹性空间（用于 SliverAppBar）
  final Widget? flexibleSpace;

  /// 是否固定在顶部
  final bool pinned;

  /// 是否浮动
  final bool floating;

  /// 是否快速显示
  final bool snap;

  /// 强制使用经典模式（不使用玻璃效果）
  final bool forceClassic;

  /// 是否居中标题
  final bool? centerTitle;

  /// 标题间距
  final double? titleSpacing;

  /// 是否自动添加返回按钮
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 强制经典模式或设置为经典风格时，使用不透明背景
    if (forceClassic || !uiStyle.isGlass) {
      return _buildClassicAppBar(context, isDark);
    }

    // 玻璃模式
    if (PlatformGlassConfig.shouldUseNativeBlur(uiStyle)) {
      return _buildNativeGlassAppBar(context, uiStyle, isDark);
    }

    return _buildFlutterGlassAppBar(context, uiStyle, isDark);
  }

  /// 经典模式 - 不透明背景
  Widget _buildClassicAppBar(BuildContext context, bool isDark) {
    final bgColor = backgroundColor ??
        (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    return SliverAppBar(
      title: title,
      leading: leading,
      actions: actions,
      bottom: bottom,
      backgroundColor: bgColor,
      elevation: elevation,
      toolbarHeight: toolbarHeight ?? kToolbarHeight,
      expandedHeight: expandedHeight,
      flexibleSpace: flexibleSpace,
      pinned: pinned,
      floating: floating,
      snap: snap,
      centerTitle: centerTitle,
      titleSpacing: titleSpacing,
      automaticallyImplyLeading: automaticallyImplyLeading,
      surfaceTintColor: Colors.transparent,
    );
  }

  /// iOS/macOS 原生玻璃效果
  Widget _buildNativeGlassAppBar(
    BuildContext context,
    UIStyle uiStyle,
    bool isDark,
  ) {
    final height = (toolbarHeight ?? kToolbarHeight) +
        (bottom?.preferredSize.height ?? 0) +
        MediaQuery.of(context).padding.top;

    final nativeStyle =
        PlatformGlassConfig.getNativeBlurStyle(uiStyle, isDark: isDark);

    final creationParams = <String, dynamic>{
      'style': nativeStyle,
      'material': nativeStyle,
      'isDark': isDark,
      'cornerRadius': 0.0,
      'enableBorder': false,
      'borderOpacity': 0.0,
      'enableVibrancy': false,
      'blendingMode': 'behindWindow',
      'useLiquidGlass': true,
      'isInteractive': false,
    };

    final viewKey = ValueKey('appbar_blur_${isDark}_${uiStyle.name}');

    return SliverPersistentHeader(
      pinned: pinned,
      floating: floating,
      delegate: _GlassAppBarDelegate(
        minHeight: (toolbarHeight ?? kToolbarHeight) +
            (bottom?.preferredSize.height ?? 0) +
            MediaQuery.of(context).padding.top,
        maxHeight: expandedHeight ?? height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 原生模糊背景
            Positioned.fill(
              child: _buildPlatformView(creationParams, viewKey),
            ),
            // 染色层
            if (backgroundColor != null)
              Positioned.fill(
                child: ColoredBox(color: backgroundColor!),
              ),
            // 底部边框
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 0.5,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            // 内容
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildToolbar(context, isDark),
                  if (bottom != null) bottom!,
                ],
              ),
            ),
          ],
        ),
        flexibleSpace: flexibleSpace,
      ),
    );
  }

  Widget _buildPlatformView(Map<String, dynamic> creationParams, Key viewKey) {
    const viewType = 'com.kkape.mynas/native_blur_view';

    if (Platform.isIOS) {
      return UiKitView(
        key: viewKey,
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    } else if (Platform.isMacOS) {
      return AppKitView(
        key: viewKey,
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }

    return const SizedBox.shrink();
  }

  /// Flutter BackdropFilter 玻璃效果
  Widget _buildFlutterGlassAppBar(
    BuildContext context,
    UIStyle uiStyle,
    bool isDark,
  ) {
    final glassStyle = GlassTheme.getNavBarStyle(uiStyle, isDark: isDark);
    final optimizedStyle =
        PlatformGlassConfig.getOptimizedStyle(glassStyle, isDark: isDark);
    final bgColor = GlassTheme.getBackgroundColor(optimizedStyle,
        isDark: isDark, tintColor: backgroundColor);

    final height = (toolbarHeight ?? kToolbarHeight) +
        (bottom?.preferredSize.height ?? 0) +
        MediaQuery.of(context).padding.top;

    return SliverPersistentHeader(
      pinned: pinned,
      floating: floating,
      delegate: _GlassAppBarDelegate(
        minHeight: (toolbarHeight ?? kToolbarHeight) +
            (bottom?.preferredSize.height ?? 0) +
            MediaQuery.of(context).padding.top,
        maxHeight: expandedHeight ?? height,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: optimizedStyle.blurIntensity,
              sigmaY: optimizedStyle.blurIntensity,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: bgColor,
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.05),
                    width: 0.5,
                  ),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _buildToolbar(context, isDark),
                    if (bottom != null) bottom!,
                  ],
                ),
              ),
            ),
          ),
        ),
        flexibleSpace: flexibleSpace,
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, bool isDark) {
    return SizedBox(
      height: toolbarHeight ?? kToolbarHeight,
      child: NavigationToolbar(
        leading: leading ??
            (automaticallyImplyLeading && Navigator.canPop(context)
                ? const BackButton()
                : null),
        middle: title,
        trailing: actions != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: actions!,
              )
            : null,
        centerMiddle: centerTitle ?? true,
        middleSpacing: titleSpacing ?? NavigationToolbar.kMiddleSpacing,
      ),
    );
  }
}

/// 玻璃顶栏委托
class _GlassAppBarDelegate extends SliverPersistentHeaderDelegate {
  _GlassAppBarDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
    this.flexibleSpace,
  });

  final double minHeight;
  final double maxHeight;
  final Widget child;
  final Widget? flexibleSpace;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    if (flexibleSpace != null && maxHeight > minHeight) {
      final progress = (shrinkOffset / (maxHeight - minHeight)).clamp(0.0, 1.0);
      return Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 1.0 - progress,
            child: flexibleSpace,
          ),
          Opacity(
            opacity: progress,
            child: child,
          ),
        ],
      );
    }
    return child;
  }

  @override
  bool shouldRebuild(_GlassAppBarDelegate oldDelegate) =>
      minHeight != oldDelegate.minHeight ||
      maxHeight != oldDelegate.maxHeight ||
      child != oldDelegate.child ||
      flexibleSpace != oldDelegate.flexibleSpace;
}

/// 简化版玻璃顶栏 - 用于非 Sliver 场景
///
/// 适用于普通 Scaffold 的 AppBar 位置
///
/// iOS 26 Liquid Glass 设计特点：
/// - 玻璃模式下无边框，与内容无缝融合
/// - 按钮悬浮在玻璃层上方，有独立的玻璃背景
/// - 经典模式保留边框作为视觉分隔
class AdaptiveGlassHeader extends ConsumerWidget {
  const AdaptiveGlassHeader({
    required this.child,
    this.height,
    this.backgroundColor,
    this.enableBorder,
    this.forceClassic = false,
    super.key,
  });

  /// 子组件（顶栏内容）
  final Widget child;

  /// 高度（不包含安全区域）
  final double? height;

  /// 背景颜色/染色
  final Color? backgroundColor;

  /// 是否显示底部边框
  /// 默认行为：玻璃模式下 false，经典模式下 true
  final bool? enableBorder;

  /// 强制使用经典模式
  final bool forceClassic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safeTop = MediaQuery.of(context).padding.top;

    // 确定是否使用玻璃模式
    final isGlassMode = !forceClassic && uiStyle.isGlass;

    // 边框默认行为：玻璃模式下 false（iOS 26 无边框设计），经典模式下 true
    final showBorder = enableBorder ?? !isGlassMode;

    // 经典模式
    if (!isGlassMode) {
      return _buildClassicHeader(context, isDark, safeTop, showBorder);
    }

    // 玻璃模式
    if (PlatformGlassConfig.shouldUseNativeBlur(uiStyle)) {
      return _buildNativeGlassHeader(context, uiStyle, isDark, safeTop, showBorder);
    }

    return _buildFlutterGlassHeader(context, uiStyle, isDark, safeTop, showBorder);
  }

  Widget _buildClassicHeader(
    BuildContext context,
    bool isDark,
    double safeTop,
    bool showBorder,
  ) {
    final bgColor = backgroundColor ??
        (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    return Container(
      padding: EdgeInsets.only(top: safeTop),
      decoration: BoxDecoration(
        color: bgColor,
        border: showBorder
            ? Border(
                bottom: BorderSide(
                  color: isDark
                      ? AppColors.darkOutline.withValues(alpha: 0.2)
                      : AppColors.lightOutline.withValues(alpha: 0.3),
                ),
              )
            : null,
      ),
      child: SizedBox(
        height: height,
        child: child,
      ),
    );
  }

  Widget _buildNativeGlassHeader(
    BuildContext context,
    UIStyle uiStyle,
    bool isDark,
    double safeTop,
    bool showBorder,
  ) {
    final nativeStyle =
        PlatformGlassConfig.getNativeBlurStyle(uiStyle, isDark: isDark);

    final creationParams = <String, dynamic>{
      'style': nativeStyle,
      'material': nativeStyle,
      'isDark': isDark,
      'cornerRadius': 0.0,
      'enableBorder': false,
      'borderOpacity': 0.0,
      'enableVibrancy': false,
      'blendingMode': 'behindWindow',
      'useLiquidGlass': true,
      'isInteractive': false,
    };

    final viewKey = ValueKey('header_blur_${isDark}_${uiStyle.name}');

    return Stack(
      children: [
        // 原生模糊背景
        Positioned.fill(
          child: _buildPlatformView(creationParams, viewKey),
        ),
        // 染色层
        if (backgroundColor != null)
          Positioned.fill(
            child: ColoredBox(color: backgroundColor!),
          ),
        // 底部边框（iOS 26 Liquid Glass 默认无边框）
        if (showBorder)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 0.5,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
        // 内容
        Padding(
          padding: EdgeInsets.only(top: safeTop),
          child: SizedBox(
            height: height,
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _buildPlatformView(Map<String, dynamic> creationParams, Key viewKey) {
    const viewType = 'com.kkape.mynas/native_blur_view';

    if (!kIsWeb && Platform.isIOS) {
      return UiKitView(
        key: viewKey,
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    } else if (!kIsWeb && Platform.isMacOS) {
      return AppKitView(
        key: viewKey,
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildFlutterGlassHeader(
    BuildContext context,
    UIStyle uiStyle,
    bool isDark,
    double safeTop,
    bool showBorder,
  ) {
    final glassStyle = GlassTheme.getNavBarStyle(uiStyle, isDark: isDark);
    final optimizedStyle =
        PlatformGlassConfig.getOptimizedStyle(glassStyle, isDark: isDark);
    final bgColor = GlassTheme.getBackgroundColor(optimizedStyle,
        isDark: isDark, tintColor: backgroundColor);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: optimizedStyle.blurIntensity,
          sigmaY: optimizedStyle.blurIntensity,
        ),
        child: Container(
          padding: EdgeInsets.only(top: safeTop),
          decoration: BoxDecoration(
            color: bgColor,
            border: showBorder
                ? Border(
                    bottom: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
                      width: 0.5,
                    ),
                  )
                : null,
          ),
          child: SizedBox(
            height: height,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 玻璃效果按钮 - iOS 26 风格的悬浮按钮
///
/// iOS 26 的按钮不再集成在导航栏中，而是悬浮在玻璃层上方
/// 带有自己的玻璃背景
class GlassButton extends ConsumerWidget {
  const GlassButton({
    required this.child,
    this.onPressed,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = 10,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsets padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 经典模式 - 普通按钮
    if (!uiStyle.isGlass) {
      return IconButton(
        onPressed: onPressed,
        padding: padding,
        icon: child,
      );
    }

    // 玻璃模式 - 带玻璃背景的按钮
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: glassStyle.borderOpacity)
        : Colors.black.withValues(alpha: glassStyle.borderOpacity * 0.5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(borderRadius),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃效果图标按钮 - iOS 26 风格的悬浮图标按钮
///
/// 专门用于顶栏的图标按钮，在玻璃模式下：
/// - 圆形玻璃背景
/// - 细微边框
/// - 轻微模糊效果
///
/// 经典模式下使用普通 IconButton
class GlassIconButton extends ConsumerWidget {
  const GlassIconButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 22,
    this.color,
    super.key,
  });

  /// 图标
  final IconData icon;

  /// 点击回调
  final VoidCallback? onPressed;

  /// 提示文字
  final String? tooltip;

  /// 图标大小
  final double size;

  /// 图标颜色（默认根据主题自动选择）
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = color ?? (isDark ? Colors.white : Colors.black87);

    // 经典模式 - 普通 IconButton
    if (!uiStyle.isGlass) {
      return IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: size, color: iconColor),
        tooltip: tooltip,
      );
    }

    // 玻璃模式 - 悬浮玻璃按钮
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.06);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: glassStyle.borderOpacity * 0.8)
        : Colors.black.withValues(alpha: glassStyle.borderOpacity * 0.4);

    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: Icon(icon, size: size, color: iconColor),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}

/// 玻璃效果按钮组 - 将多个按钮组合在一起
///
/// iOS 26 风格中，多个相邻的按钮会合并在同一个玻璃背景中
class GlassButtonGroup extends ConsumerWidget {
  const GlassButtonGroup({
    required this.children,
    this.spacing = 0,
    super.key,
  });

  /// 按钮列表（通常是 GlassIconButton）
  final List<Widget> children;

  /// 按钮间距
  final double spacing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 经典模式 - 直接排列
    if (!uiStyle.isGlass) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }

    // 玻璃模式 - 使用胶囊形玻璃背景包裹所有按钮
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.06);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: glassStyle.borderOpacity * 0.8)
        : Colors.black.withValues(alpha: glassStyle.borderOpacity * 0.4);

    // 包装每个按钮，移除其玻璃背景（因为整体会有一个）
    final wrappedChildren = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && spacing > 0) {
        wrappedChildren.add(SizedBox(width: spacing));
      }
      // 给每个按钮加一个简单的分隔线（除了最后一个）
      if (i < children.length - 1) {
        wrappedChildren.add(children[i]);
        wrappedChildren.add(
          Container(
            width: 0.5,
            height: 24,
            color: borderColor,
          ),
        );
      } else {
        wrappedChildren.add(children[i]);
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: wrappedChildren,
          ),
        ),
      ),
    );
  }
}

/// 简化版玻璃图标按钮 - 无背景，仅在玻璃模式下提供提示
///
/// 用于 GlassButtonGroup 内部，不带独立的玻璃背景
class GlassGroupIconButton extends StatelessWidget {
  const GlassGroupIconButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 22,
    this.color,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = color ?? (isDark ? Colors.white : Colors.black87);

    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(icon, size: size, color: iconColor),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}
