import 'dart:async';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';

/// 音乐播放 AudioHandler
/// 集成 just_audio 与 audio_service，实现后台音频播放和系统控制
///
/// 功能：
/// - iOS 锁屏和控制中心的媒体控制（上一首、暂停、下一首）
/// - Android 通知栏媒体控制
/// - 蓝牙耳机/AirPods 按钮控制
/// - CarPlay 支持
/// - 后台音频稳定播放
class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
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

  /// 广播播放状态
  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
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
      processingState: _mapProcessingState(_player.processingState),
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

  /// 设置当前播放的音乐（由 MusicPlayerNotifier 调用）
  Future<void> setCurrentMusic(
    MusicItem music, {
    Uint8List? artworkData,
  }) async {
    _currentMusicItem = music;
    _currentArtworkData = artworkData;

    // 创建 MediaItem 用于 Now Playing 显示
    final item = MediaItem(
      id: music.id,
      title: music.displayTitle,
      artist: music.displayArtist,
      album: music.displayAlbum,
      duration: music.duration ?? Duration.zero,
      // 封面图片 - 使用 artUri 或 artHeaders
      // audio_service 会自动将这个显示在锁屏和控制中心
      artUri: artworkData != null
          ? Uri.dataFromBytes(artworkData, mimeType: 'image/png')
          : null,
      extras: {
        'sourceId': music.sourceId,
        'path': music.path,
      },
    );

    mediaItem.add(item);
    logger.d(
        'MusicAudioHandler: 设置当前音乐 - ${music.displayTitle} by ${music.displayArtist}');
  }

  /// 更新封面图片（用于元数据加载完成后）
  Future<void> updateArtwork(Uint8List artworkData) async {
    _currentArtworkData = artworkData;

    if (mediaItem.value != null) {
      final updated = mediaItem.value!.copyWith(
        artUri: Uri.dataFromBytes(artworkData, mimeType: 'image/png'),
      );
      mediaItem.add(updated);
      logger.d('MusicAudioHandler: 封面图片已更新');
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
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
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
  Future<void> dispose() => _player.dispose();
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
