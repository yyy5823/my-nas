import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// 音乐刮削源类型
enum MusicScraperType {
  musicBrainz('MusicBrainz', 'musicbrainz'),
  acoustId('AcoustID', 'acoustid'),
  coverArtArchive('Cover Art Archive', 'coverart'),
  lastFm('Last.fm', 'lastfm'),
  neteaseMusic('网易云音乐', 'netease'),
  qqMusic('QQ音乐', 'qqmusic'),
  genius('Genius', 'genius');

  const MusicScraperType(this.displayName, this.id);

  /// 显示名称
  final String displayName;

  /// 唯一标识符
  final String id;

  /// 图标
  IconData get icon => switch (this) {
        MusicScraperType.musicBrainz => Icons.album_rounded,
        MusicScraperType.acoustId => Icons.fingerprint_rounded,
        MusicScraperType.coverArtArchive => Icons.image_rounded,
        MusicScraperType.lastFm => Icons.radio_rounded,
        MusicScraperType.neteaseMusic => Icons.cloud_rounded,
        MusicScraperType.qqMusic => Icons.music_note_rounded,
        MusicScraperType.genius => Icons.lyrics_rounded,
      };

  /// 主题色
  Color get themeColor => switch (this) {
        MusicScraperType.musicBrainz => const Color(0xFFBA478F), // MusicBrainz purple
        MusicScraperType.acoustId => const Color(0xFF5BC0DE), // AcoustID blue
        MusicScraperType.coverArtArchive => const Color(0xFFEB743B), // CAA orange
        MusicScraperType.lastFm => const Color(0xFFD51007), // Last.fm red
        MusicScraperType.neteaseMusic => const Color(0xFFE60026), // 网易云红
        MusicScraperType.qqMusic => const Color(0xFF31C27C), // QQ音乐绿
        MusicScraperType.genius => const Color(0xFFFFFF64), // Genius yellow
      };

  /// 描述
  String get description => switch (this) {
        MusicScraperType.musicBrainz => '开放音乐数据库，支持元数据查询',
        MusicScraperType.acoustId => '声纹识别服务，需要 API Key',
        MusicScraperType.coverArtArchive => 'MusicBrainz 封面数据库',
        MusicScraperType.lastFm => '音乐社区，支持元数据和封面',
        MusicScraperType.neteaseMusic => '国内音乐平台，支持歌词和封面',
        MusicScraperType.qqMusic => '国内音乐平台，支持歌词和封面',
        MusicScraperType.genius => '歌词数据库，支持英文歌词',
      };

  /// 是否支持元数据
  bool get supportsMetadata => [
        MusicScraperType.musicBrainz,
        MusicScraperType.lastFm,
        MusicScraperType.neteaseMusic,
        MusicScraperType.qqMusic,
        MusicScraperType.genius,
      ].contains(this);

  /// 是否支持封面
  bool get supportsCover => [
        MusicScraperType.coverArtArchive,
        MusicScraperType.lastFm,
        MusicScraperType.neteaseMusic,
        MusicScraperType.qqMusic,
        MusicScraperType.genius,
      ].contains(this);

  /// 是否支持歌词
  bool get supportsLyrics => [
        MusicScraperType.neteaseMusic,
        MusicScraperType.qqMusic,
        MusicScraperType.genius,
      ].contains(this);

  /// 是否支持声纹识别
  bool get supportsFingerprint => this == MusicScraperType.acoustId;

  /// 是否需要 API Key
  bool get requiresApiKey => [
        MusicScraperType.acoustId,
        MusicScraperType.lastFm,
        MusicScraperType.genius,
      ].contains(this);

  /// 是否需要 Cookie（可选）
  bool get supportsCookie => [
        MusicScraperType.neteaseMusic,
        MusicScraperType.qqMusic,
      ].contains(this);

  /// 从 id 获取类型
  static MusicScraperType fromId(String id) => MusicScraperType.values.firstWhere(
        (t) => t.id == id,
        orElse: () => MusicScraperType.musicBrainz,
      );
}

/// 音乐刮削源实体
class MusicScraperSourceEntity {
  MusicScraperSourceEntity({
    String? id,
    required this.name,
    required this.type,
    this.isEnabled = true,
    this.priority = 0,
    this.apiKey,
    this.cookie,
    this.extraConfig,
  })  : id = id ?? const Uuid().v4();

  factory MusicScraperSourceEntity.fromJson(Map<String, dynamic> json) =>
      MusicScraperSourceEntity(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        type: MusicScraperType.fromId(json['type'] as String? ?? 'musicbrainz'),
        isEnabled: json['isEnabled'] as bool? ?? true,
        priority: json['priority'] as int? ?? 0,
        apiKey: json['apiKey'] as String?,
        cookie: json['cookie'] as String?,
        extraConfig: json['extraConfig'] != null
            ? Map<String, dynamic>.from(json['extraConfig'] as Map)
            : null,
      );

  /// 唯一标识符
  final String id;

  /// 显示名称
  final String name;

  /// 刮削源类型
  final MusicScraperType type;

  /// 是否启用
  final bool isEnabled;

  /// 优先级（数值越小优先级越高）
  final int priority;

  /// API Key
  final String? apiKey;

  /// Cookie（网易云、QQ音乐可选）
  final String? cookie;

  /// 额外配置
  final Map<String, dynamic>? extraConfig;

  /// 获取显示名称
  String get displayName => name.isNotEmpty ? name : type.displayName;

  /// 是否已配置（有必要的凭证）
  bool get isConfigured => switch (type) {
        MusicScraperType.musicBrainz => true, // 无需认证
        MusicScraperType.acoustId => apiKey != null && apiKey!.isNotEmpty,
        MusicScraperType.coverArtArchive => true, // 无需认证
        MusicScraperType.lastFm => apiKey != null && apiKey!.isNotEmpty,
        MusicScraperType.neteaseMusic => true, // Cookie 可选
        MusicScraperType.qqMusic => true, // Cookie 可选
        MusicScraperType.genius => apiKey != null && apiKey!.isNotEmpty,
      };

  /// 获取请求间隔（秒）
  int get requestInterval =>
      extraConfig?['requestInterval'] as int? ??
      switch (type) {
        MusicScraperType.musicBrainz => 1, // MusicBrainz 要求 1 秒间隔
        MusicScraperType.neteaseMusic => 1,
        MusicScraperType.qqMusic => 1,
        _ => 0,
      };

  MusicScraperSourceEntity copyWith({
    String? id,
    String? name,
    MusicScraperType? type,
    bool? isEnabled,
    int? priority,
    String? apiKey,
    String? cookie,
    Map<String, dynamic>? extraConfig,
  }) =>
      MusicScraperSourceEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        isEnabled: isEnabled ?? this.isEnabled,
        priority: priority ?? this.priority,
        apiKey: apiKey ?? this.apiKey,
        cookie: cookie ?? this.cookie,
        extraConfig: extraConfig ?? this.extraConfig,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.id,
        'isEnabled': isEnabled,
        'priority': priority,
        'apiKey': apiKey,
        'cookie': cookie,
        'extraConfig': extraConfig,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicScraperSourceEntity &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 音乐刮削凭证
class MusicScraperCredential {
  const MusicScraperCredential({
    this.apiKey,
    this.cookie,
  });

  factory MusicScraperCredential.fromJson(Map<String, dynamic> json) =>
      MusicScraperCredential(
        apiKey: json['apiKey'] as String?,
        cookie: json['cookie'] as String?,
      );

  final String? apiKey;
  final String? cookie;

  bool get isEmpty =>
      (apiKey == null || apiKey!.isEmpty) &&
      (cookie == null || cookie!.isEmpty);

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'cookie': cookie,
      };
}
