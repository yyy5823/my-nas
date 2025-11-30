import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/network/dio_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/ugreen/api/ugreen_api.dart';
import 'package:my_nas/nas_adapters/ugreen/ugreen_file_system.dart';

/// 绿联 NAS 适配器
class UGreenAdapter implements NasAdapter {
  UGreenAdapter() {
    logger.i('UGreenAdapter: 初始化适配器');
    _dioClient = DioClient(allowSelfSigned: true);
    _api = UGreenApi(dio: _dioClient.dio);
  }

  late final DioClient _dioClient;
  late final UGreenApi _api;
  late UGreenFileSystem _fileSystem;

  ConnectionConfig? _config;
  ServerInfo? _serverInfo;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.ugreen,
        name: '绿联 UGREEN',
        version: AppConstants.appVersion,
        supportsMediaService: false,
        supportsToolsService: false,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  UGreenApi get api => _api;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger.i('UGreenAdapter: 开始连接');
    logger.i('UGreenAdapter: 目标地址 => ${config.baseUrl}');
    logger.i('UGreenAdapter: 用户名 => ${config.username}');
    logger.i('UGreenAdapter: 使用 SSL => ${config.useSsl}');

    _config = config;
    _dioClient.updateBaseUrl(config.baseUrl);

    // 如果不验证 SSL，添加相应配置
    if (!config.verifySSL) {
      logger.i('UGreenAdapter: 跳过 SSL 证书验证');
      _dioClient.setAllowSelfSignedCert(true);
    }

    // 尝试登录
    logger.i('UGreenAdapter: 开始登录认证...');
    final authResult = await _api.login(
      username: config.username,
      password: config.password,
    );

    logger.i('UGreenAdapter: 登录结果 => ${authResult.runtimeType}');

    return switch (authResult) {
      UGreenAuthSuccess(:final token) =>
        await _handleLoginSuccess(token),
      UGreenAuthFailure(:final error) => () {
          logger.e('UGreenAdapter: 登录失败 => $error');
          return ConnectionFailure(error: error);
        }(),
      UGreenAuthRequires2FA() => () {
          logger.i('UGreenAdapter: 需要二次验证');
          return const ConnectionRequires2FA(
            methods: [TwoFactorMethod.totp],
          );
        }(),
    };
  }

  /// 二次验证
  Future<ConnectionResult> verify2FA(
    String otpCode, {
    bool rememberDevice = false,
  }) async {
    if (_config == null) {
      return const ConnectionFailure(error: '请先调用 connect');
    }

    final authResult = await _api.login(
      username: _config!.username,
      password: _config!.password,
      otpCode: otpCode,
    );

    return switch (authResult) {
      UGreenAuthSuccess(:final token) =>
        await _handleLoginSuccess(token),
      UGreenAuthFailure(:final error) => ConnectionFailure(error: error),
      UGreenAuthRequires2FA() => const ConnectionFailure(error: '二次验证失败'),
    };
  }

  Future<ConnectionResult> _handleLoginSuccess(String token) async {
    _connected = true;
    _fileSystem = UGreenFileSystem(api: _api);

    // 获取服务器信息
    try {
      final deviceInfo = await _api.getDeviceInfo();
      _serverInfo = ServerInfo(
        hostname: deviceInfo.hostname,
        model: deviceInfo.model,
        version: deviceInfo.version,
        serial: deviceInfo.serial,
      );
    } on Exception catch (e) {
      // 获取服务器信息失败不影响连接
      logger.w('UGreenAdapter: 获取设备信息失败', e);
    }

    return ConnectionSuccess(
      sessionId: token,
      serverInfo: _serverInfo,
    );
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    await _api.logout();
    _connected = false;
    _config = null;
    _serverInfo = null;
    logger.i('UGreenAdapter: 已断开连接');
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected) {
      throw StateError('未连接到 NAS');
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
    _dioClient.dio.close();
  }
}
