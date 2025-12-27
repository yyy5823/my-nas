import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:my_nas/app/theme/color_scheme_preset.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/services/media_proxy_server.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/live_activity_service.dart';
import 'package:my_nas/features/music/data/services/music_audio_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_metadata_service.dart';
import 'package:my_nas/features/music/data/services/ncm_decrypt_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_settings_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/main.dart' show audioHandler;
import 'package:my_nas/shared/providers/theme_provider.dart';
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
    AppError.fireAndForget(
      _initLiveActivity(),
      action: 'initLiveActivity',
    );
    _initMediaProxy();
    _listenToThemeChanges();
  }

  final Ref _ref;

  /// 使用全局 AudioHandler（通过 audio_service 初始化）
  /// 这提供了后台音频播放和系统媒体控制（锁屏、控制中心、蓝牙耳机）
  MusicAudioHandler get _audioHandler => audioHandler;

  /// 获取底层的 AudioPlayer
  AudioPlayer get _player => _audioHandler.player;

  // 媒体代理服务器（用于流式播放 NAS 文件）
  final MediaProxyServer _mediaProxyServer = MediaProxyServer();

  // 当前代理的文件 ID（用于清理）
  String? _currentProxyId;

  // Live Activity 服务
  final LiveActivityService _liveActivityService = LiveActivityService();
  Timer? _liveActivityUpdateTimer;

  // Live Activity 位置更新订阅（使用播放器的 positionStream，在后台也能工作）
  StreamSubscription<Duration>? _liveActivityPositionSubscription;

  // 上次 Live Activity 更新的秒数（避免每帧都更新）
  int _lastLiveActivityUpdateSecond = -1;

  // 是否正在启动 Live Activity（防止重复启动导致竞争条件）
  bool _isStartingLiveActivity = false;

  // 主题颜色监听订阅
  ProviderSubscription<ColorSchemePreset>? _themeSubscription;

  // 音频缓存服务（用于持久化缓存，避免重复下载）
  final MusicAudioCacheService _audioCacheService = MusicAudioCacheService();

  // NCM 解密服务
  final NcmDecryptService _ncmDecryptService = NcmDecryptService();

  AudioPlayer get player => _player;

  /// 初始化媒体代理服务器
  Future<void> _initMediaProxy() async {
    await _mediaProxyServer.start();
  }

  /// 监听主题变化，自动更新 Live Activity 波形颜色
  void _listenToThemeChanges() {
    _themeSubscription = _ref.listen<ColorSchemePreset>(
      colorSchemePresetProvider,
      (previous, next) {
        if (previous != next) {
          logger.d('MusicPlayer: 检测到主题变化，更新 Live Activity 颜色');
          _updateLiveActivityThemeColor();
          // 如果正在运行 Live Activity，立即触发更新
          if (_liveActivityService.isActivityRunning) {
            AppError.fireAndForget(
              _updateLiveActivity(),
              action: 'updateLiveActivityThemeChange',
            );
          }
        }
      },
    );
  }

  void _initPlayer() {
    logger.i('MusicPlayer: 使用全局 AudioHandler');

    // 设置 audioHandler 的切歌回调
    // 当用户通过锁屏、控制中心或蓝牙耳机点击上一首/下一首时调用
    _audioHandler.onSkipToIndex = (index) async {
      await playAt(index);
    };

    // 应用保存的设置
    _applySettings();

    // 初始化音频会话中断处理
    _initAudioSessionHandling();

    // 监听播放状态
    _player.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
      // 当开始播放时，确保 Live Activity 已启动（但避免与 play() 方法竞争）
      // 使用 _isStartingLiveActivity 标志位防止重复启动
      if (playing && !_liveActivityService.isActivityRunning && !_isStartingLiveActivity) {
        final currentMusic = _ref.read(currentMusicProvider);
        if (currentMusic != null) {
          AppError.fireAndForget(
            _startLiveActivity(currentMusic),
            action: 'startLiveActivityOnPlayingStart',
          );
        }
      }
      // 播放状态变化时始终更新 Live Activity（包括暂停时）
      // 这确保灵动岛能正确显示暂停/播放状态
      AppError.fireAndForget(
        _updateLiveActivity(),
        action: 'updateLiveActivityOnPlayingChange',
      );
    });

    // 监听缓冲状态
    _player.processingStateStream.listen((processingState) {
      final wasBuffering = state.isBuffering;
      state = state.copyWith(
        isBuffering: processingState == ProcessingState.buffering ||
            processingState == ProcessingState.loading,
      );

      // 缓冲状态变化时更新 Live Activity，保持灵动岛动效同步
      if (wasBuffering != state.isBuffering) {
        AppError.fireAndForget(
          _updateLiveActivity(),
          action: 'updateLiveActivityOnBufferingChange',
        );
      }

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

  /// 显式激活 Audio Session
  /// 这是确保 Live Activity 在后台正常工作的关键步骤
  /// iOS 的 Live Activity 需要 Audio Session 在 App 进入后台前被激活
  Future<void> _activateAudioSession() async {
    if (!Platform.isIOS) return;

    try {
      final session = await AudioSession.instance;
      // 显式激活 Audio Session
      // 这会通知系统应用即将播放音频，允许后台音频播放
      await session.setActive(true);
      logger.i('MusicPlayer: Audio Session 已激活');
    } on Exception catch (e) {
      // 激活失败不应阻止播放
      logger.w('MusicPlayer: Audio Session 激活失败: $e');
    }
  }

  /// 初始化 Live Activity 服务
  Future<void> _initLiveActivity() async {
    if (!_liveActivityService.isSupported) return;

    await _liveActivityService.init();

    // 设置初始主题颜色（用于灵动岛波形）
    _updateLiveActivityThemeColor();

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

  /// 更新 Live Activity 主题颜色
  /// 当主题切换时调用，会更新灵动岛波形颜色
  void _updateLiveActivityThemeColor() {
    if (!_liveActivityService.isSupported) return;

    try {
      final colorScheme = _ref.read(colorSchemePresetProvider);
      _liveActivityService.setThemeColor(colorScheme.primary);
      logger.d('MusicPlayer: Live Activity 主题颜色已更新');
    } on Exception catch (e) {
      // 非关键功能，忽略错误
      logger.w('MusicPlayer: 更新 Live Activity 主题颜色失败: $e');
    }
  }

  /// 供外部调用更新主题颜色（当主题切换时）
  void updateThemeColor() {
    _updateLiveActivityThemeColor();
    // 如果正在运行 Live Activity，立即触发更新
    if (_liveActivityService.isActivityRunning) {
      AppError.fireAndForget(
        _updateLiveActivity(),
        action: 'updateLiveActivityThemeChange',
      );
    }
  }

  /// 启动 Live Activity 并开始定时更新
  Future<void> _startLiveActivity(MusicItem music) async {
    if (!_liveActivityService.isSupported) return;

    // 防止重复启动
    if (_isStartingLiveActivity) {
      logger.d('LiveActivity: 正在启动中，跳过重复调用');
      return;
    }
    _isStartingLiveActivity = true;

    try {
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
    } finally {
      _isStartingLiveActivity = false;
    }
  }

  /// 启动 Live Activity 更新
  /// 使用播放器的 positionStream 来触发更新，这样在后台也能正常工作
  /// Timer 在 iOS 后台会被暂停，但 AudioPlayer 的流在后台音频播放时仍然活跃
  void _startLiveActivityUpdateTimer() {
    _stopLiveActivityUpdateTimer();

    // 重置上次更新时间
    _lastLiveActivityUpdateSecond = -1;

    // 订阅播放器的位置流，每秒更新一次 Live Activity
    _liveActivityPositionSubscription = _player.positionStream.listen((position) {
      final currentSecond = position.inSeconds;
      // 只在秒数变化时更新，避免过于频繁的更新
      if (currentSecond != _lastLiveActivityUpdateSecond) {
        _lastLiveActivityUpdateSecond = currentSecond;
        _updateLiveActivity();
      }
    });

    logger.d('LiveActivity: 使用 positionStream 启动更新（支持后台）');
  }

  /// 停止 Live Activity 更新
  void _stopLiveActivityUpdateTimer() {
    _liveActivityUpdateTimer?.cancel();
    _liveActivityUpdateTimer = null;
    _liveActivityPositionSubscription?.cancel();
    _liveActivityPositionSubscription = null;
    _lastLiveActivityUpdateSecond = -1;
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
        _audioHandler.play(); // 使用 audioHandler 确保正确广播状态
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
      // 重要：在播放开始前显式激活 Audio Session
      // 这是确保 Live Activity 在后台正常工作的关键
      // 如果 Audio Session 没有在 App 进入后台前激活，Live Activity 可能不会出现
      await _activateAudioSession();

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

      // 检查是否为 NCM 文件，需要先解密
      if (_isNcmFile(music.path) || _isNcmFile(music.name)) {
        logger.i('MusicPlayer: 检测到 NCM 文件，开始解密...');
        final decryptedFile = await _getDecryptedNcmFile(music);
        if (decryptedFile == null) {
          throw Exception('NCM 文件解密失败');
        }
        logger.i('MusicPlayer: 使用解密后的文件播放: ${decryptedFile.path}');
        audioSource = AudioSource.uri(Uri.file(decryptedFile.path));
      } else if (music.sourceId != null) {
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
          // ignore: experimental_member_use
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
        // ignore: experimental_member_use
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

      // 重要：在播放前设置 AudioHandler 的当前音乐信息
      // 这确保 iOS/Android 锁屏和控制中心能正确显示歌曲信息和控制按钮
      // 如果在 play() 之后设置，Now Playing 可能无法正确初始化
      Uint8List? coverData;
      if (music.coverData != null && music.coverData!.isNotEmpty) {
        coverData = Uint8List.fromList(music.coverData!);
      } else {
        // 尝试从封面缓存中获取
        final uniqueKey = '${music.sourceId ?? ''}_${music.path}';
        final coverCacheService = MusicCoverCacheService();
        coverData = await coverCacheService.getCover(uniqueKey);
      }
      await _audioHandler.setCurrentMusic(music, artworkData: coverData);

      // 更新时长信息到 AudioHandler
      if (effectiveDuration != null && effectiveDuration > Duration.zero) {
        _audioHandler.updateDuration(effectiveDuration);
      }

      // 设置队列信息（如果有）
      final queue = _ref.read(playQueueProvider);
      if (queue.isNotEmpty) {
        final currentIndex = queue.indexWhere((m) => m.id == music.id);
        if (currentIndex >= 0) {
          _audioHandler.setQueue(queue, startIndex: currentIndex);
        }
      }

      // 开始播放
      logger.d('MusicPlayer: 调用 play()...');
      await _audioHandler.play(); // 使用 audioHandler.play() 确保正确广播状态
      logger.i('MusicPlayer: play() 调用完成');

      // 添加到播放历史
      await _ref.read(musicHistoryProvider.notifier).addToHistory(music);

      // 在后台提取元数据
      AppError.fireAndForget(
        _extractMetadataInBackground(music),
        action: 'extractMusicMetadata',
      );

      // 启动 Live Activity（iOS 灵动岛）
      // 重要：必须 await 确保在 app 进入后台前完成创建
      // 否则首次播放时如果立即切到后台，Live Activity 可能创建失败
      await _startLiveActivity(music);
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

  /// 检查是否为 NCM 文件
  bool _isNcmFile(String path) => p.extension(path).toLowerCase() == '.ncm';

  /// 获取 NCM 解密后的缓存文件
  /// 如果已有缓存则直接返回，否则解密并缓存
  Future<File?> _getDecryptedNcmFile(MusicItem music) async {
    final sourceId = music.sourceId ?? 'local';
    final originalPath = music.path;

    // 计算缓存文件路径（去掉 .ncm 后缀，添加解密后的格式后缀）
    final cacheFile = await _audioCacheService.getCacheFile(sourceId, originalPath);

    // NCM 解密后的文件需要替换后缀
    // 先检查是否已有解密缓存（mp3 或 flac）
    final mp3Cache = File('${cacheFile.path.replaceAll('.ncm', '')}.mp3');
    final flacCache = File('${cacheFile.path.replaceAll('.ncm', '')}.flac');

    if (await mp3Cache.exists()) {
      logger.i('MusicPlayer: 使用已缓存的 NCM 解密文件 (MP3): ${mp3Cache.path}');
      return mp3Cache;
    }
    if (await flacCache.exists()) {
      logger.i('MusicPlayer: 使用已缓存的 NCM 解密文件 (FLAC): ${flacCache.path}');
      return flacCache;
    }

    // 需要解密
    Uint8List ncmData;

    if (music.sourceId != null) {
      // NAS 文件：下载
      logger.d('MusicPlayer: 从 NAS 下载 NCM 文件: ${music.path}');
      final connections = _ref.read(activeConnectionsProvider);
      final connection = connections[music.sourceId];

      if (connection == null) {
        logger.e('MusicPlayer: 源未连接: ${music.sourceId}');
        return null;
      }

      final stream = await connection.adapter.fileSystem.getFileStream(music.path);
      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }
      ncmData = Uint8List.fromList(chunks);
    } else {
      // 本地文件
      final uri = Uri.tryParse(music.url);
      if (uri == null || uri.scheme != 'file') {
        logger.e('MusicPlayer: 无效的本地 NCM 文件路径: ${music.url}');
        return null;
      }
      final file = File(uri.toFilePath());
      if (!await file.exists()) {
        logger.e('MusicPlayer: NCM 文件不存在: ${file.path}');
        return null;
      }
      ncmData = await file.readAsBytes();
    }

    logger.d('MusicPlayer: NCM 文件大小: ${ncmData.length} bytes，开始解密...');

    // 解密
    final result = _ncmDecryptService.decrypt(ncmData);
    if (result == null) {
      logger.e('MusicPlayer: NCM 解密失败');
      return null;
    }

    // 根据元数据中的格式确定输出格式
    final format = result.metadata?.format.toLowerCase() ?? 'mp3';
    final outputFile = format == 'flac' ? flacCache : mp3Cache;

    // 确保父目录存在
    final parentDir = outputFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // 保存解密后的音频
    await outputFile.writeAsBytes(result.audioData);
    logger.i('MusicPlayer: NCM 解密完成，保存到: ${outputFile.path} (${result.audioData.length} bytes)');

    return outputFile;
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
          // 使用完整的 updateActivity 方法确保灵动岛正确刷新
          if (metadata.coverData != null && metadata.coverData!.isNotEmpty) {
            final coverBytes = Uint8List.fromList(metadata.coverData!);
            final showPlayingAnimation = state.isPlaying || state.isBuffering;

            // 更新 AudioHandler 的封面（用于锁屏和控制中心）
            AppError.fireAndForget(
              _audioHandler.updateArtwork(coverBytes),
              action: 'updateAudioHandlerArtwork',
            );

            // 更新 Live Activity（用于灵动岛）
            AppError.fireAndForget(
              _liveActivityService.updateActivity(
                music: updatedMusic,
                isPlaying: showPlayingAnimation,
                position: state.position,
                duration: state.duration,
                coverData: coverBytes,
              ),
              action: 'updateLiveActivityWithCover',
            );
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

    // 同步设置 AudioHandler 的队列
    // 这样锁屏和控制中心的上一首/下一首才能正确工作
    _audioHandler.setQueue(tracks, startIndex: startIndex);

    if (tracks.isNotEmpty && startIndex < tracks.length) {
      await play(tracks[startIndex]);
    }
  }

  /// 播放/暂停切换
  Future<void> playOrPause() async {
    // 使用 audioHandler 而不是直接操作 player，确保正确广播状态到系统
    if (_player.playing) {
      await _audioHandler.pause();
    } else {
      await _audioHandler.play();
    }
  }

  /// 暂停
  Future<void> pause() async {
    await _audioHandler.pause();
  }

  /// 继续播放
  Future<void> resume() async {
    await _audioHandler.play();
    // 如果 Live Activity 还没有运行，启动它
    final currentMusic = _ref.read(currentMusicProvider);
    if (currentMusic != null && !_liveActivityService.isActivityRunning) {
      unawaited(_startLiveActivity(currentMusic));
    }
  }

  /// 停止
  Future<void> stop() async {
    await _audioHandler.stop();
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
      // 使用 audioHandler.seek 确保 Now Playing 位置正确更新
      await _audioHandler.seek(position);
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

  /// 设置播放模式（仅更新播放器状态，不回调设置 provider）
  /// 由 MusicSettingsNotifier.setPlayMode 调用，避免循环调用
  void setPlayMode(PlayMode mode) {
    state = state.copyWith(playMode: mode);
    // 注意：不要在这里调用 musicSettingsProvider.notifier.setPlayMode
    // 否则会形成循环调用导致无限闪烁
  }

  /// 更新当前索引（用于队列重排序后同步）
  void updateCurrentIndex(int index) {
    state = state.copyWith(currentIndex: index);
  }

  @override
  void dispose() {
    _cleanupCurrentProxy();
    _stopLiveActivityUpdateTimer();
    _themeSubscription?.close();
    _liveActivityService.dispose();
    // 注意：不 dispose _audioHandler，因为它是全局单例
    // 它会在应用退出时自动清理
    super.dispose();
  }
}
