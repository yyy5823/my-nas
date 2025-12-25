import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/video_library_cache_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';

class StartupPage extends ConsumerStatefulWidget {
  const StartupPage({super.key});

  @override
  ConsumerState<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends ConsumerState<StartupPage> {
  final String _statusMessage = '正在启动...';
  final bool _isLoading = true;

  /// 启动画面最小显示时间（毫秒）
  /// 让用户看到品牌 Logo，同时给 UI 组件准备时间
  static const int _minSplashDurationMs = 1200;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 记录开始时间
    final startTime = DateTime.now();

    // 在后台初始化服务，不阻塞 UI
    _initServicesInBackground();

    // 等待最小显示时间，让启动画面有足够展示
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    final remaining = _minSplashDurationMs - elapsed;
    if (remaining > 0) {
      await Future<void>.delayed(Duration(milliseconds: remaining));
    }

    // 跳转到主界面
    if (mounted) {
      logger.i('StartupPage: 进入主界面');
      context.go(Routes.video);
    }
  }

  /// 在后台初始化服务，不阻塞UI
  ///
  /// 注意：SourceManagerService.init() 有锁机制，
  /// 即使被多个地方调用也只会初始化一次
  void _initServicesInBackground() {
    // 使用 Future.wait 但不 await，让初始化在后台进行
    Future.wait([
      // 初始化源管理服务（Hive 存储）
      ref.read(sourceManagerProvider).init(),
      // 预初始化视频相关服务
      VideoLibraryCacheService().init(),
      VideoMetadataService().init(),
    ]).then((_) {
      logger.i('StartupPage: 后台服务初始化完成');
    }).catchError((Object e) {
      logger.e('StartupPage: 后台服务初始化异常', e);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F0F1A),
              Color(0xFF1A1A2E),
              Color(0xFF16213E),
              Color(0xFF0F0F1A),
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .shimmer(
                      duration: 2000.ms,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                const SizedBox(height: 32),

                // App name
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [AppColors.primaryLight, AppColors.accentLight],
                  ).createShader(bounds),
                  child: Text(
                    'MyNAS',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                  ),
                ),
                const SizedBox(height: 48),

                // Loading indicator
                if (_isLoading)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.primary,
                    ),
                  ),
                const SizedBox(height: 16),

                // Status message
                Text(
                  _statusMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.darkOnSurfaceVariant,
                      ),
                ).animate().fadeIn(duration: 300.ms),
              ],
            ),
          ),
        ),
      ),
    );
}
