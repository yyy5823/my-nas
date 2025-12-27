import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:path_provider/path_provider.dart';

/// 音乐播放 AudioHandler
/// 集成 just_audio 与 audio_service，实现后台音频播放和系统控制
///
/// 功能：
/// - iOS 锁屏和控制中心的媒体控制（上一首、暂停、下一首）
/// - Android 通知栏媒体控制
/// - 蓝牙耳机/AirPods 按钮控制
/// - CarPlay 支持
/// - 后台音频稳定播放
class MusicAudioHandler extends BaseAudioHandler
    with SeekHandler, WidgetsBindingObserver {
  MusicAudioHandler() {
    _init();
  }

  final AudioPlayer _player = AudioPlayer();

  /// 当前封面数据
  Uint8List? _currentArtworkData;

  /// 当前音乐项（用于保存额外的元数据）
  MusicItem? _currentMusicItem;

  /// 播放队列
  final List<MusicItem> _musicQueue = [];

  /// 当前队列索引
  int _currentIndex = 0;

  /// 封面文件缓存目录
  Directory? _artworkCacheDir;

  /// 播放器实例
  AudioPlayer get player => _player;

  /// 当前封面数据
  Uint8List? get currentArtworkData => _currentArtworkData;

  /// 当前索引
  int get currentIndex => _currentIndex;

  /// 获取当前音乐项
  MusicItem? get currentMusicItem => _currentMusicItem;

  /// 外部切歌回调（用于处理复杂的音频源加载）
  Future<void> Function(int index)? onSkipToIndex;

  Future<void> _init() async {
    // 延迟注册生命周期监听器，确保 WidgetsBinding 已就绪
    // 使用 addPostFrameCallback 确保在第一帧渲染后注册
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addObserver(this);
      logger.i('MusicAudioHandler: 生命周期监听器已注册');
    });

    // 初始化封面缓存目录
    await _initArtworkCacheDir();

    // 监听播放状态变化，更新 playbackState
    _player.playbackEventStream.listen(_broadcastState);

    // 监听播放完成
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        skipToNext();
      }
    });

    // 监听时长变化
    _player.durationStream.listen((duration) {
      if (duration != null && mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    });

    // 监听位置变化（用于 Now Playing 的实时更新）
    _player.positionStream.listen((position) {
      // Now Playing 会自动根据 playbackState.updatePosition 和 speed 计算当前位置
      // 只有在 seek 时才需要手动更新，这里不需要做任何事
    });

    // 重要：广播初始 playbackState，确保系统知道可用的控制按钮
    // 如果不这样做，iOS/Android 在首次播放前不会显示控制按钮
    _broadcastState(PlaybackEvent());

    logger.i('MusicAudioHandler: 初始化完成');
  }

  /// 初始化封面缓存目录
  Future<void> _initArtworkCacheDir() async {
    try {
      final tempDir = await getTemporaryDirectory();
      _artworkCacheDir = Directory('${tempDir.path}/now_playing_artwork');
      if (!await _artworkCacheDir!.exists()) {
        await _artworkCacheDir!.create(recursive: true);
      }
      logger.d('MusicAudioHandler: 封面缓存目录已初始化: ${_artworkCacheDir!.path}');
    } on Exception catch (e) {
      logger.e('MusicAudioHandler: 初始化封面缓存目录失败: $e');
    }
  }

  /// 保存封面到文件并返回文件 URI
  /// 使用文件 URI 而不是 data URL，因为 iOS 对大型 data URL 支持不好
  Future<Uri?> _saveArtworkToFile(Uint8List artworkData, String musicId) async {
    if (_artworkCacheDir == null) {
      await _initArtworkCacheDir();
    }
    if (_artworkCacheDir == null) {
      logger.w('MusicAudioHandler: 封面缓存目录未初始化');
      return null;
    }

    try {
      // 清理 musicId 中的特殊字符，确保文件名合法
      final safeId = musicId.replaceAll(RegExp(r'[^\w\-]'), '_');

      // 检测图片格式（PNG 或 JPEG）
      final isPng = artworkData.length >= 8 &&
          artworkData[0] == 0x89 &&
          artworkData[1] == 0x50 &&
          artworkData[2] == 0x4E &&
          artworkData[3] == 0x47;
      final extension = isPng ? 'png' : 'jpg';

      final filePath = '${_artworkCacheDir!.path}/$safeId.$extension';
      final file = File(filePath);

      // 只有文件不存在或大小不同时才写入
      if (!await file.exists() || await file.length() != artworkData.length) {
        await file.writeAsBytes(artworkData);
        logger.i('MusicAudioHandler: 封面已保存 - path=$filePath, size=${artworkData.length}, format=$extension');
      }

      final uri = Uri.file(filePath);
      logger.d('MusicAudioHandler: 封面 URI = $uri');
      return uri;
    } on Exception catch (e, st) {
      logger.e('MusicAudioHandler: 保存封面文件失败: $e', e, st);
      return null;
    }
  }

  /// 处理 App 生命周期变化
  /// 当 App 从后台返回前台时，需要重新广播状态以刷新灵动岛/锁屏控制
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    logger.i('MusicAudioHandler: App 生命周期变化 - $state, playing=${_player.playing}, hasMediaItem=${mediaItem.value != null}');

    switch (state) {
      case AppLifecycleState.inactive:
        // App 即将进入后台（iOS 会先进入 inactive 再进入 paused）
        // 在这个时机广播状态，确保 iOS 能正确接收到 Now Playing 信息
        if (mediaItem.value != null) {
          logger.i('MusicAudioHandler: App 即将进入后台 (inactive)，刷新 Now Playing');
          _refreshNowPlaying();
        }

      case AppLifecycleState.paused:
        // App 已进入后台
        // 再次确保状态已广播（作为保险）
        if (_player.playing && mediaItem.value != null) {
          logger.i('MusicAudioHandler: App 已进入后台 (paused)，确认 Now Playing 状态');
          _broadcastState(PlaybackEvent());
        }

      case AppLifecycleState.resumed:
        // App 返回前台
        // 重新刷新 Now Playing 以确保下次进入后台时灵动岛能正确显示
        if (mediaItem.value != null) {
          logger.i('MusicAudioHandler: App 返回前台 (resumed)，刷新 Now Playing');
          _refreshNowPlaying();
        }

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // 不需要处理
        break;
    }
  }

  /// 刷新 Now Playing 信息
  /// 重新设置 mediaItem 和广播 playbackState，确保系统 Now Playing 是最新状态
  void _refreshNowPlaying() {
    // 重新设置 mediaItem 以刷新 Now Playing 信息
    if (mediaItem.value != null) {
      final currentItem = mediaItem.value!;
      // 创建一个新的 MediaItem 副本，强制系统更新
      final refreshedItem = MediaItem(
        id: currentItem.id,
        title: currentItem.title,
        artist: currentItem.artist,
        album: currentItem.album,
        duration: currentItem.duration,
        artUri: currentItem.artUri,
        extras: currentItem.extras,
      );
      mediaItem.add(refreshedItem);
    }

    // 广播最新的播放状态
    _broadcastState(PlaybackEvent());
    logger.d('MusicAudioHandler: Now Playing 已刷新');
  }

  /// 广播播放状态
  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final processingState = _mapProcessingState(_player.processingState);

    logger.d('MusicAudioHandler: 广播状态 - playing=$playing, processingState=$processingState, position=${_player.position}, hasMediaItem=${mediaItem.value != null}');

    playbackState.add(playbackState.value.copyWith(
      // 显示的控制按钮
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      // 允许的系统操作
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      // Android 紧凑视图显示的按钮索引
      androidCompactActionIndices: const [0, 1, 3],
      // 处理状态
      processingState: processingState,
      // 是否正在播放
      playing: playing,
      // 当前位置（用于 Now Playing 计算）
      updatePosition: _player.position,
      // 缓冲位置
      bufferedPosition: _player.bufferedPosition,
      // 播放速度
      speed: _player.speed,
      // 队列索引
      queueIndex: _currentIndex,
    ));
  }

  /// 映射 just_audio 的处理状态到 audio_service
  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  /// 准备切换到新歌曲
  /// 在设置新歌曲之前调用，确保旧的播放状态被正确清理
  Future<void> prepareForNewTrack() async {
    logger.d('MusicAudioHandler: 准备切换歌曲');

    // 如果正在播放，先暂停并广播状态
    if (_player.playing) {
      await _player.pause();
      _broadcastState(PlaybackEvent());
    }

    // 清理当前音乐信息
    _currentMusicItem = null;
    _currentArtworkData = null;

    // 注意：不清除 mediaItem，等 setCurrentMusic 设置新的
    // 这样可以保持 Now Playing 的连续性
  }

  /// 设置当前播放的音乐（由 MusicPlayerNotifier 调用）
  Future<void> setCurrentMusic(
    MusicItem music, {
    Uint8List? artworkData,
  }) async {
    // 检查是否与当前歌曲相同
    // 注意：即使歌曲相同，如果有新的封面数据也需要更新
    final isSameSong = _currentMusicItem?.id == music.id;
    final hasNewArtwork = artworkData != null && artworkData.isNotEmpty;

    if (isSameSong && !hasNewArtwork) {
      logger.d('MusicAudioHandler: 歌曲ID相同且无新封面，跳过: ${music.id}');
      return;
    }

    _currentMusicItem = music;
    _currentArtworkData = artworkData;

    // 将封面保存到文件并获取文件 URI
    // 使用文件 URI 而不是 data URL，因为 iOS 对大型 data URL 支持不好
    Uri? artUri;
    if (artworkData != null && artworkData.isNotEmpty) {
      artUri = await _saveArtworkToFile(artworkData, music.id);
      logger.d('MusicAudioHandler: 封面 URI = $artUri');
    }

    // 创建 MediaItem 用于 Now Playing 显示
    final item = MediaItem(
      id: music.id,
      title: music.displayTitle,
      artist: music.displayArtist,
      album: music.displayAlbum,
      duration: music.duration ?? Duration.zero,
      // 封面图片 - 使用文件 URI
      // audio_service 会自动将这个显示在锁屏和控制中心
      artUri: artUri,
      extras: {
        'sourceId': music.sourceId,
        'path': music.path,
      },
    );

    mediaItem.add(item);

    // 重要：设置 mediaItem 后立即广播 playbackState
    // 这确保 iOS Now Playing 能正确识别媒体信息和控制按钮
    _broadcastState(PlaybackEvent());

    logger.i(
        'MusicAudioHandler: 设置当前音乐 - ${music.displayTitle} by ${music.displayArtist}, hasArtwork=${artUri != null}');
  }

  /// 更新封面图片（用于元数据加载完成后）
  Future<void> updateArtwork(Uint8List artworkData) async {
    _currentArtworkData = artworkData;

    if (mediaItem.value != null) {
      // 保存封面到文件
      final artUri = await _saveArtworkToFile(artworkData, mediaItem.value!.id);

      final updated = mediaItem.value!.copyWith(
        artUri: artUri,
      );
      mediaItem.add(updated);

      // 重新广播状态以刷新 Now Playing
      _broadcastState(PlaybackEvent());

      logger.i('MusicAudioHandler: 封面图片已更新, artUri=$artUri');
    }
  }

  /// 更新时长
  void updateDuration(Duration duration) {
    if (mediaItem.value != null && duration > Duration.zero) {
      mediaItem.add(mediaItem.value!.copyWith(duration: duration));
    }
  }

  /// 设置播放队列
  void setQueue(List<MusicItem> items, {int startIndex = 0}) {
    _musicQueue
      ..clear()
      ..addAll(items);
    _currentIndex = startIndex;

    // 转换为 MediaItem 列表并更新 queue
    final mediaItems = items
        .map((m) => MediaItem(
              id: m.id,
              title: m.displayTitle,
              artist: m.displayArtist,
              album: m.displayAlbum,
              duration: m.duration,
            ))
        .toList();
    queue.add(mediaItems);

    logger.d('MusicAudioHandler: 设置队列 ${items.length} 首歌，起始索引 $startIndex');
  }

  /// 更新当前索引
  void updateCurrentIndex(int index) {
    _currentIndex = index;
    // 触发状态更新
    _broadcastState(PlaybackEvent());
  }

  @override
  Future<void> play() async {
    logger.i('MusicAudioHandler: play() 被调用');
    await _player.play();
    // 重要：显式广播状态确保 iOS Now Playing 立即更新
    _broadcastState(PlaybackEvent());
    logger.i('MusicAudioHandler: play() 完成，已广播状态');
  }

  @override
  Future<void> pause() async {
    logger.i('MusicAudioHandler: pause() 被调用');
    await _player.pause();
    // 显式广播状态确保 iOS Now Playing 立即更新
    _broadcastState(PlaybackEvent());
  }

  @override
  Future<void> stop() async {
    logger.i('MusicAudioHandler: stop() 被调用');
    await _player.stop();
    // 显式广播状态确保 iOS Now Playing 立即更新
    _broadcastState(PlaybackEvent());
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    // seek 后需要立即更新 playbackState 以保证 Now Playing 同步
    _broadcastState(PlaybackEvent());
  }

  @override
  Future<void> skipToNext() async {
    if (_musicQueue.isEmpty) return;

    final nextIndex = (_currentIndex + 1) % _musicQueue.length;
    await _skipToIndex(nextIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_musicQueue.isEmpty) return;

    // 如果播放超过3秒，回到开头
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    final prevIndex = (_currentIndex - 1 + _musicQueue.length) % _musicQueue.length;
    await _skipToIndex(prevIndex);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _skipToIndex(index);
  }

  Future<void> _skipToIndex(int index) async {
    if (index < 0 || index >= _musicQueue.length) return;

    _currentIndex = index;

    // 调用外部回调处理音频源加载（因为涉及复杂的 NAS 文件处理）
    if (onSkipToIndex != null) {
      await onSkipToIndex!(index);
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    // 由 MusicPlayerNotifier 处理
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    // 由 MusicPlayerNotifier 处理
  }

  /// 设置音量
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  /// 设置音频源
  Future<Duration?> setAudioSource(AudioSource source) => _player.setAudioSource(source);

  /// 释放资源
  Future<void> dispose() async {
    // 移除生命周期监听器
    WidgetsBinding.instance.removeObserver(this);
    await _player.dispose();
  }
}

/// 全局 AudioHandler 初始化
/// 在 main.dart 中调用
Future<MusicAudioHandler> initAudioHandler() => AudioService.init(
      builder: MusicAudioHandler.new,
      config: const AudioServiceConfig(
      // Android 通知渠道配置
      androidNotificationChannelId: 'com.kkape.mynas.channel.audio',
      androidNotificationChannelName: '音乐播放',
      androidNotificationChannelDescription: '音乐播放控制通知',
      // Android 通知配置
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      // 快进/快退间隔
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
      // 预加载（iOS 不需要，但对 Android 有帮助）
      preloadArtwork: true,
      // 通知点击后的行为
      androidNotificationClickStartsActivity: true,
    ),
  );
