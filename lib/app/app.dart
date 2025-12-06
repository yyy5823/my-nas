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
    logger.d('MyNasApp: AppLifecycleState changed to $state');

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // 应用进入后台或被销毁时，清理图片内存缓存
        StreamImage.clearCache();
        logger.d('MyNasApp: 应用进入后台，已清理图片内存缓存');
      case AppLifecycleState.resumed:
        // 应用从后台恢复
        logger.d('MyNasApp: 应用已从后台恢复');
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // 不处理这些状态
        break;
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
      // 添加 builder 来处理全局错误边界
      builder: (context, child) {
        // 使用 ErrorWidget.builder 自定义错误显示
        ErrorWidget.builder = (details) {
          logger.e('Flutter Error: ${details.exception}', details.exception, details.stack);
          return Material(
            child: Container(
              color: Colors.red.shade100,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    '发生错误',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.red),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    details.exception.toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        };
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
