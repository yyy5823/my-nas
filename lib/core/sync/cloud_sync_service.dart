import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/sync/cloud_sync_backend.dart';
import 'package:my_nas/core/sync/syncable_module.dart';

/// 同步设置：WebDAV 凭证 + 启用的模块 key 列表。
class CloudSyncSettings {
  const CloudSyncSettings({
    this.endpoint,
    this.username,
    this.password,
    this.rootPath = '/my-nas-sync',
    this.enabledModuleKeys = const {},
    this.lastSyncedAt,
  });

  factory CloudSyncSettings.fromMap(Map<dynamic, dynamic> m) =>
      CloudSyncSettings(
        endpoint: m['endpoint'] as String?,
        username: m['username'] as String?,
        password: m['password'] as String?,
        rootPath: (m['rootPath'] as String?) ?? '/my-nas-sync',
        enabledModuleKeys: ((m['enabledModuleKeys'] as List?) ?? const [])
            .cast<String>()
            .toSet(),
        lastSyncedAt: m['lastSyncedAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(m['lastSyncedAt'] as int)
            : null,
      );

  final String? endpoint;
  final String? username;
  final String? password;
  final String rootPath;
  final Set<String> enabledModuleKeys;
  final DateTime? lastSyncedAt;

  bool get isConfigured =>
      (endpoint?.isNotEmpty ?? false) &&
      (username?.isNotEmpty ?? false) &&
      (password?.isNotEmpty ?? false);

  Map<String, dynamic> toMap() => {
        if (endpoint != null) 'endpoint': endpoint,
        if (username != null) 'username': username,
        if (password != null) 'password': password,
        'rootPath': rootPath,
        'enabledModuleKeys': enabledModuleKeys.toList(),
        if (lastSyncedAt != null)
          'lastSyncedAt': lastSyncedAt!.millisecondsSinceEpoch,
      };

  CloudSyncSettings copyWith({
    Object? endpoint = const Object(),
    Object? username = const Object(),
    Object? password = const Object(),
    String? rootPath,
    Set<String>? enabledModuleKeys,
    Object? lastSyncedAt = const Object(),
  }) =>
      CloudSyncSettings(
        endpoint: identical(endpoint, const Object())
            ? this.endpoint
            : endpoint as String?,
        username: identical(username, const Object())
            ? this.username
            : username as String?,
        password: identical(password, const Object())
            ? this.password
            : password as String?,
        rootPath: rootPath ?? this.rootPath,
        enabledModuleKeys: enabledModuleKeys ?? this.enabledModuleKeys,
        lastSyncedAt: identical(lastSyncedAt, const Object())
            ? this.lastSyncedAt
            : lastSyncedAt as DateTime?,
      );
}

/// 同步结果（每模块）
class CloudSyncReport {
  CloudSyncReport({
    required this.moduleKey,
    required this.outcome,
    this.error,
  });
  final String moduleKey;
  final CloudSyncOutcome outcome;
  final String? error;
}

enum CloudSyncOutcome {
  pulled, // 远端更新，已应用到本地
  pushed, // 本地更新，已上传
  skipped, // 双方一致或本地无变更
  failed,
}

/// 中心同步服务。当前实现 WebDAV 后端。
///
/// 同步流程：
/// 1. healthCheck → 失败直接返回
/// 2. 读 manifest.json
/// 3. 对每个 enabled module:
///    - 比较 local.updatedAt 与 manifest[key].updatedAt
///    - local 更新 → exportData 上传 + manifest 更新
///    - remote 更新 → readModule + importData
///    - 一致 → skip
/// 4. 写回 manifest.json
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  static const String _boxName = 'cloud_sync_settings';
  static const String _key = 'settings';

  Box<dynamic>? _box;
  CloudSyncSettings _settings = const CloudSyncSettings();
  bool _initialized = false;
  bool _syncing = false;

  Future<void> init() async {
    if (_initialized) return;
    _box = await Hive.openBox<dynamic>(_boxName);
    final raw = _box!.get(_key);
    if (raw is Map) {
      _settings = CloudSyncSettings.fromMap(raw);
    }
    _initialized = true;
  }

  CloudSyncSettings get settings => _settings;

  bool get isSyncing => _syncing;

  Future<void> applySettings(CloudSyncSettings next) async {
    await init();
    _settings = next;
    await _box?.put(_key, next.toMap());
  }

  CloudSyncBackend? _buildBackend() {
    if (!_settings.isConfigured) return null;
    return WebDavCloudSyncBackend(
      endpoint: _settings.endpoint!,
      username: _settings.username!,
      password: _settings.password!,
      rootPath: _settings.rootPath,
    );
  }

  /// 触发一次同步。返回每模块结果。
  Future<List<CloudSyncReport>> syncNow() async {
    await init();
    if (_syncing) return const [];
    _syncing = true;
    final reports = <CloudSyncReport>[];
    try {
      final backend = _buildBackend();
      if (backend == null) {
        return [
          CloudSyncReport(
            moduleKey: '*',
            outcome: CloudSyncOutcome.failed,
            error: '未配置同步凭证',
          ),
        ];
      }
      final ok = await backend.healthCheck();
      if (!ok) {
        return [
          CloudSyncReport(
            moduleKey: '*',
            outcome: CloudSyncOutcome.failed,
            error: '无法连接到 WebDAV',
          ),
        ];
      }
      final manifest = await backend.readManifest();
      final newManifest = Map<String, dynamic>.from(manifest);

      for (final module in CloudSyncRegistry.instance.modules) {
        if (!_settings.enabledModuleKeys.contains(module.key)) continue;
        final report = await _syncModule(module, backend, manifest, newManifest);
        reports.add(report);
      }

      await backend.writeManifest(newManifest);
      await applySettings(_settings.copyWith(lastSyncedAt: DateTime.now()));
    } finally {
      _syncing = false;
    }
    return reports;
  }

  Future<CloudSyncReport> _syncModule(
    SyncableModule module,
    CloudSyncBackend backend,
    Map<String, dynamic> manifest,
    Map<String, dynamic> newManifest,
  ) async {
    try {
      final remoteEntry = manifest[module.key];
      DateTime? remoteAt;
      if (remoteEntry is Map && remoteEntry['updatedAt'] is int) {
        remoteAt = DateTime.fromMillisecondsSinceEpoch(
          remoteEntry['updatedAt'] as int,
        );
      }
      final localAt = await module.getLocalUpdatedAt();

      if (localAt == null && remoteAt == null) {
        return CloudSyncReport(
          moduleKey: module.key,
          outcome: CloudSyncOutcome.skipped,
        );
      }

      if (remoteAt != null &&
          (localAt == null || remoteAt.isAfter(localAt))) {
        // 远端更新 → 拉取
        final data = await backend.readModule(module.key);
        if (data != null) {
          await module.importData(data);
          newManifest[module.key] = {
            'updatedAt': remoteAt.millisecondsSinceEpoch,
          };
          return CloudSyncReport(
            moduleKey: module.key,
            outcome: CloudSyncOutcome.pulled,
          );
        }
      }

      if (localAt != null &&
          (remoteAt == null || localAt.isAfter(remoteAt))) {
        // 本地更新 → 推送
        final data = await module.exportData();
        await backend.writeModule(module.key, data);
        newManifest[module.key] = {
          'updatedAt': localAt.millisecondsSinceEpoch,
        };
        return CloudSyncReport(
          moduleKey: module.key,
          outcome: CloudSyncOutcome.pushed,
        );
      }

      // 一致 → 保留 manifest
      if (remoteAt != null) {
        newManifest[module.key] = {
          'updatedAt': remoteAt.millisecondsSinceEpoch,
        };
      }
      return CloudSyncReport(
        moduleKey: module.key,
        outcome: CloudSyncOutcome.skipped,
      );
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'cloudSync.${module.key}');
      return CloudSyncReport(
        moduleKey: module.key,
        outcome: CloudSyncOutcome.failed,
        error: e.toString(),
      );
    }
  }

  /// 健康检查：用户在设置页点「测试连接」时调
  Future<bool> testConnection() async {
    final backend = _buildBackend();
    if (backend == null) return false;
    return backend.healthCheck();
  }
}
