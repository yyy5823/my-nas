import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/ugreen/api/ugreen_api.dart';

/// 绿联 NAS 文件系统实现
///
/// UGOS 使用共享文件夹的概念，根目录 `/` 应该显示共享文件夹列表
class UGreenFileSystem implements NasFileSystem {
  UGreenFileSystem({required this.api});

  final UGreenApi api;

  /// 缓存的共享文件夹列表
  List<UGreenFileInfo>? _cachedShares;

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    logger.d('UGreenFileSystem: listDirectory => $path');

    // 根目录显示共享文件夹列表
    if (path == '/' || path.isEmpty) {
      return listShares();
    }

    // 非根目录，使用 API 列出目录内容
    final files = await api.listDirectory(path);

    // 如果 API 返回空且路径看起来像共享文件夹，尝试用共享路径
    if (files.isEmpty && !path.contains('/') == false) {
      logger.d('UGreenFileSystem: API 返回空，检查是否为共享文件夹');
    }

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

  /// 列出共享文件夹 (根目录内容)
  ///
  /// UGOS 使用共享文件夹的概念，这里会缓存共享列表以提高性能
  Future<List<FileItem>> listShares() async {
    logger.d('UGreenFileSystem: 获取共享文件夹列表');

    // 如果有缓存，直接返回
    if (_cachedShares != null && _cachedShares!.isNotEmpty) {
      logger.d('UGreenFileSystem: 使用缓存的共享列表 (${_cachedShares!.length} 项)');
      return _cachedShares!.map((share) => FileItem(
        name: share.name,
        path: share.path,
        isDirectory: true,
        size: 0,
      )).toList();
    }

    // 获取共享列表
    final shares = await api.listShares();
    _cachedShares = shares;

    logger.i('UGreenFileSystem: 获取到 ${shares.length} 个共享文件夹');

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
    // 通过列出父目录并查找指定文件来获取文件信息
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
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async {
    // 绿联 NAS 文件流获取需要通过 HTTP 下载
    throw UnimplementedError('绿联 NAS 文件流功能尚未实现');
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async {
    return api.getFileUrl(path);
  }

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
    throw UnimplementedError('绿联 NAS 复制功能尚未实现');
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
    throw UnimplementedError('绿联 NAS 上传功能尚未实现');
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    throw UnimplementedError('绿联 NAS 搜索功能尚未实现');
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async {
    // 绿联 NAS 尝试获取缩略图
    return api.getThumbnailUrl(path, size: size);
  }
}
