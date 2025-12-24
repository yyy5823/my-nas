import 'dart:io';

import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/local/api/local_file_api.dart';
import 'package:my_nas/nas_adapters/local/local_file_system.dart';
import 'package:my_nas/nas_adapters/mobile/file_systems/mobile_gallery_file_system.dart';

/// 本地存储适配器
///
/// 支持访问本地文件系统，跨平台兼容：
/// - Windows: 访问所有驱动器和用户目录
/// - macOS: 访问用户目录和外接卷宗
/// - Linux: 访问用户目录和挂载点
/// - Android/iOS: 访问系统相册（照片和视频）
///
/// 注意：在移动端（iOS/Android），本适配器使用系统相册 API 访问照片和视频，
/// 而不是文件系统。这是因为移动端无法直接访问相册目录。
class LocalAdapter implements NasAdapter {
  LocalAdapter() {
    logger.i('LocalAdapter: 初始化适配器');
    _api = LocalFileApi();
  }

  late final LocalFileApi _api;
  late NasFileSystem _fileSystem;

  /// 移动端相册文件系统（用于访问系统相册）
  MobileGalleryFileSystem? _galleryFileSystem;

  ConnectionConfig? _config;
  ServerInfo? _serverInfo;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.local,
        name: '本地存储',
        version: AppConstants.appVersion,
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

    // 移动端使用系统相册 API
    if (Platform.isIOS || Platform.isAndroid) {
      logger.i('LocalAdapter: 移动端 - 使用系统相册API');
      _galleryFileSystem = MobileGalleryFileSystem();

      // 请求相册权限
      final hasPermission = await _galleryFileSystem!.requestPermission();
      if (!hasPermission) {
        return const ConnectionFailure(
          error: '未获得访问相册的权限，请在系统设置中授权',
        );
      }

      _fileSystem = _galleryFileSystem!;
    } else {
      // 桌面端使用本地文件系统
      logger.i('LocalAdapter: 桌面端 - 使用本地文件系统');
      _fileSystem = LocalFileSystem(api: _api);
    }

    _connected = true;

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

  /// 获取相册文件系统（仅移动端可用）
  MobileGalleryFileSystem? get galleryFileSystem => _galleryFileSystem;

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    _connected = false;
    _config = null;
    _serverInfo = null;
    _galleryFileSystem = null;
    logger.i('LocalAdapter: 已断开连接');
  }

  @override
  Future<bool> checkConnectionHealth() async {
    // 本地存储始终可用
    if (!_connected) {
      logger.d('LocalAdapter: 连接健康检查 - 未连接');
      return false;
    }
    logger.d('LocalAdapter: 连接健康检查 - 正常');
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

  String _getHostname() {
    try {
      return Platform.localHostname;
    } on Exception catch (_) {
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
