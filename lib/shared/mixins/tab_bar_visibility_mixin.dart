import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';

/// Tab Bar 可见性控制 Mixin
///
/// 用于详情页面自动隐藏/显示底部导航栏
/// 在页面进入时隐藏，退出时恢复显示
///
/// 使用方法:
/// ```dart
/// class _MyDetailPageState extends ConsumerState<MyDetailPage>
///     with TabBarVisibilityMixin {
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
  void hideTabBar() {
    _didHideTabBar = true;
    NativeTabBarService.instance.setTabBarVisible(false);
  }

  /// 显示底部导航栏
  ///
  /// 手动恢复导航栏显示
  void showTabBar() {
    _didHideTabBar = false;
    NativeTabBarService.instance.setTabBarVisible(true);
  }

  @override
  void dispose() {
    // 如果之前隐藏了导航栏，在页面销毁时恢复显示
    if (_didHideTabBar) {
      NativeTabBarService.instance.setTabBarVisible(true);
    }
    super.dispose();
  }
}

/// 用于 ConsumerState 的 Tab Bar 可见性控制 Mixin
///
/// 与 TabBarVisibilityMixin 功能相同，但专门用于 ConsumerState
mixin ConsumerTabBarVisibilityMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  bool _didHideTabBar = false;

  /// 隐藏底部导航栏
  void hideTabBar() {
    _didHideTabBar = true;
    NativeTabBarService.instance.setTabBarVisible(false);
  }

  /// 显示底部导航栏
  void showTabBar() {
    _didHideTabBar = false;
    NativeTabBarService.instance.setTabBarVisible(true);
  }

  @override
  void dispose() {
    if (_didHideTabBar) {
      NativeTabBarService.instance.setTabBarVisible(true);
    }
    super.dispose();
  }
}
