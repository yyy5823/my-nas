import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/comic/data/services/comic_library_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_library_cache_service.dart';

/// 源管理服务 Provider
final sourceManagerProvider = Provider<SourceManagerService>((ref) => SourceManagerService());

/// 所有源列表 Provider
final sourcesProvider =
    StateNotifierProvider<SourcesNotifier, AsyncValue<List<SourceEntity>>>(
        SourcesNotifier.new);

/// 活跃连接 Provider
final activeConnectionsProvider =
    StateNotifierProvider<ActiveConnectionsNotifier, Map<String, SourceConnection>>(
        ActiveConnectionsNotifier.new);

/// 媒体库配置 Provider
final mediaLibraryConfigProvider =
    StateNotifierProvider<MediaLibraryConfigNotifier, AsyncValue<MediaLibraryConfig>>(
        MediaLibraryConfigNotifier.new);

/// 源列表管理
class SourcesNotifier extends StateNotifier<AsyncValue<List<SourceEntity>>> {
  SourcesNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final manager = _ref.read(sourceManagerProvider);
      await manager.init();
      final sources = await manager.getSources();
      // 按 sortOrder 排序
      sources.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      state = AsyncValue.data(sources);
    } on Exception catch (e, st) {
      // 捕获所有错误，包括 TypeError
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _load();
  }

  Future<void> addSource(SourceEntity source) async {
    final manager = _ref.read(sourceManagerProvider);
    await manager.addSource(source);
    await _load();
  }

  Future<void> updateSource(SourceEntity source) async {
    final manager = _ref.read(sourceManagerProvider);
    await manager.updateSource(source);
    await _load();
  }

  Future<void> removeSource(String sourceId) async {
    final manager = _ref.read(sourceManagerProvider);
    await manager.removeSource(sourceId);

    // 删除该源的所有媒体数据（包括 SQLite 数据库和 Hive 缓存）
    await Future.wait([
      VideoDatabaseService().deleteBySourceId(sourceId),
      VideoLibraryCacheService().deleteBySourceId(sourceId),
      MusicDatabaseService().deleteBySourceId(sourceId),
      PhotoDatabaseService().deleteBySourceId(sourceId),
      BookDatabaseService().deleteBySourceId(sourceId),
      ComicLibraryCacheService().deleteBySourceId(sourceId),
    ]);

    // 同时刷新连接状态
    _ref.read(activeConnectionsProvider.notifier).refresh();
    await _load();
  }

  /// 重新排序源列表
  Future<void> reorderSources(int oldIndex, int newIndex) async {
    final sources = state.valueOrNull;
    if (sources == null) return;

    // 创建可变副本
    final mutableSources = List<SourceEntity>.from(sources);

    // 调整新索引（如果是向后移动）
    final adjustedNewIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;

    // 移动元素
    final item = mutableSources.removeAt(oldIndex);
    mutableSources.insert(adjustedNewIndex, item);

    // 更新排序顺序
    final updatedSources = <SourceEntity>[];
    for (var i = 0; i < mutableSources.length; i++) {
      updatedSources.add(mutableSources[i].copyWith(sortOrder: i));
    }

    // 保存到存储
    final manager = _ref.read(sourceManagerProvider);
    for (final source in updatedSources) {
      await manager.updateSource(source);
    }

    // 立即更新状态（不需要等待 _load）
    state = AsyncValue.data(updatedSources);
  }
}

/// 活跃连接管理
class ActiveConnectionsNotifier
    extends StateNotifier<Map<String, SourceConnection>> {
  ActiveConnectionsNotifier(this._ref) : super({}) {
    // 初始化时自动连接所有源
    _initAutoConnect();
  }

  final Ref _ref;
  bool _hasInitialized = false;
  bool _isAutoConnecting = false;

  /// 已触发过初始自动连接
  bool _hasAutoConnectedOnce = false;

  /// 是否正在自动连接中
  bool get isAutoConnecting => _isAutoConnecting;

  /// 初始化自动连接
  Future<void> _initAutoConnect() async {
    if (_hasInitialized) return;
    _hasInitialized = true;

    // 等待 sourcesProvider 初始化完成
    // 只在应用启动时触发一次自动连接，而不是每次源列表变化都触发
    // 这样可以避免新建源时触发重复连接
    _ref.listen<AsyncValue<List<SourceEntity>>>(sourcesProvider, (previous, next) {
      if (next.hasValue && !_isAutoConnecting && !_hasAutoConnectedOnce) {
        // 数据已准备好，只在首次启动时自动连接（使用 microtask 避免在 listen 回调中直接调用）
        _hasAutoConnectedOnce = true;
        Future.microtask(autoConnectAll);
      }
    }, fireImmediately: true);
  }

  void refresh() {
    final manager = _ref.read(sourceManagerProvider);
    final connections = <String, SourceConnection>{};
    final sources = _ref.read(sourcesProvider).valueOrNull ?? <SourceEntity>[];
    for (final source in sources) {
      final conn = manager.getConnection(source.id);
      if (conn != null) {
        connections[source.id] = conn;
      }
    }
    state = connections;
  }

  Future<SourceConnection> connect(
    SourceEntity source, {
    required String password,
    bool saveCredential = true,
  }) async {
    final manager = _ref.read(sourceManagerProvider);
    final connection = await manager.connect(
      source,
      password: password,
      saveCredential: saveCredential,
    );
    state = {...state, source.id: connection};
    return connection;
  }

  /// 测试连接（不保存凭证，用于新建源时先验证连接）
  Future<SourceConnection> connectNew(
    SourceEntity source, {
    required String password,
  }) async {
    final manager = _ref.read(sourceManagerProvider);
    final connection = await manager.connect(
      source,
      password: password,
      saveCredential: false,
    );
    state = {...state, source.id: connection};
    return connection;
  }

  Future<SourceConnection> verify2FA(
    String sourceId,
    String otpCode, {
    bool rememberDevice = false,
    String? password,
  }) async {
    final manager = _ref.read(sourceManagerProvider);
    final connection = await manager.verify2FA(
      sourceId,
      otpCode,
      rememberDevice: rememberDevice,
      password: password,
    );
    state = {...state, sourceId: connection};
    return connection;
  }

  Future<void> disconnect(String sourceId) async {
    final manager = _ref.read(sourceManagerProvider);
    await manager.disconnect(sourceId);
    state = Map.from(state)..remove(sourceId);
  }

  Future<void> disconnectAll() async {
    final manager = _ref.read(sourceManagerProvider);
    await manager.disconnectAll();
    state = {};
  }

  Future<void> autoConnectAll() async {
    if (_isAutoConnecting) return; // 防止重复调用
    _isAutoConnecting = true;
    try {
      final manager = _ref.read(sourceManagerProvider);
      await manager.autoConnectAll();
      refresh();
    } finally {
      _isAutoConnecting = false;
    }
  }

  /// 获取指定源的文件系统
  SourceConnection? getConnection(String sourceId) => state[sourceId];
}

/// 媒体库配置管理
class MediaLibraryConfigNotifier
    extends StateNotifier<AsyncValue<MediaLibraryConfig>> {
  MediaLibraryConfigNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final manager = _ref.read(sourceManagerProvider);
      await manager.init();
      final config = await manager.getMediaLibraryConfig();
      state = AsyncValue.data(config);
    } on Exception catch (e, st) {
      // 捕获所有错误，包括 TypeError
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _load();
  }

  Future<void> addPath(MediaType type, MediaLibraryPath path) async {
    final current = state.valueOrNull ?? const MediaLibraryConfig();
    final newConfig = current.addPath(type, path);
    await _save(newConfig);
  }

  Future<void> removePath(MediaType type, String pathId) async {
    final current = state.valueOrNull ?? const MediaLibraryConfig();

    // 获取要删除的路径信息（用于清理数据）
    final paths = current.getPathsForType(type);
    final pathToRemove = paths.where((p) => p.id == pathId).firstOrNull;

    // 根据媒体类型删除对应的数据
    if (pathToRemove != null) {
      final sourceId = pathToRemove.sourceId;
      final path = pathToRemove.path;

      switch (type) {
        case MediaType.video:
          // 同时删除 SQLite 数据库和 Hive 缓存
          await Future.wait([
            VideoDatabaseService().deleteByPath(sourceId, path),
            VideoLibraryCacheService().deleteByPath(sourceId, path),
          ]);
        case MediaType.music:
          await MusicDatabaseService().deleteByPath(sourceId, path);
        case MediaType.photo:
          await PhotoDatabaseService().deleteByPath(sourceId, path);
        case MediaType.book:
          await BookDatabaseService().deleteByPath(sourceId, path);
        case MediaType.comic:
          await ComicLibraryCacheService().deleteByPath(sourceId, path);
        case MediaType.note:
          // 笔记暂不处理
          break;
      }
    }

    final newConfig = current.removePath(type, pathId);
    await _save(newConfig);
  }

  Future<void> togglePath(MediaType type, String pathId, {required bool enabled}) async {
    final current = state.valueOrNull ?? const MediaLibraryConfig();
    final paths = current.getPathsForType(type);
    final updatedPaths = paths.map((p) {
      if (p.id == pathId) {
        return p.copyWith(isEnabled: enabled);
      }
      return p;
    }).toList();

    final newConfig = switch (type) {
      MediaType.video => current.copyWith(videoPaths: updatedPaths),
      MediaType.music => current.copyWith(musicPaths: updatedPaths),
      MediaType.photo => current.copyWith(photoPaths: updatedPaths),
      MediaType.comic => current.copyWith(comicPaths: updatedPaths),
      MediaType.book => current.copyWith(bookPaths: updatedPaths),
      MediaType.note => current.copyWith(notePaths: updatedPaths),
    };

    await _save(newConfig);
  }

  Future<void> _save(MediaLibraryConfig config) async {
    final manager = _ref.read(sourceManagerProvider);
    await manager.saveMediaLibraryConfig(config);
    state = AsyncValue.data(config);
  }
}

/// 获取指定媒体类型的可用路径（带源连接状态）
final mediaPathsWithSourceProvider =
    Provider.family<List<(MediaLibraryPath, SourceConnection?)>, MediaType>(
        (ref, type) {
  final config = ref.watch(mediaLibraryConfigProvider).valueOrNull;
  final connections = ref.watch(activeConnectionsProvider);

  if (config == null) return [];

  final paths = config.getEnabledPathsForType(type);
  return paths.map((p) => (p, connections[p.sourceId])).toList();
});

/// 存储类源列表（用于连接源页面）
final storageSourcesProvider = Provider<List<SourceEntity>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources.where((s) => s.type.category.isStorageCategory).toList();
});

/// 下载工具源列表
final downloadToolSourcesProvider = Provider<List<SourceEntity>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources
      .where((s) => s.type.category == SourceCategory.downloadTools)
      .toList();
});

/// 媒体追踪源列表
final mediaTrackingSourcesProvider = Provider<List<SourceEntity>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources
      .where((s) => s.type.category == SourceCategory.mediaTracking)
      .toList();
});

/// 媒体管理源列表
final mediaManagementSourcesProvider = Provider<List<SourceEntity>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources
      .where((s) => s.type.category == SourceCategory.mediaManagement)
      .toList();
});

/// PT 站点源列表
final ptSitesSourcesProvider = Provider<List<SourceEntity>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources
      .where((s) => s.type.category == SourceCategory.ptSites)
      .toList();
});
