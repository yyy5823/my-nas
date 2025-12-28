import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui show Color;

import 'package:flutter/services.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';

/// 扩展 Color 类以获取 ARGB32 值
extension _ColorToARGB32 on ui.Color {
  // ignore: unused_element
  int toARGB32() =>
      ((a * 255.0).round().clamp(0, 255) << 24) |
      ((r * 255.0).round().clamp(0, 255) << 16) |
      ((g * 255.0).round().clamp(0, 255) << 8) |
      (b * 255.0).round().clamp(0, 255);
}

/// Android 灵动岛类型
enum AndroidDynamicIslandType {
  /// 华为 Live View Kit
  huaweiLiveView,

  /// 通用悬浮窗
  floatingWindow,

  /// 不支持
  notSupported,
}

/// Android 灵动岛服务
/// 用于在 Android 设备上显示类似 iOS 灵动岛的音乐播放控制悬浮窗
///
/// 支持两种实现方式：
/// 1. 华为 Live View Kit - 适用于华为/荣耀设备，需要 HarmonyOS 4.0+ 或 EMUI 14+
/// 2. 通用悬浮窗 - 适用于所有 Android 6.0+ 设备，需要 SYSTEM_ALERT_WINDOW 权限
class AndroidDynamicIslandService {
  factory AndroidDynamicIslandService() =>
      _instance ??= AndroidDynamicIslandService._();
  AndroidDynamicIslandService._();

  static AndroidDynamicIslandService? _instance;

  /// Method Channel
  static const _channel = MethodChannel('com.kkape.mynas/dynamic_island');

  /// 是否已初始化
  bool _initialized = false;

  /// 当前灵动岛类型
  AndroidDynamicIslandType _type = AndroidDynamicIslandType.notSupported;

  /// 是否有权限
  bool _hasPermission = false;

  /// 控制命令回调（来自灵动岛按钮点击）
  void Function(String action)? onControlAction;

  /// 当前封面数据
  Uint8List? _currentCoverData;

  /// 当前主题颜色（ARGB 格式）
  int? _currentThemeColor;

  /// 检查是否支持 Android 灵动岛
  bool get isSupported => Platform.isAndroid;

  /// 获取当前灵动岛类型
  AndroidDynamicIslandType get type => _type;

  /// 是否有悬浮窗权限
  bool get hasPermission => _hasPermission;

  /// 初始化服务
  Future<void> init() async {
    logger.i(
      'AndroidDynamicIsland: init 调用 - isSupported=$isSupported, initialized=$_initialized',
    );

    if (_initialized) {
      logger.d('AndroidDynamicIsland: 已初始化，跳过');
      return;
    }

    if (!isSupported) {
      logger.w('AndroidDynamicIsland: 当前平台不支持 (非 Android)');
      return;
    }

    try {
      logger.d('AndroidDynamicIsland: 正在初始化...');

      // 设置方法调用处理器
      _channel.setMethodCallHandler(_handleMethodCall);

      // 初始化 Android 端
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('initialize');

      if (result != null) {
        final typeStr = result['type'] as String?;
        _type = _parseType(typeStr);
        // ignore: avoid_bool_literals_in_conditional_expressions
        _hasPermission = result['hasPermission'] as bool? ?? false;

        logger.i(
          'AndroidDynamicIsland: 初始化成功 - type=$_type, hasPermission=$_hasPermission',
        );
      }

      _initialized = true;
    } on PlatformException catch (e, stackTrace) {
      logger.e('AndroidDynamicIsland: 初始化失败 (PlatformException)', e, stackTrace);
    } on Exception catch (e, stackTrace) {
      logger.e('AndroidDynamicIsland: 初始化失败', e, stackTrace);
    }
  }

  /// 处理来自 Android 的方法调用
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    logger.d('AndroidDynamicIsland: 收到回调 - ${call.method}');

    switch (call.method) {
      case 'onPlayPause':
        onControlAction?.call('playPause');
      case 'onNext':
        onControlAction?.call('next');
      case 'onPrevious':
        onControlAction?.call('previous');
      case 'onSeek':
        final args = call.arguments as Map<Object?, Object?>?;
        final position = args?['position'] as int?;
        if (position != null) {
          onControlAction?.call('seek:$position');
        }
      case 'onDismiss':
        onControlAction?.call('dismiss');
      case 'onExpand':
        onControlAction?.call('expand');
    }
  }

  /// 解析灵动岛类型
  AndroidDynamicIslandType _parseType(String? typeStr) {
    switch (typeStr) {
      case 'HUAWEI_LIVE_VIEW':
        return AndroidDynamicIslandType.huaweiLiveView;
      case 'FLOATING_WINDOW':
        return AndroidDynamicIslandType.floatingWindow;
      default:
        return AndroidDynamicIslandType.notSupported;
    }
  }

  /// 请求悬浮窗权限
  Future<bool> requestPermission() async {
    if (!isSupported || _type == AndroidDynamicIslandType.notSupported) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } on PlatformException catch (e, stackTrace) {
      logger.e('AndroidDynamicIsland: 请求权限失败', e, stackTrace);
      return false;
    }
  }

  /// 检查是否有权限
  Future<bool> checkPermission() async {
    if (!isSupported || !_initialized) return false;

    try {
      final result = await _channel.invokeMethod<bool>('hasPermission');
      _hasPermission = result ?? false;
      return _hasPermission;
    } on PlatformException catch (e, stackTrace) {
      logger.e('AndroidDynamicIsland: 检查权限失败', e, stackTrace);
      return false;
    }
  }

  /// 显示灵动岛
  Future<void> show() async {
    if (!isSupported || !_initialized) return;

    // 再次检查权限
    if (!await checkPermission()) {
      logger.w('AndroidDynamicIsland: 无权限，无法显示灵动岛');
      return;
    }

    try {
      await _channel.invokeMethod<void>('show');
      logger.i('AndroidDynamicIsland: 灵动岛已显示');
    } on PlatformException catch (e, stackTrace) {
      logger.e('AndroidDynamicIsland: 显示失败', e, stackTrace);
    }
  }

  /// 隐藏灵动岛
  Future<void> hide() async {
    if (!isSupported || !_initialized) return;

    try {
      await _channel.invokeMethod<void>('hide');
      logger.i('AndroidDynamicIsland: 灵动岛已隐藏');
    } on PlatformException catch (e, stackTrace) {
      logger.e('AndroidDynamicIsland: 隐藏失败', e, stackTrace);
    }
  }

  /// 展开灵动岛
  Future<void> expand() async {
    if (!isSupported || !_initialized) return;

    try {
      await _channel.invokeMethod<void>('expand');
      logger.i('AndroidDynamicIsland: 灵动岛已展开');
    } on PlatformException catch (e, stackTrace) {
      logger.e('AndroidDynamicIsland: 展开失败', e, stackTrace);
    }
  }

  /// 收起灵动岛
  Future<void> collapse() async {
    if (!isSupported || !_initialized) return;

    try {
      await _channel.invokeMethod<void>('collapse');
      logger.i('AndroidDynamicIsland: 灵动岛已收起');
    } on PlatformException catch (e, stackTrace) {
      logger.e('AndroidDynamicIsland: 收起失败', e, stackTrace);
    }
  }

  /// 开始音乐播放的灵动岛
  Future<void> startMusicActivity({
    required MusicItem music,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    Uint8List? coverData,
  }) async {
    if (!isSupported) return;

    if (!_initialized) {
      await init();
      if (!_initialized) {
        logger.e('AndroidDynamicIsland: 初始化失败，无法创建活动');
        return;
      }
    }

    // 检查权限
    if (!await checkPermission()) {
      logger.w('AndroidDynamicIsland: 无权限，无法显示灵动岛');
      return;
    }

    // 保存封面数据
    _currentCoverData = coverData;

    // 更新数据
    await updateActivity(
      music: music,
      isPlaying: isPlaying,
      position: position,
      duration: duration,
      coverData: coverData,
    );

    // 显示灵动岛
    await show();
  }

  /// 更新灵动岛状态
  Future<void> updateActivity({
    required MusicItem music,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    Uint8List? coverData,
  }) async {
    if (!isSupported || !_initialized) return;

    try {
      // 如果提供了新的封面，更新缓存
      if (coverData != null) {
        _currentCoverData = coverData;
      }

      // 使用缓存的封面数据
      final effectiveCoverData = coverData ?? _currentCoverData;

      final data = _buildActivityData(
        music: music,
        isPlaying: isPlaying,
        position: position,
        duration: duration,
        coverData: effectiveCoverData,
      );

      await _channel.invokeMethod<void>('updateData', data);
    } on PlatformException catch (e, stackTrace) {
      logger.e('AndroidDynamicIsland: 更新失败', e, stackTrace);
    }
  }

  /// 结束灵动岛
  Future<void> endActivity() async {
    if (!isSupported || !_initialized) return;

    await hide();
    _currentCoverData = null;
    logger.i('AndroidDynamicIsland: 活动已结束');
  }

  /// 更新封面图片
  Future<void> updateCoverImage(MusicItem music, Uint8List coverData) async {
    if (!isSupported || !_initialized) return;

    _currentCoverData = coverData;

    try {
      await _channel.invokeMethod<void>('updateData', {
        'title': music.displayTitle,
        'artist': music.displayArtist,
        'album': music.displayAlbum,
        'coverImageData': coverData,
      });
      logger.i('AndroidDynamicIsland: 封面图片已更新');
    } on PlatformException catch (e, stackTrace) {
      logger.e('AndroidDynamicIsland: 更新封面图片失败', e, stackTrace);
    }
  }

  /// 设置主题颜色
  void setThemeColor(ui.Color color) {
    _currentThemeColor = color.toARGB32();
    logger.d(
      'AndroidDynamicIsland: 主题颜色已设置为 0x${_currentThemeColor!.toRadixString(16)}',
    );
  }

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
      'title': music.displayTitle,
      'artist': music.displayArtist,
      'album': music.displayAlbum,
      'isPlaying': isPlaying,
      'progress': progress.clamp(0.0, 1.0),
      'currentTimeMs': position.inMilliseconds,
      'totalTimeMs': duration.inMilliseconds,
    };

    // 添加封面图片（如果有）
    if (coverData != null && coverData.isNotEmpty) {
      data['coverImageData'] = coverData;
    }

    // 添加主题颜色
    if (_currentThemeColor != null) {
      data['themeColor'] = _currentThemeColor;
    }

    return data;
  }

  /// 释放资源
  Future<void> dispose() async {
    if (!isSupported || !_initialized) return;

    try {
      await _channel.invokeMethod<void>('release');
      _initialized = false;
      _currentCoverData = null;
      logger.i('AndroidDynamicIsland: 已释放资源');
    } on PlatformException catch (e, stackTrace) {
      logger.e('AndroidDynamicIsland: 释放资源失败', e, stackTrace);
    }
  }
}
