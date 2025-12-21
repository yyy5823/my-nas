import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// NASTool API 客户端
///
/// 支持 NASTool v3.x API (Action-based)
/// 项目地址: https://github.com/NAStool/nas-tools
///
/// NasTool 使用 action-based API，所有请求都是 POST 到 /api/v1/
/// 请求体包含 cmd 字段指定动作名称
class NasToolApi {
  NasToolApi({
    required this.baseUrl,
    required this.apiToken,
  });

  final String baseUrl;
  final String apiToken;

  http.Client? _client;
  bool _isAuthenticated = false;

  /// 获取 HTTP 客户端
  http.Client get client {
    _client ??= http.Client();
    return _client!;
  }

  /// 是否已认证
  bool get isAuthenticated => _isAuthenticated;

  /// 验证连接
  Future<bool> validateConnection() async {
    try {
      _log('validateConnection: 开始验证连接 baseUrl=$baseUrl');

      // NASTool 使用 action-based API，验证连接使用 version 命令
      final response = await _callAction('version');
      _log('validateConnection: 响应状态码=${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // 检查返回结果
        if (data['code'] == 0 || data['success'] == true || data['version'] != null) {
          _isAuthenticated = true;
          _log('validateConnection: 连接验证成功');
          return true;
        }
      }
      _log('validateConnection: 连接验证失败，状态码=${response.statusCode}');
      return false;
    } on NasToolApiException catch (e) {
      _log('validateConnection: API异常 - ${e.message}');
      return false;
    } on Exception catch (e) {
      _log('validateConnection: 未知异常 - $e');
      return false;
    }
  }

  void _log(String message) {
    // ignore: avoid_print
    print('[NasToolApi] $message');
  }

  /// 获取系统信息
  Future<NasToolSystemInfo> getSystemInfo() async {
    final response = await _callAction('version');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return NasToolSystemInfo.fromJson(data);
  }

  /// 获取媒体库统计
  Future<NasToolMediaStats> getMediaStats() async {
    final response = await _callAction('get_library_mediacount');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return NasToolMediaStats.fromJson(data);
  }

  /// 获取订阅列表（电影 + 电视剧）
  Future<List<NasToolSubscribe>> getSubscribes() async {
    final result = <NasToolSubscribe>[];

    // 获取电影订阅
    try {
      final movieResponse = await _callAction('get_movie_rss_list');
      final movieData = jsonDecode(movieResponse.body) as Map<String, dynamic>;
      final movieItems = movieData['result'] as List<dynamic>? ?? [];
      for (final item in movieItems) {
        result.add(NasToolSubscribe.fromJson(item as Map<String, dynamic>, 'movie'));
      }
    } on Exception catch (e) {
      _log('getSubscribes: 获取电影订阅失败 - $e');
    }

    // 获取电视剧订阅
    try {
      final tvResponse = await _callAction('get_tv_rss_list');
      final tvData = jsonDecode(tvResponse.body) as Map<String, dynamic>;
      final tvItems = tvData['result'] as List<dynamic>? ?? [];
      for (final item in tvItems) {
        result.add(NasToolSubscribe.fromJson(item as Map<String, dynamic>, 'tv'));
      }
    } on Exception catch (e) {
      _log('getSubscribes: 获取电视剧订阅失败 - $e');
    }

    return result;
  }

  /// 添加订阅
  Future<void> addSubscribe({
    required String name,
    required String mediaType,
    String? tmdbId,
    String? imdbId,
    int? season,
    String? keyword,
  }) async {
    await _callAction('add_rss_media', params: {
      'name': name,
      'mtype': mediaType,
      if (tmdbId != null) 'tmdbid': tmdbId,
      if (imdbId != null) 'imdbid': imdbId,
      if (season != null) 'season': season,
      if (keyword != null) 'keyword': keyword,
    });
  }

  /// 删除订阅
  Future<void> deleteSubscribe(int subscribeId, {String type = 'MOV'}) async {
    await _callAction('remove_rss_media', params: {
      'rssid': subscribeId,
      'rtype': type,
    });
  }

  /// 搜索资源
  Future<List<NasToolSearchResult>> searchResources({
    required String keyword,
    String? mediaType,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _callAction('search', params: {
      'search_word': keyword,
      if (mediaType != null) 'media_type': mediaType,
    });

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['code'] != 0) {
      return [];
    }

    // 搜索是异步的，需要轮询获取结果
    await Future<void>.delayed(const Duration(seconds: 2));
    
    final resultResponse = await _callAction('get_search_result');
    final resultData = jsonDecode(resultResponse.body) as Map<String, dynamic>;
    final items = resultData['result'] as List<dynamic>? ?? [];
    
    return items
        .map((e) => NasToolSearchResult.fromJson(e as Map<String, dynamic>))
        .take(limit)
        .toList();
  }

  /// 下载资源
  Future<void> downloadResource({
    required String url,
    String? savePath,
  }) async {
    await _callAction('download_link', params: {
      'enclosure': url,
      if (savePath != null) 'dl_dir': savePath,
    });
  }

  /// 获取下载任务列表
  Future<List<NasToolDownloadTask>> getDownloadTasks() async {
    final response = await _callAction('get_downloading');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['result'] as List<dynamic>? ?? [];
    return items
        .map((e) => NasToolDownloadTask.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取转移历史
  Future<List<NasToolTransferHistory>> getTransferHistory({
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _callAction('get_transfer_history', params: {
      'page': page,
      'limit': limit,
    });

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['result'] as List<dynamic>? ?? [];
    return items
        .map((e) => NasToolTransferHistory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 手动识别媒体
  Future<NasToolMediaInfo?> recognizeMedia(String path) async {
    final response = await _callAction('media_info', params: {
      'name': path,
    });

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['code'] == 0 && data['data'] != null) {
      return NasToolMediaInfo.fromJson(data['data'] as Map<String, dynamic>);
    }
    return null;
  }

  /// 刷新媒体库
  Future<void> refreshMediaLibrary() async {
    await _callAction('start_mediasync');
  }

  /// 刷新 RSS 订阅
  Future<void> refreshRss() async {
    await _callAction('refresh_rss');
  }

  /// 调用 API action
  Future<http.Response> _callAction(String cmd, {Map<String, dynamic>? params}) async {
    final url = Uri.parse('$baseUrl/api/v1/');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': apiToken,
    };

    final body = <String, dynamic>{
      'cmd': cmd,
      ...?params,
    };

    _log('_callAction: POST $url cmd=$cmd');

    try {
      final response = await client.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );

      _log('_callAction: 响应 ${response.statusCode}');

      if (response.statusCode == 401) {
        _isAuthenticated = false;
        throw const NasToolApiException('认证失败，请检查 API Token');
      }

      if (response.statusCode == 403) {
        throw const NasToolApiException('没有权限执行此操作');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _log('_callAction: 错误响应 body=${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
        throw NasToolApiException(
          '请求失败: ${response.statusCode} ${response.reasonPhrase}',
        );
      }

      return response;
    } on SocketException catch (e) {
      _log('_callAction: SocketException - ${e.message}');
      throw NasToolApiException('无法连接到 NASTool: ${e.message}');
    } on http.ClientException catch (e) {
      _log('_callAction: ClientException - ${e.message}');
      throw NasToolApiException('网络错误: ${e.message}');
    } on FormatException catch (e) {
      _log('_callAction: FormatException - $e');
      throw NasToolApiException('URL格式错误: $e');
    }
  }

  /// 释放资源
  void dispose() {
    _client?.close();
    _client = null;
    _isAuthenticated = false;
  }
}

/// NASTool API 异常
class NasToolApiException implements Exception {
  const NasToolApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 系统信息
class NasToolSystemInfo {
  const NasToolSystemInfo({
    required this.version,
    this.serverName,
    this.cpuUsage,
    this.memoryUsage,
    this.diskUsage,
  });

  factory NasToolSystemInfo.fromJson(Map<String, dynamic> json) {
    // action-based API 返回格式可能不同
    final version = json['version'] as String? ?? 
                    json['data']?['version'] as String? ?? '';
    return NasToolSystemInfo(
      version: version,
      serverName: json['server_name'] as String?,
      cpuUsage: (json['cpu_usage'] as num?)?.toDouble(),
      memoryUsage: (json['memory_usage'] as num?)?.toDouble(),
      diskUsage: (json['disk_usage'] as num?)?.toDouble(),
    );
  }

  final String version;
  final String? serverName;
  final double? cpuUsage;
  final double? memoryUsage;
  final double? diskUsage;
}

/// 媒体库统计
class NasToolMediaStats {
  const NasToolMediaStats({
    required this.movieCount,
    required this.tvCount,
    required this.animeCount,
  });

  factory NasToolMediaStats.fromJson(Map<String, dynamic> json) {
    // get_library_mediacount 返回格式：{ "MovieCount": x, "SeriesCount": x }
    return NasToolMediaStats(
      movieCount: json['MovieCount'] as int? ?? 
                  json['movie_count'] as int? ?? 0,
      tvCount: json['SeriesCount'] as int? ?? 
               json['EpisodeCount'] as int? ??
               json['tv_count'] as int? ?? 0,
      animeCount: json['anime_count'] as int? ?? 0,
    );
  }

  final int movieCount;
  final int tvCount;
  final int animeCount;

  int get totalCount => movieCount + tvCount + animeCount;
}

/// 订阅
class NasToolSubscribe {
  const NasToolSubscribe({
    required this.id,
    required this.name,
    required this.type,
    this.tmdbId,
    this.imdbId,
    this.season,
    this.state,
    this.lastUpdate,
  });

  factory NasToolSubscribe.fromJson(Map<String, dynamic> json, [String? defaultType]) {
    return NasToolSubscribe(
      id: json['id'] as int? ?? json['rssid'] as int? ?? 0,
      name: json['name'] as String? ?? json['title'] as String? ?? '',
      type: json['type'] as String? ?? defaultType ?? '',
      tmdbId: json['tmdbid']?.toString(),
      imdbId: json['imdbid']?.toString(),
      season: json['season'] as int?,
      state: json['state'] as String?,
      lastUpdate: json['last_update'] != null
          ? DateTime.tryParse(json['last_update'] as String)
          : null,
    );
  }

  final int id;
  final String name;
  final String type;
  final String? tmdbId;
  final String? imdbId;
  final int? season;
  final String? state;
  final DateTime? lastUpdate;
}

/// 搜索结果
class NasToolSearchResult {
  const NasToolSearchResult({
    required this.title,
    required this.size,
    required this.seeders,
    required this.leechers,
    this.url,
    this.site,
    this.mediaType,
    this.resolution,
  });

  factory NasToolSearchResult.fromJson(Map<String, dynamic> json) => NasToolSearchResult(
      title: json['title'] as String? ?? json['torrent_name'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      seeders: json['seeders'] as int? ?? 0,
      leechers: json['leechers'] as int? ?? json['peers'] as int? ?? 0,
      url: json['enclosure'] as String? ?? json['url'] as String?,
      site: json['site'] as String?,
      mediaType: json['media_type'] as String?,
      resolution: json['res'] as String? ?? json['resolution'] as String?,
    );

  final String title;
  final int size;
  final int seeders;
  final int leechers;
  final String? url;
  final String? site;
  final String? mediaType;
  final String? resolution;
}

/// 下载任务
class NasToolDownloadTask {
  const NasToolDownloadTask({
    required this.id,
    required this.name,
    required this.state,
    required this.progress,
    this.size,
    this.speed,
    this.eta,
  });

  factory NasToolDownloadTask.fromJson(Map<String, dynamic> json) => NasToolDownloadTask(
      id: json['id']?.toString() ?? json['hash']?.toString() ?? '',
      name: json['name'] as String? ?? json['title'] as String? ?? '',
      state: json['state'] as String? ?? json['status'] as String? ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 
                ((json['percent'] as num?)?.toDouble() ?? 0) / 100,
      size: json['size'] as int? ?? json['total_size'] as int?,
      speed: json['speed'] as int? ?? json['dlspeed'] as int?,
      eta: json['eta'] as int?,
    );

  final String id;
  final String name;
  final String state;
  final double progress;
  final int? size;
  final int? speed;
  final int? eta;
}

/// 转移历史
class NasToolTransferHistory {
  const NasToolTransferHistory({
    required this.id,
    required this.title,
    required this.type,
    this.sourcePath,
    this.destPath,
    this.transferTime,
    this.success,
  });

  factory NasToolTransferHistory.fromJson(Map<String, dynamic> json) => NasToolTransferHistory(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      sourcePath: json['source_path'] as String? ?? json['source'] as String?,
      destPath: json['dest_path'] as String? ?? json['dest'] as String?,
      transferTime: json['DATE'] != null
          ? DateTime.tryParse(json['DATE'] as String)
          : (json['transfer_time'] != null
              ? DateTime.tryParse(json['transfer_time'] as String)
              : null),
      success: json['success'] as bool? ?? json['state'] == 'SUCCESS',
    );

  final int id;
  final String title;
  final String type;
  final String? sourcePath;
  final String? destPath;
  final DateTime? transferTime;
  final bool? success;
}

/// 媒体信息
class NasToolMediaInfo {
  const NasToolMediaInfo({
    required this.title,
    required this.year,
    required this.type,
    this.tmdbId,
    this.imdbId,
    this.overview,
    this.poster,
    this.backdrop,
  });

  factory NasToolMediaInfo.fromJson(Map<String, dynamic> json) => NasToolMediaInfo(
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      year: json['year'] as int?,
      type: json['type'] as String? ?? json['media_type'] as String? ?? '',
      tmdbId: json['tmdb_id'] as int? ?? json['tmdbid'] as int?,
      imdbId: json['imdb_id'] as String? ?? json['imdbid'] as String?,
      overview: json['overview'] as String? ?? json['description'] as String?,
      poster: json['poster'] as String? ?? json['poster_path'] as String?,
      backdrop: json['backdrop'] as String? ?? json['backdrop_path'] as String?,
    );

  final String title;
  final int? year;
  final String type;
  final int? tmdbId;
  final String? imdbId;
  final String? overview;
  final String? poster;
  final String? backdrop;
}
