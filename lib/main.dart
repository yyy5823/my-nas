import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:my_nas/app/app.dart';
import 'package:my_nas/core/di/injection.dart';
import 'package:my_nas/core/utils/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize dependencies
  await _initApp();

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

  // Configure dependency injection
  await configureDependencies();

  logger.i('MyNAS initialized successfully');
}
