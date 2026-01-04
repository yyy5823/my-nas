import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';

/// Tab Bar 可见性控制 Mixin
///
/// 用于详情页面自动隐藏/显示底部导航栏
/// 在页面进入时隐藏，退出时恢复显示
///
/// 同时支持：
/// - iOS 玻璃风格：通过 NativeTabBarService 控制原生 Tab Bar
/// - 经典风格：通过 bottomNavVisibleProvider 控制 Flutter 导航栏
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
///
///   // dispose 时会自动恢复显示
/// }
/// ```
mixin TabBarVisibilityMixin<T extends StatefulWidget> on State<T> {
  bool _didHideTabBar = false;

  /// 隐藏底部导航栏
  ///
  /// 调用此方法后，dispose 时会自动恢复显示
  /// 同时控制：
  /// - iOS 玻璃风格：原生 UITabBar
  /// - 经典风格：Flutter BottomNavigationBar
  void hideTabBar() {
    _didHideTabBar = true;
    // 控制 iOS 原生 Tab Bar（玻璃风格）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 控制 Flutter 导航栏（经典风格）
    BottomNavVisibilityNotifier.instance?.hide();
  }

  /// 显示底部导航栏
  ///
  /// 手动恢复导航栏显示
  void showTabBar() {
    _didHideTabBar = false;
    NativeTabBarService.instance.setTabBarVisible(true);
    BottomNavVisibilityNotifier.instance?.show();
  }

  @override
  void dispose() {
    // 如果之前隐藏了导航栏，在页面销毁时恢复显示
    if (_didHideTabBar) {
      NativeTabBarService.instance.setTabBarVisible(true);
      BottomNavVisibilityNotifier.instance?.show();
    }
    super.dispose();
  }
}

/// 用于 ConsumerState 的 Tab Bar 可见性控制 Mixin
///
/// 同时控制：
/// - iOS 玻璃风格：原生 UITabBar（通过 NativeTabBarService）
/// - 经典风格：Flutter BottomNavigationBar（通过 bottomNavVisibleProvider）
mixin ConsumerTabBarVisibilityMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  bool _didHideTabBar = false;

  /// 隐藏底部导航栏（同时隐藏原生和 Flutter 导航栏）
  void hideTabBar() {
    _didHideTabBar = true;
    // 控制 iOS 原生 Tab Bar（玻璃风格）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 控制 Flutter 导航栏（经典风格）
    ref.read(bottomNavVisibleProvider.notifier).hide();
  }

  /// 显示底部导航栏（同时显示原生和 Flutter 导航栏）
  void showTabBar() {
    _didHideTabBar = false;
    NativeTabBarService.instance.setTabBarVisible(true);
    ref.read(bottomNavVisibleProvider.notifier).show();
  }

  @override
  void dispose() {
    if (_didHideTabBar) {
      NativeTabBarService.instance.setTabBarVisible(true);
      // 使用全局实例恢复 Flutter 导航栏（经典风格）
      BottomNavVisibilityNotifier.instance?.show();
    }
    super.dispose();
  }
}

/// 隐藏底部导航栏的包装组件
///
/// 用于无法使用 mixin 的 ConsumerWidget 或 StatelessWidget
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
    // 隐藏原生 Tab Bar（iOS 玻璃风格）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 隐藏 Flutter 导航栏（经典风格）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(bottomNavVisibleProvider.notifier).hide();
      }
    });
  }

  @override
  void dispose() {
    // 恢复原生 Tab Bar
    NativeTabBarService.instance.setTabBarVisible(true);
    // 恢复 Flutter 导航栏
    BottomNavVisibilityNotifier.instance?.show();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
