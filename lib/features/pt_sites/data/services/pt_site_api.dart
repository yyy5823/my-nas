import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/features/pt_sites/domain/entities/pt_torrent.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

final _logger = Logger();

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
      // 检查必要的认证信息
      final xApiKey = source.extraConfig?['xApiKey'] as String? ?? '';
      final authorization = source.extraConfig?['authorization'] as String? ?? '';

      _logger
        ..d('MTeamApi.testConnection: extraConfig = ${source.extraConfig}')
        ..d('MTeamApi.testConnection: xApiKey = ${xApiKey.isNotEmpty ? "已配置(${xApiKey.length}字符)" : "未配置"}')
        ..d('MTeamApi.testConnection: authorization = ${authorization.isNotEmpty ? "已配置(${authorization.length}字符)" : "未配置"}')
        ..d('MTeamApi.testConnection: headers = $headers');

      if (xApiKey.isEmpty && authorization.isEmpty) {
        _logger.w('MTeamApi.testConnection: 缺少认证信息');
        AppError.ignore(
          Exception('缺少认证信息'),
          StackTrace.current,
          '馒头站点需要配置 x-api-key 或 authorization 请求头',
        );
        return false;
      }

      _logger.i('MTeamApi.testConnection: 开始请求 $_apiBase/api/member/profile');
      final response = await _client.post(
        Uri.parse('$_apiBase/api/member/profile'),
        headers: headers,
      );

      _logger
        ..d('MTeamApi.testConnection: HTTP ${response.statusCode}')
        ..d('MTeamApi.testConnection: response = ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        // 检查 API 返回的状态码
        if (data['code'] == '0') {
          _logger.i('MTeamApi.testConnection: 连接成功');
          return true;
        }
        // API 返回错误
        final message = data['message'] as String? ?? '未知错误';
        _logger.w('MTeamApi.testConnection: API 返回错误 - $message');
        AppError.ignore(
          Exception('API 返回错误: $message'),
          StackTrace.current,
          '馒头 API 返回错误: $message',
        );
        return false;
      }

      // HTTP 状态码错误
      _logger.w('MTeamApi.testConnection: HTTP 状态码错误 ${response.statusCode}');
      AppError.ignore(
        Exception('HTTP ${response.statusCode}'),
        StackTrace.current,
        '馒头连接失败: HTTP ${response.statusCode}',
      );
      return false;
    } on Exception catch (e, st) {
      _logger.e('MTeamApi.testConnection: 异常 - $e');
      AppError.ignore(e, st, '馒头测试连接失败');
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

/// 通用 PT 站点 API
/// 支持 Cookie 认证和自定义请求头认证
class GenericPTSiteApi extends PTSiteApi {
  GenericPTSiteApi({required super.source, super.client});

  @override
  Map<String, String> get headers {
    final authType = source.extraConfig?['authType'] as String? ?? 'Cookie';
    final userAgent = source.extraConfig?['userAgent'] as String? ??
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36';

    final result = <String, String>{
      'User-Agent': userAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };

    if (authType == '自定义请求头') {
      // 使用自定义请求头
      final customHeaders = source.extraConfig?['customHeaders'];
      if (customHeaders is List) {
        for (final header in customHeaders) {
          if (header is Map) {
            final key = header['key']?.toString() ?? '';
            final value = header['value']?.toString() ?? '';
            if (key.isNotEmpty) {
              result[key] = value;
            }
          }
        }
      }
      // 添加 Content-Type（自定义请求头模式通常使用 JSON API）
      result['Content-Type'] = 'application/json';
    } else {
      // Cookie 认证
      final cookie = source.extraConfig?['cookie'] as String? ?? '';
      if (cookie.isNotEmpty) {
        result['Cookie'] = cookie;
      }
    }

    return result;
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
  /// 创建 PT 站点 API 实例
  /// 根据站点类型选择合适的 API 实现
  static PTSiteApi create(SourceEntity source) {
    _logger
      ..d('PTSiteApiFactory.create: source.name = ${source.name}, host = ${source.host}')
      ..d('PTSiteApiFactory.create: extraConfig = ${source.extraConfig}');

    // 判断是否是馒头站点
    if (_isMTeamSite(source)) {
      _logger.i('PTSiteApiFactory.create: 识别为馒头站点，使用 MTeamApi');
      final convertedSource = _convertToMTeamConfig(source);
      _logger.d('PTSiteApiFactory.create: 转换后 extraConfig = ${convertedSource.extraConfig}');
      return MTeamApi(source: convertedSource);
    }
    _logger.i('PTSiteApiFactory.create: 使用通用 GenericPTSiteApi');
    return GenericPTSiteApi(source: source);
  }

  /// 判断是否是馒头站点
  static bool _isMTeamSite(SourceEntity source) {
    final host = source.host.toLowerCase();
    final name = source.name.toLowerCase();

    // 通过域名判断
    if (host.contains('m-team') || host.contains('mteam')) {
      return true;
    }

    // 通过名称判断
    if (name.contains('馒头') || name.contains('m-team') || name.contains('mteam')) {
      return true;
    }

    return false;
  }

  /// 将通用配置转换为馒头专用配置
  /// 从自定义请求头中提取 x-api-key 和 authorization
  static SourceEntity _convertToMTeamConfig(SourceEntity source) {
    final extraConfig = Map<String, dynamic>.from(source.extraConfig ?? {});

    _logger.d('PTSiteApiFactory._convertToMTeamConfig: 原始 customHeaders = ${extraConfig['customHeaders']}');

    // 从自定义请求头中提取馒头需要的字段
    final customHeaders = extraConfig['customHeaders'];
    if (customHeaders is List) {
      _logger.d('PTSiteApiFactory._convertToMTeamConfig: customHeaders 是 List，共 ${customHeaders.length} 项');
      for (final header in customHeaders) {
        _logger.d('PTSiteApiFactory._convertToMTeamConfig: 处理 header = $header (type: ${header.runtimeType})');
        if (header is Map) {
          final key = header['key']?.toString().toLowerCase() ?? '';
          final value = header['value']?.toString() ?? '';
          _logger.d('PTSiteApiFactory._convertToMTeamConfig: key = $key, value.length = ${value.length}');

          if (key == 'x-api-key') {
            extraConfig['xApiKey'] = value;
            _logger.i('PTSiteApiFactory._convertToMTeamConfig: 提取 xApiKey 成功');
          } else if (key == 'authorization') {
            extraConfig['authorization'] = value;
            _logger.i('PTSiteApiFactory._convertToMTeamConfig: 提取 authorization 成功');
          }
        }
      }
    } else {
      _logger.w('PTSiteApiFactory._convertToMTeamConfig: customHeaders 不是 List 类型: ${customHeaders?.runtimeType}');
    }

    return source.copyWith(extraConfig: extraConfig);
  }
}
