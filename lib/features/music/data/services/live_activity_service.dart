import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/activity_update.dart';
import 'package:live_activities/models/live_activity_file.dart';
import 'package:live_activities/models/url_scheme_data.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';

/// 音乐播放器 Live Activity 服务
/// 用于在 iOS 灵动岛和锁屏上显示音乐播放状态
class LiveActivityService {
  factory LiveActivityService() => _instance ??= LiveActivityService._();
  LiveActivityService._();

  static LiveActivityService? _instance;

  final LiveActivities _liveActivities = LiveActivities();

  /// 当前 Live Activity 的 ID
  String? _currentActivityId;

  /// 是否已初始化
  bool _initialized = false;

  /// URL Scheme 流订阅
  StreamSubscription<UrlSchemeData>? _urlSchemeSubscription;

  /// Activity 更新流订阅
  StreamSubscription<ActivityUpdate>? _activityUpdateSubscription;

  /// 控制命令回调
  void Function(String action)? onControlAction;

  /// 当前封面数据（用于更新时携带）
  Uint8List? _currentCoverData;

  /// App Group ID - 需要与 iOS 项目配置一致
  static const String _appGroupId = 'group.com.kkape.mynas';

  /// URL Scheme - 需要与 iOS 项目配置一致
  static const String _urlScheme = 'mynas';

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
      logger.d('LiveActivityService: 正在初始化插件 - appGroupId=$_appGroupId, urlScheme=$_urlScheme');
      await _liveActivities.init(
        appGroupId: _appGroupId,
        urlScheme: _urlScheme,
      );
      logger.d('LiveActivityService: 插件初始化完成');

      // 监听 URL Scheme 事件（用于接收控制命令）
      _urlSchemeSubscription = _liveActivities.urlSchemeStream().listen((data) {
        logger.i('LiveActivity: 收到 URL Scheme 事件: ${data.url}');
        _handleUrlScheme(data);
      });

      // 监听 Activity 状态更新
      _activityUpdateSubscription =
          _liveActivities.activityUpdateStream.listen((update) {
        update.map(
          active: (state) {
            logger.i('LiveActivity: 活动状态 - active, id=${state.activityId}');
          },
          ended: (state) {
            logger.i('LiveActivity: 活动已结束, id=${state.activityId}');
            if (state.activityId == _currentActivityId) {
              _currentActivityId = null;
            }
          },
          stale: (state) {
            logger.w('LiveActivity: 活动已过期, id=${state.activityId}');
          },
          unknown: (state) {
            logger.w('LiveActivity: 未知状态');
          },
        );
      });

      _initialized = true;
      logger.i('LiveActivityService: 初始化成功，服务已就绪');
    } on Exception catch (e, stackTrace) {
      logger.e('LiveActivityService: 初始化失败', e, stackTrace);
    }
  }

  /// 处理 URL Scheme 事件
  void _handleUrlScheme(UrlSchemeData data) {
    // URL 格式: mynas://music/play, mynas://music/pause, etc.
    final path = data.path;
    if (path != null && path.startsWith('/music/')) {
      final action = path.replaceFirst('/music/', '');
      logger.i('LiveActivity: 收到控制命令: $action');
      onControlAction?.call(action);
    }
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
      final enabled = await _liveActivities.areActivitiesEnabled();
      logger.i('LiveActivity: areActivitiesEnabled=$enabled');

      if (!enabled) {
        logger.w('LiveActivity: 用户未启用 Live Activities，请在设置中开启');
        return;
      }

      // 如果已有 Activity，先结束它
      if (_currentActivityId != null) {
        logger.d('LiveActivity: 已有活动存在，先结束它: $_currentActivityId');
        await endActivity();
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

      // 创建 Live Activity
      _currentActivityId = await _liveActivities.createActivity(
        activityData,
        removeWhenAppIsKilled: true,
      );

      if (_currentActivityId != null) {
        logger.i('LiveActivity: 创建成功, ID=$_currentActivityId');
      } else {
        logger.w('LiveActivity: 创建失败，返回 null ID - 可能是 iOS 版本不支持或配置问题');
      }
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

      await _liveActivities.updateActivity(
        _currentActivityId!,
        activityData,
      );

      // 仅在状态变化时记录日志，避免日志过多
      if (kDebugMode && position.inSeconds % 10 == 0) {
        logger.d('LiveActivity: 更新状态 - isPlaying=$isPlaying, position=${position.inSeconds}s');
      }
    } on Exception catch (e, stackTrace) {
      logger.e('LiveActivity: 更新失败', e, stackTrace);
    }
  }

  /// 结束 Live Activity
  Future<void> endActivity() async {
    if (!isSupported || !_initialized || _currentActivityId == null) return;

    try {
      await _liveActivities.endActivity(_currentActivityId!);
      logger.i('LiveActivity: 已结束, ID=$_currentActivityId');
      _currentActivityId = null;
      _currentCoverData = null;
    } on Exception catch (e, stackTrace) {
      logger.e('LiveActivity: 结束失败', e, stackTrace);
    }
  }

  /// 结束所有 Live Activities
  Future<void> endAllActivities() async {
    if (!isSupported || !_initialized) return;

    try {
      await _liveActivities.endAllActivities();
      logger.i('LiveActivity: 已结束所有活动');
      _currentActivityId = null;
      _currentCoverData = null;
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
    // live_activities 插件会自动处理 LiveActivityFile 类型的值
    // 将其保存到 App Group 共享存储，并替换为文件路径
    if (coverData != null && coverData.isNotEmpty) {
      data['coverImage'] = LiveActivityFileFromMemory.image(
        coverData,
        'cover_${music.id.hashCode}.jpg',
        imageOptions: LiveActivityImageFileOptions(resizeFactor: 0.5),
      );
    }

    return data;
  }

  /// 更新封面图片
  /// 在音乐元数据加载完成后调用
  Future<void> updateCoverImage(MusicItem music, Uint8List coverData) async {
    if (!isSupported || !_initialized || _currentActivityId == null) return;

    try {
      _currentCoverData = coverData;

      // 使用 createOrUpdateActivity 来更新活动
      // 这样可以确保封面图片被正确更新
      final activityData = <String, dynamic>{
        'title': music.displayTitle,
        'artist': music.displayArtist,
        'album': music.displayAlbum,
        'coverImage': LiveActivityFileFromMemory.image(
          coverData,
          'cover_${music.id.hashCode}.jpg',
          imageOptions: LiveActivityImageFileOptions(resizeFactor: 0.5),
        ),
      };

      await _liveActivities.updateActivity(_currentActivityId!, activityData);
      logger.i('LiveActivity: 封面图片已更新');
    } on Exception catch (e, stackTrace) {
      logger.e('LiveActivity: 更新封面图片失败', e, stackTrace);
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await _urlSchemeSubscription?.cancel();
    await _activityUpdateSubscription?.cancel();
    await endAllActivities();
    // 清理 App Group 中的临时文件
    await _liveActivities.dispose();
    _initialized = false;
    _currentCoverData = null;
    logger.i('LiveActivityService: 已释放资源');
  }
}
