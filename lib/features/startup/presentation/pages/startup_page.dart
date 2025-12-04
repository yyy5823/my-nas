import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';

class StartupPage extends ConsumerStatefulWidget {
  const StartupPage({super.key});

  @override
  ConsumerState<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends ConsumerState<StartupPage> {
  String _statusMessage = '正在启动...';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 短暂延迟让 UI 先渲染
    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    setState(() {
      _statusMessage = '初始化中...';
    });

    try {
      // 初始化源管理服务（快速的本地初始化）
      final manager = ref.read(sourceManagerProvider);
      await manager.init();

      logger.i('StartupPage: 初始化完成，进入主界面');

      // 先进入主界面，不等待连接完成
      if (mounted) {
        context.go(Routes.video);
      }

      // 后台异步进行自动连接（不阻塞主界面）
      // 使用 unawaited 明确表示不等待完成
      _autoConnectInBackground();
    } catch (e) {
      logger.e('StartupPage: 初始化异常', e);
      if (mounted) {
        // 即使初始化失败也进入主界面，用户可以在设置中配置源
        context.go(Routes.video);
      }
    }
  }

  /// 后台自动连接所有源
  void _autoConnectInBackground() {
    // 使用 Future.microtask 确保在当前帧之后执行，避免阻塞导航
    Future.microtask(() async {
      try {
        // 等待网络栈完全初始化（iOS 启动后网络可能需要一点时间就绪）
        await Future<void>.delayed(const Duration(seconds: 2));

        logger.i('StartupPage: 开始后台自动连接...');
        await ref.read(activeConnectionsProvider.notifier).autoConnectAll();
        logger.i('StartupPage: 后台自动连接完成');
      } catch (e) {
        logger.e('StartupPage: 后台自动连接异常', e);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
}
