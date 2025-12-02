import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:my_nas/app/app.dart';
import 'package:my_nas/core/di/injection.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // 保持 native splash 直到手动移除
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

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

Future<void> _initApp() async {
  logger.i('Initializing MyNAS...');

  // Initialize MediaKit for video playback
  MediaKit.ensureInitialized();

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
      TmdbService.instance.setApiKey(apiKey);
      logger.i('TMDB API key loaded');
    }
  } on Exception catch (e) {
    logger.w('Failed to load TMDB API key: $e');
  }
}
