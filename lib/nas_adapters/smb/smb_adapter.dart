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
      _client = await SmbConnect.connectAuth(
        host: config.host,
        domain: '', // 工作组/域，通常留空
        username: config.username,
        password: config.password,
      );

      // 测试连接 - 获取共享列表
      final shares = await _client!.listShares();
      logger.i('SmbAdapter: 连接成功，发现 ${shares.length} 个共享');

      _fileSystem = SmbFileSystem(client: _client!);
      _connected = true;

      return ConnectionSuccess(
        sessionId: 'smb-${DateTime.now().millisecondsSinceEpoch}',
        serverInfo: ServerInfo(
          hostname: config.host,
          model: 'SMB/CIFS Server',
        ),
      );
    } on Exception catch (e) {
      logger.e('SmbAdapter: 连接失败', e);
      _connected = false;
      return ConnectionFailure(error: _parseError(e));
    }
  }

  String _parseError(Exception e) {
    final msg = e.toString();
    if (msg.contains('Connection refused')) {
      return '连接被拒绝，请检查 SMB 服务是否启用';
    }
    if (msg.contains('timeout')) {
      return '连接超时，请检查网络和地址';
    }
    if (msg.contains('STATUS_LOGON_FAILURE')) {
      return '用户名或密码错误';
    }
    if (msg.contains('STATUS_ACCESS_DENIED')) {
      return '访问被拒绝，请检查权限';
    }
    return msg;
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
