import 'package:flutter/material.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:uuid/uuid.dart';

/// 源类型
///
/// 排列顺序按以下规则：
/// 1. NAS 设备类型（按品牌知名度排序）
/// 2. 通用协议类型
/// 3. 本地存储
/// 4. 服务类源（下载工具、媒体追踪、媒体管理）
enum SourceType {
  // === 存储类源 ===
  // NAS 设备
  synology('Synology NAS', 'synology'),
  qnap('QNAP NAS', 'qnap'),
  ugreen('绿联 NAS', 'ugreen'),
  fnos('飞牛 fnOS', 'fnos'),
  // 通用协议
  webdav('WebDAV', 'webdav'),
  smb('SMB/CIFS', 'smb'),
  // 本地存储
  local('本地存储', 'local'),

  // === 服务类源 ===
  // 下载工具
  qbittorrent('qBittorrent', 'qbittorrent'),
  transmission('Transmission', 'transmission'),
  aria2('Aria2', 'aria2'),
  // 媒体追踪
  trakt('Trakt', 'trakt'),
  // 媒体管理
  nastool('NASTool', 'nastool'),
  moviepilot('MoviePilot', 'moviepilot'),
  jellyfin('Jellyfin', 'jellyfin'),
  emby('Emby', 'emby'),
  plex('Plex', 'plex');

  const SourceType(this.displayName, this.id);
  final String displayName;
  final String id;

  /// 获取该源类型的默认端口
  int get defaultPort => switch (this) {
        // NAS 设备
        SourceType.synology => 5001,
        SourceType.ugreen => 9999,
        SourceType.fnos => 5666,
        SourceType.qnap => 8080,
        // 通用协议
        SourceType.webdav => 443,
        SourceType.smb => 445,
        // 本地存储
        SourceType.local => 0,
        // 下载工具
        SourceType.qbittorrent => 8080,
        SourceType.transmission => 9091,
        SourceType.aria2 => 6800,
        // 媒体追踪
        SourceType.trakt => 443,
        // 媒体管理
        SourceType.nastool => 3000,
        SourceType.moviepilot => 3001,
        SourceType.jellyfin => 8096,
        SourceType.emby => 8096,
        SourceType.plex => 32400,
      };

  /// 该源类型是否已实现
  bool get isSupported => switch (this) {
        // NAS 设备
        SourceType.synology => true,
        SourceType.ugreen => true,
        SourceType.fnos => false, // 飞牛OS暂未提供API
        SourceType.qnap => true,
        // 通用协议
        SourceType.webdav => true,
        SourceType.smb => true,
        // 本地存储
        SourceType.local => true,
        // 下载工具
        SourceType.qbittorrent => true,
        SourceType.transmission => true,
        SourceType.aria2 => true,
        // 媒体追踪
        SourceType.trakt => true,
        // 媒体管理
        SourceType.nastool => true,
        SourceType.moviepilot => false,
        SourceType.jellyfin => false,
        SourceType.emby => false,
        SourceType.plex => false,
      };

  /// 获取源类型所属的分组
  SourceCategory get category => switch (this) {
        // NAS 设备
        SourceType.synology ||
        SourceType.qnap ||
        SourceType.ugreen ||
        SourceType.fnos =>
          SourceCategory.nasDevices,
        // 通用协议
        SourceType.webdav || SourceType.smb => SourceCategory.genericProtocols,
        // 本地存储
        SourceType.local => SourceCategory.localStorage,
        // 下载工具
        SourceType.qbittorrent ||
        SourceType.transmission ||
        SourceType.aria2 =>
          SourceCategory.downloadTools,
        // 媒体追踪
        SourceType.trakt => SourceCategory.mediaTracking,
        // 媒体管理
        SourceType.nastool ||
        SourceType.moviepilot ||
        SourceType.jellyfin ||
        SourceType.emby ||
        SourceType.plex =>
          SourceCategory.mediaManagement,
      };

  /// 是否支持文件系统访问
  bool get supportsFileSystem => switch (this) {
        SourceType.synology ||
        SourceType.qnap ||
        SourceType.ugreen ||
        SourceType.fnos ||
        SourceType.webdav ||
        SourceType.smb ||
        SourceType.local =>
          true,
        _ => false,
      };

  /// 是否为服务类源
  bool get isServiceSource => category.isServiceCategory;

  /// 获取源类型的图标
  IconData get icon => switch (this) {
        // NAS 设备
        SourceType.synology => Icons.storage,
        SourceType.qnap => Icons.storage,
        SourceType.ugreen => Icons.storage,
        SourceType.fnos => Icons.storage,
        // 通用协议
        SourceType.webdav => Icons.cloud,
        SourceType.smb => Icons.lan,
        // 本地存储
        SourceType.local => Icons.folder,
        // 下载工具
        SourceType.qbittorrent => Icons.download,
        SourceType.transmission => Icons.download,
        SourceType.aria2 => Icons.download,
        // 媒体追踪
        SourceType.trakt => Icons.track_changes,
        // 媒体管理
        SourceType.nastool => Icons.video_library,
        SourceType.moviepilot => Icons.video_library,
        SourceType.jellyfin => Icons.live_tv,
        SourceType.emby => Icons.live_tv,
        SourceType.plex => Icons.live_tv,
      };

  /// 获取源类型的描述
  String get description => switch (this) {
        // NAS 设备
        SourceType.synology => '群晖 NAS，支持 DSM 6/7',
        SourceType.qnap => '威联通 NAS',
        SourceType.ugreen => '绿联私有云 NAS',
        SourceType.fnos => '飞牛 fnOS 系统',
        // 通用协议
        SourceType.webdav => '支持 WebDAV 协议的服务器',
        SourceType.smb => 'Windows 共享文件夹协议',
        // 本地存储
        SourceType.local => '设备本地存储',
        // 下载工具
        SourceType.qbittorrent => '开源 BT 下载客户端',
        SourceType.transmission => '轻量级 BT 下载客户端',
        SourceType.aria2 => '多协议下载工具',
        // 媒体追踪
        SourceType.trakt => '追踪观看记录和媒体状态',
        // 媒体管理
        SourceType.nastool => 'NAS 媒体库管理工具',
        SourceType.moviepilot => '影视自动化管理工具',
        SourceType.jellyfin => '开源媒体服务器',
        SourceType.emby => '媒体服务器',
        SourceType.plex => '媒体服务器',
      };

  /// 是否默认使用 SSL
  bool get defaultUseSsl => switch (this) {
        SourceType.synology ||
        SourceType.webdav ||
        SourceType.trakt =>
          true,
        _ => false,
      };

  /// 是否需要用户名（有些服务可能只需要 API Key）
  bool get requiresUsername => switch (this) {
        SourceType.trakt || SourceType.aria2 => false,
        _ => true,
      };

  /// 获取该分组下的所有源类型
  static List<SourceType> byCategory(SourceCategory category) => SourceType.values
        .where((type) => type.category == category)
        .toList();
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
    required this.name,
    required this.type,
    required this.host,
    required this.username,
    String? id,
    this.port = 5001,
    this.useSsl = true,
    this.quickConnectId,
    this.lastConnected,
    this.autoConnect = true,
    this.rememberDevice = false,
    // OAuth 相关字段
    this.accessToken,
    this.refreshToken,
    this.tokenExpiresAt,
    // API Key 相关字段
    this.apiKey,
    // 额外配置
    this.extraConfig,
    // 排序顺序
    this.sortOrder = 0,
  }) : id = id ?? const Uuid().v4();

  factory SourceEntity.fromJson(Map<String, dynamic> json) => SourceEntity(
        id: json['id'] as String,
        name: json['name'] as String,
        type: SourceType.values.firstWhere(
          (t) => t.id == json['type'],
          orElse: () => SourceType.synology,
        ),
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 5001,
        username: json['username'] as String? ?? '',
        useSsl: json['useSsl'] as bool? ?? true,
        quickConnectId: json['quickConnectId'] as String?,
        lastConnected: json['lastConnected'] != null
            ? DateTime.parse(json['lastConnected'] as String)
            : null,
        autoConnect: json['autoConnect'] as bool? ?? true,
        rememberDevice: json['rememberDevice'] as bool? ?? false,
        // OAuth 相关字段
        accessToken: json['accessToken'] as String?,
        refreshToken: json['refreshToken'] as String?,
        tokenExpiresAt: json['tokenExpiresAt'] != null
            ? DateTime.parse(json['tokenExpiresAt'] as String)
            : null,
        // API Key 相关字段
        apiKey: json['apiKey'] as String?,
        // 额外配置 - 从 Hive 读取时需要安全转换类型
        extraConfig: json['extraConfig'] != null
            ? Map<String, dynamic>.from(json['extraConfig'] as Map)
            : null,
        // 排序顺序
        sortOrder: json['sortOrder'] as int? ?? 0,
      );

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

  // === OAuth 相关字段（用于 Trakt 等） ===

  /// OAuth 访问令牌
  final String? accessToken;

  /// OAuth 刷新令牌
  final String? refreshToken;

  /// 令牌过期时间
  final DateTime? tokenExpiresAt;

  // === API Key 相关字段（用于 qBittorrent v5.2+ 等） ===

  /// API Key
  final String? apiKey;

  // === 额外配置 ===

  /// 额外配置（JSON 格式，用于特殊配置）
  /// 例如：Trakt 的 Client ID/Secret，qBittorrent 的认证类型等
  final Map<String, dynamic>? extraConfig;

  // === 排序相关 ===

  /// 排序顺序（数值越小越靠前）
  final int sortOrder;

  String get displayName => name.isNotEmpty ? name : host;

  String get baseUrl {
    final protocol = useSsl ? 'https' : 'http';
    return '$protocol://$host:$port';
  }

  /// 获取唯一标识符（用于凭证存储）
  String get credentialKey => '${type.id}_${host}_${port}_$username';

  /// 是否为服务类源
  bool get isServiceSource => type.isServiceSource;

  /// 是否支持文件系统
  bool get supportsFileSystem => type.supportsFileSystem;

  /// OAuth 令牌是否需要刷新（提前 1 小时刷新）
  bool get needsTokenRefresh {
    if (tokenExpiresAt == null) return false;
    final expiresIn = tokenExpiresAt!.difference(DateTime.now());
    return expiresIn.inHours < 1;
  }

  /// OAuth 令牌是否已过期
  bool get isTokenExpired {
    if (tokenExpiresAt == null) return false;
    return DateTime.now().isAfter(tokenExpiresAt!);
  }

  /// 是否使用 API Key 认证
  bool get usesApiKey => apiKey != null && apiKey!.isNotEmpty;

  /// 是否使用 OAuth 认证
  bool get usesOAuth => accessToken != null && accessToken!.isNotEmpty;

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
    String? accessToken,
    String? refreshToken,
    DateTime? tokenExpiresAt,
    String? apiKey,
    Map<String, dynamic>? extraConfig,
    int? sortOrder,
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
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        tokenExpiresAt: tokenExpiresAt ?? this.tokenExpiresAt,
        apiKey: apiKey ?? this.apiKey,
        extraConfig: extraConfig ?? this.extraConfig,
        sortOrder: sortOrder ?? this.sortOrder,
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
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'tokenExpiresAt': tokenExpiresAt?.toIso8601String(),
        'apiKey': apiKey,
        'extraConfig': extraConfig,
        'sortOrder': sortOrder,
      };
}
