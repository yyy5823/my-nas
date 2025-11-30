import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/subtitle_service.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/presentation/providers/playlist_provider.dart';

/// 当前播放的视频
final currentVideoProvider = StateProvider<VideoItem?>((ref) => null);

/// 视频播放器控制器
final videoPlayerControllerProvider =
    StateNotifierProvider<VideoPlayerNotifier, VideoPlayerState>((ref) {
  return VideoPlayerNotifier(ref);
});

/// 可用字幕列表
final availableSubtitlesProvider = StateProvider<List<SubtitleItem>>((ref) => []);

/// 当前选中的字幕
final currentSubtitleProvider = StateProvider<SubtitleItem?>((ref) => null);

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
  final VideoHistoryService _historyService = VideoHistoryService.instance;

  Timer? _progressSaveTimer;
  VideoItem? _currentVideo;

  Player get player => _player;
  VideoController get videoController => _videoController;

  void _initPlayer() {
    _player = Player();
    _videoController = VideoController(_player);

    // 初始化历史服务
    _historyService.init();

    // 监听播放状态
    _player.stream.playing.listen((playing) {
      state = state.copyWith(isPlaying: playing);

      // 开始播放时启动进度保存定时器
      if (playing) {
        _startProgressSaveTimer();
      } else {
        _stopProgressSaveTimer();
        // 暂停时保存一次进度
        _saveCurrentProgress();
      }
    });

    // 监听缓冲状态
    _player.stream.buffering.listen((buffering) {
      state = state.copyWith(isBuffering: buffering);
    });

    // 监听播放位置
    _player.stream.position.listen((position) {
      state = state.copyWith(position: position);
    });

    // 监听总时长
    _player.stream.duration.listen((duration) {
      state = state.copyWith(duration: duration);
    });

    // 监听音量
    _player.stream.volume.listen((volume) {
      state = state.copyWith(volume: volume / 100);
    });

    // 监听倍速
    _player.stream.rate.listen((rate) {
      state = state.copyWith(speed: rate);
    });

    // 监听错误
    _player.stream.error.listen((error) {
      if (error.isNotEmpty) {
        state = state.copyWith(errorMessage: error);
      }
    });

    // 监听播放完成
    _player.stream.completed.listen((completed) {
      if (completed && _currentVideo != null) {
        // 播放完成，清除进度
        _historyService.clearProgress(_currentVideo!.path);
        logger.d('VideoPlayerNotifier: 播放完成，清除进度');

        // 尝试播放下一个
        _playNextFromPlaylist();
      }
    });
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
    if (_currentVideo == null) return;
    if (state.position.inSeconds < 5) return; // 忽略前5秒
    if (state.duration.inSeconds < 10) return; // 忽略太短的视频

    await _historyService.saveProgress(
      videoPath: _currentVideo!.path,
      position: state.position,
      duration: state.duration,
    );
  }

  /// 播放视频
  Future<void> play(VideoItem video, {Duration? startPosition}) async {
    // 保存当前视频进度
    await _saveCurrentProgress();

    _currentVideo = video;
    _ref.read(currentVideoProvider.notifier).state = video;
    state = state.copyWith(errorMessage: null);

    await _player.open(Media(video.url));

    // 确定起始位置
    Duration? resumePosition = startPosition;

    // 如果没有指定起始位置，尝试从历史中恢复
    if (resumePosition == null) {
      final savedProgress = await _historyService.getProgress(video.path);
      if (savedProgress != null && savedProgress.progressPercent < 0.95) {
        resumePosition = savedProgress.position;
        logger.i('VideoPlayerNotifier: 从上次位置恢复 ${resumePosition.inSeconds}s');
      }
    }

    if (resumePosition != null && resumePosition > Duration.zero) {
      await _player.seek(resumePosition);
    }

    // 添加到播放历史
    await _historyService.addToHistory(
      VideoHistoryItem(
        videoPath: video.path,
        videoName: video.name,
        videoUrl: video.url,
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
  }

  /// 继续播放
  Future<void> resume() async {
    await _player.play();
  }

  /// 停止
  Future<void> stop() async {
    await _saveCurrentProgress();
    _stopProgressSaveTimer();
    await _player.stop();
    _currentVideo = null;
    _ref.read(currentVideoProvider.notifier).state = null;
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// 快进
  Future<void> seekForward({Duration amount = const Duration(seconds: 10)}) async {
    final newPosition = state.position + amount;
    if (newPosition < state.duration) {
      await seek(newPosition);
    } else {
      await seek(state.duration);
    }
  }

  /// 快退
  Future<void> seekBackward({Duration amount = const Duration(seconds: 10)}) async {
    final newPosition = state.position - amount;
    if (newPosition > Duration.zero) {
      await seek(newPosition);
    } else {
      await seek(Duration.zero);
    }
  }

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume * 100);
  }

  /// 设置播放速度
  Future<void> setSpeed(double speed) async {
    await _player.setRate(speed);
  }

  /// 切换全屏
  void toggleFullscreen() {
    state = state.copyWith(isFullscreen: !state.isFullscreen);
  }

  /// 设置全屏状态
  void setFullscreen(bool fullscreen) {
    state = state.copyWith(isFullscreen: fullscreen);
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
      } catch (e) {
        logger.e('VideoPlayerNotifier: 加载字幕失败', e);
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
    _saveCurrentProgress();
    _stopProgressSaveTimer();
    _player.dispose();
    super.dispose();
  }
}

/// 可用的播放速度
const availableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
