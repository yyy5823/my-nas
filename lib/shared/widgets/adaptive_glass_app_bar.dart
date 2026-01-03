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
/// iOS 26+: 使用原生 UIGlassEffect 实现真正的 Liquid Glass 效果
/// iOS 13-25: 使用原生 UIBlurEffect 回退
/// 其他平台: 使用 Flutter BackdropFilter
///
/// 多个相邻的按钮会合并在同一个胶囊形玻璃背景中
class GlassButtonGroup extends ConsumerStatefulWidget {
  const GlassButtonGroup({
    required this.children,
    this.spacing = 0,
    super.key,
  });

  /// 按钮列表（GlassGroupIconButton）
  final List<Widget> children;

  /// 按钮间距
  final double spacing;

  @override
  ConsumerState<GlassButtonGroup> createState() => _GlassButtonGroupState();
}

class _GlassButtonGroupState extends ConsumerState<GlassButtonGroup> {
  MethodChannel? _channel;

  /// 从 children 中提取按钮配置
  List<Map<String, dynamic>> _extractButtonConfigs() {
    final configs = <Map<String, dynamic>>[];
    for (final child in widget.children) {
      if (child is GlassGroupIconButton) {
        // 将 IconData 转换为 SF Symbol 名称
        final sfSymbol = _iconDataToSFSymbol(child.icon);
        configs.add({
          'icon': sfSymbol,
          'tooltip': child.tooltip,
        });
      }
    }
    return configs;
  }

  /// 将 Flutter IconData 转换为 iOS SF Symbol 名称
  String _iconDataToSFSymbol(IconData icon) {
    // 常用图标映射
    final mapping = <int, String>{
      Icons.search_rounded.codePoint: 'magnifyingglass',
      Icons.tune_rounded.codePoint: 'slider.horizontal.3',
      Icons.more_vert_rounded.codePoint: 'ellipsis',
      Icons.queue_music_rounded.codePoint: 'list.bullet',
      Icons.check_circle_outline_rounded.codePoint: 'checkmark.circle',
      Icons.view_timeline_rounded.codePoint: 'list.bullet.rectangle',
      Icons.grid_view_rounded.codePoint: 'square.grid.2x2',
      Icons.arrow_drop_down_rounded.codePoint: 'chevron.down',
      Icons.settings_rounded.codePoint: 'gearshape',
      Icons.refresh_rounded.codePoint: 'arrow.clockwise',
      Icons.filter_alt_rounded.codePoint: 'line.3.horizontal.decrease.circle',
      Icons.sort_rounded.codePoint: 'arrow.up.arrow.down',
      Icons.add_rounded.codePoint: 'plus',
      Icons.close_rounded.codePoint: 'xmark',
    };
    return mapping[icon.codePoint] ?? 'circle';
  }

  void _handleButtonTap(int index) {
    // 找到对应的按钮并调用其 onPressed
    var buttonIndex = 0;
    for (final child in widget.children) {
      if (child is GlassGroupIconButton) {
        if (buttonIndex == index) {
          child.onPressed?.call();
          return;
        }
        buttonIndex++;
      }
    }
  }

  void _setupChannel(int viewId) {
    _channel = MethodChannel('com.kkape.mynas/glass_button_group_$viewId');
    _channel?.setMethodCallHandler((call) async {
      if (call.method == 'onButtonTap') {
        final index = call.arguments as int;
        _handleButtonTap(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 经典模式 - 直接排列普通按钮
    if (!uiStyle.isGlass) {
      return _buildClassicButtonGroup(isDark);
    }

    // 玻璃模式
    // iOS: 使用原生 UIGlassEffect
    if (!kIsWeb && Platform.isIOS) {
      return _buildNativeGlassButtonGroup(isDark);
    }

    // 其他平台: 使用 Flutter BackdropFilter
    return _buildFlutterGlassButtonGroup(isDark);
  }

  Widget _buildClassicButtonGroup(bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: widget.children.map((child) {
        if (child is GlassGroupIconButton) {
          return IconButton(
            onPressed: child.onPressed,
            icon: Icon(
              child.icon,
              size: child.size,
              color: child.color ?? (isDark ? Colors.white : Colors.black87),
            ),
            tooltip: child.tooltip,
          );
        }
        return child;
      }).toList(),
    );
  }

  Widget _buildNativeGlassButtonGroup(bool isDark) {
    final buttonConfigs = _extractButtonConfigs();
    final buttonCount = buttonConfigs.length;

    // iOS 26 风格：更宽松的按钮布局
    // 每个按钮 40px + 分隔线 0.5px + 左右内边距 20px
    final width = buttonCount * 40.0 + (buttonCount - 1) * 0.5 + 20;
    const height = 44.0;

    final creationParams = <String, dynamic>{
      'isDark': isDark,
      'items': buttonConfigs,
      'buttonSize': 40.0,
      'spacing': widget.spacing,
      'cornerRadius': 22.0,
    };

    return SizedBox(
      width: width,
      height: height,
      child: UiKitView(
        viewType: 'com.kkape.mynas/glass_button_group',
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _setupChannel,
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
    );
  }

  Widget _buildFlutterGlassButtonGroup(bool isDark) {
    final glassStyle = GlassTheme.getStyle(ref.watch(uiStyleProvider), isDark: isDark);
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.06);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: glassStyle.borderOpacity * 0.8)
        : Colors.black.withValues(alpha: glassStyle.borderOpacity * 0.4);

    final wrappedChildren = <Widget>[];
    for (var i = 0; i < widget.children.length; i++) {
      if (i > 0 && widget.spacing > 0) {
        wrappedChildren.add(SizedBox(width: widget.spacing));
      }
      if (i < widget.children.length - 1) {
        wrappedChildren.add(widget.children[i]);
        wrappedChildren.add(
          Container(
            width: 0.5,
            height: 24,
            color: borderColor,
          ),
        );
      } else {
        wrappedChildren.add(widget.children[i]);
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
    this.size = 20,
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
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 40,
          height: 40,
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

/// 玻璃风格 PopupMenu 按钮
///
/// 与 GlassGroupIconButton 样式一致，但点击后显示紧跟按钮的弹出菜单
/// 使用 BackdropFilter 实现毛玻璃效果
class GlassGroupPopupMenuButton<T> extends StatelessWidget {
  const GlassGroupPopupMenuButton({
    required this.itemBuilder,
    this.icon = Icons.more_vert_rounded,
    this.onSelected,
    this.tooltip,
    this.size = 20,
    this.color,
    this.offset = const Offset(0, 8),
    super.key,
  });

  /// 菜单图标
  final IconData icon;

  /// 菜单项构建器
  final List<PopupMenuEntry<T>> Function(BuildContext context) itemBuilder;

  /// 选中回调
  final void Function(T value)? onSelected;

  /// 提示文本
  final String? tooltip;

  /// 图标大小
  final double size;

  /// 图标颜色
  final Color? color;

  /// 菜单偏移量
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = color ?? (isDark ? Colors.white : Colors.black87);

    return GestureDetector(
      onTap: () => _showGlassMenu(context),
      child: Tooltip(
        message: tooltip ?? '',
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(icon, size: size, color: iconColor),
        ),
      ),
    );
  }

  void _showGlassMenu(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final button = context.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;

    // 计算按钮位置
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    // 构建菜单项
    final items = itemBuilder(context);

    showGlassPopupMenu<T>(
      context: context,
      position: position,
      items: items,
      isDark: isDark,
    ).then((value) {
      if (value != null && onSelected != null) {
        onSelected!(value);
      }
    });
  }
}

/// 显示玻璃风格弹出菜单
///
/// 使用 BackdropFilter 实现毛玻璃效果
Future<T?> showGlassPopupMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  bool isDark = false,
  double elevation = 8,
  double blurSigma = 20,
}) {
  return Navigator.of(context).push<T>(
    _GlassPopupMenuRoute<T>(
      position: position,
      items: items,
      isDark: isDark,
      elevation: elevation,
      blurSigma: blurSigma,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// 玻璃风格弹出菜单路由
class _GlassPopupMenuRoute<T> extends PopupRoute<T> {
  _GlassPopupMenuRoute({
    required this.position,
    required this.items,
    required this.isDark,
    required this.elevation,
    required this.blurSigma,
    required this.barrierLabel,
  });

  final RelativeRect position;
  final List<PopupMenuEntry<T>> items;
  final bool isDark;
  final double elevation;
  final double blurSigma;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Animation<double> createAnimation() {
    return CurvedAnimation(
      parent: super.createAnimation(),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: Builder(
        builder: (context) {
          return CustomSingleChildLayout(
            delegate: _GlassPopupMenuRouteLayout(
              position,
              Directionality.of(context),
            ),
            child: _GlassPopupMenu<T>(
              route: this,
              animation: animation,
            ),
          );
        },
      ),
    );
  }
}

/// 玻璃风格弹出菜单布局
class _GlassPopupMenuRouteLayout extends SingleChildLayoutDelegate {
  _GlassPopupMenuRouteLayout(this.position, this.textDirection);

  final RelativeRect position;
  final TextDirection textDirection;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      constraints.biggest - const Offset(16, 16) as Size,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // 默认在按钮下方右对齐
    double x = size.width - position.right - childSize.width;
    double y = size.height - position.bottom + 8;

    // 确保不超出屏幕边界
    if (x < 8) x = 8;
    if (x + childSize.width > size.width - 8) {
      x = size.width - childSize.width - 8;
    }
    if (y + childSize.height > size.height - 8) {
      // 如果下方空间不够，显示在按钮上方
      y = position.top - childSize.height - 8;
    }
    if (y < 8) y = 8;

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_GlassPopupMenuRouteLayout oldDelegate) {
    return position != oldDelegate.position ||
        textDirection != oldDelegate.textDirection;
  }
}

/// 玻璃风格弹出菜单组件
class _GlassPopupMenu<T> extends StatelessWidget {
  const _GlassPopupMenu({
    required this.route,
    required this.animation,
  });

  final _GlassPopupMenuRoute<T> route;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final isDark = route.isDark;

    // 背景颜色 - 半透明
    final backgroundColor = isDark
        ? Colors.black.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.7);

    // 边框颜色
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.08);

    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
        alignment: Alignment.topRight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: route.blurSigma,
              sigmaY: route.blurSigma,
            ),
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 180,
                maxWidth: 280,
              ),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildMenuItems(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMenuItems(BuildContext context) {
    final List<Widget> children = [];

    for (int i = 0; i < route.items.length; i++) {
      final item = route.items[i];

      if (item is PopupMenuDivider) {
        children.add(
          Divider(
            height: 1,
            thickness: 0.5,
            color: route.isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.08),
          ),
        );
      } else if (item is PopupMenuItem<T>) {
        children.add(
          _GlassMenuItem<T>(
            value: item.value,
            isDark: route.isDark,
            onTap: () {
              Navigator.of(context).pop(item.value);
            },
            child: item.child ?? const SizedBox.shrink(),
          ),
        );
      }
    }

    return children;
  }
}

/// 玻璃风格菜单项
class _GlassMenuItem<T> extends StatefulWidget {
  const _GlassMenuItem({
    required this.child,
    required this.isDark,
    required this.onTap,
    this.value,
  });

  final Widget child;
  final bool isDark;
  final VoidCallback onTap;
  final T? value;

  @override
  State<_GlassMenuItem<T>> createState() => _GlassMenuItemState<T>();
}

class _GlassMenuItemState<T> extends State<_GlassMenuItem<T>> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered ? hoverColor : Colors.transparent,
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              color: widget.isDark ? Colors.white : Colors.black87,
              fontSize: 15,
            ),
            child: IconTheme(
              data: IconThemeData(
                color: widget.isDark ? Colors.white70 : Colors.black54,
                size: 22,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS 26 Liquid Glass 页面布局
///
/// 实现 iOS 26 风格的悬浮导航：
/// - 大标题在内容区域内，随内容滚动
/// - 工具栏按钮悬浮于内容之上
/// - 无固定顶栏背景区域
///
/// 使用示例：
/// ```dart
/// LiquidGlassPageLayout(
///   floatingButtons: GlassButtonGroup(children: [...]),
///   largeTitle: '问候语',
///   subtitle: '副标题',
///   body: CustomScrollView(slivers: [...]),
/// )
/// ```
class LiquidGlassPageLayout extends ConsumerWidget {
  const LiquidGlassPageLayout({
    required this.body,
    this.floatingButtons,
    this.floatingButtonsLeft,
    this.largeTitle,
    this.subtitle,
    this.subtitleWidget,
    this.backgroundColor,
    this.largeTitlePadding = const EdgeInsets.fromLTRB(20, 8, 20, 16),
    super.key,
  });

  /// 页面主体内容（通常是 CustomScrollView）
  final Widget body;

  /// 悬浮按钮组（右上角）
  final Widget? floatingButtons;

  /// 左侧悬浮按钮（如返回按钮）
  final Widget? floatingButtonsLeft;

  /// 大标题文本
  final String? largeTitle;

  /// 副标题文本
  final String? subtitle;

  /// 副标题组件（优先于 subtitle）
  final Widget? subtitleWidget;

  /// 背景颜色
  final Color? backgroundColor;

  /// 大标题内边距
  final EdgeInsets largeTitlePadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safeTop = MediaQuery.of(context).padding.top;

    // 经典模式使用传统布局
    if (!uiStyle.isGlass) {
      return _buildClassicLayout(context, isDark, safeTop);
    }

    // iOS 26 Liquid Glass 布局
    return _buildLiquidGlassLayout(context, isDark, safeTop);
  }

  Widget _buildClassicLayout(BuildContext context, bool isDark, double safeTop) {
    return Stack(
      children: [
        // 主内容
        body,
        // 悬浮按钮（右上角）
        if (floatingButtons != null)
          Positioned(
            top: safeTop + 8,
            right: 16,
            child: floatingButtons!,
          ),
        // 左侧按钮
        if (floatingButtonsLeft != null)
          Positioned(
            top: safeTop + 8,
            left: 16,
            child: floatingButtonsLeft!,
          ),
      ],
    );
  }

  Widget _buildLiquidGlassLayout(BuildContext context, bool isDark, double safeTop) {
    return Stack(
      children: [
        // 主内容（无固定顶栏，大标题在内容区域内）
        body,
        // 悬浮按钮组（右上角）- 真正悬浮于内容之上
        if (floatingButtons != null)
          Positioned(
            top: safeTop + 8,
            right: 16,
            child: floatingButtons!,
          ),
        // 左侧按钮
        if (floatingButtonsLeft != null)
          Positioned(
            top: safeTop + 8,
            left: 16,
            child: floatingButtonsLeft!,
          ),
      ],
    );
  }

  /// 构建大标题区域（用于放在 Sliver 中）
  static Widget buildLargeTitleSliver({
    required String title,
    String? subtitle,
    Widget? subtitleWidget,
    required bool isDark,
    EdgeInsets padding = const EdgeInsets.fromLTRB(20, 8, 20, 16),
    double topPadding = 0,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: padding.copyWith(top: padding.top + topPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: -0.5,
              ),
            ),
            if (subtitleWidget != null) ...[
              const SizedBox(height: 6),
              subtitleWidget,
            ] else if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.6)
                      : Colors.black.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
