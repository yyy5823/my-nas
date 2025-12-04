import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart' as webdav;

/// WebDAV 文件系统实现
class WebDavFileSystem implements NasFileSystem {
  WebDavFileSystem({required webdav.Client client}) : _client = client;

  final webdav.Client _client;

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    final normalizedPath = path.isEmpty ? '/' : path;
    final files = await _client.readDir(normalizedPath);

    return files.map((f) {
      final fileName = p.basename(f.path ?? '');
      return FileItem(
        name: fileName.isEmpty ? f.name ?? '' : fileName,
        path: f.path ?? '',
        isDirectory: f.isDir ?? false,
        size: f.size ?? 0,
        modifiedTime: f.mTime,
        createdTime: f.cTime,
        extension: f.isDir == true ? null : p.extension(f.name ?? ''),
      );
    }).toList();
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    final files = await _client.readDir(p.dirname(path));
    final fileName = p.basename(path);
    final file = files.firstWhere((f) => f.name == fileName);

    return FileItem(
      name: file.name ?? '',
      path: file.path ?? '',
      isDirectory: file.isDir ?? false,
      size: file.size ?? 0,
      modifiedTime: file.mTime,
      createdTime: file.cTime,
      extension: file.isDir == true ? null : p.extension(file.name ?? ''),
    );
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async {
    final bytes = await _client.read(path);
    if (range != null) {
      final end = range.end ?? bytes.length;
      return Stream.value(bytes.sublist(range.start, end));
    }
    return Stream.value(bytes);
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async {
    // WebDAV 返回特殊的 webdav:// URI 格式
    // 应用层需要使用 getFileStream 进行实际访问
    return 'webdav://local$path';
  }

  @override
  Future<void> createDirectory(String path) async {
    await _client.mkdir(path);
  }

  @override
  Future<void> delete(String path) async {
    await _client.remove(path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    await _client.rename(oldPath, newPath, true);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    await _client.copy(sourcePath, destPath, true);
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    await _client.rename(sourcePath, destPath, true);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final name = fileName ?? p.basename(localPath);
    final destPath = remotePath.endsWith('/')
        ? '$remotePath$name'
        : '$remotePath/$name';

    await _client.writeFromFile(
      localPath,
      destPath,
      onProgress: (count, total) {
        onProgress?.call(count, total);
      },
    );
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    // WebDAV 不支持搜索，返回空列表
    // 可以通过遍历目录实现简单搜索，但效率较低
    return [];
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async {
    // WebDAV 不支持缩略图
    return null;
  }
}
