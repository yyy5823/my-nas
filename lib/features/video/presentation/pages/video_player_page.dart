import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/video_controls.dart';

class VideoPlayerPage extends ConsumerStatefulWidget {
  const VideoPlayerPage({required this.video, super.key});

  final VideoItem video;

  @override
  ConsumerState<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends ConsumerState<VideoPlayerPage> {
  bool _showControls = true;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    // 开始播放
    Future.microtask(() {
      ref.read(videoPlayerControllerProvider.notifier).play(
            widget.video,
            startPosition: widget.video.lastPosition,
          );
    });
  }

  @override
  void dispose() {
    // 恢复系统 UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  void _toggleControls() {
    if (_isLocked) return;
    setState(() => _showControls = !_showControls);
  }

  void _hideControlsDelayed() {
    if (_showControls) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _showControls) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(videoPlayerControllerProvider);
    final playerNotifier = ref.read(videoPlayerControllerProvider.notifier);
    final isFullscreen = playerState.isFullscreen;

    // 全屏模式下隐藏系统 UI
    if (isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onDoubleTapDown: (details) {
          // 双击快进/快退
          final screenWidth = context.screenWidth;
          if (details.localPosition.dx < screenWidth / 3) {
            playerNotifier.seekBackward();
          } else if (details.localPosition.dx > screenWidth * 2 / 3) {
            playerNotifier.seekForward();
          } else {
            playerNotifier.playOrPause();
          }
        },
        child: Stack(
          children: [
            // 视频画面
            Center(
              child: Video(
                controller: playerNotifier.videoController,
                controls: (state) => const SizedBox.shrink(),
              ),
            ),

            // 缓冲指示器
            if (playerState.isBuffering)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // 控制层
            if (_showControls && !_isLocked)
              VideoControls(
                video: widget.video,
                state: playerState,
                onPlayPause: playerNotifier.playOrPause,
                onSeek: playerNotifier.seek,
                onSeekForward: playerNotifier.seekForward,
                onSeekBackward: playerNotifier.seekBackward,
                onVolumeChange: playerNotifier.setVolume,
                onSpeedChange: playerNotifier.setSpeed,
                onToggleFullscreen: playerNotifier.toggleFullscreen,
                onBack: () => Navigator.of(context).pop(),
              ),

            // 锁定按钮
            if (_showControls)
              Positioned(
                right: 16,
                top: context.padding.top + 60,
                child: IconButton(
                  onPressed: () => setState(() => _isLocked = !_isLocked),
                  icon: Icon(
                    _isLocked ? Icons.lock : Icons.lock_open,
                    color: Colors.white,
                  ),
                ),
              ),

            // 错误提示
            if (playerState.errorMessage != null)
              Center(
                child: Container(
                  padding: AppSpacing.paddingLg,
                  margin: AppSpacing.paddingLg,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: AppRadius.borderRadiusMd,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '播放失败',
                        style: context.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        playerState.errorMessage!,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => playerNotifier.play(widget.video),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
