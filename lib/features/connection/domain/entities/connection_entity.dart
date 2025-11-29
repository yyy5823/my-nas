import 'package:my_nas/nas_adapters/base/nas_adapter.dart';

/// 连接实体
class ConnectionEntity {
  const ConnectionEntity({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    required this.username,
    this.useSsl = true,
    this.quickConnectId,
    this.lastConnected,
  });

  final String id;
  final String name;
  final NasAdapterType type;
  final String host;
  final int port;
  final String username;
  final bool useSsl;
  final String? quickConnectId;
  final DateTime? lastConnected;

  String get displayName => name.isNotEmpty ? name : host;

  String get baseUrl {
    final protocol = useSsl ? 'https' : 'http';
    return '$protocol://$host:$port';
  }

  ConnectionEntity copyWith({
    String? id,
    String? name,
    NasAdapterType? type,
    String? host,
    int? port,
    String? username,
    bool? useSsl,
    String? quickConnectId,
    DateTime? lastConnected,
  }) =>
      ConnectionEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        useSsl: useSsl ?? this.useSsl,
        quickConnectId: quickConnectId ?? this.quickConnectId,
        lastConnected: lastConnected ?? this.lastConnected,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'host': host,
        'port': port,
        'username': username,
        'useSsl': useSsl,
        'quickConnectId': quickConnectId,
        'lastConnected': lastConnected?.toIso8601String(),
      };

  factory ConnectionEntity.fromJson(Map<String, dynamic> json) =>
      ConnectionEntity(
        id: json['id'] as String,
        name: json['name'] as String,
        type: NasAdapterType.values.byName(json['type'] as String),
        host: json['host'] as String,
        port: json['port'] as int,
        username: json['username'] as String,
        useSsl: json['useSsl'] as bool? ?? true,
        quickConnectId: json['quickConnectId'] as String?,
        lastConnected: json['lastConnected'] != null
            ? DateTime.parse(json['lastConnected'] as String)
            : null,
      );
}
