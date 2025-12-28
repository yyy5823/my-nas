import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:my_nas/core/services/error_report/error_report_settings.dart';
import 'package:my_nas/core/utils/hive_utils.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 日志上报设置服务
/// 管理日志上报的配置，使用 Hive 持久化存储
/// @author cq
/// @date 2025-12-28
class ErrorReportSettingsService {
  ErrorReportSettingsService._();

  static final ErrorReportSettingsService _instance = ErrorReportSettingsService._();
  static ErrorReportSettingsService get instance => _instance;

  static const String _storageKey = 'error_report_settings';

  ErrorReportSettings _settings = const ErrorReportSettings();

  /// 当前设置
  ErrorReportSettings get settings => _settings;

  /// 是否启用日志上报
  bool get isEnabled => _settings.enabled;

  /// 初始化服务
  Future<void> initialize() async {
    await _loadSettings();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final jsonStr = box.get(_storageKey) as String?;

      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _settings = ErrorReportSettings.fromJson(json);
        if (kDebugMode) {
          logger.d('[ErrorReportSettingsService] Loaded settings: $_settings');
        }
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        logger.w('[ErrorReportSettingsService] Failed to load settings: $e');
      }
    }
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final jsonStr = jsonEncode(_settings.toJson());
      await box.put(_storageKey, jsonStr);
      if (kDebugMode) {
        logger.d('[ErrorReportSettingsService] Saved settings: $_settings');
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        logger.w('[ErrorReportSettingsService] Failed to save settings: $e');
      }
    }
  }

  /// 更新设置
  Future<void> updateSettings(ErrorReportSettings newSettings) async {
    _settings = newSettings;
    await _saveSettings();
  }

  /// 设置总开关
  Future<void> setEnabled(bool enabled) async {
    _settings = _settings.copyWith(enabled: enabled);
    await _saveSettings();
  }

  /// 设置是否上报设备ID
  Future<void> setIncludeDeviceId(bool include) async {
    _settings = _settings.copyWith(includeDeviceId: include);
    await _saveSettings();
  }

  /// 设置是否上报设备型号
  Future<void> setIncludeDeviceModel(bool include) async {
    _settings = _settings.copyWith(includeDeviceModel: include);
    await _saveSettings();
  }

  /// 设置是否上报设备品牌
  Future<void> setIncludeDeviceBrand(bool include) async {
    _settings = _settings.copyWith(includeDeviceBrand: include);
    await _saveSettings();
  }

  /// 设置是否上报操作系统信息
  Future<void> setIncludeOsInfo(bool include) async {
    _settings = _settings.copyWith(includeOsInfo: include);
    await _saveSettings();
  }

  /// 设置是否上报屏幕分辨率
  Future<void> setIncludeScreenResolution(bool include) async {
    _settings = _settings.copyWith(includeScreenResolution: include);
    await _saveSettings();
  }

  /// 设置是否上报应用版本
  Future<void> setIncludeAppVersion(bool include) async {
    _settings = _settings.copyWith(includeAppVersion: include);
    await _saveSettings();
  }

  /// 设置是否上报用户信息
  Future<void> setIncludeUserId(bool include) async {
    _settings = _settings.copyWith(includeUserId: include);
    await _saveSettings();
  }

  /// 设置是否上报网络类型
  Future<void> setIncludeNetworkType(bool include) async {
    _settings = _settings.copyWith(includeNetworkType: include);
    await _saveSettings();
  }

  /// 设置是否上报页面路由
  Future<void> setIncludePageRoute(bool include) async {
    _settings = _settings.copyWith(includePageRoute: include);
    await _saveSettings();
  }

  /// 设置是否上报操作名称
  Future<void> setIncludeAction(bool include) async {
    _settings = _settings.copyWith(includeAction: include);
    await _saveSettings();
  }

  /// 设置是否上报堆栈跟踪
  Future<void> setIncludeStackTrace(bool include) async {
    _settings = _settings.copyWith(includeStackTrace: include);
    await _saveSettings();
  }

  /// 设置是否上报额外数据
  Future<void> setIncludeExtraData(bool include) async {
    _settings = _settings.copyWith(includeExtraData: include);
    await _saveSettings();
  }

  /// 重置为默认设置
  Future<void> resetToDefaults() async {
    _settings = const ErrorReportSettings();
    await _saveSettings();
  }

  /// 开启所有字段
  Future<void> enableAllFields() async {
    _settings = _settings.copyWith(
      includeDeviceId: true,
      includeDeviceModel: true,
      includeDeviceBrand: true,
      includeOsInfo: true,
      includeScreenResolution: true,
      includeAppVersion: true,
      includeUserId: true,
      includeNetworkType: true,
      includePageRoute: true,
      includeAction: true,
      includeStackTrace: true,
      includeExtraData: true,
    );
    await _saveSettings();
  }

  /// 关闭所有字段
  Future<void> disableAllFields() async {
    _settings = _settings.copyWith(
      includeDeviceId: false,
      includeDeviceModel: false,
      includeDeviceBrand: false,
      includeOsInfo: false,
      includeScreenResolution: false,
      includeAppVersion: false,
      includeUserId: false,
      includeNetworkType: false,
      includePageRoute: false,
      includeAction: false,
      includeStackTrace: false,
      includeExtraData: false,
    );
    await _saveSettings();
  }
}
