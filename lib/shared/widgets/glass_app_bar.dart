import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';

/// 玻璃效果 AppBar
/// 根据 UI 风格自动应用玻璃或经典样式
class GlassAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.bottom,
    this.centerTitle,
    this.elevation,
    this.automaticallyImplyLeading = true,
    this.toolbarHeight,
  });

  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool? centerTitle;
  final double? elevation;
  final bool automaticallyImplyLeading;
  final double? toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(
        (toolbarHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassStyle = GlassTheme.getNavBarStyle(uiStyle, isDark: isDark);
    final optimizedStyle = PlatformGlassConfig.getOptimizedStyle(glassStyle, isDark: isDark);
    final enableGlass = PlatformGlassConfig.shouldEnableGlass(uiStyle);

    // 计算背景色
    final bgColor = enableGlass
        ? GlassTheme.getBackgroundColor(optimizedStyle, isDark: isDark)
        : (isDark ? AppColors.darkSurface : Colors.white);

    final borderColor = enableGlass
        ? GlassTheme.getBorderColor(optimizedStyle, isDark: isDark)
        : Colors.transparent;

    // 构建标题
    final titleWidget = this.titleWidget ??
        (title != null
            ? Text(
                title!,
                style: TextStyle(
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null);

    Widget appBarContent = AppBar(
      title: titleWidget,
      leading: leading,
      actions: actions,
      bottom: bottom,
      centerTitle: centerTitle,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: automaticallyImplyLeading,
      toolbarHeight: toolbarHeight,
      backgroundColor: bgColor,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    );

    // 添加底部边框
    appBarContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: appBarContent),
        Container(
          height: 0.5,
          color: borderColor,
        ),
      ],
    );

    // 玻璃效果：添加模糊背景
    if (enableGlass && optimizedStyle.needsBlur) {
      appBarContent = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: optimizedStyle.blurIntensity,
            sigmaY: optimizedStyle.blurIntensity,
          ),
          child: appBarContent,
        ),
      );
    }

    return appBarContent;
  }
}

/// 玻璃效果 SliverAppBar
/// 用于 CustomScrollView 中的场景
class GlassSliverAppBar extends ConsumerWidget {
  const GlassSliverAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.bottom,
    this.centerTitle,
    this.floating = false,
    this.pinned = true,
    this.snap = false,
    this.expandedHeight,
    this.collapsedHeight,
    this.flexibleSpace,
    this.automaticallyImplyLeading = true,
    this.toolbarHeight,
    this.stretch = false,
    this.forceElevated = false,
  });

  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool? centerTitle;
  final bool floating;
  final bool pinned;
  final bool snap;
  final double? expandedHeight;
  final double? collapsedHeight;
  final Widget? flexibleSpace;
  final bool automaticallyImplyLeading;
  final double? toolbarHeight;
  final bool stretch;
  final bool forceElevated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassStyle = GlassTheme.getNavBarStyle(uiStyle, isDark: isDark);
    final optimizedStyle = PlatformGlassConfig.getOptimizedStyle(glassStyle, isDark: isDark);
    final enableGlass = PlatformGlassConfig.shouldEnableGlass(uiStyle);

    // 计算背景色
    final bgColor = enableGlass
        ? GlassTheme.getBackgroundColor(optimizedStyle, isDark: isDark)
        : (isDark ? AppColors.darkSurface : Colors.white);

    // 构建标题
    final effectiveTitleWidget = titleWidget ??
        (title != null
            ? Text(
                title!,
                style: TextStyle(
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null);

    // 如果启用玻璃效果，使用自定义的 FlexibleSpaceBar
    var effectiveFlexibleSpace = flexibleSpace;
    if (enableGlass && optimizedStyle.needsBlur && flexibleSpace == null) {
      effectiveFlexibleSpace = _GlassFlexibleSpaceBar(
        glassStyle: optimizedStyle,
        isDark: isDark,
      );
    }

    return SliverAppBar(
      title: effectiveTitleWidget,
      leading: leading,
      actions: actions,
      bottom: bottom,
      centerTitle: centerTitle,
      floating: floating,
      pinned: pinned,
      snap: snap,
      expandedHeight: expandedHeight,
      collapsedHeight: collapsedHeight,
      flexibleSpace: effectiveFlexibleSpace,
      automaticallyImplyLeading: automaticallyImplyLeading,
      toolbarHeight: toolbarHeight ?? kToolbarHeight,
      stretch: stretch,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: enableGlass ? Colors.transparent : bgColor,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      forceElevated: forceElevated,
    );
  }
}

/// 玻璃效果的 FlexibleSpaceBar 背景
class _GlassFlexibleSpaceBar extends StatelessWidget {
  const _GlassFlexibleSpaceBar({
    required this.glassStyle,
    required this.isDark,
  });

  final GlassStyle glassStyle;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bgColor = GlassTheme.getBackgroundColor(glassStyle, isDark: isDark);
    final borderColor = GlassTheme.getBorderColor(glassStyle, isDark: isDark);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: glassStyle.blurIntensity,
          sigmaY: glassStyle.blurIntensity,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(
              bottom: BorderSide(
                color: borderColor,
                width: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 用于在 Scaffold 中配合 extendBodyBehindAppBar 使用的玻璃 AppBar
/// 此版本会自动处理状态栏高度
class GlassAppBarWithSafeArea extends ConsumerWidget implements PreferredSizeWidget {
  const GlassAppBarWithSafeArea({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.bottom,
    this.centerTitle,
    this.automaticallyImplyLeading = true,
    this.toolbarHeight,
  });

  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool? centerTitle;
  final bool automaticallyImplyLeading;
  final double? toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(
        (toolbarHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassStyle = GlassTheme.getNavBarStyle(uiStyle, isDark: isDark);
    final optimizedStyle = PlatformGlassConfig.getOptimizedStyle(glassStyle, isDark: isDark);
    final enableGlass = PlatformGlassConfig.shouldEnableGlass(uiStyle);
    final statusBarHeight = MediaQuery.of(context).padding.top;

    // 计算背景色
    final bgColor = enableGlass
        ? GlassTheme.getBackgroundColor(optimizedStyle, isDark: isDark)
        : (isDark ? AppColors.darkSurface : Colors.white);

    final borderColor = enableGlass
        ? GlassTheme.getBorderColor(optimizedStyle, isDark: isDark)
        : Colors.transparent;

    // 构建标题
    final effectiveTitleWidget = titleWidget ??
        (title != null
            ? Text(
                title!,
                style: TextStyle(
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null);

    Widget appBarContent = Container(
      padding: EdgeInsets.only(top: statusBarHeight),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: borderColor,
            width: 0.5,
          ),
        ),
      ),
      child: AppBar(
        title: effectiveTitleWidget,
        leading: leading,
        actions: actions,
        bottom: bottom,
        centerTitle: centerTitle,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: automaticallyImplyLeading,
        toolbarHeight: toolbarHeight,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
    );

    // 玻璃效果：添加模糊背景
    if (enableGlass && optimizedStyle.needsBlur) {
      appBarContent = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: optimizedStyle.blurIntensity,
            sigmaY: optimizedStyle.blurIntensity,
          ),
          child: appBarContent,
        ),
      );
    }

    return appBarContent;
  }
}
