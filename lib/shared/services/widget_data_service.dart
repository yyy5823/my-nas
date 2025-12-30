import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/shared/models/widget_data_models.dart';
import 'package:my_nas/shared/services/download_service.dart';

/// 小组件数据服务
///
/// 负责将 Flutter 应用数据同步到原生小组件
/// 支持 iOS (WidgetKit)、Android (App Widgets)、macOS (WidgetKit)
class WidgetDataService {
  factory WidgetDataService() => _instance ??= WidgetDataService._();
  WidgetDataService._();

  static WidgetDataService? _instance;

  // Platform-specific Method Channels
  static const _iosChannel = MethodChannel('com.kkape.mynas/ios_widgets');
  static const _androidChannel =
      MethodChannel('com.kkape.mynas/android_widgets');
  static const _macosChannel = MethodChannel('com.kkape.mynas/macos_widgets');

  Timer? _storageUpdateTimer;
  Timer? _downloadThrottleTimer;
  bool _initialized = false;

  // 节流控制
  DateTime? _lastDownloadUpdate;
  static const _downloadThrottleDuration = Duration(seconds: 1);

  DateTime? _lastMediaUpdate;
  static const _mediaThrottleDuration = Duration(milliseconds: 500);

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;

    logger.i('WidgetDataService: 初始化');

    // 启动存储信息定时更新（每15分钟）
    _storageUpdateTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => updateStorageWidget(),
    );

    // 初始化时更新所有小组件
    await updateAllWidgets();

    _initialized = true;
    logger.i('WidgetDataService: 初始化完成');
  }

  /// 获取当前平台的 MethodChannel
  MethodChannel? get _currentChannel {
    if (Platform.isIOS) return _iosChannel;
    if (Platform.isAndroid) return _androidChannel;
    if (Platform.isMacOS) return _macosChannel;
    return null;
  }

  /// 更新所有小组件
  Future<void> updateAllWidgets() async {
    await Future.wait([
      updateStorageWidget(),
      updateDownloadWidget(),
      updateQuickAccessWidget(),
      updateThemeWidget(),
      // 媒体小组件由播放器状态变化触发，不在此处更新
    ]);
  }

  // ==================== 存储状态小组件 ====================

  /// 更新存储状态小组件
  ///
  /// 从当前连接的 NAS 获取存储信息并更新小组件
  Future<void> updateStorageWidget([StorageWidgetData? data]) async {
    final channel = _currentChannel;
    if (channel == null) return;

    try {
      // 如果没有提供数据，尝试获取当前 NAS 的存储信息
      final widgetData = data ?? await _fetchStorageData();

      await channel.invokeMethod('updateStorageWidget', widgetData.toJson());
      logger.d('WidgetDataService: 存储小组件已更新');
    } on PlatformException catch (e, st) {
      AppError.ignore(e, st, '更新存储小组件失败 (PlatformException)');
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '更新存储小组件失败');
    }
  }

  /// 清除存储状态小组件（断开连接时调用）
  Future<void> clearStorageWidget() async {
    final channel = _currentChannel;
    if (channel == null) return;

    try {
      final emptyData = StorageWidgetData(
        totalBytes: 0,
        usedBytes: 0,
        nasName: '',
        adapterType: 'unknown',
        lastUpdated: DateTime.now(),
        isConnected: false,
      );
      await channel.invokeMethod('updateStorageWidget', emptyData.toJson());
      logger.d('WidgetDataService: 存储小组件已清除');
    } on PlatformException catch (e, st) {
      AppError.ignore(e, st, '清除存储小组件失败');
    }
  }

  /// 获取存储数据
  ///
  /// 从当前连接的 NAS 适配器获取存储信息
  Future<StorageWidgetData> _fetchStorageData() async {
    final sourceManager = SourceManagerService();

    // 获取所有已连接的源
    final connections = sourceManager.getActiveConnections();
    if (connections.isEmpty) {
      return StorageWidgetData(
        totalBytes: 0,
        usedBytes: 0,
        nasName: '',
        adapterType: 'unknown',
        lastUpdated: DateTime.now(),
        isConnected: false,
      );
    }

    // 使用第一个已连接的源（通常是主要的 NAS）
    final firstConnection = connections.first;
    final adapter = firstConnection.adapter;
    final source = firstConnection.source;

    // 尝试获取存储信息
    final storageInfo = await adapter.getStorageInfo();

    if (storageInfo == null) {
      // 适配器不支持获取存储信息，但仍显示已连接状态
      return StorageWidgetData(
        totalBytes: 0,
        usedBytes: 0,
        nasName: source.name,
        adapterType: adapter.info.type.name,
        lastUpdated: DateTime.now(),
        isConnected: true,
      );
    }

    return StorageWidgetData(
      totalBytes: storageInfo.totalBytes,
      usedBytes: storageInfo.usedBytes,
      nasName: source.name,
      adapterType: adapter.info.type.name,
      lastUpdated: DateTime.now(),
      isConnected: true,
    );
  }

  // ==================== 下载进度小组件 ====================

  /// 更新下载进度小组件
  ///
  /// 由 [DownloadService] 状态变化时调用
  /// 内置节流机制，避免频繁更新
  Future<void> updateDownloadWidget([DownloadWidgetData? data]) async {
    // 节流检查
    final now = DateTime.now();
    if (_lastDownloadUpdate != null &&
        now.difference(_lastDownloadUpdate!) < _downloadThrottleDuration) {
      return;
    }
    _lastDownloadUpdate = now;

    final channel = _currentChannel;
    if (channel == null) return;

    try {
      final widgetData = data ?? _buildDownloadWidgetData();
      await channel.invokeMethod('updateDownloadWidget', widgetData.toJson());
      logger.d('WidgetDataService: 下载小组件已更新');
    } on PlatformException catch (e, st) {
      AppError.ignore(e, st, '更新下载小组件失败 (PlatformException)');
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '更新下载小组件失败');
    }
  }

  /// 构建下载小组件数据
  DownloadWidgetData _buildDownloadWidgetData() {
    final tasks = downloadService.tasks;
    final activeTasks = tasks
        .where((t) => t.status == DownloadStatus.downloading)
        .map(
          (t) => DownloadTaskSummary(
            id: t.id,
            fileName: t.fileName,
            progress: t.progress,
            status: t.status.name,
          ),
        )
        .toList();

    final completedCount =
        tasks.where((t) => t.status == DownloadStatus.completed).length;

    return DownloadWidgetData(
      activeTasks: activeTasks,
      completedCount: completedCount,
      totalCount: tasks.length,
      lastUpdated: DateTime.now(),
    );
  }

  // ==================== 快捷操作小组件 ====================

  /// 更新快捷操作小组件
  Future<void> updateQuickAccessWidget([QuickAccessWidgetData? data]) async {
    final channel = _currentChannel;
    if (channel == null) return;

    try {
      final widgetData = data ?? QuickAccessWidgetData.defaultData;
      await channel.invokeMethod('updateQuickAccessWidget', widgetData.toJson());
      logger.d('WidgetDataService: 快捷操作小组件已更新');
    } on PlatformException catch (e, st) {
      AppError.ignore(e, st, '更新快捷操作小组件失败 (PlatformException)');
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '更新快捷操作小组件失败');
    }
  }

  // ==================== 媒体播放小组件 ====================

  /// 更新媒体播放小组件
  ///
  /// 由音乐播放器状态变化时调用
  /// 内置节流机制，避免频繁更新
  ///
  /// 注意：iOS 已有 Live Activity，此方法主要用于 Android 和 macOS 的 Home Screen Widget
  Future<void> updateMediaWidget(MediaWidgetData data) async {
    // 节流检查
    final now = DateTime.now();
    if (_lastMediaUpdate != null &&
        now.difference(_lastMediaUpdate!) < _mediaThrottleDuration) {
      return;
    }
    _lastMediaUpdate = now;

    final channel = _currentChannel;
    if (channel == null) return;

    try {
      final jsonData = data.toJson();
      // 单独处理封面数据
      if (data.coverImageData != null) {
        jsonData['coverImageData'] = data.coverImageData;
      }

      await channel.invokeMethod('updateMediaWidget', jsonData);
      logger.d('WidgetDataService: 媒体小组件已更新');
    } on PlatformException catch (e, st) {
      AppError.ignore(e, st, '更新媒体小组件失败 (PlatformException)');
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '更新媒体小组件失败');
    }
  }

  /// 清除媒体播放小组件
  Future<void> clearMediaWidget() async {
    await updateMediaWidget(MediaWidgetData.empty);
  }

  // ==================== 主题小组件 ====================

  /// 更新小组件主题
  ///
  /// 将当前配色方案同步到原生小组件
  /// 由主题切换时调用
  Future<void> updateThemeWidget([ThemeWidgetData? data]) async {
    final channel = _currentChannel;
    if (channel == null) return;

    try {
      final widgetData = data ?? _buildThemeWidgetData();
      await channel.invokeMethod('updateThemeWidget', widgetData.toJson());
      logger.d('WidgetDataService: 主题小组件已更新 - ${widgetData.presetId}');
    } on PlatformException catch (e, st) {
      AppError.ignore(e, st, '更新主题小组件失败 (PlatformException)');
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '更新主题小组件失败');
    }
  }

  /// 从当前配色方案构建主题数据
  ThemeWidgetData _buildThemeWidgetData() {
    final preset = AppColors.currentPreset;
    return ThemeWidgetData(
      presetId: preset.id,
      primary: preset.primary.toARGB32(),
      primaryLight: preset.primaryLight.toARGB32(),
      primaryDark: preset.primaryDark.toARGB32(),
      secondary: preset.secondary.toARGB32(),
      accent: preset.accent.toARGB32(),
      music: preset.music.toARGB32(),
      video: preset.video.toARGB32(),
      photo: preset.photo.toARGB32(),
      book: preset.book.toARGB32(),
      download: preset.download.toARGB32(),
      darkBackground: preset.darkBackground.toARGB32(),
      darkSurface: preset.darkSurface.toARGB32(),
      darkSurfaceVariant: preset.darkSurfaceVariant.toARGB32(),
      success: AppColors.success.toARGB32(),
      warning: AppColors.warning.toARGB32(),
      error: AppColors.error.toARGB32(),
    );
  }

  // ==================== 连接状态 ====================

  /// 更新连接状态
  ///
  /// 当 NAS 连接或断开时调用，会刷新所有小组件
  Future<void> updateConnectionStatus({
    required bool isConnected,
    String? connectionName,
  }) async {
    final channel = _currentChannel;
    if (channel == null) return;

    try {
      await channel.invokeMethod('updateConnectionStatus', {
        'isConnected': isConnected,
        'connectionName': connectionName,
      });
      logger.i('WidgetDataService: 连接状态已更新 - connected: $isConnected');

      // 连接状态变化时触发所有小组件更新
      if (isConnected) {
        await updateAllWidgets();
      }
    } on PlatformException catch (e, st) {
      AppError.ignore(e, st, '更新连接状态失败');
    }
  }

  // ==================== 工具方法 ====================

  /// 强制刷新所有小组件
  ///
  /// 通知原生层重新加载所有小组件的 Timeline
  Future<void> refreshAllWidgets() async {
    final channel = _currentChannel;
    if (channel == null) return;

    try {
      await channel.invokeMethod('refreshAllWidgets');
      logger.i('WidgetDataService: 已触发所有小组件刷新');
    } on PlatformException catch (e, st) {
      AppError.ignore(e, st, '刷新小组件失败');
    }
  }

  /// 释放资源
  void dispose() {
    _storageUpdateTimer?.cancel();
    _downloadThrottleTimer?.cancel();
    _initialized = false;
    logger.i('WidgetDataService: 已释放资源');
  }
}

/// 全局小组件数据服务实例
final widgetDataService = WidgetDataService();
