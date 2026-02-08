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
      // 只通过 Provider 减少引用计数，由 MainScaffold 根据 Provider 状态决定原生 Tab Bar 的可见性
      // 不直接设置 NativeTabBarService，避免多级导航时状态错乱
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
    // 同步隐藏原生 Tab Bar（不涉及 Provider）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 延迟 Provider 修改到下一帧，避免在 initState/build 中修改 Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(bottomNavVisibleProvider.notifier).hide();
      }
    });
  }

  /// 显示底部导航栏
  void showTabBar() {
    _didHideTabBar = false;
    NativeTabBarService.instance.setTabBarVisible(true);
    // 延迟 Provider 修改到下一帧
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(bottomNavVisibleProvider.notifier).show();
      }
    });
  }

  @override
  void dispose() {
    if (_didHideTabBar) {
      // 只通过 Provider 减少引用计数，由 MainScaffold 根据 Provider 状态决定原生 Tab Bar 的可见性
      // 不直接设置 NativeTabBarService，避免多级导航时状态错乱
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
    // 同步隐藏原生导航栏（不涉及 Provider）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 延迟 Provider 修改到下一帧，避免在 initState 中修改 Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(bottomNavVisibleProvider.notifier).hide();
      }
    });
  }

  @override
  void dispose() {
    // 只通过 Provider 减少引用计数，由 MainScaffold 根据 Provider 状态决定原生 Tab Bar 的可见性
    // 不直接设置 NativeTabBarService，避免多级导航时状态错乱
    BottomNavVisibilityNotifier.instance?.show();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
