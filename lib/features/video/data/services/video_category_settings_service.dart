import 'dart:async';
import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/video_category_config.dart';

/// 视频分类设置服务
///
/// 使用 Hive 持久化存储用户的分类配置（顺序、可见性、类型分类等）
class VideoCategorySettingsService {
  VideoCategorySettingsService._();

  static final VideoCategorySettingsService _instance =
      VideoCategorySettingsService._();
  static VideoCategorySettingsService get instance => _instance;

  factory VideoCategorySettingsService() => _instance;

  static const String _boxName = 'video_category_settings';
  static const String _settingsKey = 'settings';

  Box<dynamic>? _box;
  bool _initialized = false;

  final _settingsController =
      StreamController<VideoCategorySettings>.broadcast();

  /// 设置变化流
  Stream<VideoCategorySettings> get settingsStream => _settingsController.stream;

  /// 当前设置
  VideoCategorySettings? _currentSettings;
  VideoCategorySettings get settings =>
      _currentSettings ?? VideoCategorySettings.defaults();

  /// 初始化
  Future<void> init() async {
    if (_initialized) return;

    try {
      _box = await Hive.openBox(_boxName);
      _loadSettings();
      _initialized = true;
      logger.i('VideoCategorySettingsService: 初始化完成');
    } on Exception catch (e, st) {
      logger.e('VideoCategorySettingsService: 初始化失败', e, st);
      _currentSettings = VideoCategorySettings.defaults();
    }
  }

  /// 加载设置
  void _loadSettings() {
    try {
      final jsonStr = _box?.get(_settingsKey) as String?;
      if (jsonStr != null) {
        final map = json.decode(jsonStr) as Map<String, dynamic>;
        _currentSettings = VideoCategorySettings.fromMap(map);
        logger.d('VideoCategorySettingsService: 加载配置成功，'
            '${_currentSettings!.sections.length} 个分类');
      } else {
        _currentSettings = VideoCategorySettings.defaults();
        logger.d('VideoCategorySettingsService: 使用默认配置');
      }
    } on Exception catch (e) {
      logger.w('VideoCategorySettingsService: 加载配置失败，使用默认配置', e);
      _currentSettings = VideoCategorySettings.defaults();
    }
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    if (_currentSettings == null) return;

    try {
      final jsonStr = json.encode(_currentSettings!.toMap());
      await _box?.put(_settingsKey, jsonStr);
      _settingsController.add(_currentSettings!);
      logger.d('VideoCategorySettingsService: 配置已保存');
    } on Exception catch (e) {
      logger.e('VideoCategorySettingsService: 保存配置失败', e);
    }
  }

  /// 切换分类可见性
  Future<void> toggleVisibility(String uniqueKey) async {
    await init();
    _currentSettings = settings.toggleVisibility(uniqueKey);
    await _saveSettings();
  }

  /// 重新排序分类
  Future<void> reorder(int oldIndex, int newIndex) async {
    await init();
    _currentSettings = settings.reorder(oldIndex, newIndex);
    await _saveSettings();
  }

  /// 添加类型分类
  Future<void> addGenre(String genre) async {
    await init();
    _currentSettings = settings.addGenre(genre);
    await _saveSettings();
  }

  /// 移除类型分类
  Future<void> removeGenre(String genre) async {
    await init();
    _currentSettings = settings.removeGenre(genre);
    await _saveSettings();
  }

  /// 更新完整设置
  Future<void> updateSettings(VideoCategorySettings newSettings) async {
    await init();
    _currentSettings = newSettings;
    await _saveSettings();
  }

  /// 重置为默认
  Future<void> resetToDefaults() async {
    await init();
    _currentSettings = VideoCategorySettings.defaults();
    await _saveSettings();
  }

  /// 关闭
  Future<void> close() async {
    await _settingsController.close();
    await _box?.close();
  }
}
