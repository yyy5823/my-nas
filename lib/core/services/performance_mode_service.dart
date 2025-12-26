import 'dart:async';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 性能模式服务
///
/// 用于控制刮削和扫描任务的并发数量。
/// - 普通模式：保守配置，适合后台运行，减少发热和电池消耗
/// - 性能模式：激进配置，最大化利用硬件资源，加速刮削
///
/// 使用示例：
/// ```dart
/// // 切换模式
/// await PerformanceModeService().setEnabled(true);
///
/// // 检查当前模式
/// final isEnabled = PerformanceModeService.isPerformanceMode;
///
/// // 监听模式变化
/// PerformanceModeService().stream.listen((enabled) {
///   print('性能模式: $enabled');
/// });
/// ```
class PerformanceModeService {
  factory PerformanceModeService() => _instance;
  PerformanceModeService._();

  static final _instance = PerformanceModeService._();

  static const _boxName = 'settings';
  static const _key = 'performance_mode_enabled';

  final _controller = StreamController<bool>.broadcast();

  /// 是否已初始化
  bool _initialized = false;

  /// 当前性能模式状态
  bool _enabled = false;

  /// Hive box
  Box<dynamic>? _box;

  /// 获取当前是否启用性能模式（静态方法，供配置类使用）
  static bool get isPerformanceMode => _instance._enabled;

  /// 获取当前是否启用性能模式
  bool get isEnabled => _enabled;

  /// 监听性能模式变化
  Stream<bool> get stream => _controller.stream;

  /// 初始化服务，从持久化存储加载状态
  Future<void> init() async {
    if (_initialized) return;

    _box = await Hive.openBox<dynamic>(_boxName);
    final value = _box?.get(_key);
    _enabled = value is bool && value;
    _initialized = true;
  }

  /// 设置性能模式
  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;

    _enabled = enabled;
    _controller.add(enabled);

    await _box?.put(_key, enabled);

    // 打印当前配置以便调试
    logger.i(
      'PerformanceMode: ${enabled ? "ENABLED" : "DISABLED"} - '
      'Changes will apply to NEW tasks only. '
      'Running tasks will continue at current concurrency.',
    );
  }

  /// 切换性能模式
  Future<void> toggle() async {
    await setEnabled(!_enabled);
  }

  /// 释放资源
  void dispose() {
    _controller.close();
  }
}

/// 性能模式下的并发配置倍率
class PerformanceMultiplier {
  PerformanceMultiplier._();

  /// 后台任务并发倍率
  /// 性能模式下提高 3-4 倍
  static double get backgroundTasks =>
      PerformanceModeService.isPerformanceMode ? 3.0 : 1.0;

  /// SMB 连接数倍率
  /// 性能模式下提高 2 倍
  static double get connections =>
      PerformanceModeService.isPerformanceMode ? 2.0 : 1.0;

  /// 网络请求并发倍率
  /// 性能模式下提高 2 倍
  static double get network =>
      PerformanceModeService.isPerformanceMode ? 2.0 : 1.0;

  /// 图片加载并发倍率
  /// 性能模式下提高 2 倍
  static double get imageLoad =>
      PerformanceModeService.isPerformanceMode ? 2.0 : 1.0;

  /// 封面提取并发倍率
  /// 性能模式下提高 3 倍
  static double get coverExtract =>
      PerformanceModeService.isPerformanceMode ? 3.0 : 1.0;
}
