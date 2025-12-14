import 'dart:io';

/// SMB 连接池配置
///
/// 根据平台和 CPU 核心数动态调整连接池大小：
/// - 桌面端：资源充足，基于 CPU 核心数分配更多连接
/// - 移动端：考虑电池和发热，适度限制并发数
class SmbPoolConfig {
  SmbPoolConfig._();

  /// CPU 核心数
  static int get cpuCores => Platform.numberOfProcessors;

  /// 是否为桌面平台
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 是否为移动平台
  static bool get isMobile => Platform.isIOS || Platform.isAndroid;

  /// 共享连接池大小
  ///
  /// 用于短操作（目录浏览、文件信息等）
  /// 桌面端：核心数（最小4，最大12）
  /// 移动端：核心数/2（最小2，最大6）
  static int get maxConnections {
    if (isDesktop) {
      return cpuCores.clamp(4, 12);
    }
    return (cpuCores ~/ 2).clamp(2, 6);
  }

  /// 专用连接池大小
  ///
  /// 用于长操作（视频流、文件下载等）
  /// 桌面端：核心数 * 1.5（最小6，最大16）
  /// 移动端：核心数（最小4，最大8）
  static int get maxDedicatedConnections {
    if (isDesktop) {
      return (cpuCores * 1.5).round().clamp(6, 16);
    }
    return cpuCores.clamp(4, 8);
  }

  /// 后台任务并发数
  ///
  /// 用于刮削、扫描等批量操作
  /// 桌面端：核心数/2（最小3，最大8）
  /// 移动端：核心数/3（最小2，最大4）- 考虑电池和发热
  static int get maxBackgroundTasks {
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
      'dedicated=$maxDedicatedConnections, background=$maxBackgroundTasks';
}
