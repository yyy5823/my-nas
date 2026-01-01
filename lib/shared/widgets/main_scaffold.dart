import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';
import 'package:my_nas/shared/services/update_service.dart';
import 'package:my_nas/shared/widgets/update_dialog.dart';

class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  static bool _hasCheckedForUpdates = false;

  /// 原生 Tab 选择订阅
  StreamSubscription<TabSelectedEvent>? _tabSelectedSubscription;

  /// 是否正在处理 Tab 切换（防止循环）
  bool _isHandlingTabChange = false;

  /// 缓存的 UI 风格（用于判断是否需要重新订阅原生 Tab Bar）
  UIStyle? _cachedUiStyle;

  /// 是否使用原生 Tab Bar
  /// 仅在 iOS 玻璃风格时使用原生 Tab Bar（Liquid Glass 效果）
  /// 经典风格使用 Flutter 自己的导航栏
  bool _shouldUseNativeTabBar(UIStyle uiStyle) {
    if (kIsWeb) return false;
    if (!Platform.isIOS) return false;
    // 仅玻璃风格使用原生 Tab Bar
    return uiStyle.isGlass;
  }

  @override
  void initState() {
    super.initState();

    // 仅在首次显示 MainScaffold 时检查更新
    if (!_hasCheckedForUpdates) {
      _hasCheckedForUpdates = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkForUpdatesOnStartup();
      });
    }
  }

  @override
  void dispose() {
    _tabSelectedSubscription?.cancel();
    super.dispose();
  }

  /// 处理原生 Tab 选择事件
  void _handleNativeTabSelected(TabSelectedEvent event) {
    if (_isHandlingTabChange || !mounted) return;

    _isHandlingTabChange = true;

    // 使用原生传来的路由进行导航
    context.go(event.route);

    // 延迟重置标志，避免路由变化时触发循环
    Future.delayed(const Duration(milliseconds: 50), () {
      _isHandlingTabChange = false;
    });
  }

  Future<void> _checkForUpdatesOnStartup() async {
    // 仅在非 Web 平台检查更新
    if (kIsWeb) return;

    // 延迟一点时间，确保应用完全启动
    await Future<void>.delayed(const Duration(seconds: 2));

    final updateService = UpdateService();
    await updateService.checkForUpdates(silent: true);

    // 如果有更新，显示更新对话框
    if (updateService.hasUpdate && updateService.updateInfo != null && mounted) {
      // 检查是否是桌面平台或移动平台（iOS 除外，因为需要通过 App Store 更新）
      if (!Platform.isIOS) {
        await showUpdateDialog(context, updateService.updateInfo!);
      }
    }
  }

  static const _destinations = [
    _Destination(
      icon: Icons.movie_filter_outlined,
      selectedIcon: Icons.movie_filter_rounded,
      label: '影视',
      route: Routes.video,
      sfSymbol: 'film',
    ),
    _Destination(
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music_rounded,
      label: '曲库',
      route: Routes.music,
      sfSymbol: 'music.note.list',
    ),
    _Destination(
      icon: Icons.photo_album_outlined,
      selectedIcon: Icons.photo_album_rounded,
      label: '相册',
      route: Routes.photo,
      sfSymbol: 'photo.on.rectangle',
    ),
    _Destination(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book_rounded,
      label: '阅读',
      route: Routes.reading,
      sfSymbol: 'book',
    ),
    _Destination(
      icon: Icons.account_circle_outlined,
      selectedIcon: Icons.account_circle_rounded,
      label: '我的',
      route: Routes.mine,
      sfSymbol: 'person.circle',
    ),
  ];

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    for (var i = 0; i < _destinations.length; i++) {
      if (location.startsWith(_destinations[i].route)) {
        return i;
      }
    }
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    if (_isHandlingTabChange) return;

    _isHandlingTabChange = true;
    context.go(_destinations[index].route);

    // 延迟重置标志
    Future.delayed(const Duration(milliseconds: 100), () {
      _isHandlingTabChange = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getCurrentIndex(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final glassStyle = GlassTheme.getNavBarStyle(uiStyle, isDark: isDark);
    final optimizedStyle = PlatformGlassConfig.getOptimizedStyle(glassStyle, isDark: isDark);
    final enableGlass = PlatformGlassConfig.shouldEnableGlass(uiStyle);
    final useNativeTabBar = _shouldUseNativeTabBar(uiStyle);

    // 处理 UI 风格变化时的原生 Tab Bar 订阅
    _handleUiStyleChange(uiStyle, useNativeTabBar, currentIndex);

    // Use NavigationRail for desktop, NavigationBar for mobile
    if (context.isDesktop) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : null,
        body: Row(
          children: [
            _buildDesktopNav(context, currentIndex, isDark, optimizedStyle, enableGlass),
            Expanded(child: widget.child),
          ],
        ),
      );
    }

    // iOS 玻璃风格：使用原生 UITabBar，不显示 Flutter 底部导航栏
    if (useNativeTabBar) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : null,
        body: widget.child,
      );
    }

    // 其他情况: 使用 Flutter 底部导航栏
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      // 玻璃模式下让内容延伸到导航栏下方
      extendBody: enableGlass,
      body: widget.child,
      bottomNavigationBar: _buildMobileNav(context, currentIndex, isDark, optimizedStyle, enableGlass),
    );
  }

  /// 处理 UI 风格变化
  void _handleUiStyleChange(UIStyle uiStyle, bool useNativeTabBar, int currentIndex) {
    // 首次调用或风格变化时
    if (_cachedUiStyle != uiStyle) {
      final wasUsingNative = _cachedUiStyle != null && _shouldUseNativeTabBar(_cachedUiStyle!);
      _cachedUiStyle = uiStyle;

      if (useNativeTabBar && !wasUsingNative) {
        // 切换到玻璃风格：订阅原生事件并显示原生 Tab Bar
        _tabSelectedSubscription?.cancel();
        _tabSelectedSubscription =
            NativeTabBarService.instance.onTabSelected.listen(_handleNativeTabSelected);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          NativeTabBarService.instance.setTabBarVisible(true);
          NativeTabBarService.instance.setSelectedIndex(currentIndex);
        });
      } else if (!useNativeTabBar && wasUsingNative) {
        // 切换到经典风格：取消订阅并隐藏原生 Tab Bar
        _tabSelectedSubscription?.cancel();
        _tabSelectedSubscription = null;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          NativeTabBarService.instance.setTabBarVisible(false);
        });
      }
    } else if (useNativeTabBar && !_isHandlingTabChange) {
      // 同步 Flutter 路由到原生 Tab Bar
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        NativeTabBarService.instance.setSelectedIndex(currentIndex);
      });
    }
  }

  Widget _buildDesktopNav(
    BuildContext context,
    int currentIndex,
    bool isDark,
    GlassStyle glassStyle,
    bool enableGlass,
  ) {
    final isExtended = context.screenWidth > 1400;

    // 计算背景色
    final bgColor = enableGlass
        ? GlassTheme.getBackgroundColor(glassStyle, isDark: isDark)
        : (isDark ? AppColors.darkSurface : context.colorScheme.surface);

    final borderColor = enableGlass
        ? GlassTheme.getBorderColor(glassStyle, isDark: isDark)
        : (isDark
            ? AppColors.darkOutline.withValues(alpha: 0.3)
            : context.colorScheme.outlineVariant);

    Widget navContent = Container(
      width: isExtended ? 220 : 72,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          right: BorderSide(color: borderColor),
        ),
      ),
      child: Column(
        children: [
          // Logo
          Padding(
            padding: EdgeInsets.all(isExtended ? 20 : 16),
            child: Row(
              mainAxisAlignment:
                  isExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/logo.png',
                    width: isExtended ? 40 : 36,
                    height: isExtended ? 40 : 36,
                    fit: BoxFit.cover,
                  ),
                ),
                if (isExtended) ...[
                  const SizedBox(width: 12),
                  Text(
                    'MyNAS',
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkOnSurface
                          : context.colorScheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Navigation items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _destinations.length,
              itemBuilder: (context, index) {
                final dest = _destinations[index];
                final isSelected = currentIndex == index;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _onDestinationSelected(context, index),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                          horizontal: isExtended ? 16 : 0,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: isExtended
                              ? MainAxisAlignment.start
                              : MainAxisAlignment.center,
                          children: [
                            Icon(
                              isSelected ? dest.selectedIcon : dest.icon,
                              color: isSelected
                                  ? AppColors.primary
                                  : isDark
                                      ? AppColors.darkOnSurfaceVariant
                                      : context.colorScheme.onSurfaceVariant,
                              size: 24,
                            ),
                            if (isExtended) ...[
                              const SizedBox(width: 12),
                              Text(
                                dest.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? AppColors.primary
                                      : isDark
                                          ? AppColors.darkOnSurfaceVariant
                                          : context.colorScheme.onSurfaceVariant,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    // 玻璃效果：添加模糊背景
    if (enableGlass && glassStyle.needsBlur) {
      navContent = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: glassStyle.blurIntensity,
            sigmaY: glassStyle.blurIntensity,
          ),
          child: navContent,
        ),
      );
    }

    return navContent;
  }

  Widget _buildMobileNav(
    BuildContext context,
    int currentIndex,
    bool isDark,
    GlassStyle glassStyle,
    bool enableGlass,
  ) {
    // 计算背景色
    final bgColor = enableGlass
        ? GlassTheme.getBackgroundColor(glassStyle, isDark: isDark)
        : (isDark ? AppColors.darkSurface : context.colorScheme.surface);

    final borderColor = enableGlass
        ? GlassTheme.getBorderColor(glassStyle, isDark: isDark)
        : (isDark
            ? AppColors.darkOutline.withValues(alpha: 0.3)
            : context.colorScheme.outlineVariant);

    Widget navContent = DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(color: borderColor),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_destinations.length, (index) {
                final dest = _destinations[index];
                final isSelected = currentIndex == index;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => _onDestinationSelected(context, index),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            isSelected ? dest.selectedIcon : dest.icon,
                            color: isSelected
                                ? AppColors.primary
                                : isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dest.label,
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected
                                ? AppColors.primary
                                : isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );

    // 玻璃效果：添加模糊背景
    if (enableGlass && glassStyle.needsBlur) {
      navContent = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: glassStyle.blurIntensity,
            sigmaY: glassStyle.blurIntensity,
          ),
          child: navContent,
        ),
      );
    }

    return navContent;
  }
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
    this.sfSymbol,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;
  final String? sfSymbol;
}
