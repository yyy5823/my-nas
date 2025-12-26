import 'dart:io';
import 'dart:ui' show Offset, Size;

import 'package:floating/floating.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:window_manager/window_manager.dart';

/// 画中画服务
///
/// 跨平台画中画支持：
/// - Android/iOS: 使用系统原生画中画 (floating 包)
/// - 桌面端: 使用置顶小窗口 (window_manager 包)
class PipService {
  factory PipService() => _instance ??= PipService._();
  PipService._();

  static PipService? _instance;

  /// 移动端画中画控制器
  Floating? _floating;

  /// 是否处于画中画模式
  bool _isPipMode = false;

  /// 桌面端原始窗口大小
  Size? _originalWindowSize;

  /// 桌面端原始窗口位置
  Offset? _originalWindowPosition;

  /// 桌面端画中画窗口大小
  static const Size _desktopPipSize = Size(400, 225); // 16:9 比例

  /// 是否支持画中画
  Future<bool> get isSupported async {
    if (_isMobile) {
      try {
        _floating ??= Floating();
        return await _floating!.isPipAvailable;
      } on Exception catch (e) {
        // floating 包在 iOS 上可能没有正确注册原生插件
        logger.w('PipService: 检查画中画支持失败: $e');
        return false;
      }
    }
    // 桌面端总是支持（通过窗口管理）
    return _isDesktop;
  }

  /// 当前是否处于画中画模式
  bool get isPipMode => _isPipMode;

  /// 是否为移动端
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// 是否为桌面端
  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 进入画中画模式
  Future<bool> enterPipMode({
    double aspectRatio = 16 / 9,
  }) async {
    if (_isPipMode) return true;

    try {
      if (_isMobile) {
        return _enterMobilePip(aspectRatio: aspectRatio);
      } else if (_isDesktop) {
        return _enterDesktopPip();
      }
      return false;
    } on Exception catch (e) {
      logger.e('PipService: 进入画中画失败', e);
      return false;
    }
  }

  /// 退出画中画模式
  Future<bool> exitPipMode() async {
    if (!_isPipMode) return true;

    try {
      if (_isDesktop) {
        return _exitDesktopPip();
      }
      // 移动端画中画由系统控制退出
      _isPipMode = false;
      return true;
    } on Exception catch (e) {
      logger.e('PipService: 退出画中画失败', e);
      return false;
    }
  }

  /// 切换画中画模式
  Future<bool> togglePipMode({double aspectRatio = 16 / 9}) async {
    if (_isPipMode) {
      return exitPipMode();
    } else {
      return enterPipMode(aspectRatio: aspectRatio);
    }
  }

  /// 移动端进入画中画
  Future<bool> _enterMobilePip({required double aspectRatio}) async {
    _floating ??= Floating();

    final available = await _floating!.isPipAvailable;
    if (!available) {
      logger.w('PipService: 设备不支持画中画');
      return false;
    }

    // 计算宽高比 Rational
    final rational = _aspectRatioToRational(aspectRatio);

    final status = await _floating!.enable(ImmediatePiP(aspectRatio: rational));

    _isPipMode = status == PiPStatus.enabled;
    logger.i('PipService: 移动端画中画 ${_isPipMode ? "已启用" : "启用失败"}');
    return _isPipMode;
  }

  /// 将浮点数宽高比转换为 Rational
  Rational _aspectRatioToRational(double ratio) {
    // 常见比例
    if ((ratio - 16 / 9).abs() < 0.01) return Rational.landscape();
    if ((ratio - 4 / 3).abs() < 0.01) return Rational(4, 3);
    if ((ratio - 21 / 9).abs() < 0.01) return Rational(21, 9);
    if ((ratio - 1).abs() < 0.01) return Rational.square();

    // 通用转换
    final numerator = (ratio * 100).round();
    return Rational(numerator, 100);
  }

  /// 桌面端进入画中画（小窗口模式）
  Future<bool> _enterDesktopPip() async {
    await windowManager.ensureInitialized();

    // 保存原始窗口状态
    _originalWindowSize = await windowManager.getSize();
    _originalWindowPosition = await windowManager.getPosition();

    // 设置窗口属性
    await windowManager.setSize(_desktopPipSize);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);

    // 获取屏幕大小，将窗口放在右下角
    final bounds = await windowManager.getBounds();
    // 估算屏幕大小（当前位置 + 窗口大小 的近似）
    final screenWidth = bounds.left + bounds.width + 500;
    final screenHeight = bounds.top + bounds.height + 300;

    // 移动到右下角
    final newX = screenWidth - _desktopPipSize.width - 40;
    final newY = screenHeight - _desktopPipSize.height - 100;
    await windowManager.setPosition(Offset(newX > 0 ? newX : 20, newY > 0 ? newY : 20));

    _isPipMode = true;
    logger.i('PipService: 桌面端画中画已启用');
    return true;
  }

  /// 桌面端退出画中画
  Future<bool> _exitDesktopPip() async {
    await windowManager.ensureInitialized();

    // 恢复窗口属性
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);

    // 恢复原始大小和位置
    if (_originalWindowSize != null) {
      await windowManager.setSize(_originalWindowSize!);
    }
    if (_originalWindowPosition != null) {
      await windowManager.setPosition(_originalWindowPosition!);
    }

    _isPipMode = false;
    _originalWindowSize = null;
    _originalWindowPosition = null;

    logger.i('PipService: 桌面端画中画已退出');
    return true;
  }

  /// 获取当前画中画状态（仅移动端）
  Future<PiPStatus> getPipStatus() async {
    if (_isMobile) {
      _floating ??= Floating();
      return _floating!.pipStatus;
    }
    return _isPipMode ? PiPStatus.enabled : PiPStatus.disabled;
  }

  /// 更新画中画状态（由外部调用，当检测到状态变化时）
  void updatePipStatus(bool isPip) {
    _isPipMode = isPip;
  }

  /// 释放资源
  void dispose() {
    _floating = null;
    _isPipMode = false;
    _originalWindowSize = null;
    _originalWindowPosition = null;
  }
}
