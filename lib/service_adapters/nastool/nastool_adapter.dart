import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/service_adapters/nastool/api/nastool_api.dart';
import 'package:my_nas/service_adapters/nastool/api/nastool_auth.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';

/// NASTool 服务适配器
///
/// 使用用户名密码进行会话认证
class NasToolAdapter implements ServiceAdapter {
  NasToolAdapter();

  NasToolApi? _api;
  ServiceConnectionConfig? _connection;
  NtSystemVersion? _systemVersion;

  @override
  ServiceAdapterInfo get info => ServiceAdapterInfo(
        name: 'NASTool',
        type: SourceType.nastool,
        version: _systemVersion?.version,
        description: 'NAS 媒体库管理工具',
      );

  @override
  bool get isConnected => _api?.isAuthenticated ?? false;

  @override
  ServiceConnectionConfig? get connection => _connection;

  /// 获取 API 客户端
  NasToolApi? get api => _api;

  /// 获取系统版本
  NtSystemVersion? get systemVersion => _systemVersion;

  /// 当前用户名
  String? get username => _api?.username;

  @override
  Future<ServiceConnectionResult> connect(ServiceConnectionConfig config) async {
    try {
      // 从配置获取用户名密码
      final username = config.username ?? config.extraConfig?['username'] as String?;
      final password = config.password ?? config.extraConfig?['password'] as String?;

      if (username == null || username.isEmpty) {
        return const ServiceConnectionFailure('缺少用户名');
      }

      if (password == null || password.isEmpty) {
        return const ServiceConnectionFailure('缺少密码');
      }

      _api = NasToolApi(baseUrl: config.baseUrl);

      // 登录认证
      final loginResult = await _api!.login(username, password);

      return loginResult.when(
        success: (token, user) async {
          // 获取系统版本
          try {
            _systemVersion = await _api!.getSystemVersion();
          } on Exception catch (e, st) {
            AppError.ignore(e, st, '系统版本获取失败不影响连接');
          }

          _connection = config;
          return ServiceConnectionSuccess(this);
        },
        failure: (message) {
          _api?.dispose();
          _api = null;
          return ServiceConnectionFailure(message);
        },
      );
    } on NasToolApiException catch (e) {
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure(e.message);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'connectToNasTool');
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure('连接失败: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    await _api?.logout();
    _api?.dispose();
    _api = null;
    _connection = null;
    _systemVersion = null;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
  }

  // === 媒体库方法 ===

  /// 获取媒体库统计
  Future<NtLibraryStatistics> getLibraryStatistics() async {
    _ensureConnected();
    return _api!.getLibraryStatistics();
  }

  /// 获取媒体库空间
  Future<NtLibrarySpace> getLibrarySpace() async {
    _ensureConnected();
    return _api!.getLibrarySpace();
  }

  // === 订阅方法 ===

  /// 获取所有订阅
  Future<List<NtSubscribe>> getAllSubscribes() async {
    _ensureConnected();
    return _api!.getAllSubscribes();
  }

  /// 添加订阅
  Future<void> addSubscribe({
    required String name,
    required String type,
    String? year,
    String? mediaId,
    int? season,
    String? keyword,
  }) async {
    _ensureConnected();
    await _api!.addSubscribe(
      name: name,
      type: type,
      year: year,
      mediaId: mediaId,
      season: season,
      keyword: keyword,
    );
  }

  /// 删除订阅
  Future<void> deleteSubscribe(int subscribeId, String type) async {
    _ensureConnected();
    await _api!.deleteSubscribe(rssId: subscribeId, type: type);
  }

  // === 搜索方法 ===

  /// 搜索资源
  Future<List<NtSearchResult>> searchResources(String keyword) async {
    _ensureConnected();
    await _api!.searchKeyword(searchWord: keyword);
    // 等待搜索完成
    await Future<void>.delayed(const Duration(seconds: 2));
    return _api!.getSearchResult();
  }

  // === 下载方法 ===

  /// 下载资源
  Future<void> downloadResource({
    required String enclosure,
    required String title,
    String? dlDir,
  }) async {
    _ensureConnected();
    await _api!.downloadItem(enclosure: enclosure, title: title, dlDir: dlDir);
  }

  /// 获取下载任务列表
  Future<List<NtDownloadTask>> getDownloadTasks() async {
    _ensureConnected();
    return _api!.getDownloading();
  }

  // === 转移历史方法 ===

  /// 获取转移历史
  Future<List<NtTransferHistory>> getTransferHistory({int page = 1, int pageNum = 20}) async {
    _ensureConnected();
    return _api!.getTransferHistory(page: page, pageNum: pageNum);
  }

  // === 站点方法 ===

  /// 获取站点列表
  Future<List<NtSite>> getSites() async {
    _ensureConnected();
    return _api!.listSites();
  }

  /// 获取站点统计
  Future<List<NtSiteStatistics>> getSiteStatistics() async {
    _ensureConnected();
    return _api!.getSiteStatistics();
  }

  // === 媒体方法 ===

  /// 搜索媒体
  Future<List<NtMediaDetail>> searchMedia(String keyword) async {
    _ensureConnected();
    return _api!.searchMedia(keyword);
  }

  /// 获取推荐列表
  Future<List<NtMediaDetail>> getRecommendList({
    required String type,
    required String subtype,
    int page = 1,
  }) async {
    _ensureConnected();
    return _api!.getRecommendList(type: type, subtype: subtype, page: page);
  }

  // === 系统方法 ===

  /// 刷新媒体库
  Future<void> refreshLibrary() async {
    _ensureConnected();
    await _api!.startLibrarySync();
  }

  /// 获取系统版本
  Future<NtSystemVersion> getSystemVersion() async {
    _ensureConnected();
    return _api!.getSystemVersion();
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw const NasToolApiException('未连接到 NASTool');
    }
  }
}

/// 综合统计信息
class NasToolOverviewStats {
  const NasToolOverviewStats({
    required this.movieCount,
    required this.tvCount,
    this.animeCount = 0,
    required this.subscribeCount,
    required this.activeDownloads,
    required this.completedDownloads,
  });

  final int movieCount;
  final int tvCount;
  final int animeCount;
  final int subscribeCount;
  final int activeDownloads;
  final int completedDownloads;

  int get totalMediaCount => movieCount + tvCount + animeCount;
}
