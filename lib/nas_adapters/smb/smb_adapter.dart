import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/smb/smb_connection_pool.dart';
import 'package:my_nas/nas_adapters/smb/smb_file_system.dart';
import 'package:my_nas/nas_adapters/smb/smb_pool_config.dart';
import 'package:smb_connect/smb_connect.dart';

/// SMB/CIFS NAS 适配器
///
/// 使用 smb_connect 库实现 SMB 协议连接
/// 支持 SMB 1.0, CIFS, SMB 2.0, SMB 2.1
///
/// 特性：
/// - 连接池管理：支持多连接并发，避免操作争用
/// - 自动重连：连接断开时自动重新建立
/// - 任务隔离：视频播放使用独立连接，不影响其他操作
class SmbAdapter implements NasAdapter {
  SmbAdapter() {
    logger.i('SmbAdapter: 初始化适配器');
  }

  SmbConnect? _client;
  SmbConnectionPool? _connectionPool;
  SmbFileSystem? _fileSystem;
  ConnectionConfig? _config;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.smb,
        name: 'SMB/CIFS',
        version: AppConstants.appVersion,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger..i('SmbAdapter: 开始连接')
    ..i('SmbAdapter: 目标地址 => ${config.host}:${config.port}')
    ..i('SmbAdapter: 用户名 => ${config.username}');

    _config = config;

    // 清理主机地址 - 移除可能存在的协议前缀
    var host = config.host.trim();
    if (host.startsWith('http://')) {
      host = host.substring(7);
      logger.w('SmbAdapter: 移除 http:// 前缀');
    }
    if (host.startsWith('https://')) {
      host = host.substring(8);
      logger.w('SmbAdapter: 移除 https:// 前缀');
    }
    if (host.startsWith('smb://')) {
      host = host.substring(6);
      logger.w('SmbAdapter: 移除 smb:// 前缀');
    }
    // 移除尾部的斜杠和端口
    if (host.contains('/')) {
      host = host.split('/').first;
    }
    if (host.contains(':')) {
      host = host.split(':').first;
    }

    logger.i('SmbAdapter: 清理后的主机地址 => $host');

    try {
      // SMB 连接使用 IP 地址（端口由系统处理，默认 445）
      logger.d('SmbAdapter: 正在建立 SMB 连接...');

      // 添加连接超时
      _client = await SmbConnect.connectAuth(
        host: host,
        domain: '', // 工作组/域，通常留空
        username: config.username,
        password: config.password,
        // debugPrint: true, // 禁用调试输出，避免日志刷屏
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('SMB 连接超时 (30秒)');
        },
      );

      logger.d('SmbAdapter: SMB 连接已建立，正在获取共享列表...');

      // 测试连接 - 获取共享列表 (带超时)
      final shares = await _client!.listShares().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('获取共享列表超时');
        },
      );
      logger.i('SmbAdapter: 连接成功，发现 ${shares.length} 个共享');

      for (final share in shares) {
        logger.d('SmbAdapter: 共享 => ${share.name} (${share.path})');
      }

      // 创建连接池（根据平台动态配置）
      logger.i('SmbAdapter: ${SmbPoolConfig.summary}');
      _connectionPool = SmbConnectionPool(
        host: host,
        username: config.username,
        password: config.password,
        maxConnections: SmbPoolConfig.maxConnections,
        maxDedicatedConnections: SmbPoolConfig.maxDedicatedConnections,
        maxIdleTime: SmbPoolConfig.maxIdleTime,
      );

      _fileSystem = SmbFileSystem(
        client: _client!,
        connectionPool: _connectionPool,
      );
      _connected = true;

      return ConnectionSuccess(
        sessionId: 'smb-${DateTime.now().millisecondsSinceEpoch}',
        serverInfo: ServerInfo(
          hostname: host, // 使用清理后的主机地址
          model: 'SMB/CIFS Server',
        ),
      );
    // 使用通用 catch 捕获所有类型的异常（包括 SMB 库抛出的 String 异常）
    // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      logger.e('SmbAdapter: 连接失败', e, stackTrace);
      _connected = false;
      return ConnectionFailure(error: _parseErrorAny(e));
    }
  }

  // ignore: unused_element
  String _parseError(Exception e) => _parseErrorAny(e);

  String _parseErrorAny(dynamic e) {
    // 优先处理 SmbAuthException - 认证失败
    if (e.runtimeType.toString() == 'SmbAuthException') {
      return 'SMB 认证失败\n用户名或密码错误';
    }

    final msg = e.toString().toLowerCase();
    logger.d('SmbAdapter: 解析错误消息 => $msg');

    // SmbAuthException 的字符串匹配（备用）
    if (msg.contains('smbauthexception')) {
      return 'SMB 认证失败\n用户名或密码错误';
    }

    // 连接相关错误
    if (msg.contains('connection refused')) {
      return 'SMB 连接被拒绝\n请检查：\n• SMB 服务是否启用\n• 端口 445 是否开放\n• 防火墙设置';
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return 'SMB 连接超时\n请检查：\n• 服务器地址是否正确\n• 网络是否连通\n• 服务器是否在线';
    }
    if (msg.contains('host not found') ||
        msg.contains('no address') ||
        msg.contains('getaddrinfo') ||
        msg.contains('nodename nor servname')) {
      return 'SMB 服务器地址无法解析\n请检查：\n• 服务器地址是否正确\n• DNS 设置是否正确';
    }
    if (msg.contains('network is unreachable') ||
        msg.contains('no route to host')) {
      return 'SMB 网络不可达\n请检查：\n• 网络连接是否正常\n• 是否在同一网络';
    }
    // 连接已关闭错误 (StreamSink closed)
    if (msg.contains('streamsink is closed') ||
        msg.contains('stream is closed') ||
        msg.contains('connection closed') ||
        msg.contains('socket closed')) {
      return 'SMB 连接已断开\n请检查网络连接后重试';
    }

    // 认证相关错误
    if (msg.contains('status_logon_failure') ||
        msg.contains('logon failure') ||
        msg.contains('authentication failed')) {
      return 'SMB 认证失败\n用户名或密码错误';
    }
    if (msg.contains('status_access_denied') ||
        msg.contains('access denied') ||
        msg.contains('permission denied')) {
      return 'SMB 访问被拒绝\n请检查用户权限';
    }
    if (msg.contains('status_account_disabled')) {
      return 'SMB 账户已禁用\n请联系管理员启用账户';
    }
    if (msg.contains('status_account_locked')) {
      return 'SMB 账户已锁定\n请稍后重试或联系管理员';
    }
    if (msg.contains('status_password_expired')) {
      return 'SMB 密码已过期\n请更新密码后重试';
    }

    // SMB 协议错误
    if (msg.contains("can't connect")) {
      return 'SMB 无法连接到服务器\n请检查服务器地址和网络';
    }
    if (msg.contains('invalid parameter') ||
        msg.contains('bad network name') ||
        msg.contains('status_bad_network_name')) {
      return 'SMB 网络名称无效\n请检查共享名称是否正确';
    }
    if (msg.contains('not supported') || msg.contains('status_not_supported')) {
      return 'SMB 协议版本不支持\n服务器可能不支持 SMB 2.x';
    }

    // 默认错误消息
    final originalMsg = e.toString();
    if (originalMsg.length > 100) {
      return 'SMB 连接失败\n${originalMsg.substring(0, 100)}...';
    }
    return 'SMB 连接失败\n$originalMsg';
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;

    try {
      // 先关闭连接池
      await _connectionPool?.dispose();
      // 再关闭主连接
      await _client?.close();
    // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      logger.w('SmbAdapter: 断开连接时出错', e);
    }

    _connectionPool = null;
    _client = null;
    _fileSystem = null;
    _connected = false;
    _config = null;
    logger.i('SmbAdapter: 已断开连接');
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected || _fileSystem == null) {
      throw StateError('未连接到 SMB 服务器');
    }
    return _fileSystem!;
  }

  @override
  MediaService? get mediaService => null;

  @override
  ToolsService? get toolsService => null;

  @override
  Future<void> dispose() async {
    await disconnect();
  }
}
