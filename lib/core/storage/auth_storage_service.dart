import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 安全存储异常
///
/// 当 Keychain/安全存储不可用时抛出
class SecureStorageException implements Exception {
  const SecureStorageException(this.message, {this.originalError});

  final String message;
  final Object? originalError;

  @override
  String toString() => message;

  /// 是否是 Keychain entitlement 错误
  bool get isKeychainEntitlementError {
    final error = originalError;
    if (error is PlatformException) {
      // macOS/iOS Keychain entitlement 错误码
      return error.code == 'Unexpected security result code' ||
          (error.message?.contains('-34018') ?? false) ||
          (error.message?.contains('entitlement') ?? false);
    }
    return false;
  }
}

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

  /// 安全存储是否可用
  bool _storageAvailable = true;

  /// 检查并处理存储错误
  ///
  /// 返回 true 表示是可恢复的存储错误（应静默处理）
  /// 返回 false 表示其他错误（应重新抛出）
  bool _handleStorageError(Object error, String operation) {
    if (error is PlatformException) {
      // Keychain entitlement 错误 (-34018)
      if (error.code == 'Unexpected security result code' ||
          (error.message?.contains('-34018') ?? false)) {
        logger.w(
          'AuthStorageService: 安全存储不可用 ($operation) - '
          '可能缺少 Keychain entitlement 权限，自动登录功能已禁用',
        );
        _storageAvailable = false;
        return true;
      }
    }
    return false;
  }

  /// 安全执行存储读取操作
  Future<String?> _safeRead(String key) async {
    if (!_storageAvailable) return null;
    try {
      return await _storage.read(key: key);
    } catch (e) {
      if (_handleStorageError(e, 'read($key)')) {
        return null;
      }
      rethrow;
    }
  }

  /// 安全执行存储写入操作
  Future<bool> _safeWrite(String key, String value) async {
    if (!_storageAvailable) {
      logger.d('AuthStorageService: 存储不可用，跳过写入 $key');
      return false;
    }
    try {
      await _storage.write(key: key, value: value);
      return true;
    } catch (e) {
      if (_handleStorageError(e, 'write($key)')) {
        return false;
      }
      rethrow;
    }
  }

  /// 安全执行存储删除操作
  Future<bool> _safeDelete(String key) async {
    if (!_storageAvailable) return false;
    try {
      await _storage.delete(key: key);
      return true;
    } catch (e) {
      if (_handleStorageError(e, 'delete($key)')) {
        return false;
      }
      rethrow;
    }
  }

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
  ///
  /// 返回 true 表示保存成功，false 表示存储不可用
  Future<bool> saveCredentials({
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

    final success = await _safeWrite(_keyCredentials, jsonEncode(credentials));
    if (success) {
      await _safeWrite(_keyLastConnectionId, connectionId);
    }
    return success;
  }

  /// 获取保存的凭证
  Future<SavedCredentials?> getCredentials() async {
    final data = await _safeRead(_keyCredentials);
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
    await _safeDelete(_keyCredentials);
    await _safeDelete(_keyLastConnectionId);
  }

  /// 保存设备ID（用于跳过二次验证）
  ///
  /// 返回 true 表示保存成功，false 表示存储不可用
  Future<bool> saveDeviceId(String connectionId, String deviceId) async {
    logger.i('AuthStorageService: 保存设备ID for $connectionId');

    // 读取现有设备ID映射
    final existing = await _getDeviceIdMap();
    existing[connectionId] = deviceId;

    return _safeWrite(_keyDeviceId, jsonEncode(existing));
  }

  /// 获取设备ID
  Future<String?> getDeviceId(String connectionId) async {
    final deviceMap = await _getDeviceIdMap();
    return deviceMap[connectionId];
  }

  Future<Map<String, String>> _getDeviceIdMap() async {
    final data = await _safeRead(_keyDeviceId);
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
    await _safeWrite(_keyDeviceId, jsonEncode(existing));
  }

  /// 设置记住登录状态
  Future<void> setRememberLogin(bool value) async {
    await _safeWrite(_keyRememberLogin, value.toString());

    // 如果关闭记住登录，清除凭证
    if (!value) {
      await clearCredentials();
    }
  }

  /// 获取记住登录状态
  Future<bool> getRememberLogin() async {
    final value = await _safeRead(_keyRememberLogin);
    return value == 'true';
  }

  /// 设置记住设备状态
  Future<void> setRememberDevice(bool value) async {
    await _safeWrite(_keyRememberDevice, value.toString());
  }

  /// 获取记住设备状态
  Future<bool> getRememberDevice() async {
    final value = await _safeRead(_keyRememberDevice);
    return value == 'true';
  }

  /// 获取最后连接的ID
  Future<String?> getLastConnectionId() async => _safeRead(_keyLastConnectionId);

  /// 清除所有认证数据
  Future<void> clearAll() async {
    logger.i('AuthStorageService: 清除所有认证数据');
    await _safeDelete(_keyCredentials);
    await _safeDelete(_keyDeviceId);
    await _safeDelete(_keyRememberLogin);
    await _safeDelete(_keyRememberDevice);
    await _safeDelete(_keyLastConnectionId);
  }

  /// 检查安全存储是否可用
  bool get isStorageAvailable => _storageAvailable;
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
