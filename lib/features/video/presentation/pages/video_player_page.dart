import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/subtitle_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/presentation/providers/playlist_provider.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/aspect_ratio_selector.dart';
import 'package:my_nas/features/video/presentation/widgets/bookmark_sheet.dart';
import 'package:my_nas/features/video/presentation/widgets/video_controls.dart';
import 'package:my_nas/features/video/presentation/widgets/video_gesture_controller.dart';

class VideoPlayerPage extends ConsumerStatefulWidget {
  const VideoPlayerPage({required this.video, super.key});

  final VideoItem video;

  @override
  ConsumerState<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends ConsumerState<VideoPlayerPage> {
  bool _showControls = true;
  bool _isLocked = false;
  Timer? _hideControlsTimer;

  // 双击动画
  bool _showDoubleTapLeft = false;
  bool _showDoubleTapRight = false;

  @override
  void initState() {
    super.initState();
    // 开始播放
    Future.microtask(() {
      ref.read(videoPlayerControllerProvider.notifier).play(
            widget.video,
            startPosition: widget.video.lastPosition,
          );
      _loadSubtitles();
    });
    _startHideControlsTimer();
  }

  /// 加载字幕
  Future<void> _loadSubtitles() async {
    // 查找第一个已连接的源
    final connections = ref.read(activeConnectionsProvider);
    final connectedEntry = connections.entries.firstWhere(
      (e) => e.value.status == SourceStatus.connected,
      orElse: () => throw Exception('No connected source'),
    );
    final adapter = connectedEntry.value.adapter;

    try {
      final subtitles = await SubtitleService.instance.findSubtitles(
        videoPath: widget.video.path,
        videoName: widget.video.name,
        fileSystem: adapter.fileSystem,
      );

      ref.read(availableSubtitlesProvider.notifier).state = subtitles;

      // 如果找到字幕，自动加载第一个
      if (subtitles.isNotEmpty) {
        await ref.read(videoPlayerControllerProvider.notifier).setSubtitle(subtitles.first);
        logger.i('VideoPlayerPage: 自动加载字幕 ${subtitles.first.name}');
      }
    } catch (e) {
      logger.e('VideoPlayerPage: 加载字幕失败', e);
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    // 同步停止播放 - 在 dispose 之前立即停止播放器
    final notifier = ref.read(videoPlayerControllerProvider.notifier);
    notifier.stopSync(); // 使用同步方法停止，确保在 dispose 前完成
    // 恢复系统 UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _showControls && !_isLocked) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _toggleControls() {
    if (_isLocked) {
      // 锁定时只显示锁定按钮
      setState(() => _showControls = !_showControls);
      return;
    }
    setState(() => _showControls = !_showControls);
    _startHideControlsTimer();
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (_isLocked) return;

    final screenWidth = context.screenWidth;
    final playerNotifier = ref.read(videoPlayerControllerProvider.notifier);

    if (details.localPosition.dx < screenWidth / 3) {
      // 左侧双击 - 快退
      playerNotifier.seekBackward();
      setState(() => _showDoubleTapLeft = true);
    } else if (details.localPosition.dx > screenWidth * 2 / 3) {
      // 右侧双击 - 快进
      playerNotifier.seekForward();
      setState(() => _showDoubleTapRight = true);
    } else {
      // 中间双击 - 播放/暂停
      playerNotifier.playOrPause();
    }
  }

  /// 根据画面比例模式构建视频组件
  Widget _buildVideoWidget(VideoController controller, AspectRatioMode mode) {
    final video = Video(
      controller: controller,
      controls: (state) => const SizedBox.shrink(),
      fit: switch (mode) {
        AspectRatioMode.fill => BoxFit.fill,
        AspectRatioMode.contain => BoxFit.contain,
        AspectRatioMode.cover => BoxFit.cover,
        _ => BoxFit.contain,
      },
    );

    // 如果是固定比例模式，用 AspectRatio 包裹
    if (mode.ratio != null) {
      return AspectRatio(
        aspectRatio: mode.ratio!,
        child: video,
      );
    }

    return video;
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
      body: VideoGestureController(
        playerState: playerState,
        onTap: _toggleControls,
        onDoubleTap: _handleDoubleTap,
        onVolumeChange: (volume) {
          playerNotifier.setVolume(volume);
          _startHideControlsTimer();
        },
        onSeek: (position) {
          playerNotifier.seek(position);
          _startHideControlsTimer();
        },
        child: Stack(
          children: [
            // 视频画面
            Center(
              child: Consumer(
                builder: (context, ref, _) {
                  final aspectMode = ref.watch(aspectRatioModeProvider);
                  return _buildVideoWidget(
                    playerNotifier.videoController,
                    aspectMode,
                  );
                },
              ),
            ),

            // 缓冲指示器
            if (playerState.isBuffering)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // 双击快退动画
            if (_showDoubleTapLeft)
              Positioned(
                left: 48,
                top: 0,
                bottom: 0,
                child: Center(
                  child: DoubleTapSeekOverlay(
                    isForward: false,
                    onComplete: () {
                      if (mounted) {
                        setState(() => _showDoubleTapLeft = false);
                      }
                    },
                  ),
                ),
              ),

            // 双击快进动画
            if (_showDoubleTapRight)
              Positioned(
                right: 48,
                top: 0,
                bottom: 0,
                child: Center(
                  child: DoubleTapSeekOverlay(
                    isForward: true,
                    onComplete: () {
                      if (mounted) {
                        setState(() => _showDoubleTapRight = false);
                      }
                    },
                  ),
                ),
              ),

            // 控制层
            if (_showControls && !_isLocked)
              Consumer(
                builder: (context, ref, _) {
                  final subtitles = ref.watch(availableSubtitlesProvider);
                  final currentSubtitle = ref.watch(currentSubtitleProvider);
                  final playlist = ref.watch(playlistProvider);
                  final hasPlaylist = playlist.items.length > 1;

                  return VideoControls(
                    video: widget.video,
                    state: playerState,
                    hasSubtitles: subtitles.isNotEmpty || currentSubtitle != null,
                    hasPlaylist: hasPlaylist,
                    hasPrevious: playlist.hasPrevious,
                    hasNext: playlist.hasNext,
                    onPlayPause: () {
                      playerNotifier.playOrPause();
                      _startHideControlsTimer();
                    },
                    onSeek: (position) {
                      playerNotifier.seek(position);
                      _startHideControlsTimer();
                    },
                    onSeekForward: () {
                      playerNotifier.seekForward();
                      _startHideControlsTimer();
                    },
                    onSeekBackward: () {
                      playerNotifier.seekBackward();
                      _startHideControlsTimer();
                    },
                    onVolumeChange: (volume) {
                      playerNotifier.setVolume(volume);
                      _startHideControlsTimer();
                    },
                    onSpeedChange: (speed) {
                      playerNotifier.setSpeed(speed);
                      _startHideControlsTimer();
                    },
                    onToggleFullscreen: playerNotifier.toggleFullscreen,
                    onBack: () => Navigator.of(context).pop(),
                    onPlayPrevious: () {
                      playerNotifier.playPrevious();
                      _startHideControlsTimer();
                    },
                    onPlayNext: () {
                      playerNotifier.playNext();
                      _startHideControlsTimer();
                    },
                    onShowBookmarks: () {
                      showBookmarkSheet(
                        context,
                        videoPath: widget.video.path,
                        videoName: widget.video.name,
                        currentPosition: playerState.position,
                        onSeek: (position) {
                          playerNotifier.seek(position);
                          _startHideControlsTimer();
                        },
                      );
                    },
                  );
                },
              ),

            // 锁定按钮
            if (_showControls)
              Positioned(
                right: 16,
                top: context.padding.top + 60,
                child: IconButton(
                  onPressed: () {
                    setState(() => _isLocked = !_isLocked);
                    _startHideControlsTimer();
                  },
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isLocked ? Icons.lock : Icons.lock_open,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),

            // 锁定状态提示
            if (_isLocked && _showControls)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '屏幕已锁定，点击锁图标解锁',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
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
