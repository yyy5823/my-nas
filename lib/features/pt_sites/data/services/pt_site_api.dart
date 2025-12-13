import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
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
    // 如果 host 已经包含协议，解析并使用其 scheme 和 host
    if (source.host.startsWith('http://') || source.host.startsWith('https://')) {
      final uri = Uri.parse(source.host);
      final port = source.port == 443 || source.port == 80 ? '' : ':${source.port}';
      return '${uri.scheme}://${uri.host}$port';
    }
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
  MTeamApi({required super.source, super.client}) : _ioClient = _createIOClient();

  /// 创建禁用自动重定向的 IOClient，以便更好地处理 302 等状态码
  static http.Client _createIOClient() {
    final httpClient = HttpClient();
    // ignore: cascade_invocations
    httpClient.badCertificateCallback = (cert, host, port) => true;
    // ignore: cascade_invocations
    httpClient.connectionTimeout = const Duration(seconds: 30);
    // 禁用自动重定向，以便能够检测到 302 等认证问题
    // ignore: cascade_invocations
    httpClient.autoUncompress = true;
    return IOClient(httpClient);
  }

  final http.Client _ioClient;

  @override
  Map<String, String> get headers {
    final xApiKey = source.extraConfig?['xApiKey'] as String? ?? '';
    // 获取 userAgent，确保空字符串也使用默认值
    final configUserAgent = source.extraConfig?['userAgent'] as String?;
    final userAgent = (configUserAgent != null && configUserAgent.isNotEmpty)
        ? configUserAgent
        : 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

    // 参考 nas-tools 实现: 只需要 x-api-key，不需要 authorization
    // https://github.com/linyuan0213/nas-tools/blob/master/app/indexer/client/_mteam.py
    return {
      'Content-Type': 'application/json; charset=utf-8',
      'x-api-key': xApiKey,
      'User-Agent': userAgent,
    };
  }

  String get _apiBase => 'https://api.m-team.cc';

  @override
  void dispose() {
    _ioClient.close();
    super.dispose();
  }

  @override
  Future<bool> testConnection() async {
    try {
      // 检查必要的认证信息（只需要 x-api-key）
      final xApiKey = source.extraConfig?['xApiKey'] as String? ?? '';

      _logger
        ..d('MTeamApi.testConnection: extraConfig = ${source.extraConfig}')
        ..d('MTeamApi.testConnection: xApiKey = ${xApiKey.isNotEmpty ? "已配置(${xApiKey.length}字符)" : "未配置"}')
        ..d('MTeamApi.testConnection: headers = $headers');

      if (xApiKey.isEmpty) {
        _logger.w('MTeamApi.testConnection: 缺少 x-api-key');
        AppError.ignore(
          Exception('缺少认证信息'),
          StackTrace.current,
          '馒头站点需要配置 x-api-key',
        );
        return false;
      }

      // 使用搜索接口测试连接（不需要 uid 参数）
      // 参考 nas-tools 的实现: https://github.com/linyuan0213/nas-tools
      _logger.i('MTeamApi.testConnection: 开始请求 $_apiBase/api/torrent/search');

      // 构建搜索请求体
      final searchBody = json.encode({
        'mode': 'normal',
        'categories': <String>[],
        'visible': 1,
        'keyword': '',
        'pageNumber': 1,
        'pageSize': 1, // 只获取一条用于测试
      });

      final response = await _ioClient.post(
        Uri.parse('$_apiBase/api/torrent/search'),
        headers: headers,
        body: searchBody,
      );

      _logger
        ..d('MTeamApi.testConnection: HTTP ${response.statusCode}')
        ..d('MTeamApi.testConnection: response = ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        // 检查 API 返回的状态码（可能是字符串 "0" 或整数 0）
        final code = data['code'];
        if (code == '0' || code == 0 || code == 'SUCCESS') {
          _logger.i('MTeamApi.testConnection: 连接成功');
          return true;
        }
        // API 返回错误
        final message = data['message'] as String? ?? '未知错误';
        _logger.w('MTeamApi.testConnection: API 返回错误 - code=$code, message=$message');
        AppError.ignore(
          Exception('API 返回错误: $message'),
          StackTrace.current,
          '馒头 API 返回错误: $message',
        );
        return false;
      }

      // HTTP 状态码错误
      _logger.w('MTeamApi.testConnection: HTTP 状态码错误 ${response.statusCode}');

      // 302 重定向通常表示认证信息无效或已过期
      final errorMessage = switch (response.statusCode) {
        302 => '认证信息可能已过期，请更新 x-api-key',
        401 => '认证失败，请检查 x-api-key 是否正确',
        403 => '访问被拒绝，请检查账号权限',
        _ => 'HTTP ${response.statusCode}',
      };

      AppError.ignore(
        Exception(errorMessage),
        StackTrace.current,
        '馒头连接失败: $errorMessage',
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
      // /api/member/profile 需要 uid 参数
      // 从 authorization JWT token 解析 uid，或从配置获取
      final uid = _extractUidFromConfig();
      if (uid == null) {
        _logger.w('MTeamApi.getUserInfo: 无法获取 uid，返回空用户信息');
        return const PTUserInfo(username: '', userId: '');
      }

      final response = await _ioClient.post(
        Uri.parse('$_apiBase/api/member/profile?uid=$uid'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('获取用户信息失败: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final code = data['code'];
      if (code != '0' && code != 0 && code != 'SUCCESS') {
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

  /// 从配置或 JWT token 中提取 uid
  int? _extractUidFromConfig() {
    // 优先从 extraConfig 获取
    final configUid = source.extraConfig?['uid'];
    if (configUid != null) {
      if (configUid is int) return configUid;
      if (configUid is String) return int.tryParse(configUid);
    }

    // 尝试从 authorization JWT token 解析 uid
    final authorization = source.extraConfig?['authorization'] as String?;
    if (authorization != null && authorization.isNotEmpty) {
      try {
        // JWT 格式: header.payload.signature
        final parts = authorization.split('.');
        if (parts.length == 3) {
          // Base64 解码 payload，补齐 padding
          final payload = parts[1].padRight(
            (parts[1].length + 3) & ~3,
            '=',
          );
          final decoded = utf8.decode(base64Decode(payload));
          final payloadJson = json.decode(decoded) as Map<String, dynamic>;
          final uid = payloadJson['uid'];
          if (uid is int) return uid;
          if (uid is String) return int.tryParse(uid);
        }
      } on FormatException catch (e) {
        _logger.w('MTeamApi: 解析 JWT token 失败 - $e');
      }
    }

    return null;
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

      final response = await _ioClient.post(
        Uri.parse('$_apiBase/api/torrent/search'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode != 200) {
        throw Exception('获取种子列表失败: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final code = data['code'];
      // code 可能是字符串 "0" 或整数 0
      if (code != '0' && code != 0 && code != 'SUCCESS') {
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
      final response = await _ioClient.post(
        Uri.parse('$_apiBase/api/torrent/detail'),
        headers: headers,
        body: json.encode({'id': torrentId}),
      );

      if (response.statusCode != 200) {
        throw Exception('获取种子详情失败: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final code = data['code'];
      if (code != '0' && code != 0 && code != 'SUCCESS') {
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
      final response = await _ioClient.post(
        Uri.parse('$_apiBase/api/torrent/genDlToken'),
        headers: headers,
        body: json.encode({'id': torrentId}),
      );

      if (response.statusCode != 200) {
        throw Exception('获取下载链接失败: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final code = data['code'];
      if (code != '0' && code != 0 && code != 'SUCCESS') {
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
      // 使用 IOClient 以更好地处理各种 Content-Type
      final httpClient = HttpClient();
      // ignore: cascade_invocations
      httpClient.badCertificateCallback = (cert, host, port) => true;
      // ignore: cascade_invocations
      httpClient.connectionTimeout = const Duration(seconds: 30);

      final request = await httpClient.getUrl(Uri.parse(baseUrl));
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      httpClient.close();

      // 检查是否被重定向到登录页
      return response.statusCode == 200 &&
          !body.contains('login') &&
          !body.contains('登录');
    } on FormatException catch (e, st) {
      // 处理 Content-Type 解析错误（如 "Invalid media type"）
      _logger.w('GenericPTSiteApi.testConnection: 响应格式解析错误 - $e');
      AppError.ignore(e, st, '响应格式解析错误，站点可能返回了非标准的 Content-Type');
      return false;
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
  }) async {
    try {
      // 构建种子列表 URL (NexusPHP 标准格式)
      final params = <String, String>{
        'page': (page - 1).toString(), // NexusPHP 页码从 0 开始
      };
      if (keyword != null && keyword.isNotEmpty) {
        params['search'] = keyword;
        params['notnewword'] = '1';
      }
      if (category != null) {
        params['cat'] = category;
      }

      final uri = Uri.parse('$baseUrl/torrents.php').replace(queryParameters: params);

      final httpClient = HttpClient();
      // ignore: cascade_invocations
      httpClient.badCertificateCallback = (cert, host, port) => true;
      // ignore: cascade_invocations
      httpClient.connectionTimeout = const Duration(seconds: 30);

      final request = await httpClient.getUrl(uri);
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      httpClient.close();

      if (response.statusCode != 200) {
        throw Exception('获取种子列表失败: ${response.statusCode}');
      }

      // 解析 HTML 获取种子列表
      return _parseNexusPHPTorrents(body);
    } on Exception catch (e, st) {
      _logger.e('GenericPTSiteApi.getTorrents: $e');
      AppError.ignore(e, st, '获取种子列表失败');
      return [];
    }
  }

  /// 解析 NexusPHP 种子列表 HTML
  List<PTTorrent> _parseNexusPHPTorrents(String html) {
    final torrents = <PTTorrent>[];

    try {
      // 使用正则表达式提取种子信息
      // NexusPHP 种子列表格式: <tr class="*_tr">...</tr>
      final torrentRowRegex = RegExp(
        '<tr[^>]*class="[^"]*torrent[^"]*"[^>]*>(.*?)</tr>',
        dotAll: true,
        caseSensitive: false,
      );

      // 如果没有找到带 torrent class 的行，尝试其他常见模式
      var matches = torrentRowRegex.allMatches(html);
      if (matches.isEmpty) {
        // 尝试匹配带 id="torrent_" 的行
        final altRegex = RegExp(
          '<tr[^>]*id="torrent_[^"]*"[^>]*>(.*?)</tr>',
          dotAll: true,
          caseSensitive: false,
        );
        matches = altRegex.allMatches(html);
      }

      for (final match in matches) {
        final rowHtml = match.group(1) ?? '';

        // 提取种子 ID 和标题
        final detailMatch = RegExp(
          r'href="[^"]*details\.php\?id=(\d+)[^"]*"[^>]*>([^<]+)',
          caseSensitive: false,
        ).firstMatch(rowHtml);

        if (detailMatch == null) continue;

        final id = detailMatch.group(1) ?? '';
        final name = _htmlDecode(detailMatch.group(2)?.trim() ?? '');

        if (id.isEmpty || name.isEmpty) continue;

        // 提取副标题
        final smallDescrMatch = RegExp(
          'class="[^"]*torrentname[^"]*"[^>]*>.*?<br[^>]*/?>([^<]+)',
          dotAll: true,
          caseSensitive: false,
        ).firstMatch(rowHtml);
        final smallDescr = _htmlDecode(smallDescrMatch?.group(1)?.trim() ?? '');

        // 提取大小
        final sizeMatch = RegExp(
          r'(\d+(?:\.\d+)?)\s*(GB|MB|KB|TB|GiB|MiB|KiB|TiB)',
          caseSensitive: false,
        ).firstMatch(rowHtml);
        final size = _parseSize(sizeMatch?.group(0) ?? '');

        // 提取做种/下载/完成数
        final seedersMatch = RegExp(r'class="[^"]*seeders[^"]*"[^>]*>(\d+)', caseSensitive: false).firstMatch(rowHtml);
        final leechersMatch = RegExp(r'class="[^"]*leechers[^"]*"[^>]*>(\d+)', caseSensitive: false).firstMatch(rowHtml);
        final snatchedMatch = RegExp(r'class="[^"]*snatched[^"]*"[^>]*>(\d+)', caseSensitive: false).firstMatch(rowHtml);

        final seeders = int.tryParse(seedersMatch?.group(1) ?? '') ?? 0;
        final leechers = int.tryParse(leechersMatch?.group(1) ?? '') ?? 0;
        final snatched = int.tryParse(snatchedMatch?.group(1) ?? '') ?? 0;

        // 检测免费状态
        final isFree = RegExp('free|pro_free|pro_free2up', caseSensitive: false).hasMatch(rowHtml);
        final isDoubleFree = RegExp('pro_free2up|twoupfree', caseSensitive: false).hasMatch(rowHtml);
        final isDoubleUp = RegExp('pro_2up|twoup', caseSensitive: false).hasMatch(rowHtml);
        final isHalfDown = RegExp('pro_50pctdown|halfdown', caseSensitive: false).hasMatch(rowHtml);

        torrents.add(PTTorrent(
          id: id,
          name: name,
          size: size,
          seeders: seeders,
          leechers: leechers,
          snatched: snatched,
          uploadTime: DateTime.now(), // HTML 中时间格式复杂，暂时用当前时间
          smallDescr: smallDescr.isNotEmpty ? smallDescr : null,
          detailUrl: '$baseUrl/details.php?id=$id',
          status: PTTorrentStatus(
            isFree: isFree,
            isDoubleFree: isDoubleFree,
            isDoubleUp: isDoubleUp,
            isHalfDown: isHalfDown,
          ),
        ));
      }
    } on Exception catch (e) {
      _logger.w('GenericPTSiteApi._parseNexusPHPTorrents: 解析失败 - $e');
    }

    return torrents;
  }

  /// HTML 实体解码
  String _htmlDecode(String text) => text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();

  /// 解析文件大小
  int _parseSize(String sizeStr) {
    if (sizeStr.isEmpty) return 0;
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*(GB|MB|KB|TB|GiB|MiB|KiB|TiB)', caseSensitive: false).firstMatch(sizeStr);
    if (match == null) return 0;

    final value = double.tryParse(match.group(1) ?? '0') ?? 0;
    final unit = (match.group(2) ?? '').toUpperCase();

    return switch (unit) {
      'TB' || 'TIB' => (value * 1024 * 1024 * 1024 * 1024).toInt(),
      'GB' || 'GIB' => (value * 1024 * 1024 * 1024).toInt(),
      'MB' || 'MIB' => (value * 1024 * 1024).toInt(),
      'KB' || 'KIB' => (value * 1024).toInt(),
      _ => value.toInt(),
    };
  }

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

    // 判断是否是馒头站点（只检查 host）
    if (_isMTeamSite(source)) {
      _logger.i('PTSiteApiFactory.create: 识别为馒头站点，使用 MTeamApi');

      // 预处理：从 customHeaders 或表单字段提取 API Key
      final preparedSource = _prepareApiKeyConfig(source);
      _logger.d('PTSiteApiFactory.create: 预处理后 extraConfig = ${preparedSource.extraConfig}');

      return MTeamApi(source: preparedSource);
    }

    _logger.i('PTSiteApiFactory.create: 使用通用 GenericPTSiteApi');
    return GenericPTSiteApi(source: source);
  }

  /// 判断是否是馒头站点
  /// 参考 nas-tools：只检查 host 是否包含 m-team
  static bool _isMTeamSite(SourceEntity source) {
    final host = source.host.toLowerCase();
    // 馒头域名特征
    return host.contains('m-team') || host.contains('mteam');
  }

  /// 预处理 API Key 配置
  /// 从 customHeaders 中提取 x-api-key 和 authorization，写入 extraConfig
  static SourceEntity _prepareApiKeyConfig(SourceEntity source) {
    final extraConfig = Map<String, dynamic>.from(source.extraConfig ?? {});

    // 已有的直接配置
    var xApiKey = extraConfig['xApiKey'] as String? ?? '';
    var authorization = extraConfig['authorization'] as String? ?? '';

    // 尝试从 customHeaders 提取
    var customHeaders = extraConfig['customHeaders'];

    // 解析 String 类型的 customHeaders（兼容旧数据）
    if (customHeaders is String && customHeaders.isNotEmpty) {
      _logger.d('PTSiteApiFactory._prepareApiKeyConfig: 解析 String 类型 customHeaders');
      customHeaders = _parseCustomHeadersString(customHeaders);
    }

    if (customHeaders is List) {
      for (final header in customHeaders) {
        if (header is Map) {
          final key = header['key']?.toString().toLowerCase() ?? '';
          final value = header['value']?.toString() ?? '';
          if (key == 'x-api-key' && value.isNotEmpty && xApiKey.isEmpty) {
            xApiKey = value;
            _logger.d('PTSiteApiFactory._prepareApiKeyConfig: 从 customHeaders 提取 x-api-key');
          } else if (key == 'authorization' && value.isNotEmpty && authorization.isEmpty) {
            authorization = value;
            _logger.d('PTSiteApiFactory._prepareApiKeyConfig: 从 customHeaders 提取 authorization');
          }
        }
      }
    }

    // 更新 extraConfig
    if (xApiKey.isNotEmpty) extraConfig['xApiKey'] = xApiKey;
    if (authorization.isNotEmpty) extraConfig['authorization'] = authorization;

    return source.copyWith(extraConfig: extraConfig);
  }


  /// 尝试解析 String 格式的 customHeaders
  static List<Map<String, String>>? _parseCustomHeadersString(String str) {
    if (str.isEmpty) return null;

    // 尝试 JSON 解析
    try {
      final parsed = json.decode(str);
      if (parsed is List) {
        return parsed.map((e) {
          if (e is Map) {
            return Map<String, String>.from(
              e.map((k, v) => MapEntry(k.toString(), v.toString())),
            );
          }
          return <String, String>{};
        }).toList();
      }
    } on FormatException {
      // JSON 解析失败，尝试其他格式
    }

    // 尝试解析 "key: value\nkey2: value2" 格式
    final lines = str.split(RegExp(r'[\n;]'));
    final result = <Map<String, String>>[];
    for (final line in lines) {
      final colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        final key = line.substring(0, colonIndex).trim();
        final value = line.substring(colonIndex + 1).trim();
        if (key.isNotEmpty && value.isNotEmpty) {
          result.add({'key': key, 'value': value});
        }
      }
    }

    if (result.isNotEmpty) {
      _logger.d('PTSiteApiFactory._parseCustomHeadersString: 解析出 ${result.length} 个 header');
      return result;
    }

    return null;
  }
}
