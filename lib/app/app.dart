import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/router/app_router.dart';
import 'package:my_nas/app/theme/app_theme.dart';
import 'package:my_nas/core/services/background_task_service.dart';
import 'package:my_nas/core/services/deep_link_service.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/video_scanner_service.dart';
import 'package:my_nas/shared/providers/theme_provider.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

class MyNasApp extends ConsumerStatefulWidget {
  const MyNasApp({super.key});

  @override
  ConsumerState<MyNasApp> createState() => _MyNasAppState();
}

class _MyNasAppState extends ConsumerState<MyNasApp> with WidgetsBindingObserver {
  bool _deepLinkInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 释放 DeepLinkService
    if (Platform.isIOS) {
      DeepLinkService().dispose();
    }
    super.dispose();
  }

  /// 初始化 DeepLinkService（仅 iOS）
  void _initDeepLinkService() {
    if (_deepLinkInitialized || !Platform.isIOS) return;
    _deepLinkInitialized = true;

    // 添加错误处理，防止初始化失败导致应用崩溃
    try {
      DeepLinkService().init(ref);
      logger.i('MyNasApp: DeepLinkService 初始化成功');
    } catch (e, stackTrace) {
      logger.e('MyNasApp: DeepLinkService 初始化失败', e, stackTrace);
      // 不抛出异常，允许应用继续运行
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    logger.d('MyNasApp: AppLifecycleState changed to $state');

    switch (state) {
      case AppLifecycleState.paused:
        // 应用进入后台
        // 清理图片内存缓存以节省内存
        StreamImage.clearCache();
        logger.d('MyNasApp: 应用进入后台，已清理图片内存缓存');
        // 注意：后台任务会继续运行（通过 Foreground Service）
        _logBackgroundTaskStatus();

      case AppLifecycleState.detached:
        // 应用被销毁
        StreamImage.clearCache();
        logger.d('MyNasApp: 应用即将被销毁');
        // 停止后台服务（如果正在运行）
        // 任务状态已保存到数据库，下次启动时会自动恢复
        _stopBackgroundServiceIfNeeded();

      case AppLifecycleState.resumed:
        // 应用从后台恢复
        logger.d('MyNasApp: 应用已从后台恢复');
        // 检查后台任务状态
        _checkAndResumeBackgroundTask();

      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // 不处理这些状态
        break;
    }
  }

  /// 记录后台任务状态
  void _logBackgroundTaskStatus() {
    final scanner = VideoScannerService();
    if (scanner.isScraping) {
      logger.i('MyNasApp: 刮削任务正在后台运行');
    }
    if (scanner.isScanning) {
      logger.i('MyNasApp: 扫描任务正在后台运行');
    }
  }

  /// 停止后台服务（如果需要）
  Future<void> _stopBackgroundServiceIfNeeded() async {
    // 当应用被销毁时，我们选择让服务继续运行
    // 因为用户可能希望任务在后台完成
    // 如果需要强制停止，取消下面的注释：
    // await BackgroundTaskService().stopService();
  }

  /// 检查并恢复后台任务
  Future<void> _checkAndResumeBackgroundTask() async {
    // 强制广播当前刮削统计，确保 UI 同步最新进度
    // 这解决了从后台切回前台时进度不更新的问题
    await VideoScannerService().broadcastCurrentStats();

    // 仅在移动平台检查后台服务状态
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final backgroundService = BackgroundTaskService();
    final isRunning = await backgroundService.checkServiceRunning();

    if (isRunning) {
      logger.i('MyNasApp: 后台服务仍在运行');
    } else {
      // 服务已停止，检查是否有未完成的任务需要恢复
      // 这会在 VideoListNotifier 中自动处理
      logger.d('MyNasApp: 后台服务未运行，等待自动恢复检查');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 初始化 DeepLinkService（在 build 中调用以确保 ref 可用）
    _initDeepLinkService();

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
