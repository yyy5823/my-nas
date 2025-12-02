import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_settings_provider.dart';
import 'package:path/path.dart' as p;

/// 当前播放的音乐
final currentMusicProvider = StateProvider<MusicItem?>((ref) => null);

/// 播放队列
final playQueueProvider =
    StateNotifierProvider<PlayQueueNotifier, List<MusicItem>>((ref) =>
        PlayQueueNotifier());

/// 音乐播放器控制器
final musicPlayerControllerProvider =
    StateNotifierProvider<MusicPlayerNotifier, MusicPlayerState>((ref) =>
        MusicPlayerNotifier(ref));

/// 播放模式
enum PlayMode {
  /// 列表循环
  loop,

  /// 单曲循环
  repeatOne,

  /// 随机播放
  shuffle,
}

/// 播放器状态
class MusicPlayerState {
  const MusicPlayerState({
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.playMode = PlayMode.loop,
    this.currentIndex = 0,
    this.errorMessage,
  });

  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final double volume;
  final PlayMode playMode;
  final int currentIndex;
  final String? errorMessage;

  double get progress =>
      duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0;

  String get positionText => _formatDuration(position);
  String get durationText => _formatDuration(duration);

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  MusicPlayerState copyWith({
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    double? volume,
    PlayMode? playMode,
    int? currentIndex,
    String? errorMessage,
  }) =>
      MusicPlayerState(
        isPlaying: isPlaying ?? this.isPlaying,
        isBuffering: isBuffering ?? this.isBuffering,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        volume: volume ?? this.volume,
        playMode: playMode ?? this.playMode,
        currentIndex: currentIndex ?? this.currentIndex,
        errorMessage: errorMessage,
      );
}

/// 播放队列管理
class PlayQueueNotifier extends StateNotifier<List<MusicItem>> {
  PlayQueueNotifier() : super([]);

  void setQueue(List<MusicItem> tracks) {
    state = tracks;
  }

  void addToQueue(MusicItem track) {
    state = [...state, track];
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < state.length) {
      final newList = [...state];
      newList.removeAt(index);
      state = newList;
    }
  }

  void clear() {
    state = [];
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.length) return;
    if (newIndex < 0 || newIndex >= state.length) return;

    final newList = [...state];
    final item = newList.removeAt(oldIndex);
    newList.insert(newIndex, item);
    state = newList;
  }
}

/// 音乐播放器管理
class MusicPlayerNotifier extends StateNotifier<MusicPlayerState> {
  MusicPlayerNotifier(this._ref) : super(const MusicPlayerState()) {
    _initPlayer();
  }

  final Ref _ref;
  late final AudioPlayer _player;

  AudioPlayer get player => _player;

  void _initPlayer() {
    _player = AudioPlayer();

    // 应用保存的设置
    _applySettings();

    // 监听播放状态
    _player.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });

    // 监听缓冲状态
    _player.processingStateStream.listen((processingState) {
      state = state.copyWith(
        isBuffering: processingState == ProcessingState.buffering ||
            processingState == ProcessingState.loading,
      );

      // 播放完成时自动下一曲
      if (processingState == ProcessingState.completed) {
        _onTrackCompleted();
      }
    });

    // 监听播放位置
    _player.positionStream.listen((position) {
      state = state.copyWith(position: position);
    });

    // 监听总时长
    _player.durationStream.listen((duration) {
      if (duration != null) {
        state = state.copyWith(duration: duration);
      }
    });
  }

  /// 应用保存的设置
  Future<void> _applySettings() async {
    final settings = _ref.read(musicSettingsProvider);
    await _player.setVolume(settings.volume);
    state = state.copyWith(
      volume: settings.volume,
      playMode: settings.playMode,
    );
  }

  void _onTrackCompleted() {
    switch (state.playMode) {
      case PlayMode.repeatOne:
        seek(Duration.zero);
        _player.play();
      case PlayMode.loop:
        playNext();
      case PlayMode.shuffle:
        playNext();
    }
  }

  /// 播放指定音乐
  Future<void> play(MusicItem music, {Duration? startPosition}) async {
    _ref.read(currentMusicProvider.notifier).state = music;
    state = state.copyWith(errorMessage: null);

    logger.i('MusicPlayer: 开始播放 ${music.name}');
    logger.d('MusicPlayer: URL => ${music.url}');
    logger.d('MusicPlayer: size=${music.size}, path=${music.path}');

    try {
      logger.d('MusicPlayer: 正在设置音频源...');

      // 获取文件扩展名来确定 MIME 类型
      final ext = p.extension(music.name).toLowerCase();
      String mimeType = 'audio/mpeg'; // 默认
      if (ext == '.flac') {
        mimeType = 'audio/flac';
      } else if (ext == '.wav') {
        mimeType = 'audio/wav';
      } else if (ext == '.m4a' || ext == '.aac') {
        mimeType = 'audio/aac';
      } else if (ext == '.ogg') {
        mimeType = 'audio/ogg';
      }

      // 使用 AudioSource.uri 并设置 headers 来指定正确的 Content-Type
      final audioSource = AudioSource.uri(
        Uri.parse(music.url),
        headers: {
          'Accept': mimeType,
        },
      );

      await _player.setAudioSource(audioSource);
      logger.d('MusicPlayer: 音频源设置成功 (MIME: $mimeType)');

      if (startPosition != null && startPosition > Duration.zero) {
        await _player.seek(startPosition);
      }

      logger.d('MusicPlayer: 开始播放...');
      await _player.play();
      logger.i('MusicPlayer: 播放已开始');

      // 添加到播放历史
      _ref.read(musicHistoryProvider.notifier).addToHistory(music);
    } catch (e, stackTrace) {
      logger.e('MusicPlayer: 播放失败', e, stackTrace);
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  /// 播放队列中指定索引的音乐
  Future<void> playAt(int index) async {
    final queue = _ref.read(playQueueProvider);
    if (index >= 0 && index < queue.length) {
      state = state.copyWith(currentIndex: index);
      await play(queue[index]);
    }
  }

  /// 播放队列
  Future<void> playQueue(List<MusicItem> tracks, {int startIndex = 0}) async {
    _ref.read(playQueueProvider.notifier).setQueue(tracks);
    state = state.copyWith(currentIndex: startIndex);
    if (tracks.isNotEmpty && startIndex < tracks.length) {
      await play(tracks[startIndex]);
    }
  }

  /// 播放/暂停切换
  Future<void> playOrPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
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
    _ref.read(currentMusicProvider.notifier).state = null;
  }

  /// 下一曲
  Future<void> playNext() async {
    final queue = _ref.read(playQueueProvider);
    if (queue.isEmpty) return;

    int nextIndex;
    if (state.playMode == PlayMode.shuffle) {
      // 随机选择一个不同的索引
      if (queue.length == 1) {
        nextIndex = 0;
      } else {
        do {
          nextIndex = DateTime.now().millisecondsSinceEpoch % queue.length;
        } while (nextIndex == state.currentIndex);
      }
    } else {
      nextIndex = (state.currentIndex + 1) % queue.length;
    }

    await playAt(nextIndex);
  }

  /// 上一曲
  Future<void> playPrevious() async {
    final queue = _ref.read(playQueueProvider);
    if (queue.isEmpty) return;

    // 如果播放超过3秒，回到开头
    if (state.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    final prevIndex =
        (state.currentIndex - 1 + queue.length) % queue.length;
    await playAt(prevIndex);
  }

  /// 跳转到指定位置
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
    state = state.copyWith(volume: volume);
    // 同步保存到设置
    _ref.read(musicSettingsProvider.notifier).setVolume(volume);
  }

  /// 切换播放模式
  void togglePlayMode() {
    final modes = PlayMode.values;
    final nextIndex = (state.playMode.index + 1) % modes.length;
    final newMode = modes[nextIndex];
    state = state.copyWith(playMode: newMode);
    // 同步保存到设置
    _ref.read(musicSettingsProvider.notifier).setPlayMode(newMode);
  }

  /// 设置播放模式
  void setPlayMode(PlayMode mode) {
    state = state.copyWith(playMode: mode);
    // 同步保存到设置
    _ref.read(musicSettingsProvider.notifier).setPlayMode(mode);
  }

  /// 更新当前索引（用于队列重排序后同步）
  void updateCurrentIndex(int index) {
    state = state.copyWith(currentIndex: index);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
