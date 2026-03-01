/// App Store 版本编译开关配置
///
/// 使用方式：
/// ```bash
/// # App Store 版本（隐藏敏感功能）
/// flutter build ios --release --dart-define=STORE_BUILD=true
///
/// # 完整版（所有功能可用）
/// flutter build macos --release
/// ```
class StoreConfig {
  StoreConfig._();

  /// 是否为 App Store 构建
  static const bool isStoreBuild =
      bool.fromEnvironment('STORE_BUILD', defaultValue: false);

  // === 功能开关 ===

  /// PT 站点功能
  static bool get showPTSites => !isStoreBuild;

  /// 下载器功能 (qBittorrent / Transmission / Aria2)
  static bool get showDownloaders => !isStoreBuild;

  /// 媒体管理 (NasTool / MoviePilot)
  static bool get showMediaManagement => !isStoreBuild;

  /// 在线书源 (Legado 格式)
  static bool get showBookSources => !isStoreBuild;

  /// 媒体追踪 (Trakt) — 低风险，保留
  static bool get showMediaTracking => true;
}
