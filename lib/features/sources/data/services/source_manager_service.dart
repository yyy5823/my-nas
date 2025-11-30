import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/synology/synology_adapter.dart';
import 'package:my_nas/nas_adapters/ugreen/ugreen_adapter.dart';
import 'package:my_nas/nas_adapters/webdav/webdav_adapter.dart';

/// 源连接信息
class SourceConnection {
  const SourceConnection({
    required this.source,
    required this.adapter,
    this.status = SourceStatus.disconnected,
    this.errorMessage,
  });

  final SourceEntity source;
  final NasAdapter adapter;
  final SourceStatus status;
  final String? errorMessage;

  SourceConnection copyWith({
    SourceEntity? source,
    NasAdapter? adapter,
    SourceStatus? status,
    String? errorMessage,
  }) =>
      SourceConnection(
        source: source ?? this.source,
        adapter: adapter ?? this.adapter,
        status: status ?? this.status,
        errorMessage: errorMessage,
      );
}

/// 凭证信息
class SourceCredential {
  const SourceCredential({
    required this.password,
    this.deviceId,
  });

  final String password;
  final String? deviceId;

  Map<String, dynamic> toJson() => {
        'password': password,
        'deviceId': deviceId,
      };

  factory SourceCredential.fromJson(Map<String, dynamic> json) =>
      SourceCredential(
        password: json['password'] as String,
        deviceId: json['deviceId'] as String?,
      );
}

/// 源管理服务
class SourceManagerService {
  SourceManagerService._();

  static SourceManagerService? _instance;
  static SourceManagerService get instance =>
      _instance ??= SourceManagerService._();

  late Box<dynamic> _sourcesBox;
  late Box<dynamic> _credentialsBox;
  late Box<dynamic> _libraryBox;
  bool _initialized = false;

  /// 活跃的连接
  final Map<String, SourceConnection> _connections = {};

  /// 初始化
  Future<void> init() async {
    if (_initialized) return;

    await Hive.initFlutter();
    _sourcesBox = await Hive.openBox('sources');
    _credentialsBox = await Hive.openBox('source_credentials');
    _libraryBox = await Hive.openBox('media_library');
    _initialized = true;

    logger.i('SourceManagerService: 初始化完成');
  }

  // ============ 源管理 ============

  /// 获取所有源
  Future<List<SourceEntity>> getSources() async {
    if (!_initialized) await init();

    final data = _sourcesBox.get('list') as List<dynamic>?;
    if (data == null) return [];

    try {
      return data
          .map((e) => SourceEntity.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      logger.e('SourceManagerService: 解析源列表失败', e);
      return [];
    }
  }

  /// 添加源
  Future<void> addSource(SourceEntity source) async {
    if (!_initialized) await init();

    final sources = await getSources();
    sources.add(source);
    await _saveSources(sources);

    logger.i('SourceManagerService: 添加源 ${source.name}');
  }

  /// 更新源
  Future<void> updateSource(SourceEntity source) async {
    if (!_initialized) await init();

    final sources = await getSources();
    final index = sources.indexWhere((s) => s.id == source.id);
    if (index != -1) {
      sources[index] = source;
      await _saveSources(sources);
      logger.i('SourceManagerService: 更新源 ${source.name}');
    }
  }

  /// 删除源
  Future<void> removeSource(String sourceId) async {
    if (!_initialized) await init();

    // 断开连接
    await disconnect(sourceId);

    // 删除凭证
    await removeCredential(sourceId);

    // 删除源
    final sources = await getSources();
    sources.removeWhere((s) => s.id == sourceId);
    await _saveSources(sources);

    // 删除关联的媒体库路径
    final config = await getMediaLibraryConfig();
    final newConfig = config.removePathsForSource(sourceId);
    await saveMediaLibraryConfig(newConfig);

    logger.i('SourceManagerService: 删除源 $sourceId');
  }

  Future<void> _saveSources(List<SourceEntity> sources) async {
    await _sourcesBox.put('list', sources.map((s) => s.toJson()).toList());
  }

  // ============ 凭证管理 ============

  /// 保存凭证
  Future<void> saveCredential(String sourceId, SourceCredential credential) async {
    if (!_initialized) await init();
    await _credentialsBox.put(sourceId, credential.toJson());
    logger.d('SourceManagerService: 保存凭证 $sourceId');
  }

  /// 获取凭证
  Future<SourceCredential?> getCredential(String sourceId) async {
    if (!_initialized) await init();

    final data = _credentialsBox.get(sourceId);
    if (data == null) return null;

    try {
      return SourceCredential.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (e) {
      logger.e('SourceManagerService: 解析凭证失败', e);
      return null;
    }
  }

  /// 删除凭证
  Future<void> removeCredential(String sourceId) async {
    if (!_initialized) await init();
    await _credentialsBox.delete(sourceId);
  }

  /// 更新设备ID
  Future<void> updateDeviceId(String sourceId, String deviceId) async {
    final credential = await getCredential(sourceId);
    if (credential != null) {
      await saveCredential(
        sourceId,
        SourceCredential(
          password: credential.password,
          deviceId: deviceId,
        ),
      );
    }
  }

  // ============ 连接管理 ============

  /// 获取源的连接
  SourceConnection? getConnection(String sourceId) => _connections[sourceId];

  /// 获取所有活跃连接
  List<SourceConnection> getActiveConnections() =>
      _connections.values.where((c) => c.status == SourceStatus.connected).toList();

  /// 连接到源
  Future<SourceConnection> connect(
    SourceEntity source, {
    required String password,
    bool saveCredential = true,
  }) async {
    logger.i('SourceManagerService: 连接到 ${source.name}');

    // 创建适配器
    final adapter = _createAdapter(source.type);

    // 更新状态为连接中
    _connections[source.id] = SourceConnection(
      source: source,
      adapter: adapter,
      status: SourceStatus.connecting,
    );

    // 获取已保存的设备ID
    String? deviceId;
    if (source.rememberDevice) {
      final savedCredential = await getCredential(source.id);
      deviceId = savedCredential?.deviceId;
    }

    final config = ConnectionConfig(
      type: _getAdapterType(source.type),
      host: source.host,
      port: source.port,
      username: source.username,
      password: password,
      useSsl: source.useSsl,
      verifySSL: false,
      deviceId: deviceId,
      enableDeviceToken: source.rememberDevice,
    );

    try {
      final result = await adapter.connect(config);

      final connection = switch (result) {
        ConnectionSuccess(:final deviceId) => () {
            // 保存凭证
            if (saveCredential) {
              this.saveCredential(
                source.id,
                SourceCredential(password: password, deviceId: deviceId),
              );
            }

            // 更新最后连接时间
            updateSource(source.copyWith(lastConnected: DateTime.now()));

            return SourceConnection(
              source: source,
              adapter: adapter,
              status: SourceStatus.connected,
            );
          }(),
        ConnectionFailure(:final error) => SourceConnection(
            source: source,
            adapter: adapter,
            status: SourceStatus.error,
            errorMessage: error,
          ),
        ConnectionRequires2FA() => SourceConnection(
            source: source,
            adapter: adapter,
            status: SourceStatus.requires2FA,
          ),
      };

      _connections[source.id] = connection;
      return connection;
    } catch (e) {
      final connection = SourceConnection(
        source: source,
        adapter: adapter,
        status: SourceStatus.error,
        errorMessage: e.toString(),
      );
      _connections[source.id] = connection;
      return connection;
    }
  }

  /// 二次验证
  Future<SourceConnection> verify2FA(
    String sourceId,
    String otpCode, {
    bool rememberDevice = false,
  }) async {
    final connection = _connections[sourceId];
    if (connection == null) {
      throw StateError('未找到连接');
    }

    final adapter = connection.adapter;
    ConnectionResult? result;

    if (adapter is SynologyAdapter) {
      result = await adapter.verify2FA(
        otpCode,
        rememberDevice: rememberDevice,
      );
    } else if (adapter is UGreenAdapter) {
      result = await adapter.verify2FA(
        otpCode,
        rememberDevice: rememberDevice,
      );
    }

    if (result != null) {
      final newConnection = switch (result) {
        ConnectionSuccess(:final deviceId) => () {
            // 保存设备ID
            if (rememberDevice && deviceId != null) {
              updateDeviceId(sourceId, deviceId);
            }

            return connection.copyWith(
              status: SourceStatus.connected,
              errorMessage: null,
            );
          }(),
        ConnectionFailure(:final error) => connection.copyWith(
            status: SourceStatus.error,
            errorMessage: error,
          ),
        ConnectionRequires2FA() => connection.copyWith(
            status: SourceStatus.error,
            errorMessage: '二次验证失败',
          ),
      };

      _connections[sourceId] = newConnection;
      return newConnection;
    }

    throw UnsupportedError('该源类型不支持二次验证');
  }

  /// 断开连接
  Future<void> disconnect(String sourceId) async {
    final connection = _connections[sourceId];
    if (connection != null) {
      await connection.adapter.disconnect();
      await connection.adapter.dispose();
      _connections.remove(sourceId);
      logger.i('SourceManagerService: 断开连接 $sourceId');
    }
  }

  /// 断开所有连接
  Future<void> disconnectAll() async {
    for (final sourceId in _connections.keys.toList()) {
      await disconnect(sourceId);
    }
  }

  /// 自动连接所有启用自动连接的源
  Future<void> autoConnectAll() async {
    final sources = await getSources();
    for (final source in sources) {
      if (source.autoConnect) {
        final credential = await getCredential(source.id);
        if (credential != null) {
          try {
            await connect(source, password: credential.password, saveCredential: false);
          } catch (e) {
            logger.e('SourceManagerService: 自动连接失败 ${source.name}', e);
          }
        }
      }
    }
  }

  NasAdapter _createAdapter(SourceType type) {
    return switch (type) {
      SourceType.synology => SynologyAdapter(),
      SourceType.ugreen => UGreenAdapter(),
      SourceType.webdav => WebDavAdapter(),
      _ => throw UnimplementedError('适配器 $type 尚未实现'),
    };
  }

  NasAdapterType _getAdapterType(SourceType type) {
    return switch (type) {
      SourceType.synology => NasAdapterType.synology,
      SourceType.ugreen => NasAdapterType.ugreen,
      SourceType.webdav => NasAdapterType.webdav,
      SourceType.smb => NasAdapterType.smb,
      _ => throw UnimplementedError('适配器类型 $type 尚未实现'),
    };
  }

  // ============ 媒体库配置 ============

  /// 获取媒体库配置
  Future<MediaLibraryConfig> getMediaLibraryConfig() async {
    if (!_initialized) await init();

    final data = _libraryBox.get('config');
    logger.i('SourceManagerService: 读取媒体库配置 - $data');
    if (data == null) {
      logger.i('SourceManagerService: 媒体库配置为空，返回默认配置');
      return const MediaLibraryConfig();
    }

    try {
      final config = MediaLibraryConfig.fromJson(Map<String, dynamic>.from(data as Map));
      logger.i('SourceManagerService: 解析媒体库配置成功 - 视频路径: ${config.videoPaths.length}, 音乐路径: ${config.musicPaths.length}');
      return config;
    } catch (e) {
      logger.e('SourceManagerService: 解析媒体库配置失败', e);
      return const MediaLibraryConfig();
    }
  }

  /// 保存媒体库配置
  Future<void> saveMediaLibraryConfig(MediaLibraryConfig config) async {
    if (!_initialized) await init();
    final json = config.toJson();
    logger.i('SourceManagerService: 保存媒体库配置 - $json');
    await _libraryBox.put('config', json);
    // 确保数据已写入磁盘
    await _libraryBox.flush();
    logger.i('SourceManagerService: 媒体库配置已保存');
  }
}
