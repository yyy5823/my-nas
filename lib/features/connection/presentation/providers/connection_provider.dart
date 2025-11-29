import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/storage/storage_service.dart';
import 'package:my_nas/features/connection/domain/entities/connection_entity.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/synology/synology_adapter.dart';

/// 当前活跃的 NAS 适配器
final activeAdapterProvider = StateProvider<NasAdapter?>((ref) => null);

/// 当前连接状态
final connectionStateProvider =
    StateNotifierProvider<ConnectionStateNotifier, NasConnectionState>((ref) {
  return ConnectionStateNotifier(ref);
});

/// 保存的连接列表
final savedConnectionsProvider =
    StateNotifierProvider<SavedConnectionsNotifier, List<ConnectionEntity>>(
        (ref) {
  return SavedConnectionsNotifier();
});

/// 连接状态
sealed class NasConnectionState {
  const NasConnectionState();
}

class ConnectionIdle extends NasConnectionState {
  const ConnectionIdle();
}

class ConnectionLoading extends NasConnectionState {
  const ConnectionLoading({this.message});
  final String? message;
}

class ConnectionConnected extends NasConnectionState {
  const ConnectionConnected({
    required this.adapter,
    this.serverInfo,
  });
  final NasAdapter adapter;
  final ServerInfo? serverInfo;
}

class ConnectionRequires2FAState extends NasConnectionState {
  const ConnectionRequires2FAState({required this.adapter});
  final NasAdapter adapter;
}

class ConnectionError extends NasConnectionState {
  const ConnectionError({required this.message});
  final String message;
}

/// 连接状态管理
class ConnectionStateNotifier extends StateNotifier<NasConnectionState> {
  ConnectionStateNotifier(this._ref) : super(const ConnectionIdle());

  final Ref _ref;

  Future<void> connect({
    required NasAdapterType type,
    required String host,
    required int port,
    required String username,
    required String password,
    bool useSsl = true,
    bool verifySSL = true,
  }) async {
    state = const ConnectionLoading(message: '正在连接...');

    NasAdapter? adapter;
    try {
      adapter = _createAdapter(type);
      final config = ConnectionConfig(
        type: type,
        host: host,
        port: port,
        username: username,
        password: password,
        useSsl: useSsl,
        verifySSL: verifySSL,
      );

      final result = await adapter.connect(config);

      state = switch (result) {
        ConnectionSuccess(:final serverInfo) => () {
            _ref.read(activeAdapterProvider.notifier).state = adapter;
            return ConnectionConnected(
              adapter: adapter!,
              serverInfo: serverInfo,
            );
          }(),
        ConnectionFailure(:final error) => () {
            adapter?.dispose();
            return ConnectionError(message: error);
          }(),
        ConnectionRequires2FA() => ConnectionRequires2FAState(adapter: adapter!),
      };
    } catch (e) {
      adapter?.dispose();
      state = ConnectionError(message: '连接失败: ${_getErrorMessage(e)}');
    }
  }

  String _getErrorMessage(Object e) {
    final message = e.toString();
    if (message.contains('Operation not permitted')) {
      return '网络权限被拒绝，请检查系统设置';
    }
    if (message.contains('Connection refused')) {
      return '连接被拒绝，请检查地址和端口';
    }
    if (message.contains('Connection timed out')) {
      return '连接超时，请检查网络';
    }
    if (message.contains('SocketException')) {
      return '网络连接失败';
    }
    return message;
  }

  Future<void> verify2FA(String otpCode) async {
    final currentState = state;
    if (currentState is! ConnectionRequires2FAState) return;

    state = const ConnectionLoading(message: '正在验证...');

    final adapter = currentState.adapter;
    if (adapter is SynologyAdapter) {
      final result = await adapter.verify2FA(otpCode);

      state = switch (result) {
        ConnectionSuccess(:final serverInfo) => () {
            _ref.read(activeAdapterProvider.notifier).state = adapter;
            return ConnectionConnected(
              adapter: adapter,
              serverInfo: serverInfo,
            );
          }(),
        ConnectionFailure(:final error) => ConnectionError(message: error),
        ConnectionRequires2FA() =>
          const ConnectionError(message: '二次验证失败'),
      };
    }
  }

  Future<void> disconnect() async {
    final adapter = _ref.read(activeAdapterProvider);
    if (adapter != null) {
      await adapter.disconnect();
      await adapter.dispose();
      _ref.read(activeAdapterProvider.notifier).state = null;
    }
    state = const ConnectionIdle();
  }

  NasAdapter _createAdapter(NasAdapterType type) => switch (type) {
        NasAdapterType.synology => SynologyAdapter(),
        // TODO: 实现其他适配器
        _ => throw UnimplementedError('适配器 $type 尚未实现'),
      };
}

/// 保存的连接管理
class SavedConnectionsNotifier extends StateNotifier<List<ConnectionEntity>> {
  SavedConnectionsNotifier() : super([]) {
    _loadConnections();
  }

  late final HiveStorageService _storage;
  bool _initialized = false;

  Future<void> _loadConnections() async {
    _storage = HiveStorageService(boxName: 'connections');
    await _storage.init();
    _initialized = true;

    final saved = _storage.get<List<dynamic>>('list');
    if (saved != null) {
      state = saved
          .map((e) => ConnectionEntity.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> addConnection(ConnectionEntity connection) async {
    if (!_initialized) return;

    // 检查是否已存在
    final exists = state.any((c) => c.id == connection.id);
    if (exists) {
      state = [
        for (final c in state)
          if (c.id == connection.id) connection else c,
      ];
    } else {
      state = [...state, connection];
    }

    await _saveConnections();
  }

  Future<void> removeConnection(String id) async {
    if (!_initialized) return;
    state = state.where((c) => c.id != id).toList();
    await _saveConnections();
  }

  Future<void> updateLastConnected(String id) async {
    if (!_initialized) return;
    state = [
      for (final c in state)
        if (c.id == id) c.copyWith(lastConnected: DateTime.now()) else c,
    ];
    await _saveConnections();
  }

  Future<void> _saveConnections() async {
    await _storage.put('list', state.map((c) => c.toJson()).toList());
  }
}
