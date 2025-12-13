import 'dart:async';
import 'dart:collection' as collection;
import 'dart:convert';

import 'package:dart_amqp/dart_amqp.dart';
import 'package:flutter/foundation.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/services/error_report/device_info_helper.dart';
import 'package:my_nas/core/services/error_report/error_report_model.dart';
import 'package:my_nas/core/services/error_report/route_tracker.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 错误报告服务
/// @author cq
/// @date 2025-12-08
class ErrorReportService {
  ErrorReportService._();

  static final ErrorReportService _instance = ErrorReportService._();
  static ErrorReportService get instance => _instance;

  /// 是否启用错误上报
  ///
  /// 设置为 false 可以完全禁用错误上报功能。
  /// 在 debug 模式下默认禁用，release 模式下默认启用。
  ///
  /// 使用方式：
  /// ```dart
  /// // 禁用错误上报
  /// ErrorReportService.instance.enabled = false;
  ///
  /// // 启用错误上报
  /// ErrorReportService.instance.enabled = true;
  /// ```
  bool enabled = !kDebugMode;

  // RabbitMQ 配置
  static const String _host = '192.168.0.120';
  static const int _port = 5672;
  static const String _exchangeName = 'app.error.log.exchange';
  static const String _routingKey = 'app.error.log.mynas';

  Client? _client;
  Channel? _channel;
  Exchange? _exchange;
  bool _isConnected = false;
  bool _isConnecting = false;

  // 本地缓存队列（网络不可用时）
  final collection.Queue<ErrorReportModel> _pendingQueue = collection.Queue();
  static const int _maxQueueSize = 100;

  // 重复错误检测
  final Map<String, DateTime> _recentErrors = {};
  static const Duration _deduplicationWindow = Duration(minutes: 5);
  static const int _maxRecentErrors = 50;

  // 死循环检测
  final Map<String, _LoopDetector> _loopDetectors = {};
  static const int _loopThreshold = 5;
  static const Duration _loopWindow = Duration(seconds: 10);

  // 重连配置
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 5);

  /// 初始化服务（非阻塞）
  Future<void> initialize() async {
    await DeviceInfoHelper.instance.initialize();
    // 异步连接，不阻塞应用启动
    AppError.fireAndForget(
      _connectWithTimeout(),
      action: 'ErrorReportService.connectOnInit',
    );
  }

  // 连接超时时间
  static const Duration _connectTimeout = Duration(seconds: 10);

  /// 带超时的连接方法
  Future<void> _connectWithTimeout() async {
    try {
      await _connect().timeout(
        _connectTimeout,
        onTimeout: () {
          if (kDebugMode) {
            logger.w('[ErrorReportService] Connection timeout');
          }
          _isConnecting = false;
          _scheduleReconnect();
        },
      );
    } on Exception catch (e) {
      if (kDebugMode) {
        logger.w('[ErrorReportService] Connect with timeout failed: $e');
      }
    }
  }

  /// 连接到 RabbitMQ
  Future<void> _connect() async {
    if (_isConnected || _isConnecting) return;
    _isConnecting = true;

    try {
      final settings = ConnectionSettings(
        host: _host,
        port: _port,
        authProvider: const PlainAuthenticator('flutter', 'flutter_client'),
      );

      _client = Client(settings: settings);
      _channel = await _client!.channel();
      // 使用 TOPIC 类型，与服务器已有的 exchange 类型保持一致
      _exchange = await _channel!.exchange(_exchangeName, ExchangeType.TOPIC, durable: true);

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;

      if (kDebugMode) {
        logger.i('[ErrorReportService] Connected to RabbitMQ');
      }

      // 发送缓存的错误（异步，不阻塞）
      AppError.fireAndForget(
        _flushPendingQueue(),
        action: 'ErrorReportService.flushPendingQueue',
      );
    } on Exception catch (e) {
      _isConnecting = false;
      _isConnected = false;

      if (kDebugMode) {
        logger.w('[ErrorReportService] Failed to connect: $e');
      }

      _scheduleReconnect();
    }
  }

  /// 安排重连
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      if (kDebugMode) {
        logger.w('[ErrorReportService] Max reconnect attempts reached');
      }
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay * (_reconnectAttempts + 1), () {
      _reconnectAttempts++;
      _connect();
    });
  }

  /// 报告错误
  Future<void> reportError({
    required String errorType,
    required String errorMessage,
    String? errorCode,
    String? stackTrace,
    ErrorLevel errorLevel = ErrorLevel.error,
    String? userId,
    String? userName,
    String? action,
    Map<String, dynamic>? extraData,
  }) async {
    // 如果上报功能被禁用，直接返回
    if (!enabled) {
      if (kDebugMode) {
        logger.d('[ErrorReportService] Reporting disabled, skipping: $errorType');
      }
      return;
    }

    // 获取网络类型（异步但不阻塞）
    final networkType = await DeviceInfoHelper.instance.getNetworkType();

    final report = ErrorReportModel(
      errorType: errorType,
      errorMessage: errorMessage,
      errorCode: errorCode,
      stackTrace: stackTrace,
      errorLevel: errorLevel,
      deviceId: DeviceInfoHelper.instance.deviceId,
      deviceModel: DeviceInfoHelper.instance.deviceModel,
      deviceBrand: DeviceInfoHelper.instance.deviceBrand,
      osName: DeviceInfoHelper.instance.osName,
      osVersion: DeviceInfoHelper.instance.osVersion,
      screenResolution: DeviceInfoHelper.instance.screenResolution,
      appVersion: DeviceInfoHelper.instance.appVersion,
      userId: userId,
      userName: userName,
      networkType: networkType,
      pageRoute: RouteTracker.instance.currentRoute,
      action: action,
      errorTime: DateTime.now(),
      extraData: extraData,
    );

    // 检查是否为重复错误
    if (_isDuplicateError(report)) {
      if (kDebugMode) {
        logger.d('[ErrorReportService] Duplicate error ignored: ${report.errorType}');
      }
      return;
    }

    // 检查是否为死循环
    if (_isLoopDetected(report)) {
      if (kDebugMode) {
        logger.w('[ErrorReportService] Loop detected for: ${report.errorType}');
      }
      await _sendLoopWarning(report);
      return;
    }

    await _sendReport(report);
  }

  /// 发送错误报告（非阻塞）
  Future<void> _sendReport(ErrorReportModel report) async {
    if (!_isConnected) {
      _addToPendingQueue(report);
      // 异步尝试连接，不阻塞
      AppError.fireAndForget(
        _connectWithTimeout(),
        action: 'ErrorReportService.connectOnSend',
      );
      return;
    }

    try {
      final jsonStr = jsonEncode(report.toJson());
      _exchange!.publish(jsonStr, _routingKey);

      if (kDebugMode) {
        logger.d('[ErrorReportService] Error reported: ${report.errorType}');
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        logger.w('[ErrorReportService] Failed to send report: $e');
      }
      _addToPendingQueue(report);
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  /// 添加到待发送队列
  void _addToPendingQueue(ErrorReportModel report) {
    if (_pendingQueue.length >= _maxQueueSize) {
      _pendingQueue.removeFirst();
    }
    _pendingQueue.add(report);
  }

  /// 发送缓存的错误
  Future<void> _flushPendingQueue() async {
    while (_pendingQueue.isNotEmpty && _isConnected) {
      final report = _pendingQueue.removeFirst();
      await _sendReport(report);
    }
  }

  /// 检查是否为重复错误
  bool _isDuplicateError(ErrorReportModel report) {
    final signature = report.signature;
    final now = DateTime.now();

    // 清理过期的记录
    _recentErrors.removeWhere((_, time) => now.difference(time) > _deduplicationWindow);

    // 限制记录数量
    if (_recentErrors.length >= _maxRecentErrors) {
      final oldestKey = _recentErrors.entries.reduce((a, b) => a.value.isBefore(b.value) ? a : b).key;
      _recentErrors.remove(oldestKey);
    }

    if (_recentErrors.containsKey(signature)) {
      return true;
    }

    _recentErrors[signature] = now;
    return false;
  }

  /// 检查是否检测到死循环
  bool _isLoopDetected(ErrorReportModel report) {
    final key = '${report.errorType}:${report.errorMessage.hashCode}';
    final now = DateTime.now();

    _loopDetectors.putIfAbsent(key, _LoopDetector.new);
    final detector = _loopDetectors[key]!;

    // 清理过期的时间戳
    detector.timestamps.removeWhere((time) => now.difference(time) > _loopWindow);

    detector.timestamps.add(now);

    if (detector.timestamps.length >= _loopThreshold) {
      if (!detector.warningReported) {
        detector.warningReported = true;
        return true;
      }
      return false; // 已经报告过警告，忽略后续
    }

    return false;
  }

  /// 发送死循环警告
  Future<void> _sendLoopWarning(ErrorReportModel originalReport) async {
    final networkType = await DeviceInfoHelper.instance.getNetworkType();

    final warningReport = ErrorReportModel(
      errorType: 'LoopDetected',
      errorMessage: '检测到重复执行: ${originalReport.errorType} - ${originalReport.errorMessage}',
      errorCode: 'LOOP_001',
      stackTrace: originalReport.stackTrace,
      errorLevel: ErrorLevel.warning,
      deviceId: DeviceInfoHelper.instance.deviceId,
      deviceModel: DeviceInfoHelper.instance.deviceModel,
      deviceBrand: DeviceInfoHelper.instance.deviceBrand,
      osName: DeviceInfoHelper.instance.osName,
      osVersion: DeviceInfoHelper.instance.osVersion,
      screenResolution: DeviceInfoHelper.instance.screenResolution,
      appVersion: DeviceInfoHelper.instance.appVersion,
      networkType: networkType,
      pageRoute: RouteTracker.instance.currentRoute,
      errorTime: DateTime.now(),
      extraData: {
        'originalErrorType': originalReport.errorType,
        'loopCount': _loopThreshold,
        'loopWindowSeconds': _loopWindow.inSeconds,
      },
    );

    await _sendReport(warningReport);
  }

  /// 关闭服务
  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    await _client?.close();
    _isConnected = false;
    _client = null;
    _channel = null;
    _exchange = null;
  }
}

/// 死循环检测器
class _LoopDetector {
  final List<DateTime> timestamps = [];
  bool warningReported = false;
}
