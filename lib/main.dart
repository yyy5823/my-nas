import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:my_nas/app/app.dart';
import 'package:my_nas/core/di/injection.dart';
import 'package:my_nas/core/services/error_report/error_report.dart';
import 'package:my_nas/core/services/native_log_bridge_service.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // 初始化前台服务通信端口（必须在 runApp 之前调用）
  // 这允许后台任务与主 UI 进行通信
  // 注意：仅 Android 支持 Foreground Service，iOS 不支持此机制
  if (Platform.isAndroid) {
    FlutterForegroundTask.initCommunicationPort();
  }

  // 保持 native splash 直到手动移除
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 设置全局错误处理
  _setupGlobalErrorHandling();

  // Initialize dependencies
  await _initApp();

  runApp(
    const ProviderScope(
      child: MyNasApp(),
    ),
  );

  // 等待首帧渲染完成后再移除 native splash
  // 这样可以避免用户在 UI 未完全布局时触摸屏幕导致的 "Cannot hit test" 错误
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FlutterNativeSplash.remove();
  });
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
  // ignore: no_runtimeType_toString
  final errorType = details.exception.runtimeType.toString();
  final errorMessage = details.exceptionAsString();
  final stackTrace = details.stack?.toString();

  ErrorReportService.instance.reportError(
    errorType: errorType,
    errorMessage: errorMessage,
    stackTrace: stackTrace,
    action: 'FlutterFrameworkError',
    extraData: {
      'library': details.library,
      'context': details.context?.toString(),
      'informationCollector': details.informationCollector?.call().map((e) => e.toString()).toList(),
    },
  );
}

/// 报告平台错误
void _reportPlatformError(Object error, StackTrace stack) {
  // ignore: no_runtimeType_toString
  final errorType = error.runtimeType.toString();
  final errorMessage = 'Platform Error [$errorType]: $error';
  final stackTrace = stack.toString();

  // 打印详细错误信息到日志，便于调试
  logger.e(errorMessage, error, stack);

  ErrorReportService.instance.reportError(
    errorType: errorType,
    errorMessage: errorMessage,
    stackTrace: stackTrace,
    errorLevel: ErrorLevel.fatal,
    action: 'PlatformDispatcherError',
  );
}

Future<void> _initApp() async {
  // 初始化文件日志（会清空之前的日志）
  await logger.initFileLogging();

  logger.i('Initializing MyNAS...');

  // 初始化错误报告服务（非阻塞，在后台连接）
  unawaited(ErrorReportService.instance.initialize());

  // 初始化原生日志桥接服务（iOS）
  // 用于接收 Widget Extension 的日志并上传到 RabbitMQ
  unawaited(NativeLogBridgeService().init());

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

  // Initialize AudioSession for proper audio playback on iOS/Android
  // This is critical for just_audio to work correctly
  await _initAudioSession();

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

/// 初始化音频会话
/// 这是 just_audio 在 iOS/Android 上正常播放音频的关键配置
Future<void> _initAudioSession() async {
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      // 音频类型：音乐（适合音乐播放器）
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      // Android 音频属性
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidWillPauseWhenDucked: true,
    ));
    logger.i('AudioSession initialized for music playback');
  } on Exception catch (e) {
    logger.w('Failed to initialize AudioSession: $e');
  }
}
