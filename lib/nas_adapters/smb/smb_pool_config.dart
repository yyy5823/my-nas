import 'dart:io';

/// SMB 连接池配置
///
/// 根据平台动态调整连接池大小：
/// - 桌面端（Windows/macOS/Linux）：资源充足，使用更大的连接池
/// - 移动端（iOS/Android）：资源有限，使用较小的连接池
class SmbPoolConfig {
  SmbPoolConfig._();

  /// 是否为桌面平台
  static bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 是否为移动平台
  static bool get isMobile => Platform.isIOS || Platform.isAndroid;

  /// 共享连接池大小
  ///
  /// 用于短操作（目录浏览、文件信息等）
  static int get maxConnections => isDesktop ? 8 : 4;

  /// 专用连接池大小
  ///
  /// 用于长操作（视频流、文件下载等）
  static int get maxDedicatedConnections => isDesktop ? 12 : 6;

  /// 后台任务并发数
  ///
  /// 用于刮削、扫描等批量操作
  static int get maxBackgroundTasks => isDesktop ? 6 : 3;

  /// 连接空闲超时时间
  static Duration get maxIdleTime =>
      isDesktop ? const Duration(minutes: 10) : const Duration(minutes: 5);

  /// 获取配置摘要（用于日志）
  static String get summary =>
      'SmbPoolConfig: platform=${isDesktop ? "desktop" : "mobile"}, '
      'connections=$maxConnections, dedicated=$maxDedicatedConnections, '
      'background=$maxBackgroundTasks';
}
