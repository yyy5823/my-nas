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
  String _statusMessage = '正在启动...';
  final bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 短暂延迟让 UI 先渲染（减少延迟时间）
    await Future<void>.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    setState(() {
      _statusMessage = '初始化中...';
    });

    // 关键优化：不阻塞跳转，让服务在后台初始化
    // 视频页面会自行处理服务初始化状态
    _initServicesInBackground();

    // 立即进入主界面，不等待初始化完成
    // 这样即使网络不可用或初始化较慢，用户也能立即看到界面
    logger.i('StartupPage: 立即进入主界面，服务在后台初始化');
    if (mounted) {
      context.go(Routes.video);
    }
  }

  /// 在后台初始化服务，不阻塞UI
  void _initServicesInBackground() {
    // 使用 Future.wait 但不 await，让初始化在后台进行
    Future.wait([
      // 初始化源管理服务
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
                  shaderCallback: (bounds) => const LinearGradient(
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
