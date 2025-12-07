import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';

/// 音乐播放器 Live Activity 服务
/// 用于在 iOS 灵动岛和锁屏上显示音乐播放状态
///
/// 注意：此服务使用自定义的 Method Channel 实现，
/// 专门为个人开发者账号设计，使用 pushType: nil 来避免 Push Notification 能力限制。
class LiveActivityService {
  factory LiveActivityService() => _instance ??= LiveActivityService._();
  LiveActivityService._();

  static LiveActivityService? _instance;

  /// 自定义 Method Channel（用于个人开发者账号，不需要 Push Notification）
  static const _channel = MethodChannel('com.kkape.mynas/music_live_activity');

  /// Event Channel 用于接收来自灵动岛的控制命令
  static const _eventChannel = EventChannel('com.kkape.mynas/music_live_activity_events');

  /// 当前 Live Activity 的 ID
  String? _currentActivityId;

  /// 是否已初始化
  bool _initialized = false;

  /// 控制命令回调（来自灵动岛按钮点击）
  void Function(String action)? onControlAction;

  /// 当前封面数据（用于更新时携带）
  Uint8List? _currentCoverData;

  /// Event Channel 订阅
  StreamSubscription<dynamic>? _eventSubscription;

  /// 检查是否支持 Live Activities
  bool get isSupported => Platform.isIOS;

  /// 初始化服务
  Future<void> init() async {
    logger.i('LiveActivityService: init 调用 - isSupported=$isSupported, initialized=$_initialized');

    if (_initialized) {
      logger.d('LiveActivityService: 已初始化，跳过');
      return;
    }

    if (!isSupported) {
      logger.w('LiveActivityService: 当前平台不支持 Live Activities');
      return;
    }

    try {
      logger.d('LiveActivityService: 正在初始化自定义 Method Channel');

      // 检查 Live Activities 是否已启用
      final enabled = await _channel.invokeMethod<bool>('areActivitiesEnabled') ?? false;
      logger.i('LiveActivityService: areActivitiesEnabled=$enabled');

      if (!enabled) {
        logger.w('LiveActivityService: 用户未启用 Live Activities，请在设置中开启');
      }

      // 监听来自灵动岛的控制命令
      _startListeningToControlCommands();

      _initialized = true;
      logger.i('LiveActivityService: 初始化成功，服务已就绪（使用自定义 Method Channel，无需 Push Notification）');
    } on PlatformException catch (e, stackTrace) {
      logger.e('LiveActivityService: 初始化失败', e, stackTrace);
    } on Exception catch (e, stackTrace) {
      logger.e('LiveActivityService: 初始化失败', e, stackTrace);
    }
  }

  /// 开始监听来自灵动岛的控制命令
  void _startListeningToControlCommands() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is String) {
          logger.i('LiveActivityService: 收到灵动岛控制命令: $event');
          onControlAction?.call(event);
        }
      },
      onError: (Object error) {
        logger.e('LiveActivityService: EventChannel 错误', error);
      },
    );
    logger.d('LiveActivityService: 开始监听灵动岛控制命令');
  }

  /// 开始音乐播放的 Live Activity
  Future<void> startMusicActivity({
    required MusicItem music,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    Uint8List? coverData,
  }) async {
    logger.i('LiveActivity: startMusicActivity 调用 - isSupported=$isSupported, initialized=$_initialized');

    if (!isSupported) {
      logger.w('LiveActivity: 平台不支持 (非 iOS)');
      return;
    }

    if (!_initialized) {
      logger.w('LiveActivity: 服务未初始化，尝试初始化...');
      await init();
      if (!_initialized) {
        logger.e('LiveActivity: 初始化失败，无法创建活动');
        return;
      }
    }

    try {
      // 检查是否启用了 Live Activities
      logger.d('LiveActivity: 检查用户是否启用了 Live Activities...');
      final enabled = await _channel.invokeMethod<bool>('areActivitiesEnabled') ?? false;
      logger.i('LiveActivity: areActivitiesEnabled=$enabled');

      if (!enabled) {
        logger.w('LiveActivity: 用户未启用 Live Activities，请在设置中开启');
        return;
      }

      // 如果已有 Activity，更新它而不是重新创建
      // 这样可以避免在后台时创建新 Activity 失败导致灵动岛被清除
      if (_currentActivityId != null) {
        logger.d('LiveActivity: 已有活动存在，更新它: $_currentActivityId');
        // 更新封面数据
        if (coverData != null) {
          _currentCoverData = coverData;
        }
        await updateActivity(
          music: music,
          isPlaying: isPlaying,
          position: position,
          duration: duration,
          coverData: coverData,
        );
        return;
      }

      // 保存封面数据
      _currentCoverData = coverData;

      // 创建 Activity 数据
      final activityData = _buildActivityData(
        music: music,
        isPlaying: isPlaying,
        position: position,
        duration: duration,
        coverData: coverData,
      );

      logger.d('LiveActivity: 准备创建活动，数据: title=${activityData['title']}, artist=${activityData['artist']}, hasCover=${coverData != null}');

      // 使用自定义 Method Channel 创建 Live Activity（不需要 Push Notification）
      _currentActivityId = await _channel.invokeMethod<String>(
        'createActivity',
        {'data': activityData},
      );

      if (_currentActivityId != null) {
        logger.i('LiveActivity: 创建成功, ID=$_currentActivityId');
      } else {
        logger.w('LiveActivity: 创建失败，返回 null ID - 可能是 iOS 版本不支持或配置问题');
      }
    } on PlatformException catch (e, stackTrace) {
      logger.e('LiveActivity: 创建失败 (PlatformException)', e, stackTrace);
    } on Exception catch (e, stackTrace) {
      logger.e('LiveActivity: 创建失败', e, stackTrace);
    }
  }

  /// 更新 Live Activity 状态
  Future<void> updateActivity({
    required MusicItem music,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    Uint8List? coverData,
  }) async {
    if (!isSupported || !_initialized || _currentActivityId == null) return;

    try {
      // 如果提供了新的封面，更新缓存
      if (coverData != null) {
        _currentCoverData = coverData;
      }

      final activityData = _buildActivityData(
        music: music,
        isPlaying: isPlaying,
        position: position,
        duration: duration,
        coverData: _currentCoverData,
      );

      // 使用自定义 Method Channel 更新
      await _channel.invokeMethod('updateActivity', {'data': activityData});

      // 仅在状态变化时记录日志，避免日志过多
      if (kDebugMode && position.inSeconds % 10 == 0) {
        logger.d('LiveActivity: 更新状态 - isPlaying=$isPlaying, position=${position.inSeconds}s');
      }
    } on PlatformException catch (e, stackTrace) {
      logger.e('LiveActivity: 更新失败 (PlatformException)', e, stackTrace);
    } on Exception catch (e, stackTrace) {
      logger.e('LiveActivity: 更新失败', e, stackTrace);
    }
  }

  /// 结束 Live Activity
  Future<void> endActivity() async {
    if (!isSupported || !_initialized || _currentActivityId == null) return;

    try {
      await _channel.invokeMethod('endActivity');
      logger.i('LiveActivity: 已结束, ID=$_currentActivityId');
      _currentActivityId = null;
      _currentCoverData = null;
    } on PlatformException catch (e, stackTrace) {
      logger.e('LiveActivity: 结束失败 (PlatformException)', e, stackTrace);
    } on Exception catch (e, stackTrace) {
      logger.e('LiveActivity: 结束失败', e, stackTrace);
    }
  }

  /// 结束所有 Live Activities
  Future<void> endAllActivities() async {
    if (!isSupported || !_initialized) return;

    try {
      await _channel.invokeMethod('endAllActivities');
      logger.i('LiveActivity: 已结束所有活动');
      _currentActivityId = null;
      _currentCoverData = null;
    } on PlatformException catch (e, stackTrace) {
      logger.e('LiveActivity: 结束所有活动失败 (PlatformException)', e, stackTrace);
    } on Exception catch (e, stackTrace) {
      logger.e('LiveActivity: 结束所有活动失败', e, stackTrace);
    }
  }

  /// 检查是否正在运行 Live Activity
  bool get isActivityRunning => _currentActivityId != null;

  /// 构建 Activity 数据
  Map<String, dynamic> _buildActivityData({
    required MusicItem music,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    Uint8List? coverData,
  }) {
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    final data = <String, dynamic>{
      // 静态属性
      'title': music.displayTitle,
      'artist': music.displayArtist,
      'album': music.displayAlbum,
      // 动态状态
      'isPlaying': isPlaying,
      'progress': progress.clamp(0.0, 1.0),
      'currentTime': position.inSeconds,
      'totalTime': duration.inSeconds,
    };

    // 添加封面图片（如果有）
    // 直接传递 Uint8List，iOS 端会处理保存到文件
    if (coverData != null && coverData.isNotEmpty) {
      data['coverImage'] = coverData;
    }

    return data;
  }

  /// 更新封面图片
  /// 在音乐元数据加载完成后调用
  Future<void> updateCoverImage(MusicItem music, Uint8List coverData) async {
    if (!isSupported || !_initialized || _currentActivityId == null) return;

    try {
      _currentCoverData = coverData;

      final activityData = <String, dynamic>{
        'title': music.displayTitle,
        'artist': music.displayArtist,
        'album': music.displayAlbum,
        'coverImage': coverData,
      };

      await _channel.invokeMethod('updateActivity', {'data': activityData});
      logger.i('LiveActivity: 封面图片已更新');
    } on PlatformException catch (e, stackTrace) {
      logger.e('LiveActivity: 更新封面图片失败 (PlatformException)', e, stackTrace);
    } on Exception catch (e, stackTrace) {
      logger.e('LiveActivity: 更新封面图片失败', e, stackTrace);
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await endAllActivities();
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _initialized = false;
    _currentCoverData = null;
    logger.i('LiveActivityService: 已释放资源');
  }
}
