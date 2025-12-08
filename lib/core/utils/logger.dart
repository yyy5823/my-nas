import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' as pkg_logger;
import 'package:my_nas/core/services/error_report/error_report.dart';
import 'package:path_provider/path_provider.dart';

final logger = AppLogger();

class AppLogger {
  factory AppLogger() => _instance;
  AppLogger._internal();
  static final AppLogger _instance = AppLogger._internal();

  final _logger = pkg_logger.Logger(
    printer: pkg_logger.PrettyPrinter(
      dateTimeFormat: pkg_logger.DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  File? _logFile;
  bool _initialized = false;
  final _logBuffer = <String>[];
  bool _isWriting = false;

  /// 初始化文件日志
  /// 在应用启动时调用，会清空之前的日志文件
  Future<void> initFileLogging() async {
    if (_initialized) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final logsDir = Directory('${directory.path}/logs');

      // 确保 logs 目录存在
      if (!logsDir.existsSync()) {
        logsDir.createSync(recursive: true);
      }

      _logFile = File('${logsDir.path}/app.log');

      // 清空并重新创建日志文件
      if (_logFile!.existsSync()) {
        _logFile!.deleteSync();
      }
      _logFile!.createSync();

      _initialized = true;

      // 写入启动信息
      final now = DateTime.now();
      final header = '''
========================================
MyNAS Log Started at $now
Platform: ${Platform.operatingSystem}
========================================
''';
      _logFile!.writeAsStringSync(header);

      if (kDebugMode) {
        print('[Logger] File logging initialized: ${_logFile!.path}');
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        print('[Logger] Failed to initialize file logging: $e');
      }
    }
  }

  /// 写入到文件（使用缓冲和批量写入）
  void _writeToFile(String level, String message, [Object? error, StackTrace? stackTrace]) {
    if (_logFile == null || !_initialized) return;

    final now = DateTime.now();
    final timestamp = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';

    final buffer = StringBuffer()
    ..writeln('[$timestamp] [$level] $message');

    if (error != null) {
      buffer.writeln('  Error: $error');
    }

    if (stackTrace != null) {
      buffer.writeln('  StackTrace:');
      for (final line in stackTrace.toString().split('\n').take(10)) {
        buffer.writeln('    $line');
      }
    }

    _logBuffer.add(buffer.toString());
    _flushBuffer();
  }

  /// 异步刷新缓冲区
  Future<void> _flushBuffer() async {
    if (_isWriting || _logBuffer.isEmpty || _logFile == null) return;

    _isWriting = true;
    try {
      final content = _logBuffer.join();
      _logBuffer.clear();
      _logFile!.writeAsStringSync(content, mode: FileMode.append, flush: true);
    } on Exception catch (e) {
      if (kDebugMode) {
        print('[Logger] Failed to write log: $e');
      }
    } finally {
      _isWriting = false;
      // 如果在写入期间有新日志加入，继续刷新
      if (_logBuffer.isNotEmpty) {
        await Future.microtask(_flushBuffer);
      }
    }
  }

  /// 获取日志文件路径
  String? get logFilePath => _logFile?.path;

  /// 关闭文件日志
  Future<void> close() async {
    await _flushBuffer();
    _initialized = false;
  }

  void d(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
    _writeToFile('DEBUG', message, error, stackTrace);
  }

  void i(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
    _writeToFile('INFO', message, error, stackTrace);
  }

  void w(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
    _writeToFile('WARN', message, error, stackTrace);
  }

  void e(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    _writeToFile('ERROR', message, error, stackTrace);
    _reportError(message, error, stackTrace, ErrorLevel.error);
  }

  void f(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
    _writeToFile('FATAL', message, error, stackTrace);
    _reportError(message, error, stackTrace, ErrorLevel.fatal);
  }

  /// 上报错误到远程服务
  void _reportError(String message, Object? error, StackTrace? stackTrace, ErrorLevel level) {
    final errorType = error?.runtimeType.toString() ?? 'LoggedError';
    final errorMessage = error != null ? '$message: $error' : message;

    ErrorReportService.instance.reportError(
      errorType: errorType,
      errorMessage: errorMessage,
      stackTrace: stackTrace?.toString(),
      errorLevel: level,
    );
  }
}
