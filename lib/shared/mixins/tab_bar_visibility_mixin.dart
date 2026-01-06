import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';

/// Tab Bar 可见性控制 Mixin（用于普通 State）
///
/// 用于详情页面自动隐藏/显示底部导航栏
/// 在页面进入时隐藏，退出时恢复显示
///
/// 使用方法:
/// ```dart
/// class _MyDetailPageState extends State<MyDetailPage>
///     with TabBarVisibilityMixin {
///   @override
///   void initState() {
///     super.initState();
///     hideTabBar();  // 隐藏导航栏
///   }
///   // dispose 时会自动恢复显示
/// }
/// ```
mixin TabBarVisibilityMixin<T extends StatefulWidget> on State<T> {
  bool _didHideTabBar = false;

  /// 隐藏底部导航栏
  void hideTabBar() {
    _didHideTabBar = true;
    NativeTabBarService.instance.setTabBarVisible(false);
    BottomNavVisibilityNotifier.instance?.hide();
  }

  /// 显示底部导航栏
  void showTabBar() {
    _didHideTabBar = false;
    NativeTabBarService.instance.setTabBarVisible(true);
    BottomNavVisibilityNotifier.instance?.show();
  }

  @override
  void dispose() {
    if (_didHideTabBar) {
      NativeTabBarService.instance.setTabBarVisible(true);
      BottomNavVisibilityNotifier.instance?.show();
    }
    super.dispose();
  }
}

/// Tab Bar 可见性控制 Mixin（用于 ConsumerState）
///
/// 使用方法:
/// ```dart
/// class _MyDetailPageState extends ConsumerState<MyDetailPage>
///     with ConsumerTabBarVisibilityMixin {
///   @override
///   void initState() {
///     super.initState();
///     hideTabBar();  // 隐藏导航栏
///   }
///   // dispose 时会自动恢复显示
/// }
/// ```
mixin ConsumerTabBarVisibilityMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  bool _didHideTabBar = false;

  /// 隐藏底部导航栏
  void hideTabBar() {
    _didHideTabBar = true;
    NativeTabBarService.instance.setTabBarVisible(false);
    ref.read(bottomNavVisibleProvider.notifier).hide();
  }

  /// 显示底部导航栏
  void showTabBar() {
    _didHideTabBar = false;
    NativeTabBarService.instance.setTabBarVisible(true);
    ref.read(bottomNavVisibleProvider.notifier).show();
  }

  @override
  void dispose() {
    if (_didHideTabBar) {
      NativeTabBarService.instance.setTabBarVisible(true);
      BottomNavVisibilityNotifier.instance?.show();
    }
    super.dispose();
  }
}

/// 隐藏底部导航栏的包装组件
///
/// 用于无法使用 mixin 的场景
/// 在组件挂载时自动隐藏导航栏，卸载时恢复
///
/// 使用方法:
/// ```dart
/// @override
/// Widget build(BuildContext context, WidgetRef ref) {
///   return HideBottomNavWrapper(
///     child: Scaffold(...),
///   );
/// }
/// ```
class HideBottomNavWrapper extends ConsumerStatefulWidget {
  const HideBottomNavWrapper({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  ConsumerState<HideBottomNavWrapper> createState() => _HideBottomNavWrapperState();
}

class _HideBottomNavWrapperState extends ConsumerState<HideBottomNavWrapper> {
  @override
  void initState() {
    super.initState();
    // 同步隐藏导航栏，避免闪烁
    NativeTabBarService.instance.setTabBarVisible(false);
    // 直接调用 hide()，不使用 addPostFrameCallback
    // 这样可以在页面显示前就隐藏导航栏
    ref.read(bottomNavVisibleProvider.notifier).hide();
  }

  @override
  void dispose() {
    // 恢复导航栏可见性
    NativeTabBarService.instance.setTabBarVisible(true);
    BottomNavVisibilityNotifier.instance?.show();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
