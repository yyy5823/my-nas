import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
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

  /// iOS Now Playing 的最大封面尺寸
  /// 太大的图片会导致 iOS 无法正确显示或占用过多内存
  static const int _maxArtworkSize = 600;

  /// 保存封面到文件并返回文件 URI
  /// 使用文件 URI 而不是 data URL，因为 iOS 对大型 data URL 支持不好
  /// 同时会自动调整图片大小以适配 iOS Now Playing
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
      // 使用固定扩展名 jpg，因为调整大小后统一输出 JPEG
      final filePath = '${_artworkCacheDir!.path}/$safeId.jpg';
      final file = File(filePath);

      // 检查是否需要重新处理（文件不存在或源数据大小变化）
      // 使用 artworkData 长度的 hash 作为校验
      final hashPath = '${_artworkCacheDir!.path}/$safeId.hash';
      final hashFile = File(hashPath);
      final currentHash = artworkData.length.toString();
      String? existingHash;
      if (await hashFile.exists()) {
        existingHash = await hashFile.readAsString();
      }

      if (await file.exists() && existingHash == currentHash) {
        logger.d('MusicAudioHandler: 封面文件已存在且未变化，跳过处理');
        return Uri.file(filePath);
      }

      // 解码图片
      logger.d('MusicAudioHandler: 开始处理封面图片 - 原始大小=${artworkData.length} bytes');
      final originalImage = img.decodeImage(artworkData);
      if (originalImage == null) {
        logger.e('MusicAudioHandler: 无法解码封面图片');
        return null;
      }

      logger.d('MusicAudioHandler: 原始尺寸=${originalImage.width}x${originalImage.height}');

      // 如果图片太大，调整大小
      img.Image processedImage;
      if (originalImage.width > _maxArtworkSize || originalImage.height > _maxArtworkSize) {
        // 保持宽高比，将较长边缩放到 _maxArtworkSize
        if (originalImage.width > originalImage.height) {
          processedImage = img.copyResize(originalImage, width: _maxArtworkSize);
        } else {
          processedImage = img.copyResize(originalImage, height: _maxArtworkSize);
        }
        logger.i('MusicAudioHandler: 封面已调整大小 ${originalImage.width}x${originalImage.height} -> ${processedImage.width}x${processedImage.height}');
      } else {
        processedImage = originalImage;
      }

      // 编码为 JPEG（更小的文件大小，更好的兼容性）
      final jpegData = img.encodeJpg(processedImage, quality: 85);
      await file.writeAsBytes(jpegData);

      // 保存 hash 以便下次比较
      await hashFile.writeAsString(currentHash);

      logger.i('MusicAudioHandler: 封面已保存 - path=$filePath, size=${jpegData.length} bytes, dimensions=${processedImage.width}x${processedImage.height}');

      // 验证文件是否存在
      if (!await file.exists()) {
        logger.e('MusicAudioHandler: 封面文件保存后不存在！');
        return null;
      }

      final uri = Uri.file(filePath);
      logger.i('MusicAudioHandler: 封面 URI = $uri');
      return uri;
    } on Exception catch (e, st) {
      logger.e('MusicAudioHandler: 保存封面文件失败: $e', e, st);
      return null;
    }
  }

  /// 上次状态广播时间（用于防抖）
  DateTime? _lastBroadcastTime;

  /// 标记是否刚从后台返回（用于处理 后台->前台->后台 的场景）
  bool _justResumedFromBackground = false;

  /// 处理 App 生命周期变化
  /// 当 App 从后台返回前台时，需要重新广播状态以刷新灵动岛/锁屏控制
  ///
  /// 关键问题：后台 -> 前台 -> 后台 时灵动岛可能消失
  /// 原因：iOS 的 MPNowPlayingInfoCenter 在 app 返回前台后可能被系统清除
  /// 解决：在每次生命周期变化时都强制刷新完整的媒体信息
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    logger.i('MusicAudioHandler: App 生命周期变化 - $state, playing=${_player.playing}, hasMediaItem=${mediaItem.value != null}');

    switch (state) {
      case AppLifecycleState.inactive:
        // App 即将进入后台（iOS 会先进入 inactive 再进入 paused）
        // 这是设置 Now Playing 的关键时机
        // 注意：即使是暂停状态也需要刷新，否则灵动岛不会显示
        if (mediaItem.value != null) {
          logger.i('MusicAudioHandler: App 即将进入后台 (inactive)，强制刷新 Now Playing');
          // 重要：重新设置 mediaItem 而不只是广播状态
          // iOS 的 MPNowPlayingInfoCenter 可能在 app 返回前台后丢失信息
          // 参考：https://github.com/ryanheise/audio_service/issues/684
          // ignore: discarded_futures
          _resetMediaItemForNowPlaying();
        }

      case AppLifecycleState.hidden:
        // Flutter 3.13+ 新增的状态，在 inactive 和 paused 之间
        // 在某些平台上会触发，需要同样处理
        if (mediaItem.value != null) {
          logger.i('MusicAudioHandler: App 进入 hidden 状态，刷新 Now Playing');
          // ignore: discarded_futures
          _resetMediaItemForNowPlaying();
        }

      case AppLifecycleState.paused:
        // App 已进入后台
        // 再次确保状态已广播（作为 inactive 的备份）
        // 关键：如果是从前台刚返回后台，需要强制完整刷新
        if (mediaItem.value != null) {
          if (_justResumedFromBackground) {
            // 刚从后台返回又进入后台，需要强制完整刷新
            logger.i('MusicAudioHandler: 后台->前台->后台 场景，强制完整刷新 Now Playing');
            _justResumedFromBackground = false;
            // ignore: discarded_futures
            _resetMediaItemForNowPlaying();
          } else {
            // 普通的进入后台，使用防抖避免重复广播
            final now = DateTime.now();
            if (_lastBroadcastTime == null ||
                now.difference(_lastBroadcastTime!) > const Duration(milliseconds: 500)) {
              logger.i('MusicAudioHandler: App 已进入后台 (paused)，补充广播状态');
              _broadcastState(PlaybackEvent());
              _lastBroadcastTime = now;
            }
          }
        }

      case AppLifecycleState.resumed:
        // App 返回前台
        // 关键：iOS 返回前台后 MPNowPlayingInfoCenter 可能丢失状态
        // 需要重新设置 mediaItem 以确保下次进入后台时能正确显示
        logger.i('MusicAudioHandler: App 返回前台 (resumed)');
        _justResumedFromBackground = true;
        if (mediaItem.value != null) {
          // 立即刷新一次
          // ignore: discarded_futures
          _resetMediaItemForNowPlaying();
          // 延迟后再次刷新（确保封面和状态同步，防止竞态条件）
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mediaItem.value != null) {
              logger.i('MusicAudioHandler: 返回前台后延迟刷新 mediaItem');
              _resetMediaItemForNowPlaying();
            }
          });
        }

      case AppLifecycleState.detached:
        // App 即将被销毁，不需要处理
        break;
    }
  }

  /// 刷新计数器，用于强制 audio_service 更新
  /// 通过微调 duration 来触发 iOS 原生代码的更新检测
  int _refreshCounter = 0;

  /// 重新设置 mediaItem 以刷新 iOS Now Playing 信息
  /// 这是解决 MPNowPlayingInfoCenter 竞态条件的关键
  /// 只广播 playbackState 不够，需要重新设置完整的 mediaItem
  ///
  /// 关键问题：audio_service 的 iOS 原生代码只在特定字段变化时才更新 nowPlayingInfo
  /// 比较的字段包括：title, album, artist, duration, artwork, playbackRate, elapsedPlaybackTime
  /// extras 字段不会触发更新！
  ///
  /// 解决方案：每次刷新时给 duration 加 1ms
  /// 这个微小变化用户完全感知不到（1ms vs 280000ms = 0.0004%）
  /// 但会触发 audio_service 重新设置完整的 nowPlayingInfo
  Future<void> _resetMediaItemForNowPlaying() async {
    final currentItem = mediaItem.value;
    if (currentItem == null) return;

    // 如果有缓存的封面数据但 artUri 为 null，尝试重新保存封面
    var artUri = currentItem.artUri;
    if (artUri == null && _currentArtworkData != null && _currentArtworkData!.isNotEmpty) {
      logger.i('MusicAudioHandler: artUri 为空但有缓存封面，重新保存');
      artUri = await _saveArtworkToFile(_currentArtworkData!, currentItem.id);
    }

    // 递增刷新计数器
    _refreshCounter++;

    // 获取当前 duration，并加上微小偏移量来触发更新
    // 使用 isEven 来交替加减，避免 duration 无限增长
    final baseDuration = _player.duration ?? currentItem.duration ?? Duration.zero;
    final durationOffset = _refreshCounter.isEven
        ? const Duration(milliseconds: 1)
        : Duration.zero;
    final adjustedDuration = baseDuration + durationOffset;

    // 创建新的 MediaItem 实例
    final refreshedItem = MediaItem(
      id: currentItem.id,
      title: currentItem.title,
      artist: currentItem.artist,
      album: currentItem.album,
      duration: adjustedDuration,
      artUri: artUri,
      extras: currentItem.extras,
    );

    // 设置 mediaItem
    mediaItem.add(refreshedItem);

    // 然后广播最新的播放状态
    _broadcastState(PlaybackEvent());
    _lastBroadcastTime = DateTime.now();

    logger.i('MusicAudioHandler: mediaItem 已刷新 (counter=$_refreshCounter, duration=${adjustedDuration.inMilliseconds}ms) - ${currentItem.title}');
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
    logger.i('MusicAudioHandler: 准备切换歌曲, 当前歌曲=${_currentMusicItem?.displayTitle}');

    // 如果正在播放，先暂停并广播状态
    if (_player.playing) {
      await _player.pause();
      _broadcastState(PlaybackEvent());
    }

    // 重要：清理当前音乐信息，允许设置新歌曲
    _currentMusicItem = null;
    _currentArtworkData = null;

    logger.d('MusicAudioHandler: 已清理当前歌曲信息');
  }

  /// 设置当前播放的音乐（由 MusicPlayerNotifier 调用）
  Future<void> setCurrentMusic(
    MusicItem music, {
    Uint8List? artworkData,
  }) async {
    logger.i('MusicAudioHandler: setCurrentMusic 被调用 - ${music.displayTitle}, hasArtwork=${artworkData != null}');

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
    // 注意：不等待 _player.play()，因为在 iOS 上它可能不会立即返回
    // 这会导致调用者永远等待，进而导致切歌失败
    // play() 只是触发播放，实际的播放状态通过 playbackEventStream 监听
    unawaited(_player.play());
    // 短暂等待确保播放器状态更新
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // 重要：显式广播状态确保 iOS Now Playing 立即更新
    _broadcastState(PlaybackEvent());
    logger.i('MusicAudioHandler: play() 完成，已广播状态');
  }

  @override
  Future<void> pause() async {
    logger.i('MusicAudioHandler: pause() 被调用');
    // 同样不等待，避免卡住
    unawaited(_player.pause());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // 显式广播状态确保 iOS Now Playing 立即更新
    _broadcastState(PlaybackEvent());
  }

  @override
  Future<void> stop() async {
    logger.i('MusicAudioHandler: stop() 被调用');
    // 同样不等待，避免卡住
    unawaited(_player.stop());
    await Future<void>.delayed(const Duration(milliseconds: 50));
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
