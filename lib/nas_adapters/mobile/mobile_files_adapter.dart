import 'dart:io';

import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/mobile/file_systems/mobile_files_file_system.dart';

/// 移动端文件适配器
///
/// 访问手机文件 App 中的文档和书籍
/// - iOS: 访问 Files App / iCloud Drive
/// - Android: 访问文件管理器 / Downloads
class MobileFilesAdapter implements NasAdapter {
  MobileFilesAdapter() {
    logger.i('MobileFilesAdapter: 初始化适配器');
  }

  late MobileFilesFileSystem _fileSystem;
  ConnectionConfig? _config;
  ServerInfo? _serverInfo;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.mobileFiles,
        name: '手机文件',
        version: AppConstants.appVersion,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger.i('MobileFilesAdapter: 开始连接');

    // 检查平台
    if (!Platform.isIOS && !Platform.isAndroid) {
      return const ConnectionFailure(
        error: '手机文件仅支持 iOS 和 Android 平台',
      );
    }

    _config = config;
    _fileSystem = MobileFilesFileSystem();

    // 文件系统一般不需要额外权限（访问应用沙盒）
    await _fileSystem.initialize();

    _connected = true;
    _serverInfo = ServerInfo(
      hostname: _getDeviceName(),
      model: Platform.isIOS ? 'iOS 设备' : 'Android 设备',
      version: Platform.operatingSystemVersion,
    );

    logger.i('MobileFilesAdapter: 连接成功 - ${_serverInfo!.hostname}');

    return ConnectionSuccess(
      sessionId: 'mobile_files_${DateTime.now().millisecondsSinceEpoch}',
      serverInfo: _serverInfo,
    );
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    _connected = false;
    _config = null;
    _serverInfo = null;
    logger.i('MobileFilesAdapter: 已断开连接');
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

  String _getDeviceName() {
    try {
      return Platform.localHostname;
    } on Exception catch (_) {
      return Platform.isIOS ? 'iPhone' : 'Android';
    }
  }
}
