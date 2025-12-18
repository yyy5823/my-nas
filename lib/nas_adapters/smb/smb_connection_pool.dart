import 'dart:async';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:smb_connect/smb_connect.dart';

/// SMB 连接类型
enum SmbConnectionType {
  /// 通用操作（目录列表、文件信息等短操作）
  general,

  /// 流式传输（视频播放、文件下载等长操作）
  streaming,

  /// 后台任务（刮削、扫描等批量操作）
  background,
}

/// 连接池中的连接包装
class _PooledConnection {
  _PooledConnection({
    required this.client,
    required this.type,
  }) : createdAt = DateTime.now();

  final SmbConnect client;
  final SmbConnectionType type;
  final DateTime createdAt;

  bool _inUse = false;
  DateTime? _lastUsedAt;

  bool get inUse => _inUse;
  DateTime? get lastUsedAt => _lastUsedAt;

  /// 连接空闲时间
  Duration get idleTime =>
      DateTime.now().difference(_lastUsedAt ?? createdAt);

  /// 标记为使用中
  void acquire() {
    _inUse = true;
    _lastUsedAt = DateTime.now();
  }

  /// 释放连接
  void release() {
    _inUse = false;
    _lastUsedAt = DateTime.now();
  }

  /// 检查连接是否健康
  Future<bool> isHealthy() async {
    try {
      // 尝试列出共享来验证连接
      await client.listShares().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('连接检查超时'),
      );
      return true;
    // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      logger.w('SMB 连接健康检查失败', e,  st);
      return false;
    }
  }
}

/// SMB 连接池
///
/// 管理多个 SMB 连接，支持并发操作：
/// - 短操作（目录浏览）共享 general 连接
/// - 长操作（视频流）使用独占的 streaming 连接
/// - 后台任务（刮削）使用独立的 background 连接
class SmbConnectionPool {
  SmbConnectionPool({
    required this.host,
    required this.username,
    required this.password,
    this.domain = '',
    this.maxConnections = 5,
    this.maxDedicatedConnections = 8,
    this.maxIdleTime = const Duration(minutes: 5),
  });

  final String host;
  final String username;
  final String password;
  final String domain;
  final int maxConnections;
  final int maxDedicatedConnections;
  final Duration maxIdleTime;

  final List<_PooledConnection> _connections = [];
  final _lock = _AsyncLock();
  bool _disposed = false;

  /// 当前专用连接数
  int _dedicatedConnectionCount = 0;
  final _dedicatedLock = _AsyncLock();

  /// 当前连接数
  int get connectionCount => _connections.length;

  /// 活跃连接数
  int get activeConnectionCount => _connections.where((c) => c.inUse).length;

  /// 获取连接
  ///
  /// [type] 连接类型，用于区分不同用途的连接
  /// [exclusive] 是否需要独占连接（用于长操作）
  Future<SmbConnect> acquire({
    SmbConnectionType type = SmbConnectionType.general,
    bool exclusive = false,
  }) async {
    if (_disposed) {
      throw StateError('连接池已关闭');
    }

    return _lock.synchronized(() async {
      // 1. 尝试复用现有空闲连接（非独占模式）
      if (!exclusive) {
        final idle = _connections.where(
          (c) => !c.inUse && c.type == type,
        ).toList();

        for (final conn in idle) {
          // 检查连接是否过期
          if (conn.idleTime > maxIdleTime) {
            await _removeConnection(conn);
            continue;
          }

          conn.acquire();
          // logger.d('SMB Pool: 复用 $type 连接 (活跃: $activeConnectionCount/$connectionCount)');
          return conn.client;
        }
      }

      // 2. 创建新连接（如果未达上限）
      if (_connections.length < maxConnections) {
        final newConn = await _createConnection(type);
        newConn.acquire();
        logger.i('SMB Pool: 创建新 $type 连接 (活跃: $activeConnectionCount/$connectionCount)');
        return newConn.client;
      }

      // 3. 等待空闲连接（独占模式或已达上限）
      logger.d('SMB Pool: 等待空闲连接...');
      return _waitForConnection(type, exclusive);
    });
  }

  /// 释放连接
  void release(SmbConnect client) {
    _connections
        .firstWhere(
          (c) => c.client == client,
          orElse: () => throw StateError('连接不在池中'),
        )
        .release();
    // logger.d('SMB Pool: 释放连接 (活跃: $activeConnectionCount/$connectionCount)');
  }

  /// 使用连接执行操作
  ///
  /// 自动获取和释放连接，确保连接正确归还
  Future<T> withConnection<T>(
    Future<T> Function(SmbConnect client) operation, {
    SmbConnectionType type = SmbConnectionType.general,
    bool exclusive = false,
  }) async {
    final client = await acquire(type: type, exclusive: exclusive);
    try {
      return await operation(client);
    } finally {
      release(client);
    }
  }

  /// 创建新连接
  Future<_PooledConnection> _createConnection(SmbConnectionType type) async {
    final client = await SmbConnect.connectAuth(
      host: host,
      domain: domain,
      username: username,
      password: password,
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('SMB 连接超时'),
    );

    final conn = _PooledConnection(client: client, type: type);
    _connections.add(conn);
    return conn;
  }

  /// 移除连接
  Future<void> _removeConnection(_PooledConnection conn) async {
    _connections.remove(conn);
    try {
      await conn.client.close();
    // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      logger.w('SMB Pool: 关闭连接失败', e, st);
    }
  }

  /// 等待空闲连接
  Future<SmbConnect> _waitForConnection(
    SmbConnectionType type,
    bool exclusive,
  ) async {
    const maxWait = Duration(seconds: 30);
    const checkInterval = Duration(milliseconds: 100);
    final deadline = DateTime.now().add(maxWait);

    while (DateTime.now().isBefore(deadline)) {
      // 检查是否有空闲连接
      final idle = _connections.where((c) => !c.inUse).toList();
      if (idle.isNotEmpty) {
        final conn = idle.first
        ..acquire();
        return conn.client;
      }

      await Future<void>.delayed(checkInterval);
    }

    throw TimeoutException('等待 SMB 连接超时');
  }

  /// 清理空闲连接
  Future<void> cleanup() async {
    await _lock.synchronized(() async {
      final toRemove = _connections.where(
        (c) => !c.inUse && c.idleTime > maxIdleTime,
      ).toList();

      for (final conn in toRemove) {
        await _removeConnection(conn);
      }

      if (toRemove.isNotEmpty) {
        logger.i('SMB Pool: 清理了 ${toRemove.length} 个空闲连接');
      }
    });
  }

  /// 获取一个专用连接（不放入池中，调用者负责关闭）
  ///
  /// 用于长时间运行的独占操作（如视频流传输）
  /// 会等待直到有可用的连接槽位
  ///
  /// 返回值包含连接和释放回调，调用者必须在完成后调用 releaseCallback
  Future<({SmbConnect client, void Function() releaseCallback})>
      createDedicatedConnection() async {
    // 等待连接槽位
    await _waitForDedicatedSlot();

    try {
      logger.i('SMB Pool: 创建专用连接 ($_dedicatedConnectionCount/$maxDedicatedConnections)');
      final client = await SmbConnect.connectAuth(
        host: host,
        domain: domain,
        username: username,
        password: password,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('SMB 连接超时'),
      );

      return (client: client, releaseCallback: _releaseDedicatedSlot);
    } catch (e) {
      // 创建失败，释放槽位
      _releaseDedicatedSlot();
      rethrow;
    }
  }

  /// 等待专用连接槽位
  Future<void> _waitForDedicatedSlot() async {
    const maxWait = Duration(seconds: 60);
    const checkInterval = Duration(milliseconds: 100);
    final deadline = DateTime.now().add(maxWait);

    while (DateTime.now().isBefore(deadline)) {
      final acquired = await _dedicatedLock.synchronized(() async {
        if (_dedicatedConnectionCount < maxDedicatedConnections) {
          _dedicatedConnectionCount++;
          return true;
        }
        return false;
      });

      if (acquired) return;
      await Future<void>.delayed(checkInterval);
    }

    throw TimeoutException('等待专用连接槽位超时');
  }

  /// 释放专用连接槽位
  void _releaseDedicatedSlot() {
    _dedicatedConnectionCount--;
    logger.d('SMB Pool: 释放专用连接槽位 ($_dedicatedConnectionCount/$maxDedicatedConnections)');
  }

  /// 关闭连接池
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _lock.synchronized(() async {
      for (final conn in _connections) {
        try {
          await conn.client.close();
        // ignore: avoid_catches_without_on_clauses
        } catch (e, st) {
          AppError.ignore(e, StackTrace.current, 'SMB Pool: 关闭连接失败, $e $st');
        }
      }
      _connections.clear();
    });

    logger.i('SMB Pool: 连接池已关闭');
  }
}

/// 简单的异步锁
class _AsyncLock {
  Completer<void>? _completer;

  Future<T> synchronized<T>(Future<T> Function() action) async {
    while (_completer != null) {
      await _completer!.future;
    }

    _completer = Completer<void>();
    try {
      return await action();
    } finally {
      final completer = _completer;
      _completer = null;
      completer?.complete();
    }
  }
}
