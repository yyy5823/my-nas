import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 认证凭证存储服务
///
/// 使用安全存储来保存用户凭证和设备信息
class AuthStorageService {
  AuthStorageService()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(
            encryptedSharedPreferences: true,
          ),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
          mOptions: MacOsOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );

  final FlutterSecureStorage _storage;

  // 存储键
  static const _keyCredentials = 'auth_credentials';
  static const _keyDeviceId = 'auth_device_id';
  static const _keyRememberLogin = 'auth_remember_login';
  static const _keyRememberDevice = 'auth_remember_device';
  static const _keyLastConnectionId = 'auth_last_connection_id';

  /// 获取设备名称
  String get deviceName {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'MyNAS-Client';
    }
  }

  /// 保存登录凭证
  Future<void> saveCredentials({
    required String connectionId,
    required String username,
    required String password,
  }) async {
    logger.i('AuthStorageService: 保存凭证 for $connectionId');

    final credentials = {
      'connectionId': connectionId,
      'username': username,
      'password': password,
      'savedAt': DateTime.now().toIso8601String(),
    };

    await _storage.write(
      key: _keyCredentials,
      value: jsonEncode(credentials),
    );
    await _storage.write(
      key: _keyLastConnectionId,
      value: connectionId,
    );
  }

  /// 获取保存的凭证
  Future<SavedCredentials?> getCredentials() async {
    final data = await _storage.read(key: _keyCredentials);
    if (data == null) return null;

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      return SavedCredentials(
        connectionId: json['connectionId'] as String,
        username: json['username'] as String,
        password: json['password'] as String,
      );
    } catch (e) {
      logger.e('AuthStorageService: 解析凭证失败', e);
      return null;
    }
  }

  /// 清除保存的凭证
  Future<void> clearCredentials() async {
    logger.i('AuthStorageService: 清除凭证');
    await _storage.delete(key: _keyCredentials);
    await _storage.delete(key: _keyLastConnectionId);
  }

  /// 保存设备ID（用于跳过二次验证）
  Future<void> saveDeviceId(String connectionId, String deviceId) async {
    logger.i('AuthStorageService: 保存设备ID for $connectionId');

    // 读取现有设备ID映射
    final existing = await _getDeviceIdMap();
    existing[connectionId] = deviceId;

    await _storage.write(
      key: _keyDeviceId,
      value: jsonEncode(existing),
    );
  }

  /// 获取设备ID
  Future<String?> getDeviceId(String connectionId) async {
    final deviceMap = await _getDeviceIdMap();
    return deviceMap[connectionId];
  }

  Future<Map<String, String>> _getDeviceIdMap() async {
    final data = await _storage.read(key: _keyDeviceId);
    if (data == null) return {};

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      return json.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  /// 清除特定连接的设备ID
  Future<void> clearDeviceId(String connectionId) async {
    logger.i('AuthStorageService: 清除设备ID for $connectionId');
    final existing = await _getDeviceIdMap();
    existing.remove(connectionId);
    await _storage.write(
      key: _keyDeviceId,
      value: jsonEncode(existing),
    );
  }

  /// 设置记住登录状态
  Future<void> setRememberLogin(bool value) async {
    await _storage.write(
      key: _keyRememberLogin,
      value: value.toString(),
    );

    // 如果关闭记住登录，清除凭证
    if (!value) {
      await clearCredentials();
    }
  }

  /// 获取记住登录状态
  Future<bool> getRememberLogin() async {
    final value = await _storage.read(key: _keyRememberLogin);
    return value == 'true';
  }

  /// 设置记住设备状态
  Future<void> setRememberDevice(bool value) async {
    await _storage.write(
      key: _keyRememberDevice,
      value: value.toString(),
    );
  }

  /// 获取记住设备状态
  Future<bool> getRememberDevice() async {
    final value = await _storage.read(key: _keyRememberDevice);
    return value == 'true';
  }

  /// 获取最后连接的ID
  Future<String?> getLastConnectionId() async {
    return _storage.read(key: _keyLastConnectionId);
  }

  /// 清除所有认证数据
  Future<void> clearAll() async {
    logger.i('AuthStorageService: 清除所有认证数据');
    await _storage.delete(key: _keyCredentials);
    await _storage.delete(key: _keyDeviceId);
    await _storage.delete(key: _keyRememberLogin);
    await _storage.delete(key: _keyRememberDevice);
    await _storage.delete(key: _keyLastConnectionId);
  }
}

/// 保存的凭证
class SavedCredentials {
  const SavedCredentials({
    required this.connectionId,
    required this.username,
    required this.password,
  });

  final String connectionId;
  final String username;
  final String password;
}
