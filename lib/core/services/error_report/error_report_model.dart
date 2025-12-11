/// 错误报告数据模型
/// @author cq
/// @date 2025-12-08
library;

/// 错误级别枚举
enum ErrorLevel {
  debug('DEBUG'),
  info('INFO'),
  warning('WARNING'),
  error('ERROR'),
  fatal('FATAL');

  const ErrorLevel(this.value);
  final String value;
}

/// 错误报告模型
class ErrorReportModel {
  const ErrorReportModel({
    required this.errorType,
    required this.errorMessage,
    required this.errorLevel,
    required this.errorTime,
    this.errorCode,
    this.stackTrace,
    this.deviceId,
    this.deviceModel,
    this.deviceBrand,
    this.osName,
    this.osVersion,
    this.screenResolution,
    this.userId,
    this.userName,
    this.networkType,
    this.pageRoute,
    this.action,
    this.appVersion,
    this.extraData,
  });

  static const String appId = 'com.kkape.mynas';
  static const String appName = 'MyNas';
  static const String platform = 'flutter';

  // 错误信息
  final String errorType;
  final String? errorCode;
  final String errorMessage;
  final String? stackTrace;
  final ErrorLevel errorLevel;
  final DateTime errorTime;

  // 设备信息
  final String? deviceId;
  final String? deviceModel;
  final String? deviceBrand;
  final String? osName;
  final String? osVersion;
  final String? screenResolution;

  // 用户信息
  final String? userId;
  final String? userName;

  // 上下文信息
  final String? networkType;
  final String? pageRoute;
  final String? action;
  final String? appVersion;
  final Map<String, dynamic>? extraData;

  Map<String, dynamic> toJson() => {
        'appId': appId,
        'appName': appName,
        'appVersion': appVersion ?? '1.0.0',
        'platform': platform,
        'errorType': errorType,
        'errorCode': errorCode,
        'errorMessage': errorMessage,
        'stackTrace': stackTrace,
        'errorLevel': errorLevel.value,
        'deviceId': deviceId,
        'deviceModel': deviceModel,
        'deviceBrand': deviceBrand,
        'osName': osName,
        'osVersion': osVersion,
        'screenResolution': screenResolution,
        'userId': userId,
        'userName': userName,
        'networkType': networkType,
        'pageRoute': pageRoute,
        'action': action,
        'errorTime': errorTime.toIso8601String(),
        'extraData': extraData,
      };

  /// 生成错误签名用于去重
  String get signature => '$errorType:$errorMessage:${stackTrace?.hashCode}';

  @override
  String toString() => 'ErrorReportModel(type: $errorType, message: $errorMessage, level: ${errorLevel.value})';
}
