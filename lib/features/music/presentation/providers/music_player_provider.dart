import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/audio_sources/stream_audio_source.dart';
import 'package:my_nas/features/music/data/services/music_metadata_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_settings_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
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
    logger.i('MusicPlayer: AudioPlayer 实例已创建');

    // 应用保存的设置
    _applySettings();

    // 监听播放状态
    _player.playingStream.listen((playing) {
      logger.d('MusicPlayer: playingStream => $playing');
      state = state.copyWith(isPlaying: playing);
    });

    // 监听缓冲状态
    _player.processingStateStream.listen((processingState) {
      logger.d('MusicPlayer: processingState => $processingState');
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
      logger.d('MusicPlayer: durationStream => $duration');
      if (duration != null) {
        state = state.copyWith(duration: duration);
      }
    });

    // 监听播放错误
    _player.playbackEventStream.listen(
      (event) {
        logger.d('MusicPlayer: playbackEvent => ${event.processingState}');
      },
      onError: (Object e, StackTrace stackTrace) {
        logger.e('MusicPlayer: playbackEventStream 错误', e, stackTrace);
        state = state.copyWith(errorMessage: e.toString());
      },
    );
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
    state = state.copyWith(errorMessage: null, isBuffering: true);

    logger.i('MusicPlayer: 开始播放 ${music.name}');
    logger.d('MusicPlayer: URL => ${music.url}');
    logger.d('MusicPlayer: size=${music.size}, path=${music.path}, sourceId=${music.sourceId}');

    try {
      // 先停止当前播放
      await _player.stop();
      logger.d('MusicPlayer: 已停止当前播放');

      // 验证 URL 格式
      final uri = Uri.tryParse(music.url);
      if (uri == null || !uri.hasScheme) {
        throw Exception('无效的音频 URL: ${music.url}');
      }
      logger.d('MusicPlayer: URI 解析成功 - scheme: ${uri.scheme}, host: ${uri.host}');

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

      logger.d('MusicPlayer: 正在设置音频源 (MIME: $mimeType)...');

      // 根据是否有 sourceId 选择合适的音频源
      // 有 sourceId 表示是 NAS 源（SMB/Synology/WebDAV 等），需要使用流式加载
      final AudioSource audioSource;

      if (music.sourceId != null) {
        // NAS 源：使用流式音频源
        logger.d('MusicPlayer: 检测到 NAS 源 (sourceId=${music.sourceId})，使用流式音频源');

        // 获取文件系统
        final connections = _ref.read(activeConnectionsProvider);
        final connection = connections[music.sourceId];

        if (connection == null) {
          throw Exception('源未连接，请先连接到 NAS: ${music.sourceId}');
        }

        logger.d('MusicPlayer: 使用 NasStreamAudioSource, path=${music.path}');
        audioSource = NasStreamAudioSource(
          fileSystem: connection.adapter.fileSystem,
          path: music.path,
          tag: music.id,
        );
      } else if (uri.scheme == 'http' || uri.scheme == 'https') {
        // HTTP/HTTPS URL
        logger.d('MusicPlayer: 使用 AudioSource.uri (HTTP)');
        audioSource = AudioSource.uri(
          uri,
          headers: {
            'Accept': mimeType,
          },
        );
      } else if (uri.scheme == 'file') {
        // 本地文件
        logger.d('MusicPlayer: 使用 AudioSource.uri (本地文件)');
        audioSource = AudioSource.uri(uri);
      } else {
        throw Exception('不支持的音频协议: ${uri.scheme}');
      }

      logger.d('MusicPlayer: 调用 setAudioSource...');
      await _player.setAudioSource(audioSource);
      logger.d('MusicPlayer: 音频源设置成功');

      // 检查音频时长是否获取成功
      final duration = _player.duration;
      logger.d('MusicPlayer: 音频时长 => $duration');

      if (startPosition != null && startPosition > Duration.zero) {
        logger.d('MusicPlayer: 跳转到位置 $startPosition');
        await _player.seek(startPosition);
      }

      // 确保音量正确
      final currentVolume = _player.volume;
      logger.d('MusicPlayer: 当前音量 => $currentVolume');
      if (currentVolume == 0) {
        await _player.setVolume(1.0);
        state = state.copyWith(volume: 1.0);
        logger.d('MusicPlayer: 音量已重置为 1.0');
      }

      logger.d('MusicPlayer: 调用 play()...');
      await _player.play();
      logger.i('MusicPlayer: play() 调用完成');

      // 验证播放状态
      logger.d('MusicPlayer: 播放状态 - playing: ${_player.playing}, processingState: ${_player.processingState}');

      // 添加到播放历史
      _ref.read(musicHistoryProvider.notifier).addToHistory(music);

      // 在后台提取元数据
      _extractMetadataInBackground(music);
    } catch (e, stackTrace) {
      logger.e('MusicPlayer: 播放失败', e, stackTrace);
      state = state.copyWith(errorMessage: '播放失败: $e', isBuffering: false);
    }
  }

  /// 在后台提取音乐元数据
  Future<void> _extractMetadataInBackground(MusicItem music) async {
    // 如果已经有元数据，跳过
    if (music.coverData != null || music.lyrics != null) {
      return;
    }

    try {
      final metadataService = MusicMetadataService.instance;
      await metadataService.init();

      MusicMetadata? metadata;

      if (music.sourceId != null) {
        // NAS 文件：从连接中获取文件系统
        final connections = _ref.read(activeConnectionsProvider);
        final connection = connections[music.sourceId];
        if (connection != null && connection.status == SourceStatus.connected) {
          metadata = await metadataService.extractFromNasFile(
            connection.adapter.fileSystem,
            music.path,
          );
        }
      }

      if (metadata != null) {
        // 更新当前播放的音乐信息
        final updatedMusic = metadataService.applyMetadataToItem(music, metadata);
        final currentMusic = _ref.read(currentMusicProvider);
        if (currentMusic?.id == music.id) {
          _ref.read(currentMusicProvider.notifier).state = updatedMusic;
          logger.i('MusicPlayer: 元数据已更新 - artist=${metadata.artist}, album=${metadata.album}');
        }
      }
    } catch (e) {
      logger.w('MusicPlayer: 提取元数据失败: $e');
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
