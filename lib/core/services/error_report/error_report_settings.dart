/// 日志上报设置
/// 控制是否上报日志以及上报哪些字段
/// @author cq
/// @date 2025-12-28
library;

/// 日志上报设置模型
class ErrorReportSettings {
  const ErrorReportSettings({
    this.enabled = false,
    this.includeDeviceId = true,
    this.includeDeviceModel = true,
    this.includeDeviceBrand = true,
    this.includeOsInfo = true,
    this.includeScreenResolution = true,
    this.includeAppVersion = true,
    this.includeUserId = true,
    this.includeNetworkType = true,
    this.includePageRoute = true,
    this.includeAction = true,
    this.includeStackTrace = true,
    this.includeExtraData = true,
  });

  /// 从 Map 创建设置
  factory ErrorReportSettings.fromJson(Map<String, dynamic> json) => ErrorReportSettings(
        enabled: json['enabled'] as bool? ?? false,
        includeDeviceId: json['includeDeviceId'] as bool? ?? true,
        includeDeviceModel: json['includeDeviceModel'] as bool? ?? true,
        includeDeviceBrand: json['includeDeviceBrand'] as bool? ?? true,
        includeOsInfo: json['includeOsInfo'] as bool? ?? true,
        includeScreenResolution: json['includeScreenResolution'] as bool? ?? true,
        includeAppVersion: json['includeAppVersion'] as bool? ?? true,
        includeUserId: json['includeUserId'] as bool? ?? true,
        includeNetworkType: json['includeNetworkType'] as bool? ?? true,
        includePageRoute: json['includePageRoute'] as bool? ?? true,
        includeAction: json['includeAction'] as bool? ?? true,
        includeStackTrace: json['includeStackTrace'] as bool? ?? true,
        includeExtraData: json['includeExtraData'] as bool? ?? true,
      );

  /// 总开关 - 是否启用日志上报（默认关闭）
  final bool enabled;

  // ===== 设备信息 =====
  /// 是否上报设备ID
  final bool includeDeviceId;

  /// 是否上报设备型号
  final bool includeDeviceModel;

  /// 是否上报设备品牌
  final bool includeDeviceBrand;

  /// 是否上报操作系统信息（osName, osVersion）
  final bool includeOsInfo;

  /// 是否上报屏幕分辨率
  final bool includeScreenResolution;

  // ===== 应用信息 =====
  /// 是否上报应用版本
  final bool includeAppVersion;

  // ===== 用户信息 =====
  /// 是否上报用户信息（userId, userName）
  final bool includeUserId;

  // ===== 上下文信息 =====
  /// 是否上报网络类型
  final bool includeNetworkType;

  /// 是否上报当前页面路由
  final bool includePageRoute;

  /// 是否上报操作名称
  final bool includeAction;

  // ===== 错误详情 =====
  /// 是否上报堆栈跟踪
  final bool includeStackTrace;

  /// 是否上报额外数据
  final bool includeExtraData;

  /// 总字段数量
  static const int totalFieldCount = 12;

  /// 转换为 Map
  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'includeDeviceId': includeDeviceId,
        'includeDeviceModel': includeDeviceModel,
        'includeDeviceBrand': includeDeviceBrand,
        'includeOsInfo': includeOsInfo,
        'includeScreenResolution': includeScreenResolution,
        'includeAppVersion': includeAppVersion,
        'includeUserId': includeUserId,
        'includeNetworkType': includeNetworkType,
        'includePageRoute': includePageRoute,
        'includeAction': includeAction,
        'includeStackTrace': includeStackTrace,
        'includeExtraData': includeExtraData,
      };

  /// 复制并修改
  ErrorReportSettings copyWith({
    bool? enabled,
    bool? includeDeviceId,
    bool? includeDeviceModel,
    bool? includeDeviceBrand,
    bool? includeOsInfo,
    bool? includeScreenResolution,
    bool? includeAppVersion,
    bool? includeUserId,
    bool? includeNetworkType,
    bool? includePageRoute,
    bool? includeAction,
    bool? includeStackTrace,
    bool? includeExtraData,
  }) =>
      ErrorReportSettings(
        enabled: enabled ?? this.enabled,
        includeDeviceId: includeDeviceId ?? this.includeDeviceId,
        includeDeviceModel: includeDeviceModel ?? this.includeDeviceModel,
        includeDeviceBrand: includeDeviceBrand ?? this.includeDeviceBrand,
        includeOsInfo: includeOsInfo ?? this.includeOsInfo,
        includeScreenResolution: includeScreenResolution ?? this.includeScreenResolution,
        includeAppVersion: includeAppVersion ?? this.includeAppVersion,
        includeUserId: includeUserId ?? this.includeUserId,
        includeNetworkType: includeNetworkType ?? this.includeNetworkType,
        includePageRoute: includePageRoute ?? this.includePageRoute,
        includeAction: includeAction ?? this.includeAction,
        includeStackTrace: includeStackTrace ?? this.includeStackTrace,
        includeExtraData: includeExtraData ?? this.includeExtraData,
      );

  /// 所有字段开关是否全部开启
  bool get allFieldsEnabled =>
      includeDeviceId &&
      includeDeviceModel &&
      includeDeviceBrand &&
      includeOsInfo &&
      includeScreenResolution &&
      includeAppVersion &&
      includeUserId &&
      includeNetworkType &&
      includePageRoute &&
      includeAction &&
      includeStackTrace &&
      includeExtraData;

  /// 开启的字段数量
  int get enabledFieldCount {
    var count = 0;
    if (includeDeviceId) count++;
    if (includeDeviceModel) count++;
    if (includeDeviceBrand) count++;
    if (includeOsInfo) count++;
    if (includeScreenResolution) count++;
    if (includeAppVersion) count++;
    if (includeUserId) count++;
    if (includeNetworkType) count++;
    if (includePageRoute) count++;
    if (includeAction) count++;
    if (includeStackTrace) count++;
    if (includeExtraData) count++;
    return count;
  }

  @override
  String toString() => 'ErrorReportSettings(enabled: $enabled, fields: $enabledFieldCount/$totalFieldCount)';
}
