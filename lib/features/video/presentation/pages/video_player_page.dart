import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/subtitle_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/presentation/providers/playlist_provider.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/aspect_ratio_selector.dart';
import 'package:my_nas/features/video/presentation/widgets/bookmark_sheet.dart';
import 'package:my_nas/features/video/presentation/widgets/video_controls.dart';
import 'package:my_nas/features/video/presentation/widgets/video_gesture_controller.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

class VideoPlayerPage extends ConsumerStatefulWidget {
  const VideoPlayerPage({required this.video, super.key});

  final VideoItem video;

  @override
  ConsumerState<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends ConsumerState<VideoPlayerPage> with WidgetsBindingObserver {
  bool _showControls = true;
  bool _isLocked = false;
  Timer? _hideControlsTimer;

  // 双击动画
  bool _showDoubleTapLeft = false;
  bool _showDoubleTapRight = false;

  // 缓存 notifier 引用，避免在 dispose 后使用 ref
  VideoPlayerNotifier? _playerNotifier;

  // 缓存源信息，用于 dispose 时更新缩略图
  String? _sourceId;
  NasFileSystem? _fileSystem;
  String? _videoUrl;

  // 缓存 provider 引用，避免异步操作后使用 ref
  Map<String, SourceConnection>? _connections;
  StateController<List<SubtitleItem>>? _subtitlesNotifier;

  // 记录上一次的横竖屏状态，避免重复设置
  Orientation? _lastOrientation;

  @override
  void initState() {
    super.initState();
    // 注册生命周期观察者
    WidgetsBinding.instance.addObserver(this);
    // 缓存 notifier 引用（在 widget 销毁前保存，避免异步操作后使用 ref）
    _playerNotifier = ref.read(videoPlayerControllerProvider.notifier);
    _connections = ref.read(activeConnectionsProvider);
    _subtitlesNotifier = ref.read(availableSubtitlesProvider.notifier);

    // 开始播放并缓存源信息
    Future.microtask(() async {
      if (!mounted) return;
      // 缓存源信息（用于 dispose 时更新缩略图）
      await _cacheSourceInfo();
      if (!mounted) return;
      // 开始播放
      await _playerNotifier?.play(
            widget.video,
            startPosition: widget.video.lastPosition,
          );
      if (!mounted) return;
      await _loadSubtitles();
    });
    _startHideControlsTimer();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 检测屏幕方向变化，自动切换全屏状态
    _checkOrientationAndSetFullscreen();
  }

  /// 根据屏幕方向自动设置全屏状态
  void _checkOrientationAndSetFullscreen() {
    if (!mounted) return;

    final size = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
    final orientation = size.width > size.height ? Orientation.landscape : Orientation.portrait;

    // 避免重复设置
    if (orientation == _lastOrientation) return;
    _lastOrientation = orientation;

    // 横屏时自动进入全屏，竖屏时自动退出全屏
    final isLandscape = orientation == Orientation.landscape;
    _playerNotifier?.setFullscreen(fullscreen: isLandscape);
    logger.d('VideoPlayerPage: 屏幕方向变化 => ${isLandscape ? "横屏(全屏)" : "竖屏(非全屏)"}');
  }

  /// 缓存源信息，用于 dispose 时更新缩略图
  Future<void> _cacheSourceInfo() async {
    try {
      // 使用缓存的 connections，避免使用 ref
      final connections = _connections;
      if (connections == null || connections.isEmpty) return;

      final connectedEntry = connections.entries.firstWhere(
        (e) => e.value.status == SourceStatus.connected,
        orElse: () => throw Exception('No connected source'),
      );
      _sourceId = connectedEntry.key;
      _fileSystem = connectedEntry.value.adapter.fileSystem;
      // 缓存视频 URL，用于后续缩略图生成
      _videoUrl = await _fileSystem?.getFileUrl(widget.video.path);
    } on Exception catch (e) {
      logger.w('VideoPlayerPage: 缓存源信息失败', e);
    }
  }

  /// 加载字幕
  Future<void> _loadSubtitles() async {
    // 使用缓存的 connections，避免使用 ref
    final connections = _connections;
    if (connections == null || connections.isEmpty) return;

    final connectedEntry = connections.entries.firstWhere(
      (e) => e.value.status == SourceStatus.connected,
      orElse: () => throw Exception('No connected source'),
    );
    final adapter = connectedEntry.value.adapter;

    try {
      final subtitles = await SubtitleService().findSubtitles(
        videoPath: widget.video.path,
        videoName: widget.video.name,
        fileSystem: adapter.fileSystem,
      );

      // 使用缓存的 notifier，避免使用 ref
      _subtitlesNotifier?.state = subtitles;

      // 如果找到字幕，自动加载第一个
      if (subtitles.isNotEmpty) {
        await _playerNotifier?.setSubtitle(subtitles.first);
        logger.i('VideoPlayerPage: 自动加载字幕 ${subtitles.first.name}');
      }
    } on Exception catch (e) {
      logger.e('VideoPlayerPage: 加载字幕失败', e);
    }
  }

  @override
  void dispose() {
    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    // 同步停止播放 - 使用缓存的 notifier 引用，避免在 dispose 后使用 ref
    _playerNotifier?.stopSync();
    // 后台更新缩略图（仅对没有刮削封面的视频有效）
    _triggerThumbnailUpdate();
    // 恢复系统 UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  /// 后台触发缩略图更新
  ///
  /// 在播放器停止后，异步更新缩略图为当前停止位置的帧
  /// 仅对没有刮削封面（posterUrl 和 thumbnailUrl 都为空）的视频有效
  void _triggerThumbnailUpdate() {
    if (_sourceId == null || _videoUrl == null) {
      logger.d('VideoPlayerPage: 缺少源信息，跳过缩略图更新');
      return;
    }

    // 使用 Future.microtask 在后台执行，不阻塞 dispose
    Future.microtask(() async {
      try {
        await VideoMetadataService().refreshThumbnailOnProgressUpdate(
          sourceId: _sourceId!,
          filePath: widget.video.path,
          videoUrl: _videoUrl!,
          fileSystem: _fileSystem,
        );
      } on Exception catch (e) {
        logger.w('VideoPlayerPage: 后台更新缩略图失败', e);
      }
    });
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

  /// 处理返回事件
  Future<void> _handleBack() async {
    // 在返回之前先暂停播放器
    logger.i('VideoPlayerPage: 准备返回，先暂停播放器');
    _playerNotifier?.pauseSync();

    // 等待一小段时间确保暂停生效
    await Future<void>.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (_isLocked) return;

    final screenWidth = context.screenWidth;

    if (details.localPosition.dx < screenWidth / 3) {
      // 左侧双击 - 快退
      _playerNotifier?.seekBackward();
      setState(() => _showDoubleTapLeft = true);
    } else if (details.localPosition.dx > screenWidth * 2 / 3) {
      // 右侧双击 - 快进
      _playerNotifier?.seekForward();
      setState(() => _showDoubleTapRight = true);
    } else {
      // 中间双击 - 播放/暂停
      _playerNotifier?.playOrPause();
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
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
                    onBack: _handleBack,
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
                right: 8,
                top: context.padding.top + 56,
                child: IconButton(
                  onPressed: () {
                    setState(() => _isLocked = !_isLocked);
                    _startHideControlsTimer();
                  },
                  icon: Icon(
                    _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  tooltip: _isLocked ? '解锁屏幕' : '锁定屏幕',
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
    ),
    );
  }
}
