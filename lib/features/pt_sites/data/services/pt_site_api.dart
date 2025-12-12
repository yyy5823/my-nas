import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/features/pt_sites/domain/entities/pt_torrent.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

/// PT 站点 API 基类
abstract class PTSiteApi {
  PTSiteApi({
    required this.source,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final SourceEntity source;
  final http.Client _client;

  /// 获取基础 URL
  String get baseUrl {
    final protocol = source.useSsl ? 'https' : 'http';
    final port = source.port == 443 || source.port == 80 ? '' : ':${source.port}';
    return '$protocol://${source.host}$port';
  }

  /// 获取请求头
  Map<String, String> get headers;

  /// 测试连接
  Future<bool> testConnection();

  /// 获取用户信息
  Future<PTUserInfo> getUserInfo();

  /// 获取种子列表
  Future<List<PTTorrent>> getTorrents({
    int page = 1,
    int pageSize = 50,
    String? category,
    String? keyword,
    PTTorrentSortBy sortBy = PTTorrentSortBy.uploadTime,
    bool descending = true,
  });

  /// 获取种子详情
  Future<PTTorrent> getTorrentDetail(String torrentId);

  /// 获取种子下载链接
  Future<String> getDownloadUrl(String torrentId);

  /// 获取分类列表
  Future<List<PTCategory>> getCategories();

  /// 搜索种子
  Future<List<PTTorrent>> searchTorrents(String keyword, {int page = 1});

  /// 关闭连接
  void dispose() {
    _client.close();
  }
}

/// 排序方式
enum PTTorrentSortBy {
  uploadTime,
  size,
  seeders,
  leechers,
  snatched,
  name,
}

/// 馒头 M-Team API
class MTeamApi extends PTSiteApi {
  MTeamApi({required super.source, super.client});

  @override
  Map<String, String> get headers {
    final xApiKey = source.extraConfig?['xApiKey'] as String? ?? '';
    final authorization = source.extraConfig?['authorization'] as String? ?? '';
    return {
      'Content-Type': 'application/json',
      'x-api-key': xApiKey,
      'authorization': authorization,
      'User-Agent': source.extraConfig?['userAgent'] as String? ??
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    };
  }

  String get _apiBase => 'https://api.m-team.cc';

  @override
  Future<bool> testConnection() async {
    try {
      final response = await _client.post(
        Uri.parse('$_apiBase/api/member/profile'),
        headers: headers,
      );
      return response.statusCode == 200;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '测试连接失败，用户可感知');
      return false;
    }
  }

  @override
  Future<PTUserInfo> getUserInfo() async {
    try {
      final response = await _client.post(
        Uri.parse('$_apiBase/api/member/profile'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('获取用户信息失败: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['code'] != '0') {
        throw Exception(data['message'] ?? '获取用户信息失败');
      }

      final profile = data['data'] as Map<String, dynamic>;
      final memberCount = profile['memberCount'] as Map<String, dynamic>? ?? {};

      return PTUserInfo(
        username: profile['username'] as String? ?? '',
        userId: profile['id']?.toString() ?? '',
        userClass: profile['role'] as String?,
        uploaded: _parseBytes(memberCount['uploaded']),
        downloaded: _parseBytes(memberCount['downloaded']),
        ratio: double.tryParse(memberCount['shareRate']?.toString() ?? ''),
        bonus: double.tryParse(profile['bonus']?.toString() ?? '0') ?? 0,
        seedingCount: memberCount['seeding'] as int? ?? 0,
        leechingCount: memberCount['leeching'] as int? ?? 0,
      );
    } catch (e, st) {
      AppError.handle(e, st, 'MTeamApi.getUserInfo');
      rethrow;
    }
  }

  @override
  Future<List<PTTorrent>> getTorrents({
    int page = 1,
    int pageSize = 50,
    String? category,
    String? keyword,
    PTTorrentSortBy sortBy = PTTorrentSortBy.uploadTime,
    bool descending = true,
  }) async {
    try {
      final body = <String, dynamic>{
        'pageNumber': page,
        'pageSize': pageSize,
        'visible': 1,
      };

      if (category != null) {
        body['categories'] = [category];
      }

      if (keyword != null && keyword.isNotEmpty) {
        body['keyword'] = keyword;
        body['mode'] = 'normal';
      }

      // 排序
      final sortField = switch (sortBy) {
        PTTorrentSortBy.uploadTime => 'CREATED_DATE',
        PTTorrentSortBy.size => 'SIZE',
        PTTorrentSortBy.seeders => 'LEECHERS',
        PTTorrentSortBy.leechers => 'SEEDERS',
        PTTorrentSortBy.snatched => 'TIMES_COMPLETED',
        PTTorrentSortBy.name => 'NAME',
      };
      body['sortField'] = sortField;
      body['sortDirection'] = descending ? 'DESC' : 'ASC';

      final response = await _client.post(
        Uri.parse('$_apiBase/api/torrent/search'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode != 200) {
        throw Exception('获取种子列表失败: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['code'] != '0') {
        throw Exception(data['message'] ?? '获取种子列表失败');
      }

      final torrentsData = data['data'] as Map<String, dynamic>? ?? {};
      final list = torrentsData['data'] as List<dynamic>? ?? [];

      return list.map((item) => _parseTorrent(item as Map<String, dynamic>)).toList();
    } catch (e, st) {
      AppError.handle(e, st, 'MTeamApi.getTorrents');
      rethrow;
    }
  }

  @override
  Future<PTTorrent> getTorrentDetail(String torrentId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_apiBase/api/torrent/detail'),
        headers: headers,
        body: json.encode({'id': torrentId}),
      );

      if (response.statusCode != 200) {
        throw Exception('获取种子详情失败: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['code'] != '0') {
        throw Exception(data['message'] ?? '获取种子详情失败');
      }

      return _parseTorrent(data['data'] as Map<String, dynamic>);
    } catch (e, st) {
      AppError.handle(e, st, 'MTeamApi.getTorrentDetail');
      rethrow;
    }
  }

  @override
  Future<String> getDownloadUrl(String torrentId) async {
    try {
      final response = await _client.post(
        Uri.parse('$_apiBase/api/torrent/genDlToken'),
        headers: headers,
        body: json.encode({'id': torrentId}),
      );

      if (response.statusCode != 200) {
        throw Exception('获取下载链接失败: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['code'] != '0') {
        throw Exception(data['message'] ?? '获取下载链接失败');
      }

      return data['data'] as String? ?? '';
    } catch (e, st) {
      AppError.handle(e, st, 'MTeamApi.getDownloadUrl');
      rethrow;
    }
  }

  @override
  Future<List<PTCategory>> getCategories() async => [
      const PTCategory(id: '401', name: '电影/Movie'),
      const PTCategory(id: '404', name: '纪录/Documentary'),
      const PTCategory(id: '405', name: '动漫/Anime'),
      const PTCategory(id: '402', name: '剧集/TV Series'),
      const PTCategory(id: '403', name: '综艺/TV Show'),
      const PTCategory(id: '406', name: '体育/Sports'),
      const PTCategory(id: '407', name: 'MV/Music Video'),
      const PTCategory(id: '408', name: '音乐/Music'),
      const PTCategory(id: '410', name: '软件/Software'),
      const PTCategory(id: '411', name: '学习/Education'),
      const PTCategory(id: '409', name: '其他/Other'),
    ];

  @override
  Future<List<PTTorrent>> searchTorrents(String keyword, {int page = 1}) =>
      getTorrents(keyword: keyword, page: page);

  PTTorrent _parseTorrent(Map<String, dynamic> data) {
    final status = data['status'] as Map<String, dynamic>? ?? {};

    return PTTorrent(
      id: data['id']?.toString() ?? '',
      name: data['name'] as String? ?? '',
      size: _parseBytes(data['size']),
      seeders: (status['seeders'] as int?) ?? 0,
      leechers: (status['leechers'] as int?) ?? 0,
      snatched: (status['timesCompleted'] as int?) ?? 0,
      uploadTime: DateTime.tryParse(data['createdDate'] as String? ?? '') ?? DateTime.now(),
      category: data['category'] as String?,
      smallDescr: data['smallDescr'] as String?,
      detailUrl: '$baseUrl/detail/${data['id']}',
      imdbId: data['imdb'] as String?,
      doubanId: data['douban'] as String?,
      status: PTTorrentStatus(
        isFree: status['discount'] == 'FREE' || status['discount'] == '_2X_FREE',
        isDoubleFree: status['discount'] == '_2X_FREE',
        isHalfDown: status['discount'] == '_50_PERCENT_OFF',
        isDoubleUp: status['discount'] == '_2X_UPLOAD',
        freeEndTime: status['discountEndTime'] != null
            ? DateTime.tryParse(status['discountEndTime'] as String)
            : null,
      ),
      labels: _parseLabels(data),
    );
  }

  List<String> _parseLabels(Map<String, dynamic> data) {
    final labels = <String>[];

    // 解析标签
    if (data['labels'] != null) {
      final labelList = data['labels'] as List<dynamic>? ?? [];
      for (final label in labelList) {
        if (label is String) {
          labels.add(label);
        } else if (label is Map) {
          labels.add(label['name']?.toString() ?? '');
        }
      }
    }

    // 解析编码格式等
    if (data['videoCodec'] != null) labels.add(data['videoCodec'] as String);
    if (data['audioCodec'] != null) labels.add(data['audioCodec'] as String);
    if (data['resolution'] != null) labels.add(data['resolution'] as String);
    if (data['source'] != null) labels.add(data['source'] as String);

    return labels.where((l) => l.isNotEmpty).toList();
  }

  int _parseBytes(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

/// Cookie 认证的 PT 站点 API 基类
class CookiePTSiteApi extends PTSiteApi {
  CookiePTSiteApi({required super.source, super.client});

  @override
  Map<String, String> get headers {
    final cookie = source.extraConfig?['cookie'] as String? ?? '';
    return {
      'Cookie': cookie,
      'User-Agent': source.extraConfig?['userAgent'] as String? ??
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };
  }

  @override
  Future<bool> testConnection() async {
    try {
      final response = await _client.get(
        Uri.parse(baseUrl),
        headers: headers,
      );
      // 检查是否被重定向到登录页
      return response.statusCode == 200 &&
          !response.body.contains('login') &&
          !response.body.contains('登录');
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '测试连接失败，用户可感知');
      return false;
    }
  }

  @override
  Future<PTUserInfo> getUserInfo() async => const PTUserInfo(
    username: '',
    userId: '',
  );

  @override
  Future<List<PTTorrent>> getTorrents({
    int page = 1,
    int pageSize = 50,
    String? category,
    String? keyword,
    PTTorrentSortBy sortBy = PTTorrentSortBy.uploadTime,
    bool descending = true,
  }) async => [];

  @override
  Future<PTTorrent> getTorrentDetail(String torrentId) async =>
      throw UnimplementedError('需要在子类中实现');

  @override
  Future<String> getDownloadUrl(String torrentId) async =>
      '$baseUrl/download.php?id=$torrentId';

  @override
  Future<List<PTCategory>> getCategories() async => [];

  @override
  Future<List<PTTorrent>> searchTorrents(String keyword, {int page = 1}) =>
      getTorrents(keyword: keyword, page: page);
}

/// PT 站点 API 工厂
class PTSiteApiFactory {
  static PTSiteApi create(SourceEntity source) => switch (source.type) {
      SourceType.mteam => MTeamApi(source: source),
      // 其他站点暂时使用通用 Cookie API
      _ => CookiePTSiteApi(source: source),
    };
}
