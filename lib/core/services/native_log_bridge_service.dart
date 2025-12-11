import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:my_nas/core/services/error_report/error_report_model.dart';
import 'package:my_nas/core/services/error_report/error_report_service.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 原生日志桥接服务
/// 接收来自 iOS Swift 端（包括 Widget Extension）的日志
/// 并上传到 RabbitMQ
class NativeLogBridgeService {
  factory NativeLogBridgeService() => _instance ??= NativeLogBridgeService._();
  NativeLogBridgeService._();

  static NativeLogBridgeService? _instance;

  static const _channel = MethodChannel('com.kkape.mynas/native_log_bridge');

  bool _initialized = false;

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;

    // 仅在 iOS 上启用
    if (!Platform.isIOS) {
      logger.d('NativeLogBridgeService: 非 iOS 平台，跳过初始化');
      return;
    }

    // 设置方法调用处理器
    _channel.setMethodCallHandler(_handleMethodCall);

    _initialized = true;
    logger.i('NativeLogBridgeService: 初始化完成');

    // 启动时检查是否有待上传的日志
    unawaited(_uploadPendingLogs());
  }

  /// 处理来自原生端的方法调用
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'uploadPendingLogs':
        // 原生端通知有待上传的日志
        final args = call.arguments as Map<Object?, Object?>?;
        final count = args?['count'] as int? ?? 0;
        logger.d('NativeLogBridgeService: 收到上传通知，待上传日志数: $count');
        await _uploadPendingLogs();
        return null;
      default:
        throw PlatformException(
          code: 'NOT_IMPLEMENTED',
          message: '未实现的方法: ${call.method}',
        );
    }
  }

  /// 上传待处理的日志
  Future<void> _uploadPendingLogs() async {
    try {
      // 获取待上传的日志
      final logs = await _getPendingLogs();
      if (logs.isEmpty) {
        logger.d('NativeLogBridgeService: 无待上传的日志');
        return;
      }

      logger.i('NativeLogBridgeService: 开始上传 ${logs.length} 条原生日志');

      // 逐条上传到 RabbitMQ
      for (final log in logs) {
        await _uploadLog(log);
      }

      // 清空已上传的日志
      await _clearLogs();
      logger.i('NativeLogBridgeService: 原生日志上传完成');
    } on Exception catch (e, stackTrace) {
      logger.e('NativeLogBridgeService: 上传日志失败', e, stackTrace);
    }
  }

  /// 获取待上传的日志
  Future<List<Map<String, dynamic>>> _getPendingLogs() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getPendingLogs');
      return result?.cast<Map<dynamic, dynamic>>().map((e) =>
        e.map((key, value) => MapEntry(key.toString(), value)),
      ).toList() ?? [];
    } on PlatformException catch (e) {
      logger.e('NativeLogBridgeService: 获取待上传日志失败', e);
      return [];
    }
  }

  /// 清空已上传的日志
  Future<void> _clearLogs() async {
    try {
      await _channel.invokeMethod<void>('clearLogs');
    } on PlatformException catch (e) {
      logger.e('NativeLogBridgeService: 清空日志失败', e);
    }
  }

  /// 上传单条日志到 RabbitMQ
  Future<void> _uploadLog(Map<String, dynamic> log) async {
    final level = _parseLogLevel(log['level'] as String? ?? 'INFO');
    final message = log['message'] as String? ?? '';
    final source = log['source'] as String? ?? 'Unknown';
    final file = log['file'] as String? ?? '';
    final function = log['function'] as String? ?? '';
    final line = log['line'] as int? ?? 0;
    final timestamp = log['timestamp'] as String?;

    // 构建错误报告
    final report = ErrorReportModel(
      errorType: 'NativeLog',
      errorCode: level.name.toUpperCase(),
      errorMessage: '[$source] $message',
      stackTrace: 'at $function ($file:$line)',
      errorLevel: level,
      errorTime: timestamp != null ? DateTime.tryParse(timestamp) ?? DateTime.now() : DateTime.now(),
      extra: {
        'source': source,
        'file': file,
        'function': function,
        'line': line,
        'platform': 'iOS-Native',
      },
    );

    // 上传到 RabbitMQ
    await ErrorReportService.instance.reportError(
      errorType: report.errorType,
      errorMessage: report.errorMessage,
      stackTrace: report.stackTrace,
      errorLevel: report.errorLevel,
      extra: report.extra,
    );
  }

  /// 解析日志级别
  ErrorLevel _parseLogLevel(String level) => switch (level.toUpperCase()) {
        'DEBUG' => ErrorLevel.debug,
        'INFO' => ErrorLevel.info,
        'WARNING' => ErrorLevel.warning,
        'ERROR' => ErrorLevel.error,
        'FATAL' => ErrorLevel.fatal,
        _ => ErrorLevel.info,
      };

  /// 手动触发上传（可在需要时调用）
  Future<void> forceUpload() async {
    if (!_initialized) {
      logger.w('NativeLogBridgeService: 服务未初始化');
      return;
    }
    await _uploadPendingLogs();
  }

  /// 获取待上传日志数量
  Future<int> getPendingLogCount() async {
    if (!_initialized) return 0;
    try {
      return await _channel.invokeMethod<int>('getPendingLogCount') ?? 0;
    } on PlatformException {
      return 0;
    }
  }
}
