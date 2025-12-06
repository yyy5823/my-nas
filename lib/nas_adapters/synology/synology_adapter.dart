import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/network/dio_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/synology/api/synology_api.dart';
import 'package:my_nas/nas_adapters/synology/synology_file_system.dart';

/// 群晖 NAS 适配器
class SynologyAdapter implements NasAdapter {
  SynologyAdapter() {
    logger.i('SynologyAdapter: 初始化适配器');
    _dioClient = DioClient(allowSelfSigned: true);
    _api = SynologyApi(dio: _dioClient.dio);
  }

  late final DioClient _dioClient;
  late final SynologyApi _api;
  late SynologyFileSystem _fileSystem;

  ConnectionConfig? _config;
  ServerInfo? _serverInfo;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.synology,
        name: '群晖 Synology',
        version: AppConstants.appVersion,
        supportsMediaService: true,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  SynologyApi get api => _api;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger..i('SynologyAdapter: 开始连接')
    ..i('SynologyAdapter: 目标地址 => ${config.baseUrl}')
    ..i('SynologyAdapter: 用户名 => ${config.username}')
    ..i('SynologyAdapter: 使用 SSL => ${config.useSsl}')
    ..i('SynologyAdapter: 验证 SSL => ${config.verifySSL}');

    _config = config;
    _dioClient.updateBaseUrl(config.baseUrl);

    // 如果不验证 SSL，添加相应配置
    if (!config.verifySSL) {
      logger.i('SynologyAdapter: 跳过 SSL 证书验证');
      _dioClient.setAllowSelfSignedCert(allow: true);
    }

    // 尝试登录
    logger.i('SynologyAdapter: 开始登录认证...');
    final authResult = await _api.login(
      account: config.username,
      password: config.password,
      deviceId: config.deviceId,
      deviceName: config.deviceName,
      enableDeviceToken: config.enableDeviceToken,
    );

    logger.i('SynologyAdapter: 登录结果 => ${authResult.runtimeType}');

    return switch (authResult) {
      AuthSuccess(:final sid, :final deviceId) =>
        await _handleLoginSuccess(sid, deviceId: deviceId),
      AuthFailure(:final error) => () {
          logger.e('SynologyAdapter: 登录失败 => $error');
          return ConnectionFailure(error: error);
        }(),
      AuthRequires2FA() => () {
          logger.i('SynologyAdapter: 需要二次验证');
          return const ConnectionRequires2FA(
            methods: [TwoFactorMethod.totp],
          );
        }(),
    };
  }

  Future<ConnectionResult> verify2FA(
    String otpCode, {
    bool rememberDevice = false,
    String? deviceName,
  }) async {
    if (_config == null) {
      return const ConnectionFailure(error: '请先调用 connect');
    }

    // 如果需要记住设备，必须提供设备名称
    // 优先使用传入的设备名，其次使用配置中的设备名，最后使用默认名称
    final effectiveDeviceName = rememberDevice
        ? (deviceName ?? _config!.deviceName ?? 'MyNAS-${DateTime.now().millisecondsSinceEpoch}')
        : null;

    logger.d('SynologyAdapter: verify2FA - rememberDevice=$rememberDevice, deviceName=$effectiveDeviceName');

    final authResult = await _api.login(
      account: _config!.username,
      password: _config!.password,
      otpCode: otpCode,
      deviceName: effectiveDeviceName,
      enableDeviceToken: rememberDevice,
    );

    return switch (authResult) {
      AuthSuccess(:final sid, :final deviceId) =>
        await _handleLoginSuccess(sid, deviceId: deviceId),
      AuthFailure(:final error) => ConnectionFailure(error: error),
      AuthRequires2FA() => const ConnectionFailure(error: '二次验证失败'),
    };
  }

  Future<ConnectionResult> _handleLoginSuccess(
    String sid, {
    String? deviceId,
  }) async {
    _connected = true;
    _fileSystem = SynologyFileSystem(api: _api);

    // 获取服务器信息
    try {
      final dsmInfo = await _api.getDsmInfo();
      _serverInfo = ServerInfo(
        hostname: dsmInfo.hostname,
        model: dsmInfo.model,
        version: dsmInfo.version,
        serial: dsmInfo.serial,
      );
    } on Exception {
      // 获取服务器信息失败不影响连接
    }

    return ConnectionSuccess(
      sessionId: sid,
      serverInfo: _serverInfo,
      deviceId: deviceId,
    );
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    await _api.logout();
    _connected = false;
    _config = null;
    _serverInfo = null;
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected) {
      throw StateError('未连接到 NAS');
    }
    return _fileSystem;
  }

  @override
  MediaService? get mediaService => null; // TODO: 实现 Video Station / Audio Station

  @override
  ToolsService? get toolsService => null;

  @override
  Future<void> dispose() async {
    await disconnect();
    _dioClient.dio.close();
  }
}
