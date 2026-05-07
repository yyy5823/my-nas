import 'package:uuid/uuid.dart';

/// 刮削源类型。
///
/// 注意：本应用 **不内嵌任何 scrape 源**，所有源均由用户自行导入。
enum ScrapeSourceType {
  video, // 影视元数据
  music, // 音乐元数据
  lyric, // 歌词
}

ScrapeSourceType _parseType(String? raw) => switch (raw) {
      'music' => ScrapeSourceType.music,
      'lyric' => ScrapeSourceType.lyric,
      _ => ScrapeSourceType.video,
    };

String _typeName(ScrapeSourceType t) => switch (t) {
      ScrapeSourceType.video => 'video',
      ScrapeSourceType.music => 'music',
      ScrapeSourceType.lyric => 'lyric',
    };

/// 单条 HTTP 请求模板。`url` / `body` 内可以包含变量占位符：
/// `{query}` / `{link}` / `{title}` / `{artist}` 等，由引擎在执行时替换。
class ScrapeRequest {
  ScrapeRequest({
    required this.url,
    this.method = 'GET',
    this.body,
    this.bodyType = 'form', // form | json | raw
    this.responseType = 'html', // html | json
  });

  factory ScrapeRequest.fromJson(Map<String, dynamic> json) => ScrapeRequest(
        url: json['url'] as String? ?? '',
        method: (json['method'] as String? ?? 'GET').toUpperCase(),
        body: json['body'] as String?,
        bodyType: json['bodyType'] as String? ?? 'form',
        responseType: json['responseType'] as String? ?? 'html',
      );

  final String url;
  final String method;
  final String? body;
  final String bodyType;
  final String responseType;

  Map<String, dynamic> toJson() => {
        'url': url,
        'method': method,
        if (body != null) 'body': body,
        'bodyType': bodyType,
        'responseType': responseType,
      };
}

/// 字段提取规则。
///
/// 每个字段值是一个 selector 字符串，按前缀分发：
/// - `xpath::xxx`  — XPath（HTML/XML 响应）
/// - `json::$.x.y` — JSONPath（JSON 响应）
/// - `regex::p`    — 正则（在响应纯文本上）
/// - `css::a.cls`  — CSS 选择器（默认；前缀可省）
///
/// 前缀后再加 `@attr` 取属性，加 `@text` 取文本，加 `@html` 取 innerHTML。
/// 例：`css::div.title@text`、`xpath:://img/@src`。
class ScrapeFieldsRule {
  ScrapeFieldsRule(this.fields);

  factory ScrapeFieldsRule.fromJson(Map<String, dynamic> json) =>
      ScrapeFieldsRule(
        json.map((k, v) => MapEntry(k, v.toString())),
      );

  final Map<String, String> fields;

  String? operator [](String key) => fields[key];

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(fields);
}

/// 刮削源实体。结构对齐 BookSource 的命名风格便于复用 UI 习惯。
class JsScrapeSource {
  JsScrapeSource({
    String? id,
    required this.name,
    required this.type,
    this.origin = '',
    this.enabled = true,
    this.headers,
    this.searchRequest,
    this.searchListSelector = '',
    this.searchItemRule,
    this.detailRequest,
    this.detailRule,
    this.lyricRequest,
    this.lyricContentSelector,
    this.customOrder = 0,
    this.lastUpdateTime = 0,
  }) : id = id ?? const Uuid().v4();

  factory JsScrapeSource.fromJson(Map<String, dynamic> json) {
    int parseIntSafe(dynamic v, [int d = 0]) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? d;
      return d;
    }

    bool parseBoolSafe(dynamic v, [bool d = true]) {
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true' || v == '1';
      if (v is int) return v != 0;
      return d;
    }

    final headersRaw = json['headers'];
    final headers = headersRaw is Map
        ? headersRaw.map((k, v) => MapEntry(k.toString(), v.toString()))
        : null;

    return JsScrapeSource(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      type: _parseType(json['type'] as String?),
      origin: json['origin'] as String? ?? '',
      enabled: parseBoolSafe(json['enabled'], true),
      headers: headers,
      searchRequest: json['searchRequest'] is Map
          ? ScrapeRequest.fromJson(
              Map<String, dynamic>.from(json['searchRequest'] as Map))
          : null,
      searchListSelector: json['searchListSelector'] as String? ?? '',
      searchItemRule: json['searchItemRule'] is Map
          ? ScrapeFieldsRule.fromJson(
              Map<String, dynamic>.from(json['searchItemRule'] as Map))
          : null,
      detailRequest: json['detailRequest'] is Map
          ? ScrapeRequest.fromJson(
              Map<String, dynamic>.from(json['detailRequest'] as Map))
          : null,
      detailRule: json['detailRule'] is Map
          ? ScrapeFieldsRule.fromJson(
              Map<String, dynamic>.from(json['detailRule'] as Map))
          : null,
      lyricRequest: json['lyricRequest'] is Map
          ? ScrapeRequest.fromJson(
              Map<String, dynamic>.from(json['lyricRequest'] as Map))
          : null,
      lyricContentSelector: json['lyricContentSelector'] as String?,
      customOrder: parseIntSafe(json['customOrder'], 0),
      lastUpdateTime: parseIntSafe(json['lastUpdateTime'], 0),
    );
  }

  final String id;
  String name;
  ScrapeSourceType type;
  String origin;
  bool enabled;
  Map<String, String>? headers;

  ScrapeRequest? searchRequest;
  String searchListSelector; // 选择条目数组的根节点
  ScrapeFieldsRule? searchItemRule;

  ScrapeRequest? detailRequest;
  ScrapeFieldsRule? detailRule;

  ScrapeRequest? lyricRequest;
  String? lyricContentSelector;

  int customOrder;
  int lastUpdateTime;

  String get displayName => name.isEmpty ? origin : name;

  JsScrapeSource copyWith({
    String? id,
    String? name,
    ScrapeSourceType? type,
    String? origin,
    bool? enabled,
    Map<String, String>? headers,
    ScrapeRequest? searchRequest,
    String? searchListSelector,
    ScrapeFieldsRule? searchItemRule,
    ScrapeRequest? detailRequest,
    ScrapeFieldsRule? detailRule,
    ScrapeRequest? lyricRequest,
    String? lyricContentSelector,
    int? customOrder,
    int? lastUpdateTime,
  }) =>
      JsScrapeSource(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        origin: origin ?? this.origin,
        enabled: enabled ?? this.enabled,
        headers: headers ?? this.headers,
        searchRequest: searchRequest ?? this.searchRequest,
        searchListSelector: searchListSelector ?? this.searchListSelector,
        searchItemRule: searchItemRule ?? this.searchItemRule,
        detailRequest: detailRequest ?? this.detailRequest,
        detailRule: detailRule ?? this.detailRule,
        lyricRequest: lyricRequest ?? this.lyricRequest,
        lyricContentSelector:
            lyricContentSelector ?? this.lyricContentSelector,
        customOrder: customOrder ?? this.customOrder,
        lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': _typeName(type),
        'origin': origin,
        'enabled': enabled,
        if (headers != null) 'headers': headers,
        if (searchRequest != null) 'searchRequest': searchRequest!.toJson(),
        'searchListSelector': searchListSelector,
        if (searchItemRule != null) 'searchItemRule': searchItemRule!.toJson(),
        if (detailRequest != null) 'detailRequest': detailRequest!.toJson(),
        if (detailRule != null) 'detailRule': detailRule!.toJson(),
        if (lyricRequest != null) 'lyricRequest': lyricRequest!.toJson(),
        if (lyricContentSelector != null)
          'lyricContentSelector': lyricContentSelector,
        'customOrder': customOrder,
        'lastUpdateTime': lastUpdateTime,
      };
}

/// 搜索结果条目（统一 schema，按 type 解释）。
class ScrapeItem {
  ScrapeItem(this.fields);
  final Map<String, String> fields;

  String? get title => fields['title'];
  String? get subtitle => fields['subtitle'];
  String? get year => fields['year'];
  String? get image => fields['image'];
  String? get link => fields['link'];
  String? get extraId => fields['id'];

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(fields);
}
