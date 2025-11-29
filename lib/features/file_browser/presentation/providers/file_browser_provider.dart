import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/connection/presentation/providers/connection_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 当前路径
final currentPathProvider = StateProvider<String>((ref) => '/');

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

/// 文件列表管理
class FileListNotifier extends StateNotifier<FileListState> {
  FileListNotifier(this._ref) : super(const FileListLoading());

  final Ref _ref;

  Future<void> loadDirectory(String path) async {
    state = const FileListLoading();

    final adapter = _ref.read(activeAdapterProvider);
    if (adapter == null || !adapter.isConnected) {
      state = const FileListError(message: '未连接到 NAS');
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
    final adapter = _ref.read(activeAdapterProvider);
    if (adapter == null) return;

    final currentPath = _ref.read(currentPathProvider);
    final newPath = currentPath == '/' ? '/$name' : '$currentPath/$name';

    await adapter.fileSystem.createDirectory(newPath);
    await refresh();
  }

  Future<void> delete(String path) async {
    final adapter = _ref.read(activeAdapterProvider);
    if (adapter == null) return;

    await adapter.fileSystem.delete(path);
    await refresh();
  }

  Future<void> rename(String oldPath, String newName) async {
    final adapter = _ref.read(activeAdapterProvider);
    if (adapter == null) return;

    final parts = oldPath.split('/');
    parts.removeLast();
    final newPath = '${parts.join('/')}/$newName';

    await adapter.fileSystem.rename(oldPath, newPath);
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
