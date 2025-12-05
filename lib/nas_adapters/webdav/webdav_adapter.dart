import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/webdav/webdav_file_system.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

/// WebDAV NAS 适配器
class WebDavAdapter implements NasAdapter {
  WebDavAdapter() {
    logger.i('WebDavAdapter: 初始化适配器');
  }

  webdav.Client? _client;
  WebDavFileSystem? _fileSystem;
  ConnectionConfig? _config;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.webdav,
        name: 'WebDAV',
        version: AppConstants.appVersion,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger..i('WebDavAdapter: 开始连接')
    ..i('WebDavAdapter: 目标地址 => ${config.baseUrl}')
    ..i('WebDavAdapter: 用户名 => ${config.username}');

    _config = config;

    try {
      _client = webdav.newClient(
        config.baseUrl,
        user: config.username,
        password: config.password,
      );

      // 设置超时和自签名证书支持
      _client!.setConnectTimeout(30000);
      _client!.setSendTimeout(60000);
      _client!.setReceiveTimeout(60000);

      // 测试连接 - 尝试读取根目录
      await _client!.ping();

      _fileSystem = WebDavFileSystem(
        client: _client!,
        baseUrl: config.baseUrl,
        username: config.username,
        password: config.password,
      );
      _connected = true;

      logger.i('WebDavAdapter: 连接成功');

      return ConnectionSuccess(
        sessionId: 'webdav-${DateTime.now().millisecondsSinceEpoch}',
        serverInfo: ServerInfo(
          hostname: config.host,
          model: 'WebDAV Server',
        ),
      );
    } on Exception catch (e) {
      logger.e('WebDavAdapter: 连接失败', e);
      _connected = false;
      return ConnectionFailure(error: e.toString());
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    _client = null;
    _fileSystem = null;
    _connected = false;
    _config = null;
    logger.i('WebDavAdapter: 已断开连接');
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected || _fileSystem == null) {
      throw StateError('未连接到 WebDAV 服务器');
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
