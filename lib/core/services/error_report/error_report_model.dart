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
    this.osName,
    this.osVersion,
    this.userId,
    this.appVersion,
    this.extra,
  });

  static const String appId = 'com.kkape.mynas';
  static const String appName = 'MyNas';
  static const String platform = 'flutter';

  final String errorType;
  final String? errorCode;
  final String errorMessage;
  final String? stackTrace;
  final ErrorLevel errorLevel;
  final String? deviceId;
  final String? deviceModel;
  final String? osName;
  final String? osVersion;
  final String? userId;
  final String? appVersion;
  final DateTime errorTime;
  final Map<String, dynamic>? extra;

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
        'osName': osName,
        'osVersion': osVersion,
        'userId': userId,
        'errorTime': errorTime.toIso8601String(),
        if (extra != null) ...extra!,
      };

  /// 生成错误签名用于去重
  String get signature => '$errorType:$errorMessage:${stackTrace?.hashCode}';

  @override
  String toString() => 'ErrorReportModel(type: $errorType, message: $errorMessage, level: ${errorLevel.value})';
}
