import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/smb/smb_file_system.dart';
import 'package:smb_connect/smb_connect.dart';

/// SMB/CIFS NAS 适配器
///
/// 使用 smb_connect 库实现 SMB 协议连接
/// 支持 SMB 1.0, CIFS, SMB 2.0, SMB 2.1
class SmbAdapter implements NasAdapter {
  SmbAdapter() {
    logger.i('SmbAdapter: 初始化适配器');
  }

  SmbConnect? _client;
  SmbFileSystem? _fileSystem;
  ConnectionConfig? _config;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.smb,
        name: 'SMB/CIFS',
        version: AppConstants.appVersion,
        supportsMediaService: false,
        supportsToolsService: false,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger.i('SmbAdapter: 开始连接');
    logger.i('SmbAdapter: 目标地址 => ${config.host}:${config.port}');
    logger.i('SmbAdapter: 用户名 => ${config.username}');

    _config = config;

    try {
      // SMB 连接使用 IP 地址（端口由系统处理，默认 445）
      logger.d('SmbAdapter: 正在建立 SMB 连接...');
      _client = await SmbConnect.connectAuth(
        host: config.host,
        domain: '', // 工作组/域，通常留空
        username: config.username,
        password: config.password,
        debugPrint: true, // 启用调试输出
      );

      logger.d('SmbAdapter: SMB 连接已建立，正在获取共享列表...');

      // 测试连接 - 获取共享列表
      final shares = await _client!.listShares();
      logger.i('SmbAdapter: 连接成功，发现 ${shares.length} 个共享');

      for (final share in shares) {
        logger.d('SmbAdapter: 共享 => ${share.name} (${share.path})');
      }

      _fileSystem = SmbFileSystem(client: _client!);
      _connected = true;

      return ConnectionSuccess(
        sessionId: 'smb-${DateTime.now().millisecondsSinceEpoch}',
        serverInfo: ServerInfo(
          hostname: config.host,
          model: 'SMB/CIFS Server',
        ),
      );
    } on Exception catch (e, stackTrace) {
      logger.e('SmbAdapter: 连接失败', e, stackTrace);
      _connected = false;
      return ConnectionFailure(error: _parseError(e));
    } catch (e, stackTrace) {
      // 捕获非 Exception 类型的错误（如 String）
      logger.e('SmbAdapter: 连接失败 (非异常)', e, stackTrace);
      _connected = false;
      return ConnectionFailure(error: _parseErrorAny(e));
    }
  }

  String _parseError(Exception e) {
    return _parseErrorAny(e);
  }

  String _parseErrorAny(dynamic e) {
    final msg = e.toString().toLowerCase();
    logger.d('SmbAdapter: 解析错误消息 => $msg');

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
      await _client?.close();
    } catch (e) {
      logger.w('SmbAdapter: 断开连接时出错', e);
    }

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
