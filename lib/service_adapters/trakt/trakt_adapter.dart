import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';

import 'api/trakt_api.dart';

/// Trakt 服务适配器
///
/// 提供 Trakt 媒体追踪服务的连接和管理功能
/// 支持 OAuth 2.0 认证
class TraktAdapter implements ServiceAdapter {
  TraktAdapter();

  TraktApi? _api;
  ServiceConnectionConfig? _connection;
  TraktUserSettings? _userSettings;

  @override
  ServiceAdapterInfo get info => ServiceAdapterInfo(
        name: 'Trakt',
        type: SourceType.trakt,
        description: '追踪观看记录和媒体状态',
      );

  @override
  bool get isConnected => _api?.isAuthenticated ?? false;

  @override
  ServiceConnectionConfig? get connection => _connection;

  /// 获取 API 客户端
  TraktApi? get api => _api;

  /// 获取用户设置
  TraktUserSettings? get userSettings => _userSettings;

  /// Token 是否需要刷新
  bool get needsTokenRefresh => _api?.needsTokenRefresh ?? false;

  /// 获取授权 URL
  String getAuthorizationUrl(String clientId, String clientSecret) {
    _api = TraktApi(
      clientId: clientId,
      clientSecret: clientSecret,
    );
    return _api!.getAuthorizationUrl();
  }

  /// 使用授权码完成认证
  Future<ServiceConnectionResult> authenticateWithCode(
    String code,
    String clientId,
    String clientSecret,
  ) async {
    try {
      _api ??= TraktApi(
        clientId: clientId,
        clientSecret: clientSecret,
      );

      final tokenResponse = await _api!.exchangeCodeForToken(code);

      // 获取用户信息
      try {
        _userSettings = await _api!.getUserSettings();
      } catch (_) {
        // 用户信息获取失败不影响连接
      }

      _connection = ServiceConnectionConfig(
        baseUrl: TraktApi.apiUrl,
        extraConfig: {
          'clientId': clientId,
          'clientSecret': clientSecret,
          'accessToken': tokenResponse.accessToken,
          'refreshToken': tokenResponse.refreshToken,
          'expiresIn': tokenResponse.expiresIn,
        },
      );

      return ServiceConnectionSuccess(this);
    } on TraktApiException catch (e) {
      return ServiceConnectionFailure(e.message);
    } catch (e) {
      return ServiceConnectionFailure('认证失败: $e');
    }
  }

  @override
  Future<ServiceConnectionResult> connect(ServiceConnectionConfig config) async {
    try {
      final extraConfig = config.extraConfig;
      if (extraConfig == null) {
        return const ServiceConnectionFailure('缺少 OAuth 配置信息');
      }

      final clientId = extraConfig['clientId'] as String?;
      final clientSecret = extraConfig['clientSecret'] as String?;
      final accessToken = extraConfig['accessToken'] as String?;
      final refreshToken = extraConfig['refreshToken'] as String?;

      if (clientId == null || clientSecret == null) {
        return const ServiceConnectionFailure('缺少 Client ID 或 Client Secret');
      }

      _api = TraktApi(
        clientId: clientId,
        clientSecret: clientSecret,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      // 如果没有 token，需要进行 OAuth 授权
      if (accessToken == null || accessToken.isEmpty) {
        return const ServiceConnectionFailure('需要进行 OAuth 授权');
      }

      // 检查 token 是否需要刷新
      if (_api!.needsTokenRefresh && refreshToken != null) {
        await _api!.refreshAccessToken();
      }

      // 验证连接
      try {
        _userSettings = await _api!.getUserSettings();
      } catch (e) {
        _api?.dispose();
        _api = null;
        return ServiceConnectionFailure('连接验证失败: $e');
      }

      _connection = config;
      return ServiceConnectionSuccess(this);
    } on TraktApiException catch (e) {
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure(e.message);
    } catch (e) {
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure('连接失败: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _api?.revokeToken();
    } catch (_) {
      // 忽略撤销错误
    }
    _api?.dispose();
    _api = null;
    _connection = null;
    _userSettings = null;
  }

  @override
  Future<void> dispose() async {
    _api?.dispose();
    _api = null;
    _connection = null;
    _userSettings = null;
  }

  // === 媒体追踪方法 ===

  /// 获取观看历史
  Future<List<TraktHistoryItem>> getWatchedHistory({
    String type = 'movies,shows',
    int page = 1,
    int limit = 20,
  }) async {
    _ensureConnected();
    return _api!.getWatchedHistory(type: type, page: page, limit: limit);
  }

  /// 获取待看列表
  Future<List<TraktWatchlistItem>> getWatchlist({
    String type = 'movies,shows',
    int page = 1,
    int limit = 20,
  }) async {
    _ensureConnected();
    return _api!.getWatchlist(type: type, page: page, limit: limit);
  }

  /// 获取收藏列表
  Future<List<TraktCollectionItem>> getCollection({
    String type = 'movies',
  }) async {
    _ensureConnected();
    return _api!.getCollection(type: type);
  }

  /// 获取评分列表
  Future<List<TraktRatingItem>> getRatings({
    String type = 'movies,shows',
  }) async {
    _ensureConnected();
    return _api!.getRatings(type: type);
  }

  /// 标记为已观看
  Future<void> markAsWatched(TraktMediaItem item) async {
    _ensureConnected();
    await _api!.addToHistory([item]);
  }

  /// 添加到待看列表
  Future<void> addToWatchlist(TraktMediaItem item) async {
    _ensureConnected();
    await _api!.addToWatchlist([item]);
  }

  /// 添加评分
  Future<void> addRating(TraktMediaItem item, int rating) async {
    _ensureConnected();
    await _api!.addRating(item, rating);
  }

  /// 搜索媒体
  Future<List<TraktSearchResult>> search(
    String query, {
    String type = 'movie,show',
    int page = 1,
    int limit = 10,
  }) async {
    _ensureConnected();
    return _api!.search(query, type: type, page: page, limit: limit);
  }

  /// 获取同步统计
  Future<TraktSyncStats> getSyncStats() async {
    _ensureConnected();

    final movies = await _api!.getCollection(type: 'movies');
    final shows = await _api!.getCollection(type: 'shows');
    final watchlist = await _api!.getWatchlist();
    final ratings = await _api!.getRatings();

    return TraktSyncStats(
      moviesCollected: movies.length,
      showsCollected: shows.length,
      watchlistItems: watchlist.length,
      ratingsCount: ratings.length,
    );
  }

  /// 刷新 Token（如果需要）
  Future<void> refreshTokenIfNeeded() async {
    if (_api != null && _api!.needsTokenRefresh) {
      await _api!.refreshAccessToken();
    }
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw const TraktApiException('未连接到 Trakt');
    }
  }
}

/// 同步统计信息
class TraktSyncStats {
  const TraktSyncStats({
    required this.moviesCollected,
    required this.showsCollected,
    required this.watchlistItems,
    required this.ratingsCount,
  });

  final int moviesCollected;
  final int showsCollected;
  final int watchlistItems;
  final int ratingsCount;
}
