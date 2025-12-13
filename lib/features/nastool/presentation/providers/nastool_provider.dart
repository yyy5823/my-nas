import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/service_adapters/nastool/api/nastool_api.dart';
import 'package:my_nas/service_adapters/nastool/nastool_adapter.dart';

/// NASTool 连接状态
enum NasToolConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// NASTool 连接信息
class NasToolConnection {
  const NasToolConnection({
    required this.source,
    required this.adapter,
    this.status = NasToolConnectionStatus.disconnected,
    this.errorMessage,
  });

  final SourceEntity source;
  final NasToolAdapter adapter;
  final NasToolConnectionStatus status;
  final String? errorMessage;

  NasToolConnection copyWith({
    SourceEntity? source,
    NasToolAdapter? adapter,
    NasToolConnectionStatus? status,
    String? errorMessage,
  }) =>
      NasToolConnection(
        source: source ?? this.source,
        adapter: adapter ?? this.adapter,
        status: status ?? this.status,
        errorMessage: errorMessage,
      );
}

/// NASTool 连接管理 Provider
final nastoolConnectionProvider = StateNotifierProvider.family<
    NasToolConnectionNotifier, NasToolConnection?, String>(
  (ref, sourceId) => NasToolConnectionNotifier(sourceId),
);

class NasToolConnectionNotifier extends StateNotifier<NasToolConnection?> {
  NasToolConnectionNotifier(this.sourceId) : super(null);

  final String sourceId;

  /// 连接到 NASTool
  Future<NasToolConnection> connect(SourceEntity source) async {
    logger.i('NasToolProvider: 连接到 ${source.name}');

    final adapter = NasToolAdapter();

    // 更新状态为连接中
    state = NasToolConnection(
      source: source,
      adapter: adapter,
      status: NasToolConnectionStatus.connecting,
    );

    final config = ServiceConnectionConfig.fromSource(source);

    try {
      final result = await adapter.connect(config);

      final connection = result.when(
        success: (_) => NasToolConnection(
          source: source,
          adapter: adapter,
          status: NasToolConnectionStatus.connected,
        ),
        failure: (error) => NasToolConnection(
          source: source,
          adapter: adapter,
          status: NasToolConnectionStatus.error,
          errorMessage: error,
        ),
      );

      state = connection;
      return connection;
    } on Exception catch (e) {
      final connection = NasToolConnection(
        source: source,
        adapter: adapter,
        status: NasToolConnectionStatus.error,
        errorMessage: e.toString(),
      );
      state = connection;
      return connection;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    final connection = state;
    if (connection != null) {
      await connection.adapter.disconnect();
      state = null;
      logger.i('NasToolProvider: 断开连接 $sourceId');
    }
  }

  /// 获取适配器
  NasToolAdapter? get adapter => state?.adapter;
}

/// NASTool 概览统计 Provider
final nastoolOverviewProvider = FutureProvider.family
    .autoDispose<NasToolOverviewStats?, String>((ref, sourceId) async {
  final connection = ref.watch(nastoolConnectionProvider(sourceId));
  if (connection == null ||
      connection.status != NasToolConnectionStatus.connected) {
    return null;
  }

  try {
    return await connection.adapter.getOverviewStats();
  } on Exception catch (e) {
    logger.e('NasToolProvider: 获取概览统计失败', e);
    return null;
  }
});

/// NASTool 媒体统计 Provider
final nastoolMediaStatsProvider = FutureProvider.family
    .autoDispose<NasToolMediaStats?, String>((ref, sourceId) async {
  final connection = ref.watch(nastoolConnectionProvider(sourceId));
  if (connection == null ||
      connection.status != NasToolConnectionStatus.connected) {
    return null;
  }

  try {
    return await connection.adapter.getMediaStats();
  } on Exception catch (e) {
    logger.e('NasToolProvider: 获取媒体统计失败', e);
    return null;
  }
});

/// NASTool 订阅列表 Provider
final nastoolSubscribesProvider = FutureProvider.family
    .autoDispose<List<NasToolSubscribe>, String>((ref, sourceId) async {
  final connection = ref.watch(nastoolConnectionProvider(sourceId));
  if (connection == null ||
      connection.status != NasToolConnectionStatus.connected) {
    return [];
  }

  try {
    return await connection.adapter.getSubscribes();
  } on Exception catch (e) {
    logger.e('NasToolProvider: 获取订阅列表失败', e);
    return [];
  }
});

/// NASTool 下载任务 Provider
final nastoolDownloadTasksProvider = FutureProvider.family
    .autoDispose<List<NasToolDownloadTask>, String>((ref, sourceId) async {
  final connection = ref.watch(nastoolConnectionProvider(sourceId));
  if (connection == null ||
      connection.status != NasToolConnectionStatus.connected) {
    return [];
  }

  try {
    return await connection.adapter.getDownloadTasks();
  } on Exception catch (e) {
    logger.e('NasToolProvider: 获取下载任务失败', e);
    return [];
  }
});

/// NASTool 转移历史 Provider
final nastoolTransferHistoryProvider = FutureProvider.family
    .autoDispose<List<NasToolTransferHistory>, String>((ref, sourceId) async {
  final connection = ref.watch(nastoolConnectionProvider(sourceId));
  if (connection == null ||
      connection.status != NasToolConnectionStatus.connected) {
    return [];
  }

  try {
    return await connection.adapter.getTransferHistory();
  } on Exception catch (e) {
    logger.e('NasToolProvider: 获取转移历史失败', e);
    return [];
  }
});

/// 自动刷新的概览统计 Provider
class NasToolOverviewAutoRefreshNotifier
    extends StateNotifier<NasToolOverviewStats?> {
  NasToolOverviewAutoRefreshNotifier(this._ref, this._sourceId) : super(null) {
    _startAutoRefresh();
  }

  final Ref _ref;
  final String _sourceId;
  Timer? _timer;

  void _startAutoRefresh() {
    _refresh();
    // 每 10 秒刷新一次
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final connection = _ref.read(nastoolConnectionProvider(_sourceId));
    if (connection == null ||
        connection.status != NasToolConnectionStatus.connected) {
      return;
    }

    try {
      final stats = await connection.adapter.getOverviewStats();
      if (mounted) {
        state = stats;
      }
    } on Exception catch (e) {
      logger.e('NasToolOverviewAutoRefresh: 刷新失败', e);
    }
  }

  /// 手动刷新
  Future<void> refresh() => _refresh();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final nastoolOverviewAutoRefreshProvider = StateNotifierProvider.family
    .autoDispose<NasToolOverviewAutoRefreshNotifier, NasToolOverviewStats?,
        String>(
  NasToolOverviewAutoRefreshNotifier.new,
);

/// NASTool 操作 Provider
final nastoolActionsProvider =
    Provider.family<NasToolActions, String>(NasToolActions.new);

class NasToolActions {
  NasToolActions(this._ref, this._sourceId);

  final Ref _ref;
  final String _sourceId;

  NasToolAdapter? get _adapter =>
      _ref.read(nastoolConnectionProvider(_sourceId))?.adapter;

  void _invalidateSubscribes() {
    _ref.invalidate(nastoolSubscribesProvider(_sourceId));
  }

  void _invalidateDownloads() {
    _ref.invalidate(nastoolDownloadTasksProvider(_sourceId));
  }

  void _invalidateAll() {
    _ref
      ..invalidate(nastoolOverviewProvider(_sourceId))
      ..invalidate(nastoolOverviewAutoRefreshProvider(_sourceId))
      ..invalidate(nastoolSubscribesProvider(_sourceId))
      ..invalidate(nastoolDownloadTasksProvider(_sourceId))
      ..invalidate(nastoolTransferHistoryProvider(_sourceId));
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
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.addSubscribe(
      name: name,
      mediaType: mediaType,
      tmdbId: tmdbId,
      imdbId: imdbId,
      season: season,
      keyword: keyword,
    );
    _invalidateSubscribes();
  }

  /// 删除订阅
  Future<void> deleteSubscribe(int subscribeId) async {
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.deleteSubscribe(subscribeId);
    _invalidateSubscribes();
  }

  /// 搜索资源
  Future<List<NasToolSearchResult>> searchResources({
    required String keyword,
    String? mediaType,
    int page = 1,
    int limit = 20,
  }) async {
    final adapter = _adapter;
    if (adapter == null) return [];

    return adapter.searchResources(
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
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.downloadResource(url: url, savePath: savePath);
    _invalidateDownloads();
  }

  /// 刷新媒体库
  Future<void> refreshMediaLibrary() async {
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.refreshMediaLibrary();
  }

  /// 刷新所有数据
  void refreshAll() {
    _invalidateAll();
  }
}

/// 当前选中的标签页
enum NasToolTab {
  overview,
  subscribes,
  downloads,
  history,
  search,
}

/// 当前标签页 Provider
final nastoolCurrentTabProvider =
    StateProvider.family<NasToolTab, String>((ref, sourceId) => NasToolTab.overview);
