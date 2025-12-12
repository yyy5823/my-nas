import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:my_nas/core/errors/app_error_handler.dart';

/// NASTool API 客户端
///
/// 支持 NASTool v3.x API
/// 项目地址: https://github.com/NAStool/nas-tools
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
      final response = await _makeRequest('GET', '/api/v1/system/info');
      if (response.statusCode == 200) {
        _isAuthenticated = true;
        return true;
      }
      return false;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'validateNasToolConnection');
      return false;
    }
  }

  /// 获取系统信息
  Future<NasToolSystemInfo> getSystemInfo() async {
    final response = await _makeRequest('GET', '/api/v1/system/info');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return NasToolSystemInfo.fromJson(data);
  }

  /// 获取媒体库统计
  Future<NasToolMediaStats> getMediaStats() async {
    final response = await _makeRequest('GET', '/api/v1/media/stats');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return NasToolMediaStats.fromJson(data);
  }

  /// 获取订阅列表
  Future<List<NasToolSubscribe>> getSubscribes() async {
    final response = await _makeRequest('GET', '/api/v1/subscribe/list');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['data'] as List<dynamic>? ?? [];
    return items
        .map((e) => NasToolSubscribe.fromJson(e as Map<String, dynamic>))
        .toList();
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
    await _makeRequest(
      'POST',
      '/api/v1/subscribe/add',
      body: {
        'name': name,
        'type': mediaType,
        if (tmdbId != null) 'tmdbid': tmdbId,
        if (imdbId != null) 'imdbid': imdbId,
        if (season != null) 'season': season,
        if (keyword != null) 'keyword': keyword,
      },
    );
  }

  /// 删除订阅
  Future<void> deleteSubscribe(int subscribeId) async {
    await _makeRequest(
      'POST',
      '/api/v1/subscribe/delete',
      body: {'id': subscribeId},
    );
  }

  /// 搜索资源
  Future<List<NasToolSearchResult>> searchResources({
    required String keyword,
    String? mediaType,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _makeRequest(
      'POST',
      '/api/v1/resource/search',
      body: {
        'keyword': keyword,
        if (mediaType != null) 'type': mediaType,
        'page': page,
        'limit': limit,
      },
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['data'] as List<dynamic>? ?? [];
    return items
        .map((e) => NasToolSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 下载资源
  Future<void> downloadResource({
    required String url,
    String? savePath,
  }) async {
    await _makeRequest(
      'POST',
      '/api/v1/download/add',
      body: {
        'url': url,
        if (savePath != null) 'save_path': savePath,
      },
    );
  }

  /// 获取下载任务列表
  Future<List<NasToolDownloadTask>> getDownloadTasks() async {
    final response = await _makeRequest('GET', '/api/v1/download/list');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['data'] as List<dynamic>? ?? [];
    return items
        .map((e) => NasToolDownloadTask.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取转移历史
  Future<List<NasToolTransferHistory>> getTransferHistory({
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _makeRequest(
      'GET',
      '/api/v1/history/transfer',
      queryParams: {
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['data'] as List<dynamic>? ?? [];
    return items
        .map((e) => NasToolTransferHistory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 手动识别媒体
  Future<NasToolMediaInfo?> recognizeMedia(String path) async {
    final response = await _makeRequest(
      'POST',
      '/api/v1/media/recognize',
      body: {'path': path},
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['success'] == true && data['data'] != null) {
      return NasToolMediaInfo.fromJson(data['data'] as Map<String, dynamic>);
    }
    return null;
  }

  /// 刷新媒体库
  Future<void> refreshMediaLibrary() async {
    await _makeRequest('POST', '/api/v1/media/refresh');
  }

  /// 发起请求
  Future<http.Response> _makeRequest(
    String method,
    String path, {
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
  }) async {
    var url = Uri.parse('$baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      url = url.replace(queryParameters: queryParams);
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiToken',
    };

    http.Response response;

    try {
      if (method == 'GET') {
        response = await client.get(url, headers: headers);
      } else if (method == 'POST') {
        response = await client.post(
          url,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      } else if (method == 'DELETE') {
        response = await client.delete(url, headers: headers);
      } else {
        throw NasToolApiException('不支持的 HTTP 方法: $method');
      }

      if (response.statusCode == 401) {
        _isAuthenticated = false;
        throw const NasToolApiException('认证失败，请检查 API Token');
      }

      if (response.statusCode == 403) {
        throw const NasToolApiException('没有权限执行此操作');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NasToolApiException(
          '请求失败: ${response.statusCode} ${response.reasonPhrase}',
        );
      }

      return response;
    } on SocketException catch (e) {
      throw NasToolApiException('无法连接到 NASTool: ${e.message}');
    } on http.ClientException catch (e) {
      throw NasToolApiException('网络错误: ${e.message}');
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
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return NasToolSystemInfo(
      version: data['version'] as String? ?? '',
      serverName: data['server_name'] as String?,
      cpuUsage: (data['cpu_usage'] as num?)?.toDouble(),
      memoryUsage: (data['memory_usage'] as num?)?.toDouble(),
      diskUsage: (data['disk_usage'] as num?)?.toDouble(),
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
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return NasToolMediaStats(
      movieCount: data['movie_count'] as int? ?? 0,
      tvCount: data['tv_count'] as int? ?? 0,
      animeCount: data['anime_count'] as int? ?? 0,
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

  factory NasToolSubscribe.fromJson(Map<String, dynamic> json) => NasToolSubscribe(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      tmdbId: json['tmdbid'] as String?,
      imdbId: json['imdbid'] as String?,
      season: json['season'] as int?,
      state: json['state'] as String?,
      lastUpdate: json['last_update'] != null
          ? DateTime.tryParse(json['last_update'] as String)
          : null,
    );

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
      title: json['title'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      seeders: json['seeders'] as int? ?? 0,
      leechers: json['leechers'] as int? ?? 0,
      url: json['url'] as String?,
      site: json['site'] as String?,
      mediaType: json['media_type'] as String?,
      resolution: json['resolution'] as String?,
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
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      state: json['state'] as String? ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      size: json['size'] as int?,
      speed: json['speed'] as int?,
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
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? '',
      sourcePath: json['source_path'] as String?,
      destPath: json['dest_path'] as String?,
      transferTime: json['transfer_time'] != null
          ? DateTime.tryParse(json['transfer_time'] as String)
          : null,
      success: json['success'] as bool?,
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
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      type: json['type'] as String? ?? '',
      tmdbId: json['tmdb_id'] as int?,
      imdbId: json['imdb_id'] as String?,
      overview: json['overview'] as String?,
      poster: json['poster'] as String?,
      backdrop: json['backdrop'] as String?,
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
