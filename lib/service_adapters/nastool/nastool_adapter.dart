import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/service_adapters/nastool/api/nastool_api.dart';

/// NASTool 服务适配器
///
/// 提供 NASTool 媒体管理服务的连接和管理功能
class NasToolAdapter implements ServiceAdapter {
  NasToolAdapter();

  NasToolApi? _api;
  ServiceConnectionConfig? _connection;
  NasToolSystemInfo? _systemInfo;

  @override
  ServiceAdapterInfo get info => ServiceAdapterInfo(
        name: 'NASTool',
        type: SourceType.nastool,
        version: _systemInfo?.version,
        description: 'NAS 媒体库管理工具',
      );

  @override
  bool get isConnected => _api?.isAuthenticated ?? false;

  @override
  ServiceConnectionConfig? get connection => _connection;

  /// 获取 API 客户端
  NasToolApi? get api => _api;

  /// 获取系统信息
  NasToolSystemInfo? get systemInfo => _systemInfo;

  @override
  Future<ServiceConnectionResult> connect(ServiceConnectionConfig config) async {
    try {
      final apiToken = config.apiKey ?? config.extraConfig?['apiToken'] as String?;

      if (apiToken == null || apiToken.isEmpty) {
        return const ServiceConnectionFailure('缺少 API Token');
      }

      _api = NasToolApi(
        baseUrl: config.baseUrl,
        apiToken: apiToken,
      );

      // 验证连接
      final valid = await _api!.validateConnection();
      if (!valid) {
        _api?.dispose();
        _api = null;
        return const ServiceConnectionFailure('连接验证失败，请检查地址和 API Token');
      }

      // 获取系统信息
      try {
        _systemInfo = await _api!.getSystemInfo();
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '系统信息获取失败不影响连接');
      }

      _connection = config;
      return ServiceConnectionSuccess(this);
    } on NasToolApiException catch (e) {
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure(e.message);
    } on Exception catch (e) {
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure('连接失败: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    _api?.dispose();
    _api = null;
    _connection = null;
    _systemInfo = null;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
  }

  // === 媒体管理方法 ===

  /// 获取媒体库统计
  Future<NasToolMediaStats> getMediaStats() async {
    _ensureConnected();
    return _api!.getMediaStats();
  }

  /// 获取订阅列表
  Future<List<NasToolSubscribe>> getSubscribes() async {
    _ensureConnected();
    return _api!.getSubscribes();
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
    _ensureConnected();
    await _api!.addSubscribe(
      name: name,
      mediaType: mediaType,
      tmdbId: tmdbId,
      imdbId: imdbId,
      season: season,
      keyword: keyword,
    );
  }

  /// 删除订阅
  Future<void> deleteSubscribe(int subscribeId) async {
    _ensureConnected();
    await _api!.deleteSubscribe(subscribeId);
  }

  /// 搜索资源
  Future<List<NasToolSearchResult>> searchResources({
    required String keyword,
    String? mediaType,
    int page = 1,
    int limit = 20,
  }) async {
    _ensureConnected();
    return _api!.searchResources(
      keyword: keyword,
      mediaType: mediaType,
      page: page,
      limit: limit,
    );
  }

  /// 下载资源
  Future<void> downloadResource({
    required String url,
    String? savePath,
  }) async {
    _ensureConnected();
    await _api!.downloadResource(url: url, savePath: savePath);
  }

  /// 获取下载任务列表
  Future<List<NasToolDownloadTask>> getDownloadTasks() async {
    _ensureConnected();
    return _api!.getDownloadTasks();
  }

  /// 获取转移历史
  Future<List<NasToolTransferHistory>> getTransferHistory({
    int page = 1,
    int limit = 20,
  }) async {
    _ensureConnected();
    return _api!.getTransferHistory(page: page, limit: limit);
  }

  /// 识别媒体
  Future<NasToolMediaInfo?> recognizeMedia(String path) async {
    _ensureConnected();
    return _api!.recognizeMedia(path);
  }

  /// 刷新媒体库
  Future<void> refreshMediaLibrary() async {
    _ensureConnected();
    await _api!.refreshMediaLibrary();
  }

  /// 获取综合统计
  Future<NasToolOverviewStats> getOverviewStats() async {
    _ensureConnected();

    final mediaStats = await _api!.getMediaStats();
    final subscribes = await _api!.getSubscribes();
    final downloadTasks = await _api!.getDownloadTasks();

    var activeDownloads = 0;
    var completedDownloads = 0;

    for (final task in downloadTasks) {
      if (task.progress >= 1.0) {
        completedDownloads++;
      } else {
        activeDownloads++;
      }
    }

    return NasToolOverviewStats(
      movieCount: mediaStats.movieCount,
      tvCount: mediaStats.tvCount,
      animeCount: mediaStats.animeCount,
      subscribeCount: subscribes.length,
      activeDownloads: activeDownloads,
      completedDownloads: completedDownloads,
    );
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
    required this.animeCount,
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
