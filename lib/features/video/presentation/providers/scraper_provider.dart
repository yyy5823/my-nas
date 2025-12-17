import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/data/services/scraper_factory.dart';
import 'package:my_nas/features/video/data/services/scraper_manager_service.dart';
import 'package:my_nas/features/video/domain/entities/scraper_result.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';

/// 刮削源管理服务 Provider
final scraperManagerProvider = Provider<ScraperManagerService>((ref) => ScraperManagerService());

/// 刮削源列表 Provider
final scraperSourcesProvider =
    StateNotifierProvider<ScraperSourcesNotifier, AsyncValue<List<ScraperSourceEntity>>>(
        ScraperSourcesNotifier.new);

/// 已启用的刮削源数量 Provider
final enabledScraperCountProvider = Provider<int>((ref) {
  final sources = ref.watch(scraperSourcesProvider).valueOrNull ?? [];
  return sources.where((s) => s.isEnabled).length;
});

/// 总刮削源数量 Provider
final totalScraperCountProvider = Provider<int>((ref) {
  final sources = ref.watch(scraperSourcesProvider).valueOrNull ?? [];
  return sources.length;
});

/// 刮削源列表管理
class ScraperSourcesNotifier extends StateNotifier<AsyncValue<List<ScraperSourceEntity>>> {
  ScraperSourcesNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final manager = _ref.read(scraperManagerProvider);
      await manager.init();

      // 尝试从旧配置迁移
      await manager.migrateFromLegacyConfig();

      final sources = await manager.getSources();
      state = AsyncValue.data(sources);
    } on Exception catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 刷新列表
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _load();
  }

  /// 添加刮削源
  Future<void> addSource(ScraperSourceEntity source) async {
    final manager = _ref.read(scraperManagerProvider);
    await manager.addSource(source);
    await _load();
  }

  /// 更新刮削源
  Future<void> updateSource(ScraperSourceEntity source) async {
    final manager = _ref.read(scraperManagerProvider);
    await manager.updateSource(source);
    await _load();
  }

  /// 删除刮削源
  Future<void> removeSource(String sourceId) async {
    final manager = _ref.read(scraperManagerProvider);
    await manager.removeSource(sourceId);
    await _load();
  }

  /// 重新排序刮削源
  Future<void> reorderSources(int oldIndex, int newIndex) async {
    final sources = state.valueOrNull;
    if (sources == null) return;

    // 创建可变副本
    final mutableSources = List<ScraperSourceEntity>.from(sources);

    // 调整新索引（如果是向后移动）
    final adjustedNewIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;

    // 移动元素
    final item = mutableSources.removeAt(oldIndex);
    mutableSources.insert(adjustedNewIndex, item);

    // 更新排序顺序
    final updatedSources = <ScraperSourceEntity>[];
    for (var i = 0; i < mutableSources.length; i++) {
      updatedSources.add(mutableSources[i].copyWith(priority: i));
    }

    // 保存到存储
    final manager = _ref.read(scraperManagerProvider);
    for (final source in updatedSources) {
      await manager.updateSource(source);
    }

    // 立即更新状态
    state = AsyncValue.data(updatedSources);
  }

  /// 启用/禁用刮削源
  Future<void> toggleSource(String sourceId, {required bool enabled}) async {
    final manager = _ref.read(scraperManagerProvider);
    await manager.toggleSource(sourceId, enabled: enabled);

    // 立即更新状态（不需要完整 reload）
    final sources = state.valueOrNull;
    if (sources != null) {
      final updatedSources = sources.map((s) {
        if (s.id == sourceId) {
          return s.copyWith(isEnabled: enabled);
        }
        return s;
      }).toList();
      state = AsyncValue.data(updatedSources);
    }
  }

  /// 测试刮削源连接
  Future<bool> testConnection(ScraperSourceEntity source) async {
    final manager = _ref.read(scraperManagerProvider);
    final scraper = await manager.getScraper(source.id);
    if (scraper == null) return false;
    return scraper.testConnection();
  }

  /// 使用临时凭证测试连接（用于新建或编辑时）
  Future<bool> testConnectionWithCredential(
    ScraperType type,
    ScraperCredential credential, {
    String? apiUrl,
    int requestInterval = 0,
  }) async {
    final scraper = ScraperFactory.createFromCredential(
      type,
      credential,
      apiUrl: apiUrl,
      requestInterval: requestInterval,
    );

    try {
      return await scraper.testConnection();
    } finally {
      scraper.dispose();
    }
  }
}

/// 搜索电影结果 Provider（带参数）
final searchMoviesProvider = FutureProvider.family
    .autoDispose<ScraperSearchResult, MovieSearchParams>((ref, params) async {
  final manager = ref.read(scraperManagerProvider);
  await manager.init();
  return manager.searchMovies(
    params.query,
    page: params.page,
    language: params.language,
    year: params.year,
  );
});

/// 搜索电视剧结果 Provider（带参数）
final searchTvShowsProvider = FutureProvider.family
    .autoDispose<ScraperSearchResult, TvSearchParams>((ref, params) async {
  final manager = ref.read(scraperManagerProvider);
  await manager.init();
  return manager.searchTvShows(
    params.query,
    page: params.page,
    language: params.language,
    year: params.year,
  );
});

/// 电影详情 Provider
final movieDetailProvider = FutureProvider.family
    .autoDispose<ScraperMovieDetail?, MovieDetailParams>((ref, params) async {
  final manager = ref.read(scraperManagerProvider);
  await manager.init();
  return manager.getMovieDetail(
    query: params.query,
    externalId: params.externalId,
    source: params.source,
    language: params.language,
    year: params.year,
  );
});

/// 电视剧详情 Provider
final tvDetailProvider = FutureProvider.family
    .autoDispose<ScraperTvDetail?, TvDetailParams>((ref, params) async {
  final manager = ref.read(scraperManagerProvider);
  await manager.init();
  return manager.getTvDetail(
    query: params.query,
    externalId: params.externalId,
    source: params.source,
    language: params.language,
    year: params.year,
  );
});

/// 电影搜索参数
class MovieSearchParams {
  const MovieSearchParams({
    required this.query,
    this.page = 1,
    this.language,
    this.year,
  });

  final String query;
  final int page;
  final String? language;
  final int? year;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovieSearchParams &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          page == other.page &&
          language == other.language &&
          year == other.year;

  @override
  int get hashCode => Object.hash(query, page, language, year);
}

/// 电视剧搜索参数
class TvSearchParams {
  const TvSearchParams({
    required this.query,
    this.page = 1,
    this.language,
    this.year,
  });

  final String query;
  final int page;
  final String? language;
  final int? year;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TvSearchParams &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          page == other.page &&
          language == other.language &&
          year == other.year;

  @override
  int get hashCode => Object.hash(query, page, language, year);
}

/// 电影详情参数
class MovieDetailParams {
  const MovieDetailParams({
    this.query,
    this.externalId,
    this.source,
    this.language,
    this.year,
  });

  final String? query;
  final String? externalId;
  final ScraperType? source;
  final String? language;
  final int? year;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovieDetailParams &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          externalId == other.externalId &&
          source == other.source &&
          language == other.language &&
          year == other.year;

  @override
  int get hashCode => Object.hash(query, externalId, source, language, year);
}

/// 电视剧详情参数
class TvDetailParams {
  const TvDetailParams({
    this.query,
    this.externalId,
    this.source,
    this.language,
    this.year,
  });

  final String? query;
  final String? externalId;
  final ScraperType? source;
  final String? language;
  final int? year;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TvDetailParams &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          externalId == other.externalId &&
          source == other.source &&
          language == other.language &&
          year == other.year;

  @override
  int get hashCode => Object.hash(query, externalId, source, language, year);
}
