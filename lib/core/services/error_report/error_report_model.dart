/// 错误报告数据模型
/// @author cq
/// @date 2025-12-08
library;

import 'package:my_nas/core/services/error_report/error_report_settings.dart';

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

  /// 根据设置过滤字段后转换为 JSON
  /// 必传字段（errorType, errorMessage, errorLevel, errorTime）始终包含
  Map<String, dynamic> toFilteredJson(ErrorReportSettings settings) {
    final json = <String, dynamic>{
      // 必传字段 - 始终包含
      'appId': appId,
      'appName': appName,
      'platform': platform,
      'errorType': errorType,
      'errorCode': errorCode,
      'errorMessage': errorMessage,
      'errorLevel': errorLevel.value,
      'errorTime': errorTime.toIso8601String(),
    };

    // 可选字段 - 根据设置决定是否包含
    if (settings.includeAppVersion) {
      json['appVersion'] = appVersion ?? '1.0.0';
    }

    if (settings.includeDeviceId) {
      json['deviceId'] = deviceId;
    }

    if (settings.includeDeviceModel) {
      json['deviceModel'] = deviceModel;
    }

    if (settings.includeDeviceBrand) {
      json['deviceBrand'] = deviceBrand;
    }

    if (settings.includeOsInfo) {
      json['osName'] = osName;
      json['osVersion'] = osVersion;
    }

    if (settings.includeScreenResolution) {
      json['screenResolution'] = screenResolution;
    }

    if (settings.includeUserId) {
      json['userId'] = userId;
      json['userName'] = userName;
    }

    if (settings.includeNetworkType) {
      json['networkType'] = networkType;
    }

    if (settings.includePageRoute) {
      json['pageRoute'] = pageRoute;
    }

    if (settings.includeAction) {
      json['action'] = action;
    }

    if (settings.includeStackTrace) {
      json['stackTrace'] = stackTrace;
    }

    if (settings.includeExtraData) {
      json['extraData'] = extraData;
    }

    return json;
  }

  /// 生成错误签名用于去重
  String get signature => '$errorType:$errorMessage:${stackTrace?.hashCode}';

  @override
  String toString() => 'ErrorReportModel(type: $errorType, message: $errorMessage, level: ${errorLevel.value})';
}
