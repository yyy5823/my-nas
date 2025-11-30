import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

/// 源管理服务 Provider
final sourceManagerProvider = Provider<SourceManagerService>((ref) {
  return SourceManagerService.instance;
});

/// 所有源列表 Provider
final sourcesProvider =
    StateNotifierProvider<SourcesNotifier, AsyncValue<List<SourceEntity>>>(
        (ref) {
  return SourcesNotifier(ref);
});

/// 活跃连接 Provider
final activeConnectionsProvider =
    StateNotifierProvider<ActiveConnectionsNotifier, Map<String, SourceConnection>>(
        (ref) {
  return ActiveConnectionsNotifier(ref);
});

/// 媒体库配置 Provider
final mediaLibraryConfigProvider =
    StateNotifierProvider<MediaLibraryConfigNotifier, AsyncValue<MediaLibraryConfig>>(
        (ref) {
  return MediaLibraryConfigNotifier(ref);
});

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
      state = AsyncValue.data(sources);
    } catch (e, st) {
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
    // 同时刷新连接状态
    _ref.read(activeConnectionsProvider.notifier).refresh();
    await _load();
  }
}

/// 活跃连接管理
class ActiveConnectionsNotifier
    extends StateNotifier<Map<String, SourceConnection>> {
  ActiveConnectionsNotifier(this._ref) : super({});

  final Ref _ref;

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

  Future<SourceConnection> verify2FA(
    String sourceId,
    String otpCode, {
    bool rememberDevice = false,
  }) async {
    final manager = _ref.read(sourceManagerProvider);
    final connection = await manager.verify2FA(
      sourceId,
      otpCode,
      rememberDevice: rememberDevice,
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
    final manager = _ref.read(sourceManagerProvider);
    await manager.autoConnectAll();
    refresh();
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
    } catch (e, st) {
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
    final newConfig = current.removePath(type, pathId);
    await _save(newConfig);
  }

  Future<void> togglePath(MediaType type, String pathId, bool enabled) async {
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
