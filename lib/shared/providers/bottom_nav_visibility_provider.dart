import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
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
/// 使用引用计数来管理导航栏可见性：
/// - 每个需要隐藏导航栏的页面调用 hide() 时增加计数
/// - 页面关闭调用 show() 时减少计数
/// - 只有计数为 0 时导航栏才可见
///
/// 这解决了嵌套页面和竞态条件的问题
class BottomNavVisibilityNotifier extends StateNotifier<bool> {
  BottomNavVisibilityNotifier._() : super(true) {
    _instance = this;
  }

  /// 全局单例
  /// 由 Provider 创建时自动设置
  static BottomNavVisibilityNotifier? _instance;

  /// 获取全局实例（用于 dispose 等场景）
  static BottomNavVisibilityNotifier? get instance => _instance;

  /// 隐藏请求计数
  /// 大于 0 表示有页面请求隐藏导航栏
  int _hideRequestCount = 0;

  /// 隐藏底部导航栏
  ///
  /// 增加隐藏请求计数
  void hide() {
    _hideRequestCount++;
    _updateVisibility();
    debugPrint('BottomNavVisibility: hide() called, count=$_hideRequestCount');
  }

  /// 显示底部导航栏
  ///
  /// 减少隐藏请求计数，只有计数归零时才显示
  void show() {
    if (_hideRequestCount > 0) {
      _hideRequestCount--;
    }
    debugPrint('BottomNavVisibility: show() called, count=$_hideRequestCount');
    _updateVisibility();

    // 确保在页面过渡完成后再次更新状态
    // 这解决了从 dispose 调用时 UI 可能不立即重建的问题
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _updateVisibility();
    });
  }

  /// 更新可见性状态
  void _updateVisibility() {
    final shouldBeVisible = _hideRequestCount <= 0;
    if (state != shouldBeVisible) {
      state = shouldBeVisible;
      debugPrint('BottomNavVisibility: state changed to $state');
    }
  }

  /// 重置状态（用于热重载或异常恢复）
  void reset() {
    _hideRequestCount = 0;
    state = true;
    debugPrint('BottomNavVisibility: reset');
  }

  /// 设置可见性（直接设置，不影响计数）
  void setVisible(bool visible) {
    if (visible) {
      _hideRequestCount = 0;
    } else {
      _hideRequestCount = 1;
    }
    state = visible;
  }
}
