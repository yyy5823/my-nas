import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';

/// 当前播放的视频
final currentVideoProvider = StateProvider<VideoItem?>((ref) => null);

/// 视频播放器控制器
final videoPlayerControllerProvider =
    StateNotifierProvider<VideoPlayerNotifier, VideoPlayerState>((ref) {
  return VideoPlayerNotifier(ref);
});

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
    this.errorMessage,
  });

  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final double volume;
  final double speed;
  final bool isFullscreen;
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

  Player get player => _player;
  VideoController get videoController => _videoController;

  void _initPlayer() {
    _player = Player();
    _videoController = VideoController(_player);

    // 监听播放状态
    _player.stream.playing.listen((playing) {
      state = state.copyWith(isPlaying: playing);
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
  }

  /// 播放视频
  Future<void> play(VideoItem video, {Duration? startPosition}) async {
    _ref.read(currentVideoProvider.notifier).state = video;
    state = state.copyWith(errorMessage: null);

    await _player.open(Media(video.url));

    if (startPosition != null && startPosition > Duration.zero) {
      await _player.seek(startPosition);
    }
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
    await _player.stop();
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

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

/// 可用的播放速度
const availableSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
