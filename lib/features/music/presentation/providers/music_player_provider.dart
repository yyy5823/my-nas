import 'dart:async';
import 'dart:io';

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
    StateNotifierProvider<MusicPlayerNotifier, MusicPlayerState>(MusicPlayerNotifier.new);

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
      final newList = [...state]
      ..removeAt(index);
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
  Timer? _positionUpdateTimer;

  // 用于位置估算的变量（当 StreamAudioSource 无法获取真实位置时使用）
  DateTime? _playStartTime;
  Duration _playStartPosition = Duration.zero;
  bool _useEstimatedPosition = false;

  AudioPlayer get player => _player;

  void _initPlayer() {
    _player = AudioPlayer();
    logger.i('MusicPlayer: AudioPlayer 实例已创建');

    // 应用保存的设置
    _applySettings();

    // 监听播放状态
    _player.playingStream.listen((playing) {
      logger.i('MusicPlayer: playingStream => $playing');
      state = state.copyWith(isPlaying: playing);

      // 管理定时器和位置估算
      if (playing) {
        // 开始播放时记录时间点
        if (_useEstimatedPosition) {
          _playStartTime = DateTime.now();
          _playStartPosition = state.position;
          logger.d('MusicPlayer: 开始位置估算 - startPosition=$_playStartPosition');
        }
        _startPositionUpdateTimer();
      } else {
        // 暂停时更新起始位置
        if (_useEstimatedPosition && _playStartTime != null) {
          _playStartPosition = _getEstimatedPosition();
          _playStartTime = null;
          logger.d('MusicPlayer: 暂停位置估算 - savedPosition=$_playStartPosition');
        }
        _stopPositionUpdateTimer();
      }
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
      // 只在位置变化超过1秒时记录日志，避免日志过多
      if ((position.inSeconds - state.position.inSeconds).abs() >= 1) {
        logger.d('MusicPlayer: positionStream => $position (duration: ${state.duration})');
      }
      state = state.copyWith(position: position);
    });

    // 监听总时长
    _player.durationStream.listen((duration) {
      logger.i('MusicPlayer: durationStream => $duration');
      if (duration != null) {
        state = state.copyWith(duration: duration);
      } else {
        logger.w('MusicPlayer: durationStream 返回 null');
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

  /// 获取估算的播放位置
  Duration _getEstimatedPosition() {
    if (_playStartTime == null) {
      return _playStartPosition;
    }
    final elapsed = DateTime.now().difference(_playStartTime!);
    final estimated = _playStartPosition + elapsed;

    // 不超过总时长
    if (state.duration > Duration.zero && estimated > state.duration) {
      return state.duration;
    }
    return estimated;
  }

  /// 启动位置更新定时器
  void _startPositionUpdateTimer() {
    _stopPositionUpdateTimer();
    logger.i('MusicPlayer: 启动位置更新定时器 (useEstimated=$_useEstimatedPosition)');

    _positionUpdateTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final playerPosition = _player.position;
      final duration = _player.duration;
      final playerState = _player.processingState;

      // 决定使用哪个位置
      Duration effectivePosition;
      if (_useEstimatedPosition) {
        effectivePosition = _getEstimatedPosition();
      } else {
        effectivePosition = playerPosition;
      }

      // 每秒打印一次状态
      if (effectivePosition.inMilliseconds % 1000 < 200) {
        logger.d('MusicPlayer: 定时器 - position=$effectivePosition (player=$playerPosition), duration=${state.duration}, state=$playerState');
      }

      // 更新位置
      if (effectivePosition != state.position) {
        state = state.copyWith(position: effectivePosition);
      }

      // 如果播放器有了新的 duration，更新它
      if (duration != null && duration != state.duration && duration > Duration.zero) {
        logger.i('MusicPlayer: 定时器检测到 duration 更新 => $duration');
        state = state.copyWith(duration: duration);
        // 如果播放器能获取到有效 duration，可能也能获取 position
        // 但保持当前模式不变，以确保一致性
      }

      // 检测播放完成（基于估算位置）
      if (_useEstimatedPosition &&
          state.duration > Duration.zero &&
          effectivePosition >= state.duration) {
        logger.i('MusicPlayer: 估算位置达到结尾，触发播放完成');
        _onTrackCompleted();
      }
    });
  }

  /// 停止位置更新定时器
  void _stopPositionUpdateTimer() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = null;
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
    state = state.copyWith(isBuffering: true);

    logger..i('MusicPlayer: 开始播放 ${music.name}')
    ..d('MusicPlayer: URL => ${music.url}')
    ..d('MusicPlayer: size=${music.size}, path=${music.path}, sourceId=${music.sourceId}');

    try {
      // 先停止当前播放并重置位置估算
      await _player.stop();
      _stopPositionUpdateTimer();
      _useEstimatedPosition = false;
      _playStartTime = null;
      _playStartPosition = Duration.zero;
      state = state.copyWith(position: Duration.zero, duration: Duration.zero);
      logger.d('MusicPlayer: 已停止当前播放并重置状态');

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

      // 根据音频来源选择合适的音频源
      // 对于 NAS 源，优先使用 NasStreamAudioSource 以确保认证和编码正确处理
      // 对于本地文件或其他直接 URL，使用 AudioSource.uri
      final AudioSource audioSource;

      if (music.sourceId != null) {
        // NAS 源：使用流式音频源，通过 Dart HTTP 客户端处理认证
        // 这可以避免 iOS AVPlayer 对 NAS URL 的兼容性问题（如自签名证书、特殊字符编码等）
        logger.d('MusicPlayer: 检测到 NAS 源 (sourceId=${music.sourceId})');

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
        // NasStreamAudioSource 在 iOS 上无法获取真实播放位置，需要使用估算
        _useEstimatedPosition = true;
        logger.i('MusicPlayer: 启用位置估算模式 (NasStreamAudioSource)');
      } else if (uri.scheme == 'file') {
        // 本地文件
        logger.d('MusicPlayer: 使用 AudioSource.uri (本地文件)');
        audioSource = AudioSource.uri(uri);
      } else if (uri.scheme == 'http' || uri.scheme == 'https') {
        // 非 NAS 源的 HTTP/HTTPS URL - 直接播放
        logger.d('MusicPlayer: 使用 AudioSource.uri (HTTP/HTTPS)');
        audioSource = AudioSource.uri(
          uri,
          headers: {
            'Accept': mimeType,
          },
        );
      } else {
        throw Exception('不支持的音频协议: ${uri.scheme}');
      }

      logger.d('MusicPlayer: 调用 setAudioSource...');
      await _player.setAudioSource(audioSource);
      logger.d('MusicPlayer: 音频源设置成功');

      // 获取音频时长 - 使用多种来源
      Duration? effectiveDuration;

      // 1. 首先检查播放器是否获取到时长
      final playerDuration = _player.duration;
      logger.i('MusicPlayer: 播放器时长 => $playerDuration');

      if (playerDuration != null && playerDuration > Duration.zero) {
        effectiveDuration = playerDuration;
        logger.i('MusicPlayer: 使用播放器时长');
      }
      // 2. 如果播放器没有时长，使用 MusicItem 的元数据时长
      else if (music.duration != null && music.duration! > Duration.zero) {
        effectiveDuration = music.duration;
        logger.i('MusicPlayer: 使用 MusicItem 的时长信息 => ${music.duration}');
      }
      // 3. 如果仍然没有时长且是 NAS 源，尝试通过直接 URL 获取时长
      else if (music.sourceId != null) {
        logger.i('MusicPlayer: 尝试通过直接 URL 获取音频时长...');
        try {
          final connections = _ref.read(activeConnectionsProvider);
          final connection = connections[music.sourceId];
          if (connection != null) {
            // 获取直接访问 URL
            final directUrl = await connection.adapter.fileSystem.getFileUrl(music.path);
            logger.d('MusicPlayer: 直接 URL => ${directUrl.substring(0, directUrl.length.clamp(0, 100))}...');

            // 使用临时播放器获取时长
            final tempPlayer = AudioPlayer();
            try {
              await tempPlayer.setUrl(directUrl);
              final tempDuration = tempPlayer.duration;
              if (tempDuration != null && tempDuration > Duration.zero) {
                effectiveDuration = tempDuration;
                logger.i('MusicPlayer: 从直接 URL 获取到时长 => $tempDuration');
              }
            } on Exception catch (e) {
              logger.w('MusicPlayer: 通过直接 URL 获取时长失败: $e');
            } finally {
              await tempPlayer.dispose();
            }
          }
        } on Exception catch (e) {
          logger.w('MusicPlayer: 获取直接 URL 失败: $e');
        }
      }

      // 应用时长
      if (effectiveDuration != null) {
        state = state.copyWith(duration: effectiveDuration);
        logger.i('MusicPlayer: 最终时长 => $effectiveDuration');
      } else {
        logger.w('MusicPlayer: 无法获取音频时长');
      }

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
      logger..i('MusicPlayer: play() 调用完成')

      // 验证播放状态
      ..d('MusicPlayer: 播放状态 - playing: ${_player.playing}, processingState: ${_player.processingState}');

      // 添加到播放历史
      _ref.read(musicHistoryProvider.notifier).addToHistory(music);

      // 在后台提取元数据
      logger.i('MusicPlayer: 开始后台提取元数据...');
      unawaited(_extractMetadataInBackground(music));
    } on Exception catch (e, stackTrace) {
      logger.e('MusicPlayer: 播放失败', e, stackTrace);
      state = state.copyWith(errorMessage: '播放失败: $e', isBuffering: false);
    }
  }

  /// 在后台提取音乐元数据
  Future<void> _extractMetadataInBackground(MusicItem music) async {
    logger.d('MusicPlayer: 开始提取元数据 - name=${music.name}, sourceId=${music.sourceId}, url=${music.url}');

    // 如果已经有元数据，跳过
    if (music.coverData != null || music.lyrics != null) {
      logger.d('MusicPlayer: 已有元数据，跳过 - hasCover=${music.coverData != null}, hasLyrics=${music.lyrics != null}');
      return;
    }

    try {
      final metadataService = MusicMetadataService.instance;
      await metadataService.init();

      MusicMetadata? metadata;

      // 优先根据 URL scheme 判断文件类型
      final uri = Uri.tryParse(music.url);
      logger.d('MusicPlayer: 解析URL - uri=$uri, scheme=${uri?.scheme}');

      if (uri != null && uri.scheme == 'file') {
        // 本地文件：直接从文件路径提取（无论是否有 sourceId）
        logger.d('MusicPlayer: 检测到本地文件 (file:// scheme)');
        final filePath = uri.toFilePath();
        logger.d('MusicPlayer: 文件路径 = $filePath');
        final file = File(filePath);
        final exists = await file.exists();
        logger.d('MusicPlayer: 文件存在 = $exists');

        if (exists) {
          logger.d('MusicPlayer: 开始从本地文件提取元数据...');
          metadata = await metadataService.extractFromLocalFile(file);
          logger.d('MusicPlayer: 提取完成 - metadata=${metadata != null}');
          if (metadata != null) {
            logger.d('MusicPlayer: 元数据详情 - title=${metadata.title}, artist=${metadata.artist}, album=${metadata.album}, hasCover=${metadata.coverData != null}, hasLyrics=${metadata.lyrics != null}');
          }
        }
      } else if (music.sourceId != null) {
        // NAS 文件（非 file:// scheme 且有 sourceId）：从连接中获取文件系统
        logger.d('MusicPlayer: 检测到 NAS 文件，sourceId=${music.sourceId}');
        final connections = _ref.read(activeConnectionsProvider);
        final connection = connections[music.sourceId];
        if (connection != null && connection.status == SourceStatus.connected) {
          metadata = await metadataService.extractFromNasFile(
            connection.adapter.fileSystem,
            music.path,
          );
        } else {
          logger.w('MusicPlayer: NAS连接不可用 - connection=${connection != null}, status=${connection?.status}');
        }
      } else {
        logger.w('MusicPlayer: 无法确定文件类型 - url=${music.url}, sourceId=${music.sourceId}');
      }

      if (metadata != null) {
        // 更新当前播放的音乐信息
        final updatedMusic = metadataService.applyMetadataToItem(music, metadata);
        final currentMusic = _ref.read(currentMusicProvider);
        logger.d('MusicPlayer: 当前播放ID=${currentMusic?.id}, 提取的音乐ID=${music.id}');

        if (currentMusic?.id == music.id) {
          _ref.read(currentMusicProvider.notifier).state = updatedMusic;
          logger.i('MusicPlayer: 元数据已更新 - artist=${metadata.artist}, album=${metadata.album}, hasCover=${metadata.coverData != null}, hasLyrics=${metadata.lyrics != null}');
        } else {
          logger.w('MusicPlayer: 当前播放的音乐已变更，跳过更新');
        }
      } else {
        logger.w('MusicPlayer: 未能提取到元数据');
      }
    } on Exception catch (e, stackTrace) {
      logger.e('MusicPlayer: 提取元数据失败: $e', e, stackTrace);
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
    _stopPositionUpdateTimer();
    _useEstimatedPosition = false;
    _playStartTime = null;
    _playStartPosition = Duration.zero;
    state = state.copyWith(position: Duration.zero, duration: Duration.zero);
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
    logger.d('MusicPlayer: seek => $position (useEstimated=$_useEstimatedPosition)');

    // 对于估算模式，需要更新起始位置
    if (_useEstimatedPosition) {
      _playStartPosition = position;
      if (state.isPlaying) {
        _playStartTime = DateTime.now();
      } else {
        _playStartTime = null;
      }
      // 立即更新 UI
      state = state.copyWith(position: position);
    }

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
    _stopPositionUpdateTimer();
    _player.dispose();
    super.dispose();
  }
}
