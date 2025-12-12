import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/service_adapters/trakt/api/trakt_api.dart';

/// Trakt 连接状态
enum TraktConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Trakt 同步统计
class TraktStats {
  const TraktStats({
    this.moviesWatched = 0,
    this.showsWatched = 0,
    this.episodesWatched = 0,
    this.watchlistCount = 0,
  });

  final int moviesWatched;
  final int showsWatched;
  final int episodesWatched;
  final int watchlistCount;

  factory TraktStats.fromJson(Map<String, dynamic> json) {
    final movies = json['movies'] as Map<String, dynamic>? ?? {};
    final shows = json['shows'] as Map<String, dynamic>? ?? {};
    final episodes = json['episodes'] as Map<String, dynamic>? ?? {};

    return TraktStats(
      moviesWatched: movies['watched'] as int? ?? 0,
      showsWatched: shows['watched'] as int? ?? 0,
      episodesWatched: episodes['watched'] as int? ?? 0,
      watchlistCount: 0, // 需要单独获取
    );
  }
}

/// Trakt 连接状态
class TraktConnectionState {
  const TraktConnectionState({
    this.status = TraktConnectionStatus.disconnected,
    this.userSettings,
    this.stats,
    this.errorMessage,
  });

  final TraktConnectionStatus status;
  final TraktUserSettings? userSettings;
  final TraktStats? stats;
  final String? errorMessage;

  bool get isConnected => status == TraktConnectionStatus.connected;

  TraktConnectionState copyWith({
    TraktConnectionStatus? status,
    TraktUserSettings? userSettings,
    TraktStats? stats,
    String? errorMessage,
  }) =>
      TraktConnectionState(
        status: status ?? this.status,
        userSettings: userSettings ?? this.userSettings,
        stats: stats ?? this.stats,
        errorMessage: errorMessage,
      );
}

/// Trakt 持久化配置
class TraktConfig {
  const TraktConfig({
    required this.clientId,
    required this.clientSecret,
    this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String clientId;
  final String clientSecret;
  final String? accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  bool get hasValidToken =>
      accessToken != null &&
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'clientSecret': clientSecret,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt?.toIso8601String(),
      };

  factory TraktConfig.fromJson(Map<String, dynamic> json) => TraktConfig(
        clientId: json['clientId'] as String,
        clientSecret: json['clientSecret'] as String,
        accessToken: json['accessToken'] as String?,
        refreshToken: json['refreshToken'] as String?,
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
      );

  TraktConfig copyWith({
    String? clientId,
    String? clientSecret,
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) =>
      TraktConfig(
        clientId: clientId ?? this.clientId,
        clientSecret: clientSecret ?? this.clientSecret,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        expiresAt: expiresAt ?? this.expiresAt,
      );
}

/// Trakt 连接管理器
final traktConnectionProvider =
    StateNotifierProvider<TraktConnectionNotifier, TraktConnectionState>(
  (ref) => TraktConnectionNotifier(),
);

class TraktConnectionNotifier extends StateNotifier<TraktConnectionState> {
  TraktConnectionNotifier() : super(const TraktConnectionState()) {
    _init();
  }

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions:
        IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    mOptions:
        MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static const _configKey = 'trakt_config';

  TraktApi? _api;
  TraktConfig? _config;

  /// 获取 API 实例
  TraktApi? get api => _api;

  /// 初始化：尝试从安全存储加载配置并自动连接
  Future<void> _init() async {
    try {
      final configJson = await _storage.read(key: _configKey);
      if (configJson != null) {
        _config = TraktConfig.fromJson(
          jsonDecode(configJson) as Map<String, dynamic>,
        );

        if (_config!.hasValidToken) {
          await _connectWithConfig(_config!);
        } else if (_config!.refreshToken != null) {
          // Token 过期，尝试刷新
          await _refreshToken();
        }
      }
    } on Exception catch (e, st) {
      logger.e('TraktConnectionNotifier: 初始化失败', e, st);
    }
  }

  /// 获取授权 URL
  String getAuthorizationUrl(String clientId, String clientSecret) {
    _api = TraktApi(clientId: clientId, clientSecret: clientSecret);
    return _api!.getAuthorizationUrl();
  }

  /// 使用授权码完成认证
  Future<void> authenticateWithCode(
    String code,
    String clientId,
    String clientSecret,
  ) async {
    state = state.copyWith(status: TraktConnectionStatus.connecting);

    try {
      _api = TraktApi(clientId: clientId, clientSecret: clientSecret);
      final tokenResponse = await _api!.exchangeCodeForToken(code);

      // 保存配置
      _config = TraktConfig(
        clientId: clientId,
        clientSecret: clientSecret,
        accessToken: tokenResponse.accessToken,
        refreshToken: tokenResponse.refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: tokenResponse.expiresIn)),
      );
      await _saveConfig();

      // 获取用户信息和统计
      await _fetchUserData();

      state = state.copyWith(status: TraktConnectionStatus.connected);
      logger.i('TraktConnectionNotifier: 认证成功');
    } on Exception catch (e, st) {
      logger.e('TraktConnectionNotifier: 认证失败', e, st);
      state = state.copyWith(
        status: TraktConnectionStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 使用已保存的配置连接
  Future<void> _connectWithConfig(TraktConfig config) async {
    state = state.copyWith(status: TraktConnectionStatus.connecting);

    try {
      _api = TraktApi(
        clientId: config.clientId,
        clientSecret: config.clientSecret,
        accessToken: config.accessToken,
        refreshToken: config.refreshToken,
        tokenExpiresAt: config.expiresAt,
      );

      await _fetchUserData();
      state = state.copyWith(status: TraktConnectionStatus.connected);
      logger.i('TraktConnectionNotifier: 使用保存的配置连接成功');
    } on Exception catch (e, st) {
      logger.e('TraktConnectionNotifier: 连接失败', e, st);
      state = state.copyWith(
        status: TraktConnectionStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 刷新 Token
  Future<void> _refreshToken() async {
    if (_config?.refreshToken == null) return;

    try {
      _api = TraktApi(
        clientId: _config!.clientId,
        clientSecret: _config!.clientSecret,
        refreshToken: _config!.refreshToken,
      );

      final tokenResponse = await _api!.refreshAccessToken();

      _config = _config!.copyWith(
        accessToken: tokenResponse.accessToken,
        refreshToken: tokenResponse.refreshToken,
        expiresAt: DateTime.now().add(Duration(seconds: tokenResponse.expiresIn)),
      );
      await _saveConfig();

      await _fetchUserData();
      state = state.copyWith(status: TraktConnectionStatus.connected);
      logger.i('TraktConnectionNotifier: Token 刷新成功');
    } on Exception catch (e, st) {
      logger.e('TraktConnectionNotifier: Token 刷新失败', e, st);
      state = state.copyWith(
        status: TraktConnectionStatus.error,
        errorMessage: 'Token 刷新失败，请重新登录',
      );
    }
  }

  /// 获取用户数据
  Future<void> _fetchUserData() async {
    if (_api == null) return;

    try {
      // 获取用户设置
      final userSettings = await _api!.getUserSettings();

      // 获取统计数据（watchlist 需要单独获取）
      final watchlist = await _api!.getWatchlist(limit: 1);

      state = state.copyWith(
        userSettings: userSettings,
        stats: TraktStats(
          moviesWatched: 0, // 需要额外 API 调用
          showsWatched: 0,
          episodesWatched: 0,
          watchlistCount: watchlist.length,
        ),
      );
    } on Exception catch (e, st) {
      logger.w('TraktConnectionNotifier: 获取用户数据失败', e, st);
    }
  }

  /// 刷新统计数据
  Future<void> refreshStats() async {
    if (_api == null || state.status != TraktConnectionStatus.connected) return;

    await _fetchUserData();
  }

  /// 注销
  Future<void> logout() async {
    try {
      if (_api != null) {
        await _api!.revokeToken();
      }
    } on Exception catch (e, st) {
      logger.w('TraktConnectionNotifier: 撤销 Token 失败（忽略）', e, st);
    }

    _api?.dispose();
    _api = null;
    _config = null;

    await _storage.delete(key: _configKey);

    state = const TraktConnectionState();
    logger.i('TraktConnectionNotifier: 已注销');
  }

  /// 保存配置到安全存储
  Future<void> _saveConfig() async {
    if (_config == null) return;

    try {
      await _storage.write(
        key: _configKey,
        value: jsonEncode(_config!.toJson()),
      );
    } on Exception catch (e, st) {
      logger.e('TraktConnectionNotifier: 保存配置失败', e, st);
    }
  }

  @override
  void dispose() {
    _api?.dispose();
    super.dispose();
  }
}
