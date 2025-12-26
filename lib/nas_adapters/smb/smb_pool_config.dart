import 'dart:io';

import 'package:my_nas/core/services/performance_mode_service.dart';

/// SMB 连接池配置
///
/// 根据平台和 CPU 核心数动态调整连接池大小：
/// - 桌面端：资源充足，基于 CPU 核心数分配更多连接
/// - 移动端：考虑电池和发热，适度限制并发数
///
/// 支持性能模式：
/// - 普通模式：保守配置，适合后台运行
/// - 性能模式：激进配置，最大化利用硬件资源
class SmbPoolConfig {
  SmbPoolConfig._();

  /// CPU 核心数
  static int get cpuCores => Platform.numberOfProcessors;

  /// 是否为桌面平台
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 是否为移动平台
  static bool get isMobile => Platform.isIOS || Platform.isAndroid;

  /// 是否启用性能模式
  static bool get isPerformanceMode => PerformanceModeService.isPerformanceMode;

  /// 共享连接池大小
  ///
  /// 用于短操作（目录浏览、文件信息等）
  /// 普通模式：桌面端 4-12，移动端 2-6
  /// 性能模式：桌面端 16-24，移动端 8-12
  static int get maxConnections {
    if (isPerformanceMode) {
      if (isDesktop) {
        return (cpuCores * 2).clamp(16, 24);
      }
      return cpuCores.clamp(8, 12);
    }
    if (isDesktop) {
      return cpuCores.clamp(4, 12);
    }
    return (cpuCores ~/ 2).clamp(2, 6);
  }

  /// 专用连接池大小
  ///
  /// 用于长操作（视频流、文件下载等）
  /// 普通模式：桌面端 6-16，移动端 2-4
  /// 性能模式：桌面端 24-32，移动端 8-12
  static int get maxDedicatedConnections {
    if (isPerformanceMode) {
      if (isDesktop) {
        return (cpuCores * 3).clamp(24, 32);
      }
      return cpuCores.clamp(8, 12);
    }
    if (isDesktop) {
      return (cpuCores * 1.5).round().clamp(6, 16);
    }
    // 移动端减少专用连接数以降低 OOM 风险
    return (cpuCores ~/ 2).clamp(2, 4);
  }

  /// 流式传输的块大小（字节）
  ///
  /// 桌面端：64KB - 大块可提高吞吐量
  /// 移动端：16KB - 小块可减少内存峰值
  /// 性能模式：桌面端 128KB，移动端 32KB
  static int get streamChunkSize {
    if (isPerformanceMode) {
      if (isDesktop) {
        return 128 * 1024; // 128KB
      }
      return 32 * 1024; // 32KB
    }
    if (isDesktop) {
      return 64 * 1024; // 64KB
    }
    return 16 * 1024; // 16KB
  }

  /// 后台任务并发数
  ///
  /// 用于刮削、扫描等批量操作
  /// 普通模式：桌面端 3-8，移动端 2-4
  /// 性能模式：桌面端 16-32，移动端 8-12
  static int get maxBackgroundTasks {
    if (isPerformanceMode) {
      if (isDesktop) {
        return (cpuCores * 2).clamp(16, 32);
      }
      return cpuCores.clamp(8, 12);
    }
    if (isDesktop) {
      return (cpuCores ~/ 2).clamp(3, 8);
    }
    return (cpuCores ~/ 3).clamp(2, 4);
  }

  /// 连接空闲超时时间
  static Duration get maxIdleTime =>
      isDesktop ? const Duration(minutes: 10) : const Duration(minutes: 5);

  /// 获取配置摘要（用于日志）
  static String get summary =>
      'SmbPoolConfig: platform=${isDesktop ? "desktop" : "mobile"}, '
      'cores=$cpuCores, connections=$maxConnections, '
      'dedicated=$maxDedicatedConnections, background=$maxBackgroundTasks, '
      'performanceMode=$isPerformanceMode';
}
