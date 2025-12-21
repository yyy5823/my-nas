import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/services/media_proxy_server.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/audio_track_service.dart';
import 'package:my_nas/features/video/data/services/pip_service.dart';
import 'package:my_nas/features/video/data/services/subtitle_service.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/data/services/video_thumbnail_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/presentation/providers/playback_settings_provider.dart';
import 'package:my_nas/features/video/presentation/providers/playlist_provider.dart';

/// 当前播放的视频（autoDispose: 离开播放器页面后自动清理）
final currentVideoProvider = StateProvider.autoDispose<VideoItem?>((ref) => null);

/// 视频播放器控制器（autoDispose: 离开播放器页面后自动清理资源）
final videoPlayerControllerProvider =
    StateNotifierProvider.autoDispose<VideoPlayerNotifier, VideoPlayerState>(VideoPlayerNotifier.new);

/// 可用字幕列表（autoDispose）
final availableSubtitlesProvider = StateProvider.autoDispose<List<SubtitleItem>>((ref) => []);

/// 当前选中的字幕（autoDispose）
final currentSubtitleProvider = StateProvider.autoDispose<SubtitleItem?>((ref) => null);

/// 当前选中的内嵌字幕轨道 ID（autoDispose）
/// 用于跟踪内嵌字幕的选中状态
final currentEmbeddedSubtitleIdProvider = StateProvider.autoDispose<String?>((ref) => null);

/// 播放器状态
class VideoPlayerState {
  const VideoPlayerState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.speed = 1.0,
    this.isFullscreen = false,
    this.isPictureInPicture = false,
    this.subtitleEnabled = true,
    this.errorMessage,
  });

  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final double volume;
  final double speed;
  final bool isFullscreen;
  final bool isPictureInPicture;
  final bool subtitleEnabled;
  final String? errorMessage;

  double get progress =>
      duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0;

  String get positionText => _formatDuration(position);
  String get durationText => _formatDuration(duration);

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  VideoPlayerState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    double? volume,
    double? speed,
    bool? isFullscreen,
    bool? isPictureInPicture,
    bool? subtitleEnabled,
    String? errorMessage,
  }) =>
      VideoPlayerState(
        isPlaying: isPlaying ?? this.isPlaying,
        isBuffering: isBuffering ?? this.isBuffering,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        volume: volume ?? this.volume,
        speed: speed ?? this.speed,
        isFullscreen: isFullscreen ?? this.isFullscreen,
        isPictureInPicture: isPictureInPicture ?? this.isPictureInPicture,
        subtitleEnabled: subtitleEnabled ?? this.subtitleEnabled,
        errorMessage: errorMessage,
      );
}

/// 视频播放器管理
class VideoPlayerNotifier extends StateNotifier<VideoPlayerState> {
  VideoPlayerNotifier(this._ref) : super(const VideoPlayerState()) {
    _initPlayer();
  }

  final Ref _ref;
  late final Player _player;
  late final VideoController _videoController;
  final VideoHistoryService _historyService = VideoHistoryService();
  final VideoThumbnailService _thumbnailService = VideoThumbnailService();
  final AudioTrackService _audioTrackService = AudioTrackService();
  final PipService _pipService = PipService();

  /// 是否已经自动选择过音轨（每个视频只选择一次）
  bool _hasAutoSelectedAudioTrack = false;

  Timer? _progressSaveTimer;
  VideoItem? _currentVideo;

  /// 进度保存计数器（用于控制截图频率）
  int _progressSaveCount = 0;

  // Stream subscriptions 管理
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _isDisposed = false;

  Player get player => _player;
  VideoController get videoController => _videoController;

  /// 是否支持画中画
  Future<bool> get isPipSupported => _pipService.isSupported;

  void _initPlayer() {
    _player = Player();
    _videoController = VideoController(_player);

    // 初始化服务
    _historyService.init();
    _thumbnailService.init();

    // 应用保存的设置
    _applySettings();

    // 监听播放状态
    _subscriptions..add(_player.stream.playing.listen((playing) {
      if (_isDisposed) return;
      state = state.copyWith(isPlaying: playing);

      // 开始播放时启动进度保存定时器
      if (playing) {
        _startProgressSaveTimer();
      } else {
        _stopProgressSaveTimer();
        // 暂停时保存一次进度
        _saveCurrentProgress();
      }
    }))

    // 监听缓冲状态
    ..add(_player.stream.buffering.listen((buffering) {
      if (_isDisposed) return;
      state = state.copyWith(isBuffering: buffering);
    }))

    // 监听播放位置
    ..add(_player.stream.position.listen((position) {
      if (_isDisposed) return;
      state = state.copyWith(position: position);
    }))

    // 监听总时长
    ..add(_player.stream.duration.listen((duration) {
      if (_isDisposed) return;
      state = state.copyWith(duration: duration);
    }))

    // 监听音量
    ..add(_player.stream.volume.listen((volume) {
      if (_isDisposed) return;
      state = state.copyWith(volume: volume / 100);
    }))

    // 监听倍速
    ..add(_player.stream.rate.listen((rate) {
      if (_isDisposed) return;
      state = state.copyWith(speed: rate);
    }))

    // 监听错误
    ..add(_player.stream.error.listen((error) {
      if (_isDisposed) return;
      if (error.isNotEmpty) {
        state = state.copyWith(errorMessage: error);
      }
    }))

    // 监听播放完成
    ..add(_player.stream.completed.listen((completed) {
      if (_isDisposed) return;
      if (completed && _currentVideo != null) {
        // 播放完成，清除进度
        _historyService.clearProgress(_currentVideo!.path);
        logger.d('VideoPlayerNotifier: 播放完成，清除进度');

        // 尝试播放下一个
        _playNextFromPlaylist();
      }
    }))

    // 监听音轨列表变化，自动选择最佳音轨
    ..add(_player.stream.tracks.listen((tracks) {
      if (_isDisposed) return;
      if (!_hasAutoSelectedAudioTrack && tracks.audio.length > 1) {
        _autoSelectAudioTrack(tracks.audio);
      }
    }));
  }

  /// 自动选择最佳音轨
  Future<void> _autoSelectAudioTrack(List<AudioTrack> tracks) async {
    if (_hasAutoSelectedAudioTrack) return;
    _hasAutoSelectedAudioTrack = true;

    final bestTrack = _audioTrackService.selectBestAudioTrack(tracks);
    if (bestTrack != null) {
      // 检查是否需要切换（如果当前音轨已经是最佳音轨则不切换）
      final currentTrack = _player.state.track.audio;
      if (currentTrack.id != bestTrack.id) {
        await setAudioTrack(bestTrack);
        logger.i('VideoPlayerNotifier: 自动选择音轨 ${bestTrack.title ?? bestTrack.id}');
      }
    }
  }

  /// 应用保存的设置
  Future<void> _applySettings() async {
    final settings = _ref.read(playbackSettingsProvider);
    await _player.setVolume(settings.volume * 100);
    await _player.setRate(settings.speed);
    state = state.copyWith(volume: settings.volume, speed: settings.speed);
    logger.i('VideoPlayerNotifier: 应用设置 volume=${settings.volume}, speed=${settings.speed}');
  }

  /// 重新初始化 stream listeners（在 stopSync 后再次播放时调用）
  void _reinitStreamListeners() {
    // 确保先清理旧的订阅
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions..clear()

    // 重新添加所有 stream listeners
    ..add(_player.stream.playing.listen((playing) {
      if (_isDisposed) return;
      state = state.copyWith(isPlaying: playing);
      if (playing) {
        _startProgressSaveTimer();
      } else {
        _stopProgressSaveTimer();
        _saveCurrentProgress();
      }
    }))

    ..add(_player.stream.buffering.listen((buffering) {
      if (_isDisposed) return;
      state = state.copyWith(isBuffering: buffering);
    }))

    ..add(_player.stream.position.listen((position) {
      if (_isDisposed) return;
      state = state.copyWith(position: position);
    }))

    ..add(_player.stream.duration.listen((duration) {
      if (_isDisposed) return;
      state = state.copyWith(duration: duration);
    }))

    ..add(_player.stream.volume.listen((volume) {
      if (_isDisposed) return;
      state = state.copyWith(volume: volume / 100);
    }))

    ..add(_player.stream.rate.listen((rate) {
      if (_isDisposed) return;
      state = state.copyWith(speed: rate);
    }))

    ..add(_player.stream.error.listen((error) {
      if (_isDisposed) return;
      if (error.isNotEmpty) {
        state = state.copyWith(errorMessage: error);
      }
    }))

    ..add(_player.stream.completed.listen((completed) {
      if (_isDisposed) return;
      if (completed && _currentVideo != null) {
        _historyService.clearProgress(_currentVideo!.path);
        logger.d('VideoPlayerNotifier: 播放完成，清除进度');
        _playNextFromPlaylist();
      }
    }))

    ..add(_player.stream.tracks.listen((tracks) {
      if (_isDisposed) return;
      if (!_hasAutoSelectedAudioTrack && tracks.audio.length > 1) {
        _autoSelectAudioTrack(tracks.audio);
      }
    }));

    logger.d('VideoPlayerNotifier: 重新初始化 stream listeners');
  }

  /// 尝试从播放列表播放下一个
  Future<void> _playNextFromPlaylist() async {
    final playlist = _ref.read(playlistProvider);

    // 检查单曲循环
    if (playlist.repeatMode == RepeatMode.one && _currentVideo != null) {
      await play(_currentVideo!, startPosition: Duration.zero);
      return;
    }

    // 播放下一个
    final nextVideo = _ref.read(playlistProvider.notifier).playNext();
    if (nextVideo != null) {
      await play(nextVideo);
    }
  }

  void _startProgressSaveTimer() {
    _stopProgressSaveTimer();
    // 每10秒保存一次进度
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _saveCurrentProgress();
    });
  }

  void _stopProgressSaveTimer() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = null;
  }

  Future<void> _saveCurrentProgress() async {
    if (_currentVideo == null) {
      logger.d('VideoPlayerNotifier: 保存进度跳过 - 无当前视频');
      return;
    }
    if (state.position.inSeconds < 5) {
      logger.d('VideoPlayerNotifier: 保存进度跳过 - 位置小于5秒');
      return;
    }
    if (state.duration.inSeconds < 10) {
      logger.d('VideoPlayerNotifier: 保存进度跳过 - 时长小于10秒');
      return;
    }

    logger.d('VideoPlayerNotifier: 保存进度 ${_currentVideo!.path} => ${state.position.inSeconds}s / ${state.duration.inSeconds}s');
    await _historyService.saveProgress(
      videoPath: _currentVideo!.path,
      position: state.position,
      duration: state.duration,
    );

    // 每3次保存进度时（每30秒），同时保存进度截图
    _progressSaveCount++;
    if (_progressSaveCount >= 3) {
      _progressSaveCount = 0;
      // 异步保存截图，不阻塞进度保存
      AppError.fireAndForget(
        _captureProgressThumbnail(),
        action: 'periodicProgressThumbnail',
      );
    }
  }

  /// 播放视频
  Future<void> play(VideoItem video, {Duration? startPosition}) async {
    // 如果之前已停止，需要重新初始化 stream listeners
    if (_isDisposed) {
      _isDisposed = false;
      _reinitStreamListeners();
    }

    // 保存当前视频进度
    await _saveCurrentProgress();

    // 重置自动选择标志（新视频需要重新选择音轨）
    _hasAutoSelectedAudioTrack = false;

    _currentVideo = video;
    _ref.read(currentVideoProvider.notifier).state = video;
    state = state.copyWith();

    logger..i('VideoPlayer: 开始播放 ${video.name}')
    ..d('VideoPlayer: URL => ${video.url}')
    ..d('VideoPlayer: size=${video.size}, path=${video.path}');

    // 如果 URL 为空，需要先获取 URL（用于播放列表中的项）
    var resolvedVideo = video;
    if (video.needsUrlResolution) {
      if (video.sourceId == null) {
        logger.e('VideoPlayer: 视频缺少 sourceId，无法获取 URL');
        state = state.copyWith(errorMessage: '无法播放：缺少数据源信息');
        return;
      }
      
      try {
        final connections = _ref.read(activeConnectionsProvider);
        final connection = connections[video.sourceId];
        
        if (connection == null || connection.status != SourceStatus.connected) {
          logger.e('VideoPlayer: 数据源未连接');
          state = state.copyWith(errorMessage: '无法播放：数据源未连接');
          return;
        }
        
        final resolvedUrl = await connection.adapter.fileSystem.getFileUrl(video.path);
        resolvedVideo = video.copyWith(url: resolvedUrl);
        
        // 更新当前视频信息
        _currentVideo = resolvedVideo;
        _ref.read(currentVideoProvider.notifier).state = resolvedVideo;
        
        logger.i('VideoPlayer: URL 已解析 => $resolvedUrl');
      } on Exception catch (e, st) {
        AppError.handle(e, st, 'VideoPlayer.resolveUrl', {'path': video.path});
        state = state.copyWith(errorMessage: '无法获取视频地址');
        return;
      }
    }

    // 确定播放 URL（SMB 等协议需要通过代理）
    var playUrl = resolvedVideo.url;
    if (resolvedVideo.needsProxy) {
      if (resolvedVideo.sourceId == null) {
        logger.e('VideoPlayer: SMB 视频缺少 sourceId，无法使用代理');
        state = state.copyWith(errorMessage: '无法播放：缺少数据源信息');
        return;
      }
      try {
        playUrl = await MediaProxyServer().registerFile(
          sourceId: resolvedVideo.sourceId!,
          filePath: resolvedVideo.path,
          fileSize: resolvedVideo.size,
        );
        logger.i('VideoPlayer: 使用代理 URL => $playUrl');
      } on Exception catch (e, st) {
        AppError.handle(e, st, 'VideoPlayer.startProxyServer');
        state = state.copyWith(errorMessage: '无法启动媒体代理服务');
        return;
      }
    }

    // 确定起始位置
    var resumePosition = startPosition;

    // 如果没有指定起始位置，尝试从历史中恢复
    if (resumePosition == null) {
      final savedProgress = await _historyService.getProgress(video.path);
      if (savedProgress != null && savedProgress.progressPercent < 0.95) {
        resumePosition = savedProgress.position;
        logger.i('VideoPlayerNotifier: 从上次位置恢复 ${resumePosition.inSeconds}s');
      }
    }

    // 打开视频并设置起始位置
    logger.d('VideoPlayer: 正在打开视频源...');
    try {
      await _player.open(Media(playUrl));
      logger.d('VideoPlayer: 视频源打开成功');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'VideoPlayer.openVideo', {'path': video.path});
      state = state.copyWith(errorMessage: AppError.getUserFriendlyMessage(e));
      return;
    }

    // 等待播放器准备好后再 seek
    if (resumePosition != null && resumePosition > Duration.zero) {
      // 监听 duration 变化，等视频加载完成后再 seek
      StreamSubscription<Duration>? subscription;
      final completer = Completer<void>();

      subscription = _player.stream.duration.listen((duration) {
        if (duration > Duration.zero && !completer.isCompleted) {
          // 视频已准备好，执行 seek
          _player.seek(resumePosition!).then((_) {
            logger.i('VideoPlayerNotifier: 跳转到 ${resumePosition!.inSeconds}s');
          });
          subscription?.cancel();
          completer.complete();
        }
      });

      // 设置超时，避免无限等待
      Future.delayed(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.complete();
          // 超时后尝试直接 seek
          _player.seek(resumePosition!);
        }
      });

      await completer.future;
    }

    // 添加到播放历史
    await _historyService.addToHistory(
      VideoHistoryItem(
        videoPath: video.path,
        videoName: video.name,
        videoUrl: video.url,
        sourceId: video.sourceId,
        thumbnailUrl: video.thumbnailUrl,
        size: video.size,
        watchedAt: DateTime.now(),
      ),
    );
  }

  /// 播放/暂停切换
  Future<void> playOrPause() async {
    await _player.playOrPause();
  }

  /// 暂停
  Future<void> pause() async {
    await _player.pause();
    // 用户暂停时保存进度截图
    AppError.fireAndForget(
      _captureProgressThumbnail(),
      action: 'pauseProgressThumbnail',
    );
  }

  /// 同步暂停（用于 dispose）
  void pauseSync() {
    _player.pause();
  }

  /// 继续播放
  Future<void> resume() async {
    await _player.play();
  }

  /// 停止
  Future<void> stop() async {
    // 先截图（在停止播放器之前）
    await _captureProgressThumbnail();
    await _saveCurrentProgress();
    _stopProgressSaveTimer();
    await _player.stop();
    _currentVideo = null;
    _ref.read(currentVideoProvider.notifier).state = null;
  }

  /// 捕获当前帧作为进度截图
  Future<void> _captureProgressThumbnail() async {
    if (_currentVideo == null) return;
    // 只在播放进度 > 5% 且 < 95% 时保存进度截图
    if (state.progress <= 0.05 || state.progress >= 0.95) return;

    try {
      final screenshot = await _player.screenshot();
      if (screenshot != null && screenshot.isNotEmpty) {
        await _thumbnailService.saveProgressThumbnail(
          videoPath: _currentVideo!.path,
          imageBytes: screenshot,
        );
        logger.d('VideoPlayerNotifier: 进度截图已保存');
      }
    } on Exception catch (e, st) {
      // 截图失败不影响正常流程
      AppError.ignore(e, st, '进度截图捕获失败（非关键错误）');
    }
  }

  /// 同步停止（用于 dispose，不等待异步操作）
  void stopSync() {
    // 标记为已停止，防止 stream listeners 继续更新状态
    _isDisposed = true;

    // 取消所有 stream subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    _stopProgressSaveTimer();

    // 保存当前视频和状态的引用，用于异步保存进度
    final videoToSave = _currentVideo;
    final positionToSave = state.position;
    final durationToSave = state.duration;

    // 直接停止播放器
    _player..pause()
    ..stop();
    _currentVideo = null;

    // 延迟修改 provider 状态，避免在 dispose 期间修改
    Future.microtask(() {
      try {
        _ref.read(currentVideoProvider.notifier).state = null;
      } on Exception catch (e, st) {
        // Provider 可能已被销毁，这是预期行为
        AppError.ignore(e, st, 'Provider已销毁，无法修改状态');
      }
    });

    // 异步保存进度（使用保存的引用）
    if (videoToSave != null &&
        positionToSave.inSeconds >= 5 &&
        durationToSave.inSeconds >= 10) {
      logger.d('VideoPlayerNotifier: 异步保存进度 ${videoToSave.path} => ${positionToSave.inSeconds}s / ${durationToSave.inSeconds}s');
      Future.microtask(() async {
        try {
          await _historyService.saveProgress(
            videoPath: videoToSave.path,
            position: positionToSave,
            duration: durationToSave,
          );
          logger.i('VideoPlayerNotifier: 进度保存成功');
        } on Exception catch (e, st) {
          AppError.handle(e, st, 'VideoPlayer.saveProgress');
        }
      });
    }

    logger.i('VideoPlayerNotifier: 同步停止播放');
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// 快进
  Future<void> seekForward({Duration? amount}) async {
    final settings = _ref.read(playbackSettingsProvider);
    final seekAmount = amount ?? Duration(seconds: settings.seekInterval);
    final newPosition = state.position + seekAmount;
    if (newPosition < state.duration) {
      await seek(newPosition);
    } else {
      await seek(state.duration);
    }
  }

  /// 快退
  Future<void> seekBackward({Duration? amount}) async {
    final settings = _ref.read(playbackSettingsProvider);
    final seekAmount = amount ?? Duration(seconds: settings.seekInterval);
    final newPosition = state.position - seekAmount;
    if (newPosition > Duration.zero) {
      await seek(newPosition);
    } else {
      await seek(Duration.zero);
    }
  }

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume * 100);
    // 保存音量设置
    await _ref.read(playbackSettingsProvider.notifier).setVolume(volume);
  }

  /// 设置播放速度
  Future<void> setSpeed(double speed) async {
    await _player.setRate(speed);
    // 保存速度设置
    await _ref.read(playbackSettingsProvider.notifier).setSpeed(speed);
  }

  /// 切换全屏
  void toggleFullscreen() {
    state = state.copyWith(isFullscreen: !state.isFullscreen);
  }

  /// 设置全屏状态
  void setFullscreen({required bool fullscreen}) {
    state = state.copyWith(isFullscreen: fullscreen);
  }

  /// 切换画中画模式
  Future<bool> togglePictureInPicture() async {
    final success = await _pipService.togglePipMode(
      aspectRatio: _calculateAspectRatio(),
    );
    if (success) {
      state = state.copyWith(isPictureInPicture: _pipService.isPipMode);
      // 进入画中画时退出全屏
      if (_pipService.isPipMode && state.isFullscreen) {
        state = state.copyWith(isFullscreen: false);
      }
    }
    return success;
  }

  /// 进入画中画模式
  Future<bool> enterPictureInPicture() async {
    final success = await _pipService.enterPipMode(
      aspectRatio: _calculateAspectRatio(),
    );
    if (success) {
      state = state.copyWith(isPictureInPicture: true, isFullscreen: false);
    }
    return success;
  }

  /// 退出画中画模式
  Future<bool> exitPictureInPicture() async {
    final success = await _pipService.exitPipMode();
    if (success) {
      state = state.copyWith(isPictureInPicture: false);
    }
    return success;
  }

  /// 计算视频宽高比
  double _calculateAspectRatio() {
    final width = _player.state.width;
    final height = _player.state.height;
    if (width != null && height != null && height > 0) {
      return width / height;
    }
    return 16 / 9; // 默认 16:9
  }

  /// 初始化画中画状态监听
  ///
  /// 由于 floating 包不提供状态流，我们通过轮询来检查状态变化
  void initPipStatusListener() {
    // floating 包没有提供实时的状态流
    // 画中画状态在 togglePictureInPicture 等方法中手动更新
    logger.d('VideoPlayerNotifier: 画中画状态监听已初始化');
  }

  /// 设置字幕
  Future<void> setSubtitle(SubtitleItem? subtitle) async {
    _ref.read(currentSubtitleProvider.notifier).state = subtitle;

    if (subtitle == null) {
      // 关闭字幕
      await _player.setSubtitleTrack(SubtitleTrack.no());
      logger.i('VideoPlayerNotifier: 关闭字幕');
    } else {
      // 加载外部字幕
      try {
        await _player.setSubtitleTrack(
          SubtitleTrack.uri(subtitle.url, title: subtitle.name),
        );
        logger.i('VideoPlayerNotifier: 加载字幕 ${subtitle.name}');
      } on Exception catch (e, st) {
        AppError.handle(e, st, 'VideoPlayer.loadSubtitle', {'name': subtitle.name});
      }
    }
  }

  /// 切换字幕显示
  void toggleSubtitle() {
    state = state.copyWith(subtitleEnabled: !state.subtitleEnabled);
    if (!state.subtitleEnabled) {
      _player.setSubtitleTrack(SubtitleTrack.no());
    } else {
      final current = _ref.read(currentSubtitleProvider);
      if (current != null) {
        _player.setSubtitleTrack(
          SubtitleTrack.uri(current.url, title: current.name),
        );
      }
    }
  }

  /// 获取内嵌字幕轨道
  List<SubtitleTrack> get embeddedSubtitles => _player.state.tracks.subtitle;

  /// 设置内嵌字幕轨道
  Future<void> setEmbeddedSubtitleTrack(SubtitleTrack track) async {
    await _player.setSubtitleTrack(track);
    logger.i('VideoPlayerNotifier: 设置内嵌字幕 ${track.title ?? track.id}');
  }

  /// 设置字幕延时（秒）
  /// [delay] 正值使字幕延后显示，负值使字幕提前显示
  ///
  /// 注意：media_kit 当前版本不支持直接设置 MPV 的 sub-delay 属性。
  /// 此方法仅记录延时设置，UI 层会保存用户的偏好设置。
  /// 如果 media_kit 未来版本支持此功能，可以在此处启用。
  // ignore: avoid_unused_constructor_parameters
  void setSubtitleDelay(double delay) {
    // media_kit 不暴露 setProperty 方法，无法直接设置 MPV 的 sub-delay
    // 用户设置的延时值已保存在 subtitleStyleProvider 中
    // TODO(developer): 当 media_kit 支持 sub-delay 时启用此功能
    if (delay != 0) {
      logger.d('VideoPlayerNotifier: 字幕延时设置为 ${delay}s（需 media_kit 支持）');
    }
  }

  /// 获取可用音轨列表
  List<AudioTrack> get audioTracks => _player.state.tracks.audio;

  /// 获取当前音轨
  AudioTrack? get currentAudioTrack => _player.state.track.audio;

  /// 设置音轨
  Future<void> setAudioTrack(AudioTrack track) async {
    await _player.setAudioTrack(track);
    logger.i('VideoPlayerNotifier: 设置音轨 ${track.title ?? track.id}');
  }

  /// 播放列表中的下一个
  Future<void> playNext() async {
    final nextVideo = _ref.read(playlistProvider.notifier).playNext();
    if (nextVideo != null) {
      await play(nextVideo);
    }
  }

  /// 播放列表中的上一个
  Future<void> playPrevious() async {
    final prevVideo = _ref.read(playlistProvider.notifier).playPrevious();
    if (prevVideo != null) {
      await play(prevVideo);
    }
  }

  /// 是否有下一个
  bool get hasNext => _ref.read(playlistProvider).hasNext;

  /// 是否有上一个
  bool get hasPrevious => _ref.read(playlistProvider).hasPrevious;

  @override
  void dispose() {
    _isDisposed = true;
    // 取消所有 stream subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    // 退出画中画模式
    if (_pipService.isPipMode) {
      _pipService.exitPipMode();
    }

    _saveCurrentProgress();
    _stopProgressSaveTimer();
    _player.dispose();
    super.dispose();
  }
}

/// 可用的播放速度
const availableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
