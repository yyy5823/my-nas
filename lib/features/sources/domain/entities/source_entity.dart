import 'package:uuid/uuid.dart';

/// 源类型
enum SourceType {
  synology('Synology NAS', 'synology'),
  ugreen('绿联 NAS', 'ugreen'),
  fnos('飞牛 fnOS', 'fnos'),
  qnap('QNAP NAS', 'qnap'),
  webdav('WebDAV', 'webdav'),
  smb('SMB/CIFS', 'smb'),
  local('本地存储', 'local');

  const SourceType(this.displayName, this.id);
  final String displayName;
  final String id;

  /// 获取该源类型的默认端口
  int get defaultPort => switch (this) {
    SourceType.synology => 5001,
    SourceType.ugreen => 9999,
    SourceType.fnos => 5666,
    SourceType.qnap => 8080,
    SourceType.webdav => 443,
    SourceType.smb => 445,
    SourceType.local => 0,
  };

  /// 该源类型是否已实现
  bool get isSupported => switch (this) {
    SourceType.synology => true,
    SourceType.ugreen => true,
    SourceType.fnos => true,
    SourceType.webdav => true,
    SourceType.smb => true,
    SourceType.qnap => false,
    SourceType.local => false,
  };
}

/// 源连接状态
enum SourceStatus {
  disconnected,
  connecting,
  requires2FA,
  connected,
  error,
}

/// 连接源实体
class SourceEntity {
  SourceEntity({
    String? id,
    required this.name,
    required this.type,
    required this.host,
    this.port = 5001,
    required this.username,
    this.useSsl = true,
    this.quickConnectId,
    this.lastConnected,
    this.autoConnect = true,
    this.rememberDevice = false,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String name;
  final SourceType type;
  final String host;
  final int port;
  final String username;
  final bool useSsl;
  final String? quickConnectId;
  final DateTime? lastConnected;

  /// 是否自动连接（启动时自动连接）
  final bool autoConnect;

  /// 是否记住设备（跳过二次验证）
  final bool rememberDevice;

  String get displayName => name.isNotEmpty ? name : host;

  String get baseUrl {
    final protocol = useSsl ? 'https' : 'http';
    return '$protocol://$host:$port';
  }

  /// 获取唯一标识符（用于凭证存储）
  String get credentialKey => '${type.id}_${host}_${port}_$username';

  SourceEntity copyWith({
    String? id,
    String? name,
    SourceType? type,
    String? host,
    int? port,
    String? username,
    bool? useSsl,
    String? quickConnectId,
    DateTime? lastConnected,
    bool? autoConnect,
    bool? rememberDevice,
  }) =>
      SourceEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        useSsl: useSsl ?? this.useSsl,
        quickConnectId: quickConnectId ?? this.quickConnectId,
        lastConnected: lastConnected ?? this.lastConnected,
        autoConnect: autoConnect ?? this.autoConnect,
        rememberDevice: rememberDevice ?? this.rememberDevice,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.id,
        'host': host,
        'port': port,
        'username': username,
        'useSsl': useSsl,
        'quickConnectId': quickConnectId,
        'lastConnected': lastConnected?.toIso8601String(),
        'autoConnect': autoConnect,
        'rememberDevice': rememberDevice,
      };

  factory SourceEntity.fromJson(Map<String, dynamic> json) => SourceEntity(
        id: json['id'] as String,
        name: json['name'] as String,
        type: SourceType.values.firstWhere(
          (t) => t.id == json['type'],
          orElse: () => SourceType.synology,
        ),
        host: json['host'] as String,
        port: json['port'] as int? ?? 5001,
        username: json['username'] as String,
        useSsl: json['useSsl'] as bool? ?? true,
        quickConnectId: json['quickConnectId'] as String?,
        lastConnected: json['lastConnected'] != null
            ? DateTime.parse(json['lastConnected'] as String)
            : null,
        autoConnect: json['autoConnect'] as bool? ?? true,
        rememberDevice: json['rememberDevice'] as bool? ?? false,
      );
}
