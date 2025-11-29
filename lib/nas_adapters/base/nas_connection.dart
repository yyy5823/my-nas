import 'package:my_nas/nas_adapters/base/nas_adapter.dart';

/// 连接配置
class ConnectionConfig {
  const ConnectionConfig({
    required this.type,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.useSsl = true,
    this.verifySSL = true,
    this.quickConnectId,
  });

  final NasAdapterType type;
  final String host;
  final int port;
  final String username;
  final String password;
  final bool useSsl;
  final bool verifySSL;
  final String? quickConnectId;

  String get baseUrl {
    final protocol = useSsl ? 'https' : 'http';
    return '$protocol://$host:$port';
  }

  ConnectionConfig copyWith({
    NasAdapterType? type,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? useSsl,
    bool? verifySSL,
    String? quickConnectId,
  }) =>
      ConnectionConfig(
        type: type ?? this.type,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
        useSsl: useSsl ?? this.useSsl,
        verifySSL: verifySSL ?? this.verifySSL,
        quickConnectId: quickConnectId ?? this.quickConnectId,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'host': host,
        'port': port,
        'username': username,
        'useSsl': useSsl,
        'verifySSL': verifySSL,
        'quickConnectId': quickConnectId,
      };

  static ConnectionConfig fromJson(
    Map<String, dynamic> json, {
    required String password,
  }) =>
      ConnectionConfig(
        type: NasAdapterType.values.byName(json['type'] as String),
        host: json['host'] as String,
        port: json['port'] as int,
        username: json['username'] as String,
        password: password,
        useSsl: json['useSsl'] as bool? ?? true,
        verifySSL: json['verifySSL'] as bool? ?? true,
        quickConnectId: json['quickConnectId'] as String?,
      );
}

/// 连接结果
sealed class ConnectionResult {
  const ConnectionResult();
}

/// 连接成功
class ConnectionSuccess extends ConnectionResult {
  const ConnectionSuccess({
    required this.sessionId,
    this.serverInfo,
  });

  final String sessionId;
  final ServerInfo? serverInfo;
}

/// 连接失败
class ConnectionFailure extends ConnectionResult {
  const ConnectionFailure({
    required this.error,
    this.code,
  });

  final String error;
  final int? code;
}

/// 需要二次验证
class ConnectionRequires2FA extends ConnectionResult {
  const ConnectionRequires2FA({required this.methods});

  final List<TwoFactorMethod> methods;
}

/// 服务器信息
class ServerInfo {
  const ServerInfo({
    required this.hostname,
    this.model,
    this.version,
    this.serial,
  });

  final String hostname;
  final String? model;
  final String? version;
  final String? serial;
}

/// 二次验证方式
enum TwoFactorMethod {
  totp,
  email,
  sms,
}
