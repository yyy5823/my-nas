import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 底部导航栏可见性 Provider
///
/// 用于控制经典风格下 Flutter 底部导航栏的显示/隐藏
/// 玻璃风格下由 NativeTabBarService 直接控制原生 Tab Bar
final bottomNavVisibleProvider = StateNotifierProvider<BottomNavVisibilityNotifier, bool>(
  (ref) => BottomNavVisibilityNotifier._(),
);

/// 底部导航栏可见性 Notifier
///
/// 提供全局单例访问，方便在 dispose 等无法访问 ref 的地方使用
class BottomNavVisibilityNotifier extends StateNotifier<bool> {
  BottomNavVisibilityNotifier._() : super(true) {
    _instance = this;
  }

  /// 全局单例
  /// 由 Provider 创建时自动设置
  static BottomNavVisibilityNotifier? _instance;

  /// 获取全局实例（用于 dispose 等场景）
  static BottomNavVisibilityNotifier? get instance => _instance;

  /// 隐藏底部导航栏
  void hide() {
    if (state) {
      state = false;
    }
  }

  /// 显示底部导航栏
  void show() {
    if (!state) {
      state = true;
    }
  }

  /// 设置可见性
  void setVisible(bool visible) {
    if (state != visible) {
      state = visible;
    }
  }
}
