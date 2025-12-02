import 'dart:io';

import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/local/api/local_file_api.dart';
import 'package:my_nas/nas_adapters/local/local_file_system.dart';

/// 本地存储适配器
///
/// 支持访问本地文件系统，跨平台兼容：
/// - Windows: 访问所有驱动器
/// - macOS: 访问用户目录和外接卷宗
/// - Linux: 访问用户目录和挂载点
/// - Android: 访问内部存储和 SD 卡
/// - iOS: 访问应用沙盒目录
class LocalAdapter implements NasAdapter {
  LocalAdapter() {
    logger.i('LocalAdapter: 初始化适配器');
    _api = LocalFileApi();
  }

  late final LocalFileApi _api;
  late LocalFileSystem _fileSystem;

  ConnectionConfig? _config;
  ServerInfo? _serverInfo;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.local,
        name: '本地存储',
        version: AppConstants.appVersion,
        supportsMediaService: false,
        supportsToolsService: false,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  LocalFileApi get api => _api;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger.i('LocalAdapter: 开始连接本地存储');

    _config = config;
    _connected = true;
    _fileSystem = LocalFileSystem(api: _api);

    // 获取系统信息
    _serverInfo = ServerInfo(
      hostname: _getHostname(),
      model: _getPlatformName(),
      version: Platform.operatingSystemVersion,
    );

    logger.i('LocalAdapter: 连接成功 - ${_serverInfo!.hostname}');

    return ConnectionSuccess(
      sessionId: 'local_${DateTime.now().millisecondsSinceEpoch}',
      serverInfo: _serverInfo,
    );
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    _connected = false;
    _config = null;
    _serverInfo = null;
    logger.i('LocalAdapter: 已断开连接');
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected) {
      throw StateError('未连接');
    }
    return _fileSystem;
  }

  @override
  MediaService? get mediaService => null;

  @override
  ToolsService? get toolsService => null;

  @override
  Future<void> dispose() async {
    await disconnect();
  }

  String _getHostname() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return '本地设备';
    }
  }

  String _getPlatformName() {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return Platform.operatingSystem;
  }
}
