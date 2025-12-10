import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:my_nas/core/services/media_proxy_server.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/live_activity_service.dart';
import 'package:my_nas/features/music/data/services/music_audio_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
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
    this.bufferedPosition = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1.0,
    this.playMode = PlayMode.loop,
    this.currentIndex = 0,
    this.errorMessage,
  });

  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  final double volume;
  final PlayMode playMode;
  final int currentIndex;
  final String? errorMessage;

  double get progress =>
      duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0;

  /// 缓冲进度 (0.0 - 1.0)
  double get bufferedProgress =>
      duration.inMilliseconds > 0 ? bufferedPosition.inMilliseconds / duration.inMilliseconds : 0;

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
    Duration? bufferedPosition,
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
        bufferedPosition: bufferedPosition ?? this.bufferedPosition,
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

  /// 添加到下一首播放（在指定索引后插入）
  void addNext(MusicItem track, int currentIndex) {
    if (state.isEmpty) {
      state = [track];
    } else {
      final insertIndex = (currentIndex + 1).clamp(0, state.length);
      final newList = [...state]..insert(insertIndex, track);
      state = newList;
    }
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
    // 注意：_initLiveActivity 是异步的，但我们不在构造函数中等待它
    // 它会在后台初始化，如果首次播放时未初始化完成，会在 _startLiveActivity 中重试
    unawaited(_initLiveActivity());
    _initMediaProxy();
  }

  final Ref _ref;
  late final AudioPlayer _player;

  // 媒体代理服务器（用于流式播放 NAS 文件）
  final MediaProxyServer _mediaProxyServer = MediaProxyServer();

  // 当前代理的文件 ID（用于清理）
  String? _currentProxyId;

  // Live Activity 服务
  final LiveActivityService _liveActivityService = LiveActivityService();
  Timer? _liveActivityUpdateTimer;

  // 音频缓存服务（用于持久化缓存，避免重复下载）
  final MusicAudioCacheService _audioCacheService = MusicAudioCacheService();

  AudioPlayer get player => _player;

  /// 初始化媒体代理服务器
  Future<void> _initMediaProxy() async {
    await _mediaProxyServer.start();
  }

  void _initPlayer() {
    _player = AudioPlayer();
    logger.i('MusicPlayer: AudioPlayer 实例已创建');

    // 应用保存的设置
    _applySettings();

    // 初始化音频会话中断处理
    _initAudioSessionHandling();

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

    // 监听播放位置（使用播放器原生的 positionStream，无需定时器）
    _player.positionStream.listen((position) {
      state = state.copyWith(position: position);
    });

    // 监听总时长
    _player.durationStream.listen((duration) {
      if (duration != null && duration > Duration.zero) {
        state = state.copyWith(duration: duration);
      }
    });

    // 监听缓冲位置（边下边播时显示已下载进度）
    _player.bufferedPositionStream.listen((bufferedPosition) {
      state = state.copyWith(bufferedPosition: bufferedPosition);
    });

    // 监听播放错误（仅处理错误，不记录正常事件）
    _player.playbackEventStream.listen(
      null, // 正常事件无需处理，processingStateStream 已处理
      onError: (Object e, StackTrace stackTrace) {
        logger.e('MusicPlayer: playbackEventStream 错误', e, stackTrace);
        state = state.copyWith(errorMessage: e.toString());
      },
    );

  }

  /// 初始化音频会话中断处理
  /// 处理来电、其他应用播放音频等中断事件
  Future<void> _initAudioSessionHandling() async {
    try {
      final session = await AudioSession.instance;

      // 监听音频中断事件（如来电、其他应用播放等）
      session.interruptionEventStream.listen((event) {
        logger.d('MusicPlayer: 音频中断事件 - begin=${event.begin}, type=${event.type}');
        if (event.begin) {
          // 中断开始
          switch (event.type) {
            case AudioInterruptionType.duck:
              // 降低音量（其他应用短暂播放）
              _player.setVolume(state.volume * 0.3);
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              // 暂停播放
              _player.pause();
          }
        } else {
          // 中断结束
          switch (event.type) {
            case AudioInterruptionType.duck:
              // 恢复音量
              _player.setVolume(state.volume);
            case AudioInterruptionType.pause:
              // 可选：恢复播放（某些应用可能不希望自动恢复）
              // _player.play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      // 监听音频设备变化（如耳机拔出）
      session.becomingNoisyEventStream.listen((_) {
        logger.d('MusicPlayer: 音频设备变化（耳机拔出），暂停播放');
        _player.pause();
      });

      logger.i('MusicPlayer: 音频会话中断处理已初始化');
    } on Exception catch (e) {
      logger.w('MusicPlayer: 初始化音频会话中断处理失败: $e');
    }
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

  /// 初始化 Live Activity 服务
  Future<void> _initLiveActivity() async {
    if (!_liveActivityService.isSupported) return;

    await _liveActivityService.init();

    // 设置控制命令回调（来自灵动岛按钮点击）
    _liveActivityService.onControlAction = (action) {
      logger.i('MusicPlayer: 收到 Live Activity 控制命令: $action');
      switch (action) {
        case 'play':
          resume();
        case 'pause':
          pause();
        case 'toggle':
          // 切换播放/暂停
          if (state.isPlaying) {
            pause();
          } else {
            resume();
          }
        case 'previous':
          playPrevious();
        case 'next':
          playNext();
        case 'favorite':
          // 收藏功能需要外部处理，这里只记录日志
          // 实际收藏功能通过 ref.read(musicFavoritesProvider.notifier) 处理
          logger.i('MusicPlayer: 收藏命令需要在外部处理');
        default:
          logger.w('MusicPlayer: 未知的控制命令: $action');
      }
    };

    logger.i('MusicPlayer: Live Activity 服务已初始化');
  }

  /// 启动 Live Activity 并开始定时更新
  Future<void> _startLiveActivity(MusicItem music) async {
    if (!_liveActivityService.isSupported) return;

    // 获取封面数据
    Uint8List? coverData;
    if (music.coverData != null && music.coverData!.isNotEmpty) {
      coverData = Uint8List.fromList(music.coverData!);
      logger.d('LiveActivity: 使用音乐自带封面 - size=${coverData.length} bytes');
    } else {
      // 尝试从封面缓存中获取
      // uniqueKey 格式: sourceId_path
      final uniqueKey = '${music.sourceId ?? ''}_${music.path}';
      final coverCacheService = MusicCoverCacheService();
      coverData = await coverCacheService.getCover(uniqueKey);
      if (coverData != null) {
        logger.d('LiveActivity: 从缓存获取到封面 - $uniqueKey, size=${coverData.length} bytes');
      } else {
        logger.w('LiveActivity: 无法获取封面 - $uniqueKey');
      }
    }

    // 当正在缓冲（切换歌曲）时，也显示播放动效
    final showPlayingAnimation = state.isPlaying || state.isBuffering;

    // 切歌时需要强制更新灵动岛的歌曲信息（标题、艺术家、封面等）
    // 不能仅依赖定时更新，因为定时更新可能不会立即触发
    await _liveActivityService.startMusicActivity(
      music: music,
      isPlaying: showPlayingAnimation,
      position: state.position,
      duration: state.duration,
      coverData: coverData,
    );

    logger.i('LiveActivity: 切歌更新完成 - title=${music.displayTitle}, artist=${music.displayArtist}');

    // 启动定时更新
    _startLiveActivityUpdateTimer();
  }

  /// 启动 Live Activity 定时更新
  void _startLiveActivityUpdateTimer() {
    _stopLiveActivityUpdateTimer();

    // 每秒更新一次 Live Activity
    _liveActivityUpdateTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateLiveActivity(),
    );
  }

  /// 停止 Live Activity 定时更新
  void _stopLiveActivityUpdateTimer() {
    _liveActivityUpdateTimer?.cancel();
    _liveActivityUpdateTimer = null;
  }

  /// 更新 Live Activity 状态
  Future<void> _updateLiveActivity() async {
    if (!_liveActivityService.isActivityRunning) return;

    final currentMusic = _ref.read(currentMusicProvider);
    if (currentMusic == null) return;

    // 当正在缓冲（切换歌曲）时，也显示播放动效，避免动效停止
    // isPlaying 为 true 或者 isBuffering 为 true（正在加载新歌曲）时都显示动效
    final showPlayingAnimation = state.isPlaying || state.isBuffering;

    await _liveActivityService.updateActivity(
      music: currentMusic,
      isPlaying: showPlayingAnimation,
      position: state.position,
      duration: state.duration,
    );
  }

  /// 结束 Live Activity
  Future<void> _endLiveActivity() async {
    _stopLiveActivityUpdateTimer();
    await _liveActivityService.endActivity();
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
      // 先停止当前播放并清理之前的代理
      await _player.stop();
      _cleanupCurrentProxy();
      state = state.copyWith(position: Duration.zero, duration: Duration.zero);
      logger.d('MusicPlayer: 已停止当前播放并重置状态');

      // 验证 URL 格式
      final uri = Uri.tryParse(music.url);
      if (uri == null || !uri.hasScheme) {
        throw Exception('无效的音频 URL: ${music.url}');
      }
      logger.d('MusicPlayer: URI 解析成功 - scheme: ${uri.scheme}, host: ${uri.host}');

      // 根据音频来源选择合适的播放方式
      AudioSource audioSource;

      if (music.sourceId != null) {
        // NAS 源：优先检查本地缓存，避免重复下载
        logger.d('MusicPlayer: 检测到 NAS 源 (sourceId=${music.sourceId})');

        // 检查是否已有完整缓存
        final cacheFile = await _audioCacheService.getCacheFile(music.sourceId, music.path);
        final isCached = await _audioCacheService.isCached(music.sourceId, music.path);

        if (isCached) {
          // 已有缓存，直接播放本地文件
          logger.i('MusicPlayer: 使用本地缓存播放 ${cacheFile.path}');
          audioSource = AudioSource.uri(Uri.file(cacheFile.path));
        } else {
          // 无缓存，使用流式播放并缓存
          final connections = _ref.read(activeConnectionsProvider);
          final connection = connections[music.sourceId];

          if (connection == null) {
            throw Exception('源未连接，请先连接到 NAS: ${music.sourceId}');
          }

          // 获取文件大小
          final fileInfo = await connection.adapter.fileSystem.getFileInfo(music.path);
          final fileSize = fileInfo.size;

          // 确保缓存配额足够
          await _audioCacheService.ensureCacheQuota(newFileSize: fileSize);

          // 注册文件到代理服务器
          final proxyUrl = await _mediaProxyServer.registerFile(
            sourceId: music.sourceId!,
            filePath: music.path,
            fileSize: fileSize,
          );

          // 保存代理 ID 以便清理
          _currentProxyId = proxyUrl.split('/').last;

          logger..i('MusicPlayer: 使用流式播放模式 (边下边播并缓存到 ${cacheFile.path})')
          ..d('MusicPlayer: 代理URL => $proxyUrl');

          // 使用 LockCachingAudioSource 实现边下边播并自动缓存到指定文件
          // 这样下次播放相同歌曲时可以直接使用缓存
          audioSource = LockCachingAudioSource(
            Uri.parse(proxyUrl),
            cacheFile: cacheFile,
          );
        }
      } else if (uri.scheme == 'file') {
        // 本地文件：直接使用 URI
        logger.d('MusicPlayer: 本地文件');
        audioSource = AudioSource.uri(uri);
      } else if (uri.scheme == 'http' || uri.scheme == 'https') {
        // HTTP/HTTPS URL：使用 LockCachingAudioSource 边下边播
        logger.d('MusicPlayer: 使用 HTTP/HTTPS URL (流式播放)');
        audioSource = LockCachingAudioSource(uri);
      } else {
        throw Exception('不支持的音频协议: ${uri.scheme}');
      }

      // 设置音频源
      logger.d('MusicPlayer: 设置音频源...');
      await _player.setAudioSource(audioSource);
      logger.d('MusicPlayer: 音频源设置成功');

      // 获取播放器时长
      final playerDuration = _player.duration;
      logger.i('MusicPlayer: 播放器时长 => $playerDuration');

      // 使用播放器时长或 MusicItem 的元数据时长
      var effectiveDuration = playerDuration;
      if ((effectiveDuration == null || effectiveDuration == Duration.zero) &&
          music.duration != null && music.duration! > Duration.zero) {
        effectiveDuration = music.duration;
        logger.i('MusicPlayer: 使用 MusicItem 的时长信息 => ${music.duration}');
      }

      if (effectiveDuration != null && effectiveDuration > Duration.zero) {
        state = state.copyWith(duration: effectiveDuration);
        logger.i('MusicPlayer: 最终时长 => $effectiveDuration');
      }

      // 跳转到指定位置
      if (startPosition != null && startPosition > Duration.zero) {
        logger.d('MusicPlayer: 跳转到位置 $startPosition');
        await _player.seek(startPosition);
      }

      // 确保音量正确
      final currentVolume = _player.volume;
      if (currentVolume == 0) {
        await _player.setVolume(1);
        state = state.copyWith(volume: 1);
        logger.d('MusicPlayer: 音量已重置为 1.0');
      }

      // 开始播放
      logger.d('MusicPlayer: 调用 play()...');
      await _player.play();
      logger.i('MusicPlayer: play() 调用完成');

      // 添加到播放历史
      await _ref.read(musicHistoryProvider.notifier).addToHistory(music);

      // 在后台提取元数据
      unawaited(_extractMetadataInBackground(music));

      // 启动 Live Activity（iOS 灵动岛）
      unawaited(_startLiveActivity(music));
    } on Exception catch (e, stackTrace) {
      logger.e('MusicPlayer: 播放失败', e, stackTrace);
      state = state.copyWith(errorMessage: '播放失败: $e', isBuffering: false);
    }
  }

  /// 清理当前代理的文件
  void _cleanupCurrentProxy() {
    if (_currentProxyId != null) {
      _mediaProxyServer.unregisterFile(_currentProxyId!);
      _currentProxyId = null;
    }
  }

  /// 基于文件大小估算音频时长
  /// 使用常见比特率估算，对于无法获取元数据的文件提供 fallback
  Duration? _estimateDurationFromFileSize(MusicItem music) {
    final fileSize = music.size;
    if (fileSize == null || fileSize <= 0) return null;

    // 根据文件扩展名选择估算比特率
    final ext = p.extension(music.name).toLowerCase();
    int estimatedBitrate; // kbps

    switch (ext) {
      case '.flac':
        // FLAC 通常是 800-1400 kbps，使用 1000 kbps 作为平均值
        estimatedBitrate = 1000;
      case '.wav':
        // WAV 通常是 1411 kbps (CD 质量)
        estimatedBitrate = 1411;
      case '.m4a':
      case '.aac':
        // AAC 通常是 128-256 kbps
        estimatedBitrate = 192;
      case '.ogg':
        // OGG 通常是 128-320 kbps
        estimatedBitrate = 192;
      case '.mp3':
      default:
        // MP3 通常是 128-320 kbps，使用 192 kbps 作为平均值
        estimatedBitrate = 192;
    }

    // 文件大小 (bytes) / (比特率 (kbps) * 1000 / 8) = 时长 (秒)
    // 简化：时长 (秒) = 文件大小 (bytes) * 8 / (比特率 (kbps) * 1000)
    final durationSeconds = (fileSize * 8) / (estimatedBitrate * 1000);

    // 验证结果是否合理（1秒到3小时之间）
    if (durationSeconds < 1 || durationSeconds > 10800) {
      logger.w('MusicPlayer: 估算时长不合理: ${durationSeconds}s, 跳过');
      return null;
    }

    return Duration(seconds: durationSeconds.round());
  }

  /// 在后台提取音乐元数据
  Future<void> _extractMetadataInBackground(MusicItem music) async {
    logger.d('MusicPlayer: 开始提取元数据 - name=${music.name}, sourceId=${music.sourceId}, url=${music.url}');

    // 检查是否需要提取元数据
    // 需要提取的情况：没有封面数据、没有歌词、或者没有时长
    final needsCover = music.coverData == null || music.coverData!.isEmpty;
    final needsLyrics = music.lyrics == null || music.lyrics!.isEmpty;
    final needsDuration = music.duration == null || music.duration == Duration.zero;

    // 如果所有元数据都已存在，跳过提取
    if (!needsCover && !needsLyrics && !needsDuration) {
      logger.d('MusicPlayer: 元数据完整，跳过提取 - hasCover=true, hasLyrics=true, hasDuration=true');
      return;
    }

    logger.d('MusicPlayer: 需要提取元数据 - needsCover=$needsCover, needsLyrics=$needsLyrics, needsDuration=$needsDuration');

    try {
      final metadataService = MusicMetadataService();
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
          logger.i('MusicPlayer: 元数据已更新 - artist=${metadata.artist}, album=${metadata.album}, hasCover=${metadata.coverData != null}, hasLyrics=${metadata.lyrics != null}, duration=${metadata.duration}');

          // 如果提取到了有效的 duration，且当前没有时长或者时长为零，更新播放器状态
          if (metadata.duration != null && metadata.duration! > Duration.zero) {
            final currentDuration = state.duration;
            // 更新条件：当前没有时长，或者元数据时长与当前时长差异较大（可能之前是估算值）
            final shouldUpdate = currentDuration == Duration.zero ||
                (currentDuration.inSeconds > 0 &&
                    (metadata.duration!.inSeconds - currentDuration.inSeconds).abs() >
                        currentDuration.inSeconds * 0.1); // 差异超过 10%

            if (shouldUpdate) {
              state = state.copyWith(duration: metadata.duration);
              logger.i('MusicPlayer: 从元数据更新播放器时长 => ${metadata.duration} (之前: $currentDuration)');
            }
          }

          // 更新 Live Activity 封面图片
          if (metadata.coverData != null && metadata.coverData!.isNotEmpty) {
            unawaited(_liveActivityService.updateCoverImage(
              updatedMusic,
              Uint8List.fromList(metadata.coverData!),
            ));
          }
        } else {
          logger.w('MusicPlayer: 当前播放的音乐已变更，跳过更新');
        }
      } else {
        logger.w('MusicPlayer: 未能提取到元数据');
        // 元数据提取失败时，如果没有时长，尝试基于文件大小估算
        if (state.duration == Duration.zero) {
          final estimatedDuration = _estimateDurationFromFileSize(music);
          if (estimatedDuration != null && estimatedDuration > Duration.zero) {
            final currentMusic = _ref.read(currentMusicProvider);
            if (currentMusic?.id == music.id) {
              state = state.copyWith(duration: estimatedDuration);
              logger.i('MusicPlayer: 元数据提取失败，使用文件大小估算时长 => $estimatedDuration');
              _ref.read(currentMusicProvider.notifier).state = music.copyWith(duration: estimatedDuration);
            }
          }
        }
      }
    } on Exception catch (e, stackTrace) {
      logger.e('MusicPlayer: 提取元数据失败: $e', e, stackTrace);
      // 元数据提取异常时，如果没有时长，尝试基于文件大小估算
      if (state.duration == Duration.zero) {
        final estimatedDuration = _estimateDurationFromFileSize(music);
        if (estimatedDuration != null && estimatedDuration > Duration.zero) {
          final currentMusic = _ref.read(currentMusicProvider);
          if (currentMusic?.id == music.id) {
            state = state.copyWith(duration: estimatedDuration);
            logger.i('MusicPlayer: 元数据提取异常，使用文件大小估算时长 => $estimatedDuration');
            _ref.read(currentMusicProvider.notifier).state = music.copyWith(duration: estimatedDuration);
          }
        }
      }
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
    // 如果 Live Activity 还没有运行，启动它
    final currentMusic = _ref.read(currentMusicProvider);
    if (currentMusic != null && !_liveActivityService.isActivityRunning) {
      unawaited(_startLiveActivity(currentMusic));
    }
  }

  /// 停止
  Future<void> stop() async {
    await _player.stop();
    _cleanupCurrentProxy();
    state = state.copyWith(position: Duration.zero, duration: Duration.zero);
    _ref.read(currentMusicProvider.notifier).state = null;
    // 结束 Live Activity
    unawaited(_endLiveActivity());
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
    logger.d('MusicPlayer: seek => $position');

    try {
      await _player.seek(position);
      // seek 完成后更新 state 以确保 UI 同步
      state = state.copyWith(position: position);
      logger.d('MusicPlayer: seek 完成');
    } on Exception catch (e) {
      logger.e('MusicPlayer: seek 失败: $e');
    }
  }

  /// 设置音量 (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
    state = state.copyWith(volume: volume);
    // 同步保存到设置
    await _ref.read(musicSettingsProvider.notifier).setVolume(volume);
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
    _cleanupCurrentProxy();
    _stopLiveActivityUpdateTimer();
    _liveActivityService.dispose();
    _player.dispose();
    super.dispose();
  }
}
