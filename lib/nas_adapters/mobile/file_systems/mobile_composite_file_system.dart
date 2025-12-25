import 'dart:io';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/mobile/file_systems/mobile_files_file_system.dart';
import 'package:my_nas/nas_adapters/mobile/file_systems/mobile_gallery_file_system.dart';
import 'package:my_nas/nas_adapters/mobile/file_systems/mobile_music_file_system.dart';

/// 移动端复合文件系统
///
/// 将多个移动端文件系统统一为一个接口，根据路径前缀路由到不同的底层文件系统：
/// - /gallery/  → MobileGalleryFileSystem（系统相册：照片、视频）
/// - /music/    → MobileMusicFileSystem（系统音乐库）
/// - /files/    → MobileFilesFileSystem（文件App：Documents、Downloads）
///
/// 这样 LocalAdapter 只需要暴露一个 fileSystem，但实际上支持访问多种本机内容。
class MobileCompositeFileSystem implements NasFileSystem {
  MobileCompositeFileSystem();

  late final MobileGalleryFileSystem _galleryFileSystem;
  late final MobileMusicFileSystem _musicFileSystem;
  late final MobileFilesFileSystem _filesFileSystem;

  /// 请求所有必要的权限
  Future<bool> requestPermissions() async {
    _galleryFileSystem = MobileGalleryFileSystem();
    _musicFileSystem = MobileMusicFileSystem();
    _filesFileSystem = MobileFilesFileSystem();

    // 请求相册权限
    final galleryPermission = await _galleryFileSystem.requestPermission();
    if (!galleryPermission) {
      logger.w('MobileCompositeFileSystem: 相册权限被拒绝');
      // 继续，不阻塞其他功能
    }

    // 请求音乐库权限
    final musicPermission = await _musicFileSystem.requestPermission();
    if (!musicPermission) {
      logger.w('MobileCompositeFileSystem: 音乐库权限被拒绝');
      // 继续，不阻塞其他功能
    }

    // 初始化文件系统
    await _filesFileSystem.initialize();

    logger.i('MobileCompositeFileSystem: 初始化完成');

    // 只要有一个权限通过就返回 true
    return galleryPermission || musicPermission || true;
  }

  /// 获取相册文件系统（用于直接访问）
  MobileGalleryFileSystem get galleryFileSystem => _galleryFileSystem;

  /// 获取音乐文件系统（用于直接访问）
  MobileMusicFileSystem get musicFileSystem => _musicFileSystem;

  /// 获取文件系统（用于直接访问）
  MobileFilesFileSystem get filesFileSystem => _filesFileSystem;

  /// 根据路径确定使用哪个文件系统
  NasFileSystem _getFileSystem(String path) {
    if (path.startsWith('/gallery') || path.startsWith('/photos') || path.startsWith('/videos')) {
      return _galleryFileSystem;
    }
    if (path.startsWith('/music')) {
      return _musicFileSystem;
    }
    if (path.startsWith('/files') || path.startsWith('/documents') || path.startsWith('/downloads')) {
      return _filesFileSystem;
    }
    // 默认返回相册（保持向后兼容）
    return _galleryFileSystem;
  }

  /// 转换路径：移除顶级前缀
  String _transformPath(String path) {
    // /gallery/xxx -> /xxx
    // /music/xxx -> /xxx
    // /files/xxx -> /xxx
    if (path.startsWith('/gallery')) {
      return path.replaceFirst('/gallery', '');
    }
    if (path.startsWith('/photos')) {
      return path.replaceFirst('/photos', '');
    }
    if (path.startsWith('/videos')) {
      return path.replaceFirst('/videos', '');
    }
    if (path.startsWith('/music')) {
      return path.replaceFirst('/music', '');
    }
    if (path.startsWith('/files')) {
      return path.replaceFirst('/files', '');
    }
    // documents 和 downloads 直接传递给 filesFileSystem
    return path;
  }

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    logger.d('MobileCompositeFileSystem: listDirectory - $path');

    // 根目录：显示所有可用的文件系统
    if (path == '/' || path.isEmpty) {
      return _listRoot();
    }

    final fs = _getFileSystem(path);
    final transformedPath = _transformPath(path);
    final items = await fs.listDirectory(transformedPath.isEmpty ? '/' : transformedPath);

    // 为返回的项目添加前缀
    final prefix = _getPrefix(path);
    return items.map((item) => FileItem(
      name: item.name,
      path: '$prefix${item.path}',
      isDirectory: item.isDirectory,
      size: item.size,
      modifiedTime: item.modifiedTime,
      createdTime: item.createdTime,
      extension: item.extension,
      mimeType: item.mimeType,
      isHidden: item.isHidden,
      thumbnailUrl: item.thumbnailUrl,
    )).toList();
  }

  /// 获取路径前缀
  String _getPrefix(String path) {
    if (path.startsWith('/gallery')) return '/gallery';
    if (path.startsWith('/photos')) return '/gallery'; // 统一为 gallery
    if (path.startsWith('/videos')) return '/gallery';
    if (path.startsWith('/music')) return '/music';
    if (path.startsWith('/files')) return '/files';
    if (path.startsWith('/documents')) return '/files';
    if (path.startsWith('/downloads')) return '/files';
    return '';
  }

  /// 列出根目录
  Future<List<FileItem>> _listRoot() async {
    final items = <FileItem>[]

    // 相册（照片和视频）
    ..add(const FileItem(
      name: '相册',
      path: '/gallery',
      isDirectory: true,
      size: 0,
    ));

    // 音乐库
    if (Platform.isAndroid) {
      // iOS 音乐库访问受限，只在 Android 上显示
      items.add(const FileItem(
        name: '音乐',
        path: '/music',
        isDirectory: true,
        size: 0,
      ));
    }

    // 文件（Documents 和 Downloads）
    items.add(const FileItem(
      name: '文件',
      path: '/files',
      isDirectory: true,
      size: 0,
    ));

    return items;
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    final fs = _getFileSystem(path);
    final transformedPath = _transformPath(path);
    final item = await fs.getFileInfo(transformedPath);

    final prefix = _getPrefix(path);
    return FileItem(
      name: item.name,
      path: '$prefix${item.path}',
      isDirectory: item.isDirectory,
      size: item.size,
      modifiedTime: item.modifiedTime,
      createdTime: item.createdTime,
      extension: item.extension,
      mimeType: item.mimeType,
      isHidden: item.isHidden,
      thumbnailUrl: item.thumbnailUrl,
    );
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async {
    final fs = _getFileSystem(path);
    final transformedPath = _transformPath(path);
    return fs.getFileStream(transformedPath, range: range);
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async {
    final fs = _getFileSystem(path);
    final transformedPath = _transformPath(path);
    return fs.getFileUrl(transformedPath, expiry: expiry);
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async {
    final fs = _getFileSystem(path);
    final transformedPath = _transformPath(path);
    return fs.getThumbnailUrl(transformedPath, size: size);
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) async {
    // 根据 URL 判断使用哪个文件系统
    if (url.startsWith('file://')) {
      return _filesFileSystem.getUrlStream(url);
    }
    throw UnimplementedError('不支持的 URL: $url');
  }

  @override
  Future<void> createDirectory(String path) async {
    final fs = _getFileSystem(path);
    final transformedPath = _transformPath(path);
    await fs.createDirectory(transformedPath);
  }

  @override
  Future<void> delete(String path) async {
    final fs = _getFileSystem(path);
    final transformedPath = _transformPath(path);
    await fs.delete(transformedPath);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    final fs = _getFileSystem(oldPath);
    final transformedOldPath = _transformPath(oldPath);
    final transformedNewPath = _transformPath(newPath);
    await fs.rename(transformedOldPath, transformedNewPath);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    final fs = _getFileSystem(sourcePath);
    final transformedSourcePath = _transformPath(sourcePath);
    final transformedDestPath = _transformPath(destPath);
    await fs.copy(transformedSourcePath, transformedDestPath);
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    final fs = _getFileSystem(sourcePath);
    final transformedSourcePath = _transformPath(sourcePath);
    final transformedDestPath = _transformPath(destPath);
    await fs.move(transformedSourcePath, transformedDestPath);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final fs = _getFileSystem(remotePath);
    final transformedPath = _transformPath(remotePath);
    await fs.upload(localPath, transformedPath, fileName: fileName, onProgress: onProgress);
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    final fs = _getFileSystem(remotePath);
    final transformedPath = _transformPath(remotePath);
    await fs.writeFile(transformedPath, data);
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    // 如果指定了路径，在对应文件系统中搜索
    if (path != null && path != '/') {
      final fs = _getFileSystem(path);
      final transformedPath = _transformPath(path);
      final items = await fs.search(query, path: transformedPath);
      final prefix = _getPrefix(path);
      return items.map((item) => FileItem(
        name: item.name,
        path: '$prefix${item.path}',
        isDirectory: item.isDirectory,
        size: item.size,
        modifiedTime: item.modifiedTime,
        createdTime: item.createdTime,
        extension: item.extension,
        mimeType: item.mimeType,
        isHidden: item.isHidden,
        thumbnailUrl: item.thumbnailUrl,
      )).toList();
    }

    // 否则在所有文件系统中搜索
    final results = <FileItem>[];

    // 搜索相册
    final galleryItems = await _galleryFileSystem.search(query);
    results.addAll(galleryItems.map((item) => FileItem(
      name: item.name,
      path: '/gallery${item.path}',
      isDirectory: item.isDirectory,
      size: item.size,
      modifiedTime: item.modifiedTime,
      createdTime: item.createdTime,
      extension: item.extension,
    )));

    // 搜索音乐
    if (Platform.isAndroid) {
      final musicItems = await _musicFileSystem.search(query);
      results.addAll(musicItems.map((item) => FileItem(
        name: item.name,
        path: '/music${item.path}',
        isDirectory: item.isDirectory,
        size: item.size,
        modifiedTime: item.modifiedTime,
        createdTime: item.createdTime,
        extension: item.extension,
      )));
    }

    // 搜索文件
    final filesItems = await _filesFileSystem.search(query);
    results.addAll(filesItems.map((item) => FileItem(
      name: item.name,
      path: '/files${item.path}',
      isDirectory: item.isDirectory,
      size: item.size,
      modifiedTime: item.modifiedTime,
      createdTime: item.createdTime,
      extension: item.extension,
    )));

    return results;
  }
}
