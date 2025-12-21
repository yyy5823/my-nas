import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:my_nas/service_adapters/nastool/api/nastool_auth.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';

/// NASTool API 客户端
///
/// 使用会话认证，支持 NASTool v3.x API
class NasToolApi {
  NasToolApi({required this.baseUrl});

  final String baseUrl;
  
  http.Client? _client;
  late final NasToolAuth _auth = NasToolAuth(baseUrl: baseUrl);

  http.Client get client {
    _client ??= http.Client();
    return _client!;
  }

  /// 是否已认证
  bool get isAuthenticated => _auth.isAuthenticated;
  
  /// 当前用户名
  String? get username => _auth.username;

  // ============================================================
  // 认证相关
  // ============================================================

  /// 登录
  Future<NasToolLoginResult> login(String username, String password) =>
      _auth.login(username, password);

  /// 登出
  Future<void> logout() => _auth.logout();

  /// 验证会话
  Future<bool> validateSession() => _auth.validateSession();

  // ============================================================
  // 系统相关
  // ============================================================

  /// 获取系统版本
  Future<NtSystemVersion> getSystemVersion() async {
    final data = await _post('/system/version');
    return NtSystemVersion.fromJson(data);
  }

  /// 获取进度
  Future<NtSystemProgress?> getProgress(String type) async {
    final data = await _post('/system/progress', {'type': type});
    if (data['value'] == null) return null;
    return NtSystemProgress.fromJson(data);
  }

  /// 获取目录
  Future<List<NtPathInfo>> listPath(String dir, {String filter = 'ALL'}) async {
    final data = await _post('/system/path', {'dir': dir, 'filter': filter});
    final items = data['PathList'] as List? ?? data['result'] as List? ?? [];
    return items.map((e) => NtPathInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 重启系统
  Future<void> restartSystem() async {
    await _post('/system/restart');
  }

  /// 升级系统
  Future<void> updateSystem() async {
    await _post('/system/update');
  }

  // ============================================================
  // 站点相关
  // ============================================================

  /// 获取站点列表
  Future<List<NtSite>> listSites() async {
    final data = await _post('/site/list');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtSite.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取站点详情
  Future<NtSite?> getSiteInfo(int id) async {
    final data = await _post('/site/info', {'id': id});
    if (data['result'] == null) return null;
    return NtSite.fromJson(data['result'] as Map<String, dynamic>);
  }

  /// 更新站点
  Future<void> updateSite({
    required String siteName,
    int? siteId,
    String? sitePri,
    String? siteRssUrl,
    String? siteSignUrl,
    String? siteCookie,
    String? siteNote,
    String? siteInclude,
  }) async {
    await _post('/site/update', {
      'site_name': siteName,
      if (siteId != null) 'site_id': siteId,
      if (sitePri != null) 'site_pri': sitePri,
      if (siteRssUrl != null) 'site_rssurl': siteRssUrl,
      if (siteSignUrl != null) 'site_signurl': siteSignUrl,
      if (siteCookie != null) 'site_cookie': siteCookie,
      if (siteNote != null) 'site_note': siteNote,
      if (siteInclude != null) 'site_include': siteInclude,
    });
  }

  /// 删除站点
  Future<void> deleteSite(int id) async {
    await _post('/site/delete', {'id': id});
  }

  /// 测试站点
  Future<bool> testSite(int id) async {
    final data = await _post('/site/test', {'id': id});
    return data['code'] == 0;
  }

  /// 获取站点统计
  Future<List<NtSiteStatistics>> getSiteStatistics() async {
    final response = await _get('/site/statistics');
    if (response.isEmpty) return [];
    final items = response as List? ?? [];
    return items.map((e) => NtSiteStatistics.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取站点索引器
  Future<List<NtSiteIndexer>> getSiteIndexers() async {
    final data = await _post('/site/indexers');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtSiteIndexer.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 订阅相关
  // ============================================================

  /// 获取电影订阅
  Future<List<NtSubscribe>> getMovieSubscribes() async {
    final data = await _post('/subscribe/movie/list');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtSubscribe.fromJson(e as Map<String, dynamic>, 'MOV')).toList();
  }

  /// 获取电视剧订阅
  Future<List<NtSubscribe>> getTvSubscribes() async {
    final data = await _post('/subscribe/tv/list');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtSubscribe.fromJson(e as Map<String, dynamic>, 'TV')).toList();
  }

  /// 获取所有订阅
  Future<List<NtSubscribe>> getAllSubscribes() async {
    final movies = await getMovieSubscribes();
    final tvs = await getTvSubscribes();
    return [...movies, ...tvs];
  }

  /// 添加订阅
  Future<void> addSubscribe({
    required String name,
    required String type,
    String? year,
    String? keyword,
    int? season,
    String? mediaId,
    int? fuzzyMatch,
    String? rssSites,
    String? searchSites,
    int? overEdition,
    String? filterRestype,
    String? filterPix,
    String? filterTeam,
    int? filterRule,
    int? downloadSetting,
    String? savePath,
    int? totalEp,
    int? currentEp,
  }) async {
    await _post('/subscribe/add', {
      'name': name,
      'type': type,
      if (year != null) 'year': year,
      if (keyword != null) 'keyword': keyword,
      if (season != null) 'season': season,
      if (mediaId != null) 'mediaid': mediaId,
      if (fuzzyMatch != null) 'fuzzy_match': fuzzyMatch,
      if (rssSites != null) 'rss_sites': rssSites,
      if (searchSites != null) 'search_sites': searchSites,
      if (overEdition != null) 'over_edition': overEdition,
      if (filterRestype != null) 'filter_restype': filterRestype,
      if (filterPix != null) 'filter_pix': filterPix,
      if (filterTeam != null) 'filter_team': filterTeam,
      if (filterRule != null) 'filter_rule': filterRule,
      if (downloadSetting != null) 'download_setting': downloadSetting,
      if (savePath != null) 'save_path': savePath,
      if (totalEp != null) 'total_ep': totalEp,
      if (currentEp != null) 'current_ep': currentEp,
    });
  }

  /// 删除订阅
  Future<void> deleteSubscribe({
    String? name,
    String? type,
    String? year,
    int? season,
    int? rssId,
    String? tmdbId,
  }) async {
    await _post('/subscribe/delete', {
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (year != null) 'year': year,
      if (season != null) 'season': season,
      if (rssId != null) 'rssid': rssId,
      if (tmdbId != null) 'tmdbid': tmdbId,
    });
  }

  /// 获取订阅详情
  Future<NtSubscribe?> getSubscribeInfo(int rssId, String type) async {
    final data = await _post('/subscribe/info', {'rssid': rssId, 'type': type});
    if (data['result'] == null) return null;
    return NtSubscribe.fromJson(data['result'] as Map<String, dynamic>, type);
  }

  /// 搜索订阅
  Future<void> searchSubscribe(int rssId, String type) async {
    await _post('/subscribe/search', {'rssid': rssId, 'type': type});
  }

  /// 获取订阅历史
  Future<List<NtSubscribeHistory>> getSubscribeHistory(String type) async {
    final data = await _post('/subscribe/history', {'type': type});
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtSubscribeHistory.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 搜索相关
  // ============================================================

  /// 搜索资源
  Future<void> searchKeyword({
    required String searchWord,
    int? unident,
    String? filters,
    String? tmdbId,
    String? mediaType,
  }) async {
    await _post('/search/keyword', {
      'search_word': searchWord,
      if (unident != null) 'unident': unident,
      if (filters != null) 'filters': filters,
      if (tmdbId != null) 'tmdbid': tmdbId,
      if (mediaType != null) 'media_type': mediaType,
    });
  }

  /// 获取搜索结果
  Future<List<NtSearchResult>> getSearchResult() async {
    final data = await _post('/search/result');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtSearchResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 下载相关
  // ============================================================

  /// 下载资源
  Future<void> downloadItem({
    required String enclosure,
    required String title,
    String? site,
    String? description,
    String? pageUrl,
    String? size,
    String? seeders,
    double? uploadFactor,
    double? downloadFactor,
    String? dlDir,
  }) async {
    await _post('/download/item', {
      'enclosure': enclosure,
      'title': title,
      if (site != null) 'site': site,
      if (description != null) 'description': description,
      if (pageUrl != null) 'page_url': pageUrl,
      if (size != null) 'size': size,
      if (seeders != null) 'seeders': seeders,
      if (uploadFactor != null) 'uploadvolumefactor': uploadFactor,
      if (downloadFactor != null) 'downloadvolumefactor': downloadFactor,
      if (dlDir != null) 'dl_dir': dlDir,
    });
  }

  /// 获取正在下载的任务
  Future<List<NtDownloadTask>> getDownloading() async {
    final data = await _post('/download/now');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtDownloadTask.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取下载历史
  Future<List<NtDownloadHistory>> getDownloadHistory(int page) async {
    final data = await _post('/download/history', {'page': page});
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtDownloadHistory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取下载进度
  Future<Map<String, dynamic>> getDownloadInfo(String ids) async {
    return _post('/download/info', {'ids': ids});
  }

  /// 开始下载
  Future<void> startDownload(String id) async {
    await _post('/download/start', {'id': id});
  }

  /// 暂停下载
  Future<void> stopDownload(String id) async {
    await _post('/download/stop', {'id': id});
  }

  /// 删除下载
  Future<void> removeDownload(String id) async {
    await _post('/download/remove', {'id': id});
  }

  /// 下载搜索结果
  Future<void> downloadSearchResult(String id, {String? dir, String? setting}) async {
    await _post('/download/search', {
      'id': id,
      if (dir != null) 'dir': dir,
      if (setting != null) 'setting': setting,
    });
  }

  /// 获取下载器列表
  Future<List<NtDownloadClient>> listDownloadClients({String? did}) async {
    final data = await _post('/download/client/list', {if (did != null) 'did': did});
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtDownloadClient.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 媒体库相关
  // ============================================================

  /// 获取媒体库统计
  Future<NtLibraryStatistics> getLibraryStatistics() async {
    final data = await _post('/library/mediaserver/statistics');
    return NtLibraryStatistics.fromJson(data);
  }

  /// 获取媒体库空间
  Future<NtLibrarySpace> getLibrarySpace() async {
    final data = await _post('/library/space');
    return NtLibrarySpace.fromJson(data);
  }

  /// 获取播放历史
  Future<List<NtPlayHistory>> getPlayHistory() async {
    final data = await _post('/library/mediaserver/playhistory');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtPlayHistory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 开始媒体库同步
  Future<void> startLibrarySync() async {
    await _post('/library/sync/start');
  }

  /// 获取媒体库同步状态
  Future<Map<String, dynamic>> getLibrarySyncStatus() async {
    return _post('/library/sync/status');
  }

  // ============================================================
  // 媒体相关
  // ============================================================

  /// 搜索媒体
  Future<List<NtMediaDetail>> searchMedia(String keyword) async {
    final data = await _post('/media/search', {'keyword': keyword});
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtMediaDetail.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取媒体详情
  Future<NtMediaDetail?> getMediaDetail(String type, {String? tmdbId}) async {
    final data = await _post('/media/detail', {
      'type': type,
      if (tmdbId != null) 'tmdbid': tmdbId,
    });
    if (data['data'] == null && data['title'] == null) return null;
    return NtMediaDetail.fromJson(data['data'] as Map<String, dynamic>? ?? data);
  }

  /// 获取电视剧季列表
  Future<List<NtTvSeason>> getTvSeasons(String tmdbId) async {
    final data = await _post('/media/tv/seasons', {'tmdbid': tmdbId});
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtTvSeason.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取相似媒体
  Future<List<NtMediaDetail>> getSimilarMedia(String type, String tmdbId, {int? page}) async {
    final data = await _post('/media/similar', {
      'type': type,
      'tmdbid': tmdbId,
      if (page != null) 'page': page,
    });
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtMediaDetail.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取推荐媒体
  Future<List<NtMediaDetail>> getRecommendations(String type, String tmdbId, {int? page}) async {
    final data = await _post('/media/recommendations', {
      'type': type,
      'tmdbid': tmdbId,
      if (page != null) 'page': page,
    });
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtMediaDetail.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 整理相关
  // ============================================================

  /// 获取转移历史
  Future<List<NtTransferHistory>> getTransferHistory({
    required int page,
    required int pageNum,
    String? keyword,
  }) async {
    final data = await _post('/organization/history/list', {
      'page': page,
      'pagenum': pageNum,
      if (keyword != null) 'keyword': keyword,
    });
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtTransferHistory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取转移统计
  Future<NtTransferStatistics> getTransferStatistics() async {
    final data = await _post('/organization/history/statistics');
    return NtTransferStatistics.fromJson(data);
  }

  /// 获取未识别列表
  Future<List<NtUnknownRecord>> listUnknown() async {
    final data = await _post('/organization/unknown/list');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtUnknownRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 删除未识别记录
  Future<void> deleteUnknown(String id) async {
    await _post('/organization/unknown/delete', {'id': id});
  }

  // ============================================================
  // 推荐相关
  // ============================================================

  /// 获取推荐列表
  Future<List<NtMediaDetail>> getRecommendList({
    required String type,
    required String subtype,
    required int page,
  }) async {
    final data = await _post('/recommend/list', {
      'type': type,
      'subtype': subtype,
      'page': page,
    });
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtMediaDetail.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 用户相关
  // ============================================================

  /// 获取用户信息
  Future<NtUserInfo?> getUserInfo(String username) async {
    final data = await _post('/user/info', {'username': username});
    if (data['result'] == null) return null;
    return NtUserInfo.fromJson(data['result'] as Map<String, dynamic>);
  }

  /// 获取用户列表
  Future<List<NtUserInfo>> listUsers() async {
    final data = await _post('/user/list');
    final items = data['result'] as List? ?? [];
    return items.map((e) => NtUserInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ============================================================
  // 私有方法
  // ============================================================

  Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic>? params]) async {
    final url = Uri.parse('$baseUrl/api/v1$path');
    
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      ..._auth.authHeaders,
    };

    try {
      final response = await client.post(
        url,
        headers: headers,
        body: params?.map((k, v) => MapEntry(k, v.toString())),
      );

      if (response.statusCode == 401) {
        throw const NasToolApiException('认证失败，请重新登录');
      }

      if (response.statusCode == 403) {
        throw const NasToolApiException('没有权限执行此操作');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NasToolApiException('请求失败: ${response.statusCode}');
      }

      if (response.body.isEmpty) return {};
      
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        return data;
      }
      return {'result': data};
    } on SocketException catch (e) {
      throw NasToolApiException('无法连接服务器: ${e.message}');
    } on FormatException {
      throw const NasToolApiException('响应格式错误');
    }
  }

  Future<dynamic> _get(String path) async {
    final url = Uri.parse('$baseUrl/api/v1$path');
    
    final headers = <String, String>{
      ..._auth.authHeaders,
    };

    try {
      final response = await client.get(url, headers: headers);

      if (response.statusCode == 401) {
        throw const NasToolApiException('认证失败，请重新登录');
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NasToolApiException('请求失败: ${response.statusCode}');
      }

      if (response.body.isEmpty) return {};
      return jsonDecode(response.body);
    } on SocketException catch (e) {
      throw NasToolApiException('无法连接服务器: ${e.message}');
    }
  }

  /// 释放资源
  void dispose() {
    _client?.close();
    _client = null;
    _auth.clear();
  }
}

/// NASTool API 异常
class NasToolApiException implements Exception {
  const NasToolApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
