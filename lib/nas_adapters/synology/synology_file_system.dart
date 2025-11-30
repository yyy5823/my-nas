import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/synology/api/synology_api.dart';
import 'package:path/path.dart' as p;

/// 群晖文件系统实现
class SynologyFileSystem implements NasFileSystem {
  SynologyFileSystem({required SynologyApi api}) : _api = api;

  final SynologyApi _api;

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    // 根目录返回共享文件夹列表
    if (path == '/' || path.isEmpty) {
      final shares = await _api.listShareFolders();
      return shares
          .map(
            (s) => FileItem(
              name: s.name,
              path: s.path,
              isDirectory: true,
              size: 0,
            ),
          )
          .toList();
    }

    final files = await _api.listFiles(folderPath: path);
    return files
        .map(
          (f) => FileItem(
            name: f.name,
            path: f.path,
            isDirectory: f.isDir,
            size: f.size,
            modifiedTime: f.modifyTime,
            createdTime: f.createTime,
            extension: f.isDir ? null : p.extension(f.name),
          ),
        )
        .toList();
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    final file = await _api.getFileInfo(path);
    return FileItem(
      name: file.name,
      path: file.path,
      isDirectory: file.isDir,
      size: file.size,
      modifiedTime: file.modifyTime,
      createdTime: file.createTime,
      extension: file.isDir ? null : p.extension(file.name),
    );
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) {
    // Synology 使用 URL 下载，这里返回空流
    // 实际使用时应该用 getFileUrl 获取下载链接
    throw UnimplementedError('请使用 getFileUrl 获取下载链接');
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async =>
      _api.getDownloadUrl(path);

  @override
  Future<void> createDirectory(String path) async {
    final dirName = p.basename(path);
    final parentPath = p.dirname(path);
    await _api.createFolder(folderPath: parentPath, name: dirName);
  }

  @override
  Future<void> delete(String path) async {
    await _api.deleteFiles([path]);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    final newName = p.basename(newPath);
    await _api.rename(path: oldPath, name: newName);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    final taskId = await _api.copyFiles(
      paths: [sourcePath],
      destFolderPath: destPath,
    );
    await _api.waitForCopyMove(taskId);
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    final taskId = await _api.moveFiles(
      paths: [sourcePath],
      destFolderPath: destPath,
    );
    await _api.waitForCopyMove(taskId);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    await _api.uploadFile(
      localPath: localPath,
      destFolderPath: remotePath,
      fileName: fileName,
      onProgress: onProgress,
    );
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    final folderPath = path ?? '/';
    final taskId = await _api.startSearch(
      folderPath: folderPath,
      pattern: query,
    );

    // 轮询等待搜索完成
    SearchResult result;
    do {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      result = await _api.getSearchResult(taskId);
    } while (!result.finished);

    return result.files
        .map(
          (f) => FileItem(
            name: f.name,
            path: f.path,
            isDirectory: f.isDir,
            size: f.size,
            modifiedTime: f.modifyTime,
            createdTime: f.createTime,
            extension: f.isDir ? null : p.extension(f.name),
          ),
        )
        .toList();
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async {
    final sizeStr = switch (size) {
      ThumbnailSize.small => 'small',
      ThumbnailSize.medium => 'medium',
      ThumbnailSize.large => 'large',
      ThumbnailSize.xlarge => 'xl',
      null => 'small',
    };
    return _api.getThumbnailUrl(path, size: sizeStr);
  }
}
