import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:my_nas/app/app.dart';
import 'package:my_nas/core/di/injection.dart';
import 'package:my_nas/core/services/error_report/error_report.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // 保持 native splash 直到手动移除
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 设置全局错误处理
  _setupGlobalErrorHandling();

  // Initialize dependencies
  await _initApp();

  // 移除 native splash，立即显示 StartupPage
  FlutterNativeSplash.remove();

  runApp(
    const ProviderScope(
      child: MyNasApp(),
    ),
  );
}

/// 设置全局错误处理
void _setupGlobalErrorHandling() {
  // 捕获 Flutter 框架错误
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _reportFlutterError(details);
  };

  // 捕获异步错误和平台错误
  PlatformDispatcher.instance.onError = (error, stack) {
    _reportPlatformError(error, stack);
    return true;
  };
}

/// 报告 Flutter 框架错误
void _reportFlutterError(FlutterErrorDetails details) {
  final errorType = details.exception.runtimeType.toString();
  final errorMessage = details.exceptionAsString();
  final stackTrace = details.stack?.toString();

  ErrorReportService.instance.reportError(
    errorType: errorType,
    errorMessage: errorMessage,
    stackTrace: stackTrace,
    extra: {
      'library': details.library,
      'context': details.context?.toString(),
    },
  );
}

/// 报告平台错误
void _reportPlatformError(Object error, StackTrace stack) {
  final errorType = error.runtimeType.toString();
  final errorMessage = error.toString();
  final stackTrace = stack.toString();

  ErrorReportService.instance.reportError(
    errorType: errorType,
    errorMessage: errorMessage,
    stackTrace: stackTrace,
    errorLevel: ErrorLevel.fatal,
  );
}

Future<void> _initApp() async {
  // 初始化文件日志（会清空之前的日志）
  await logger.initFileLogging();

  logger.i('Initializing MyNAS...');

  // 初始化错误报告服务
  await ErrorReportService.instance.initialize();

  // Initialize sqflite_common_ffi for desktop platforms (Windows, macOS, Linux)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    logger.i('SQLite FFI initialized for desktop platform');
  }

  // Initialize MediaKit for video playback
  MediaKit.ensureInitialized();

  // Initialize JustAudioMediaKit to use MediaKit as audio backend
  // This fixes the just_audio_windows threading issue on Windows
  JustAudioMediaKit.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Configure dependency injection
  await configureDependencies();

  // Load TMDB API key from settings
  await _loadTmdbApiKey();

  logger.i('MyNAS initialized successfully');
}

Future<void> _loadTmdbApiKey() async {
  try {
    // Hive 已经在 configureDependencies 中通过其他服务初始化了
    // 这里直接打开 box 即可
    final box = await Hive.openBox<String>('settings');
    final apiKey = box.get('tmdb_api_key', defaultValue: '');
    if (apiKey != null && apiKey.isNotEmpty) {
      TmdbService().setApiKey(apiKey);
      logger.i('TMDB API key loaded');
    }
  } on Exception catch (e) {
    logger.w('Failed to load TMDB API key: $e');
  }
}
