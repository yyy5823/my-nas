import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/service_adapters/nastool/api/nastool_api.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';
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

/// NASTool 综合统计 Provider
final nastoolStatsProvider = FutureProvider.family
    .autoDispose<NasToolOverviewStats?, String>((ref, sourceId) async {
  final connection = ref.watch(nastoolConnectionProvider(sourceId));
  if (connection == null || connection.status != NasToolConnectionStatus.connected) {
    return null;
  }

  try {
    final adapter = connection.adapter;
    
    // 并行获取各项数据
    final results = await Future.wait([
      adapter.getLibraryStatistics().catchError((_) => const NtLibraryStatistics(movieCount: 0, tvCount: 0)),
      adapter.getAllSubscribes().catchError((_) => <NtSubscribe>[]),
      adapter.getDownloadTasks().catchError((_) => <NtDownloadTask>[]),
    ]);

    final stats = results[0] as NtLibraryStatistics;
    final subscribes = results[1] as List<NtSubscribe>;
    final downloads = results[2] as List<NtDownloadTask>;

    final activeDownloads = downloads.where((t) => !t.isCompleted).length;
    final completedDownloads = downloads.where((t) => t.isCompleted).length;

    return NasToolOverviewStats(
      movieCount: stats.movieCount,
      tvCount: stats.tvCount,
      animeCount: stats.animeCount ?? 0,
      subscribeCount: subscribes.length,
      activeDownloads: activeDownloads,
      completedDownloads: completedDownloads,
    );
  } on Exception catch (e) {
    logger.e('NasToolProvider: 获取统计失败', e);
    return null;
  }
});

/// NASTool 订阅列表 Provider
final nastoolSubscribesProvider = FutureProvider.family
    .autoDispose<List<NtSubscribe>, String>((ref, sourceId) async {
  final connection = ref.watch(nastoolConnectionProvider(sourceId));
  if (connection == null || connection.status != NasToolConnectionStatus.connected) {
    return [];
  }

  try {
    return await connection.adapter.getAllSubscribes();
  } on Exception catch (e) {
    logger.e('NasToolProvider: 获取订阅列表失败', e);
    return [];
  }
});

/// NASTool 下载任务 Provider
final nastoolDownloadsProvider = FutureProvider.family
    .autoDispose<List<NtDownloadTask>, String>((ref, sourceId) async {
  final connection = ref.watch(nastoolConnectionProvider(sourceId));
  if (connection == null || connection.status != NasToolConnectionStatus.connected) {
    return [];
  }

  try {
    return await connection.adapter.getDownloadTasks();
  } on Exception catch (e) {
    logger.e('NasToolProvider: 获取下载任务失败', e);
    return [];
  }
});

/// NASTool 站点列表 Provider
final nastoolSitesProvider = FutureProvider.family
    .autoDispose<List<NtSite>, String>((ref, sourceId) async {
  final connection = ref.watch(nastoolConnectionProvider(sourceId));
  if (connection == null || connection.status != NasToolConnectionStatus.connected) {
    return [];
  }

  try {
    return await connection.adapter.getSites();
  } on Exception catch (e) {
    logger.e('NasToolProvider: 获取站点列表失败', e);
    return [];
  }
});

/// NASTool 转移历史 Provider
final nastoolTransferHistoryProvider = FutureProvider.family
    .autoDispose<List<NtTransferHistory>, String>((ref, sourceId) async {
  final connection = ref.watch(nastoolConnectionProvider(sourceId));
  if (connection == null || connection.status != NasToolConnectionStatus.connected) {
    return [];
  }

  try {
    return await connection.adapter.getTransferHistory();
  } on Exception catch (e) {
    logger.e('NasToolProvider: 获取转移历史失败', e);
    return [];
  }
});

/// NASTool 操作 Provider
final nastoolActionsProvider = Provider.family<NasToolActions, String>(NasToolActions.new);

class NasToolActions {
  NasToolActions(this._ref, this._sourceId);

  final Ref _ref;
  final String _sourceId;

  NasToolAdapter? get _adapter =>
      _ref.read(nastoolConnectionProvider(_sourceId))?.adapter;

  void _invalidateAll() {
    _ref
      ..invalidate(nastoolStatsProvider(_sourceId))
      ..invalidate(nastoolSubscribesProvider(_sourceId))
      ..invalidate(nastoolDownloadsProvider(_sourceId))
      ..invalidate(nastoolSitesProvider(_sourceId))
      ..invalidate(nastoolTransferHistoryProvider(_sourceId));
  }

  /// 添加订阅
  Future<void> addSubscribe({
    required String name,
    required String type,
    String? year,
    String? mediaId,
    int? season,
  }) async {
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.addSubscribe(
      name: name,
      type: type,
      year: year,
      mediaId: mediaId,
      season: season,
    );
    _ref.invalidate(nastoolSubscribesProvider(_sourceId));
  }

  /// 删除订阅
  Future<void> deleteSubscribe(int id, String type) async {
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.deleteSubscribe(id, type);
    _ref.invalidate(nastoolSubscribesProvider(_sourceId));
  }

  /// 搜索资源
  Future<List<NtSearchResult>> searchResources(String keyword) async {
    final adapter = _adapter;
    if (adapter == null) return [];

    return adapter.searchResources(keyword);
  }

  /// 下载资源
  Future<void> downloadResource({
    required String enclosure,
    required String title,
  }) async {
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.downloadResource(enclosure: enclosure, title: title);
    _ref.invalidate(nastoolDownloadsProvider(_sourceId));
  }

  /// 刷新媒体库
  Future<void> refreshLibrary() async {
    final adapter = _adapter;
    if (adapter == null) return;

    await adapter.refreshLibrary();
  }

  /// 刷新所有数据
  void refreshAll() {
    _invalidateAll();
  }
}
