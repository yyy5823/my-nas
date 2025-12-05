import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/router/app_router.dart';
import 'package:my_nas/app/theme/app_theme.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/shared/providers/theme_provider.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

class MyNasApp extends ConsumerStatefulWidget {
  const MyNasApp({super.key});

  @override
  ConsumerState<MyNasApp> createState() => _MyNasAppState();
}

class _MyNasAppState extends ConsumerState<MyNasApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // 应用进入后台或被销毁时，清理图片内存缓存
      StreamImage.clearCache();
      logger.d('MyNasApp: 应用进入后台，已清理图片内存缓存');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'MyNAS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
