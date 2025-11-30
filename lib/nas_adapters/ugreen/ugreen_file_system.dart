import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/ugreen/api/ugreen_api.dart';

/// 绿联 NAS 文件系统实现
class UGreenFileSystem implements NasFileSystem {
  UGreenFileSystem({required this.api});

  final UGreenApi api;

  @override
  Future<List<FileItem>> listDirectory(String path) async {
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
    final shares = await api.listShares();

    return shares.map((share) => FileItem(
      name: share.name,
      path: share.path,
      isDirectory: true,
      size: 0,
    )).toList();
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
    // 绿联 NAS 可能不支持缩略图，返回 null
    return null;
  }
}
