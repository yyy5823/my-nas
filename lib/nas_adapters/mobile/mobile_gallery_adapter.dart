import 'dart:io';

import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/mobile/file_systems/mobile_gallery_file_system.dart';

/// 移动端相册适配器
///
/// 通过系统 API 访问手机相册中的照片和视频
/// 仅在 iOS/Android 平台可用
class MobileGalleryAdapter implements NasAdapter {
  MobileGalleryAdapter() {
    logger.i('MobileGalleryAdapter: 初始化适配器');
  }

  late MobileGalleryFileSystem _fileSystem;
  ConnectionConfig? _config;
  ServerInfo? _serverInfo;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.mobileGallery,
        name: '手机相册',
        version: AppConstants.appVersion,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger.i('MobileGalleryAdapter: 开始连接');

    // 检查平台
    if (!Platform.isIOS && !Platform.isAndroid) {
      return const ConnectionFailure(
        error: '手机相册仅支持 iOS 和 Android 平台',
      );
    }

    _config = config;
    _fileSystem = MobileGalleryFileSystem();

    // 请求权限
    final hasPermission = await _fileSystem.requestPermission();
    if (!hasPermission) {
      return const ConnectionFailure(
        error: '未获得访问相册的权限，请在系统设置中授权',
      );
    }

    _connected = true;
    _serverInfo = ServerInfo(
      hostname: _getDeviceName(),
      model: Platform.isIOS ? 'iOS 设备' : 'Android 设备',
      version: Platform.operatingSystemVersion,
    );

    logger.i('MobileGalleryAdapter: 连接成功 - ${_serverInfo!.hostname}');

    return ConnectionSuccess(
      sessionId: 'mobile_gallery_${DateTime.now().millisecondsSinceEpoch}',
      serverInfo: _serverInfo,
    );
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    _connected = false;
    _config = null;
    _serverInfo = null;
    logger.i('MobileGalleryAdapter: 已断开连接');
  }

  @override
  Future<bool> checkConnectionHealth() async {
    // 移动端媒体始终可用（只要有权限）
    if (!_connected) {
      logger.d('MobileGalleryAdapter: 连接健康检查 - 未连接');
      return false;
    }
    logger.d('MobileGalleryAdapter: 连接健康检查 - 正常');
    return true;
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
