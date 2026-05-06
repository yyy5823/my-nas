import 'dart:convert';
import 'dart:typed_data';

import 'package:my_nas/core/utils/logger.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

/// 云同步后端抽象。当前默认实现为 WebDAV，未来可加 Supabase / Firebase 等。
abstract class CloudSyncBackend {
  /// 后端可读时返回 true。失败 = 凭证错或网络不通。
  Future<bool> healthCheck();

  /// 读 manifest.json。404 视为首次同步，返回空 map。
  Future<Map<String, dynamic>> readManifest();

  /// 覆盖 manifest.json
  Future<void> writeManifest(Map<String, dynamic> manifest);

  /// 读模块数据。404 返回 null。
  Future<Map<String, dynamic>?> readModule(String key);

  /// 覆盖模块数据
  Future<void> writeModule(String key, Map<String, dynamic> data);

  /// 删除模块文件（用于完整 reset 同步）
  Future<void> deleteModule(String key);
}

/// WebDAV 实现。文件结构：
/// ```
/// /<rootPath>/manifest.json
/// /<rootPath>/<module-key>.json
/// ```
class WebDavCloudSyncBackend implements CloudSyncBackend {
  WebDavCloudSyncBackend({
    required this.endpoint,
    required this.username,
    required this.password,
    this.rootPath = '/my-nas-sync',
  });

  final String endpoint;
  final String username;
  final String password;
  final String rootPath;

  webdav.Client? _client;

  webdav.Client _ensureClient() {
    final c = _client ??= webdav.newClient(
      endpoint,
      user: username,
      password: password,
    );
    return c;
  }

  String _path(String name) {
    final base = rootPath.endsWith('/') ? rootPath : '$rootPath/';
    return '$base$name';
  }

  @override
  Future<bool> healthCheck() async {
    try {
      final c = _ensureClient();
      await c.ping();
      // 确保根目录存在
      try {
        await c.mkdir(rootPath);
      } on Exception catch (_) {/* 已存在视为正常 */}
      return true;
    } on Exception catch (e) {
      logger.w('WebDavSync: 健康检查失败 $e');
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> readManifest() => _readJson('manifest.json');

  @override
  Future<void> writeManifest(Map<String, dynamic> manifest) =>
      _writeJson('manifest.json', manifest);

  @override
  Future<Map<String, dynamic>?> readModule(String key) async {
    final m = await _readJson('$key.json');
    return m.isEmpty ? null : m;
  }

  @override
  Future<void> writeModule(String key, Map<String, dynamic> data) =>
      _writeJson('$key.json', data);

  @override
  Future<void> deleteModule(String key) async {
    try {
      final c = _ensureClient();
      await c.remove(_path('$key.json'));
    } on Exception catch (e) {
      logger.w('WebDavSync: 删除 $key 失败 $e');
    }
  }

  Future<Map<String, dynamic>> _readJson(String name) async {
    try {
      final c = _ensureClient();
      final bytes = await c.read(_path(name));
      if (bytes.isEmpty) return <String, dynamic>{};
      final str = utf8.decode(bytes);
      final decoded = jsonDecode(str);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    } on Exception catch (e) {
      // 404 / 不存在视为空
      logger.d('WebDavSync: 读 $name 失败（视为空）$e');
      return <String, dynamic>{};
    }
  }

  Future<void> _writeJson(String name, Map<String, dynamic> data) async {
    final c = _ensureClient();
    final str = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = Uint8List.fromList(utf8.encode(str));
    // 确保根目录存在
    try {
      await c.mkdir(rootPath);
    } on Exception catch (_) {/* 已存在视为正常 */}
    await c.write(_path(name), bytes);
  }
}
