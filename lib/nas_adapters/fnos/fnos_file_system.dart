import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/fnos/api/fnos_api.dart';

/// 飞牛 NAS 文件系统实现
class FnOSFileSystem implements NasFileSystem {
  FnOSFileSystem({required this.api});

  final FnOSApi api;

  /// 缓存的共享文件夹列表
  List<FnOSFileInfo>? _cachedShares;

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    logger.d('FnOSFileSystem: listDirectory => $path');

    // 根目录显示共享文件夹列表
    if (path == '/' || path.isEmpty) {
      return listShares();
    }

    final files = await api.listDirectory(path);

    return files.map((file) => FileItem(
      name: file.name,
      path: file.path,
      isDirectory: file.isDir,
      size: file.size ?? 0,
      modifiedTime: file.modified,
      createdTime: file.created,
      mimeType: file.mimeType,
      extension: _getExtension(file.name),
    )).toList();
  }

  /// 列出共享文件夹
  Future<List<FileItem>> listShares() async {
    logger.d('FnOSFileSystem: 获取共享文件夹列表');

    if (_cachedShares != null && _cachedShares!.isNotEmpty) {
      logger.d('FnOSFileSystem: 使用缓存的共享列表');
      return _cachedShares!.map((share) => FileItem(
        name: share.name,
        path: share.path,
        isDirectory: true,
        size: 0,
      )).toList();
    }

    final shares = await api.listShares();
    _cachedShares = shares;

    logger.i('FnOSFileSystem: 获取到 ${shares.length} 个共享文件夹');

    return shares.map((share) => FileItem(
      name: share.name,
      path: share.path,
      isDirectory: true,
      size: 0,
    )).toList();
  }

  /// 清除共享文件夹缓存
  void clearSharesCache() {
    _cachedShares = null;
  }

  String? _getExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) return null;
    return fileName.substring(dotIndex + 1);
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    final parentPath = path.substring(0, path.lastIndexOf('/'));
    final fileName = path.substring(path.lastIndexOf('/') + 1);

    final files = await listDirectory(parentPath.isEmpty ? '/' : parentPath);
    final file = files.firstWhere(
      (f) => f.name == fileName,
      orElse: () => throw Exception('文件不存在: $path'),
    );
    return file;
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async =>
      api.getUrlStream(await api.getFileUrl(path));

  @override
  Future<Stream<List<int>>> getUrlStream(String url) => api.getUrlStream(url);

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async => api.getFileUrl(path);

  @override
  Future<void> createDirectory(String path) async {
    await api.createDirectory(path);
  }

  @override
  Future<void> delete(String path) async {
    await api.delete(path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    await api.rename(oldPath, newPath);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    throw UnimplementedError('飞牛 NAS 复制功能尚未实现');
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    await api.rename(sourcePath, destPath);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    throw UnimplementedError('飞牛 NAS 上传功能尚未实现');
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    throw UnimplementedError('飞牛 NAS 写入功能尚未实现');
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    throw UnimplementedError('飞牛 NAS 搜索功能尚未实现');
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async =>
      api.getThumbnailUrl(path, size: size);
}

