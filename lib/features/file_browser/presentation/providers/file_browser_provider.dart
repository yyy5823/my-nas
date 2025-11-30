import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 当前路径
final currentPathProvider = StateProvider<String>((ref) => '/');

/// 当前选中的源ID（用于文件浏览器）
final selectedSourceIdProvider = StateProvider<String?>((ref) => null);

/// 获取当前选中的源连接
final selectedSourceConnectionProvider = Provider<SourceConnection?>((ref) {
  final selectedId = ref.watch(selectedSourceIdProvider);
  if (selectedId == null) return null;

  final connections = ref.watch(activeConnectionsProvider);
  return connections[selectedId];
});

/// 获取所有已连接的源列表
final connectedSourcesProvider = Provider<List<(SourceEntity, SourceConnection)>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  final connections = ref.watch(activeConnectionsProvider);

  final result = <(SourceEntity, SourceConnection)>[];
  for (final source in sources) {
    final connection = connections[source.id];
    if (connection != null && connection.status == SourceStatus.connected) {
      result.add((source, connection));
    }
  }
  return result;
});

/// 文件列表状态
final fileListProvider =
    StateNotifierProvider<FileListNotifier, FileListState>((ref) {
  return FileListNotifier(ref);
});

/// 视图模式
final viewModeProvider = StateProvider<ViewMode>((ref) => ViewMode.grid);

/// 排序方式
final sortModeProvider = StateProvider<SortMode>((ref) => SortMode.name);

/// 排序方向
final sortAscendingProvider = StateProvider<bool>((ref) => true);

enum ViewMode { list, grid }

enum SortMode { name, size, date, type }

/// 文件列表状态
sealed class FileListState {
  const FileListState();
}

class FileListLoading extends FileListState {
  const FileListLoading();
}

class FileListLoaded extends FileListState {
  const FileListLoaded({
    required this.files,
    required this.path,
  });
  final List<FileItem> files;
  final String path;
}

class FileListError extends FileListState {
  const FileListError({required this.message});
  final String message;
}

/// 未连接到 NAS 的状态
class FileListNotConnected extends FileListState {
  const FileListNotConnected();
}

/// 文件列表管理
class FileListNotifier extends StateNotifier<FileListState> {
  FileListNotifier(this._ref) : super(const FileListLoading());

  final Ref _ref;

  /// 获取当前选中的适配器
  SourceConnection? _getSelectedConnection() {
    final connection = _ref.read(selectedSourceConnectionProvider);
    if (connection != null && connection.status == SourceStatus.connected) {
      return connection;
    }
    return null;
  }

  Future<void> loadDirectory(String path) async {
    state = const FileListLoading();

    // 首先尝试使用选中的源
    var connection = _ref.read(selectedSourceConnectionProvider);

    // 如果没有选中的源，自动选择第一个已连接的源
    if (connection == null || connection.status != SourceStatus.connected) {
      final connectedSources = _ref.read(connectedSourcesProvider);
      if (connectedSources.isEmpty) {
        state = const FileListNotConnected();
        return;
      }
      // 自动选择第一个已连接的源
      final (source, conn) = connectedSources.first;
      _ref.read(selectedSourceIdProvider.notifier).state = source.id;
      connection = conn;
    }

    final adapter = connection.adapter;
    if (!adapter.isConnected) {
      state = const FileListNotConnected();
      return;
    }

    try {
      final files = await adapter.fileSystem.listDirectory(path);

      // 排序
      final sortMode = _ref.read(sortModeProvider);
      final ascending = _ref.read(sortAscendingProvider);
      final sortedFiles = _sortFiles(files, sortMode, ascending);

      _ref.read(currentPathProvider.notifier).state = path;
      state = FileListLoaded(files: sortedFiles, path: path);
    } on Exception catch (e) {
      state = FileListError(message: e.toString());
    }
  }

  Future<void> refresh() async {
    final currentPath = _ref.read(currentPathProvider);
    await loadDirectory(currentPath);
  }

  Future<void> navigateUp() async {
    final currentPath = _ref.read(currentPathProvider);
    if (currentPath == '/' || currentPath.isEmpty) return;

    final parts = currentPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return;

    parts.removeLast();
    final parentPath = parts.isEmpty ? '/' : '/${parts.join('/')}';
    await loadDirectory(parentPath);
  }

  Future<void> createFolder(String name) async {
    final connection = _getSelectedConnection();
    if (connection == null) return;

    final currentPath = _ref.read(currentPathProvider);
    final newPath = currentPath == '/' ? '/$name' : '$currentPath/$name';

    await connection.adapter.fileSystem.createDirectory(newPath);
    await refresh();
  }

  Future<void> delete(String path) async {
    final connection = _getSelectedConnection();
    if (connection == null) return;

    await connection.adapter.fileSystem.delete(path);
    await refresh();
  }

  Future<void> rename(String oldPath, String newName) async {
    final connection = _getSelectedConnection();
    if (connection == null) return;

    final parts = oldPath.split('/');
    parts.removeLast();
    final newPath = '${parts.join('/')}/$newName';

    await connection.adapter.fileSystem.rename(oldPath, newPath);
    await refresh();
  }

  Future<void> uploadFile(
    String localPath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final connection = _getSelectedConnection();
    if (connection == null) return;

    final currentPath = _ref.read(currentPathProvider);
    await connection.adapter.fileSystem.upload(
      localPath,
      currentPath,
      fileName: fileName,
      onProgress: onProgress,
    );
    await refresh();
  }

  Future<void> copyTo(String sourcePath, String destPath) async {
    final connection = _getSelectedConnection();
    if (connection == null) return;

    await connection.adapter.fileSystem.copy(sourcePath, destPath);
    await refresh();
  }

  Future<void> moveTo(String sourcePath, String destPath) async {
    final connection = _getSelectedConnection();
    if (connection == null) return;

    await connection.adapter.fileSystem.move(sourcePath, destPath);
    await refresh();
  }

  List<FileItem> _sortFiles(
    List<FileItem> files,
    SortMode mode,
    bool ascending,
  ) {
    final sorted = [...files];

    // 先分离文件夹和文件
    final directories = sorted.where((f) => f.isDirectory).toList();
    final regularFiles = sorted.where((f) => !f.isDirectory).toList();

    int compare(FileItem a, FileItem b) {
      final result = switch (mode) {
        SortMode.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        SortMode.size => a.size.compareTo(b.size),
        SortMode.date => (a.modifiedTime ?? DateTime(0))
            .compareTo(b.modifiedTime ?? DateTime(0)),
        SortMode.type =>
          (a.extension ?? '').compareTo(b.extension ?? ''),
      };
      return ascending ? result : -result;
    }

    directories.sort(compare);
    regularFiles.sort(compare);

    // 文件夹始终在前
    return [...directories, ...regularFiles];
  }
}
