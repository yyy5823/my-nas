import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 设备信息帮助类
/// @author cq
/// @date 2025-12-08
class DeviceInfoHelper {
  DeviceInfoHelper._();

  static final DeviceInfoHelper _instance = DeviceInfoHelper._();
  static DeviceInfoHelper get instance => _instance;

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  String? _deviceId;
  String? _deviceModel;
  String? _osName;
  String? _osVersion;
  String? _appVersion;
  bool _initialized = false;

  String? get deviceId => _deviceId;
  String? get deviceModel => _deviceModel;
  String? get osName => _osName;
  String? get osVersion => _osVersion;
  String? get appVersion => _appVersion;

  /// 初始化设备信息
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _loadDeviceInfo();
      await _loadAppVersion();
      _initialized = true;
    } on Exception catch (e) {
      if (kDebugMode) {
        print('[DeviceInfoHelper] Failed to initialize: $e');
      }
    }
  }

  Future<void> _loadDeviceInfo() async {
    if (kIsWeb) {
      final webInfo = await _deviceInfo.webBrowserInfo;
      _deviceId = webInfo.userAgent?.hashCode.toString();
      _deviceModel = webInfo.browserName.name;
      _osName = 'Web';
      _osVersion = webInfo.appVersion;
    } else if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      _deviceId = androidInfo.id;
      _deviceModel = '${androidInfo.brand} ${androidInfo.model}';
      _osName = 'Android';
      _osVersion = androidInfo.version.release;
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      _deviceId = iosInfo.identifierForVendor;
      _deviceModel = iosInfo.utsname.machine;
      _osName = 'iOS';
      _osVersion = iosInfo.systemVersion;
    } else if (Platform.isMacOS) {
      final macInfo = await _deviceInfo.macOsInfo;
      _deviceId = macInfo.systemGUID;
      _deviceModel = macInfo.model;
      _osName = 'macOS';
      _osVersion = '${macInfo.majorVersion}.${macInfo.minorVersion}.${macInfo.patchVersion}';
    } else if (Platform.isWindows) {
      final windowsInfo = await _deviceInfo.windowsInfo;
      _deviceId = windowsInfo.deviceId;
      _deviceModel = windowsInfo.productName;
      _osName = 'Windows';
      _osVersion = '${windowsInfo.majorVersion}.${windowsInfo.minorVersion}.${windowsInfo.buildNumber}';
    } else if (Platform.isLinux) {
      final linuxInfo = await _deviceInfo.linuxInfo;
      _deviceId = linuxInfo.machineId;
      _deviceModel = linuxInfo.prettyName;
      _osName = 'Linux';
      _osVersion = linuxInfo.versionId;
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    } on Exception catch (e) {
      if (kDebugMode) {
        print('[DeviceInfoHelper] Failed to load app version: $e');
      }
      _appVersion = '1.0.0';
    }
  }
}
