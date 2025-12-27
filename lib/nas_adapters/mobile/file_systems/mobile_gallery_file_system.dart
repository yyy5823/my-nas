import 'dart:io';
import 'dart:typed_data';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart' as fs;
import 'package:photo_manager/photo_manager.dart' as pm;

/// URL 编码辅助方法（仅编码斜杠和百分号）
String _encodeId(String id) => id.replaceAll('%', '%25').replaceAll('/', '%2F');

/// URL 解码辅助方法
String _decodeId(String encoded) =>
    encoded.replaceAll('%2F', '/').replaceAll('%25', '%');

/// 移动端相册文件系统
///
/// 将系统相册映射为虚拟文件系统结构：
/// - /albums/           - 按相册分组
/// - /albums/{name}/    - 具体相册内容
/// - /all/              - 所有照片和视频
///
/// 路径格式：
/// - gallery://albums/{albumId}/{assetId}
/// - gallery://all/{assetId}
class MobileGalleryFileSystem implements NasFileSystem {
  MobileGalleryFileSystem();

  List<pm.AssetPathEntity>? _cachedAlbums;
  final Map<String, pm.AssetEntity> _assetCache = {};

  /// 请求相册访问权限
  Future<bool> requestPermission() async {
    final permission = await pm.PhotoManager.requestPermissionExtend();
    if (permission.isAuth) {
      return true;
    }
    if (permission == pm.PermissionState.limited) {
      // iOS 14+ 限制访问
      return true;
    }
    logger.w('MobileGalleryFileSystem: 权限被拒绝 - $permission');
    return false;
  }

  /// 获取所有相册
  Future<List<pm.AssetPathEntity>> _getAlbums() async {
    if (_cachedAlbums != null) return _cachedAlbums!;

    _cachedAlbums = await pm.PhotoManager.getAssetPathList(
      type: pm.RequestType.common, // 照片和视频
      hasAll: true,
      onlyAll: false,
    );

    return _cachedAlbums!;
  }

  /// 刷新相册缓存
  Future<void> refreshCache() async {
    _cachedAlbums = null;
    _assetCache.clear();
  }

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    logger.d('MobileGalleryFileSystem: listDirectory - $path');

    // 根目录
    if (path == '/' || path.isEmpty) {
      return _listRoot();
    }

    // 相册列表
    if (path == '/albums' || path == '/albums/') {
      return _listAlbums();
    }

    // 所有照片
    if (path == '/all' || path == '/all/') {
      return _listAllAssets();
    }

    // 具体相册内容
    // 路径格式: /albums/{encodedAlbumId} 或 /albums/{encodedAlbumId}/{encodedAssetId}
    if (path.startsWith('/albums/')) {
      final remaining = path.replaceFirst('/albums/', '');
      final segments = remaining.split('/');
      // 第一段是编码后的 album ID，需要解码
      final albumId = _decodeId(segments.first);

      // 如果路径包含多个段（如 /albums/{albumId}/{assetId}），
      // 说明是访问具体资源，不是目录，返回空列表
      if (segments.length > 1 && segments[1].isNotEmpty) {
        logger.d('MobileGalleryFileSystem: 跳过资源路径 - $path');
        return [];
      }

      return _listAlbumAssets(albumId);
    }

    return [];
  }

  /// 列出根目录
  Future<List<FileItem>> _listRoot() async => [
    const FileItem(
      name: 'albums',
      path: '/albums',
      isDirectory: true,
      size: 0,
    ),
    const FileItem(
      name: 'all',
      path: '/all',
      isDirectory: true,
      size: 0,
    ),
  ];

  /// 列出所有相册
  Future<List<FileItem>> _listAlbums() async {
    final albums = await _getAlbums();
    final items = <FileItem>[];

    for (final album in albums) {
      final count = await album.assetCountAsync;
      // 对 album ID 进行编码，避免包含斜杠导致路径解析错误
      final encodedId = _encodeId(album.id);
      items.add(FileItem(
        name: album.name,
        path: '/albums/$encodedId',
        isDirectory: true,
        size: count,
      ));
    }

    return items;
  }

  /// 列出所有资源
  Future<List<FileItem>> _listAllAssets() async {
    final albums = await _getAlbums();

    // 找到 "所有照片" 相册
    final allAlbum = albums.firstWhere(
      (a) => a.isAll,
      orElse: () => albums.first,
    );

    return _listAlbumAssets(allAlbum.id);
  }

  /// 列出相册内资源
  Future<List<FileItem>> _listAlbumAssets(String albumId) async {
    final albums = await _getAlbums();
    final album = albums.firstWhere(
      (a) => a.id == albumId,
      orElse: () => throw Exception('Album not found: $albumId'),
    );

    final count = await album.assetCountAsync;
    final assets = await album.getAssetListRange(start: 0, end: count);

    // 对 album ID 进行编码
    final encodedAlbumId = _encodeId(albumId);

    final items = <FileItem>[];
    for (final asset in assets) {
      _assetCache[asset.id] = asset;

      final file = await asset.file;

      // 提取扩展名：优先从文件名获取，否则从 mimeType 推断
      String? extension;
      final title = asset.title;
      if (title != null && title.contains('.')) {
        extension = title.split('.').last.toLowerCase();
      } else if (asset.mimeType != null) {
        // 从 mimeType 推断扩展名，如 image/heic → heic
        final parts = asset.mimeType!.split('/');
        if (parts.length == 2) {
          extension = parts[1].toLowerCase();
        }
      }

      // 检测是否为 Live Photo（iOS 实况照片）
      // Live Photo 的 subtype 包含 PHAssetMediaSubtypePhotoLive (1 << 3 = 8)
      final isLivePhoto = Platform.isIOS && (asset.subtype & 8) != 0;

      // 获取 Live Photo 的视频路径
      String? livePhotoVideoPath;
      if (isLivePhoto) {
        final videoFile = await asset.fileWithSubtype;
        livePhotoVideoPath = videoFile?.path;
      }

      // 对 asset ID 进行编码
      final encodedAssetId = _encodeId(asset.id);

      items.add(FileItem(
        name: asset.title ?? asset.id,
        path: '/albums/$encodedAlbumId/$encodedAssetId',
        isDirectory: false,
        size: file?.lengthSync() ?? 0,
        modifiedTime: asset.modifiedDateTime,
        createdTime: asset.createDateTime,
        extension: extension,
        mimeType: asset.mimeType,
        isLivePhoto: isLivePhoto,
        livePhotoVideoPath: livePhotoVideoPath,
      ));
    }

    return items;
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    // 解码 asset ID（路径最后一段是编码后的 ID）
    final assetId = _decodeId(path.split('/').last);
    final asset = _assetCache[assetId];

    if (asset == null) {
      throw Exception('Asset not found: $assetId');
    }

    final file = await asset.file;

    // 提取扩展名：优先从文件名获取，否则从 mimeType 推断
    String? extension;
    final title = asset.title;
    if (title != null && title.contains('.')) {
      extension = title.split('.').last.toLowerCase();
    } else if (asset.mimeType != null) {
      final parts = asset.mimeType!.split('/');
      if (parts.length == 2) {
        extension = parts[1].toLowerCase();
      }
    }

    // 检测是否为 Live Photo
    final isLivePhoto = Platform.isIOS && (asset.subtype & 8) != 0;

    // 获取 Live Photo 的视频路径
    String? livePhotoVideoPath;
    if (isLivePhoto) {
      final videoFile = await asset.fileWithSubtype;
      livePhotoVideoPath = videoFile?.path;
    }

    return FileItem(
      name: asset.title ?? asset.id,
      path: path,
      isDirectory: false,
      size: file?.lengthSync() ?? 0,
      modifiedTime: asset.modifiedDateTime,
      createdTime: asset.createDateTime,
      extension: extension,
      mimeType: asset.mimeType,
      isLivePhoto: isLivePhoto,
      livePhotoVideoPath: livePhotoVideoPath,
    );
  }

  /// 获取 Live Photo 的视频文件
  ///
  /// 返回 Live Photo 关联的视频文件路径，用于播放实况效果
  Future<File?> getLivePhotoVideoFile(String assetId) async {
    final asset = _assetCache[assetId];
    if (asset == null) return null;

    // 检测是否为 Live Photo
    if (!Platform.isIOS || (asset.subtype & 8) == 0) return null;

    return asset.fileWithSubtype;
  }

  /// 获取 Live Photo 的视频 URL（用于播放）
  Future<String?> getLivePhotoVideoUrl(String assetId) async {
    final asset = _assetCache[assetId];
    if (asset == null) return null;

    // 检测是否为 Live Photo
    if (!Platform.isIOS || (asset.subtype & 8) == 0) return null;

    return asset.getMediaUrl();
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async {
    // 解码 asset ID
    final assetId = _decodeId(path.split('/').last);
    final asset = _assetCache[assetId];

    if (asset == null) {
      throw Exception('Asset not found: $assetId');
    }

    final file = await asset.file;
    if (file == null) {
      throw Exception('Cannot get file for asset: $assetId');
    }

    // 处理范围请求
    if (range != null) {
      return _getFileStreamWithRange(file, range);
    }

    return file.openRead();
  }

  Future<Stream<List<int>>> _getFileStreamWithRange(File file, FileRange range) async {
    final length = await file.length();
    final end = range.end ?? length - 1;

    return file.openRead(range.start, end + 1);
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async {
    // 解码 asset ID
    final assetId = _decodeId(path.split('/').last);
    final asset = _assetCache[assetId];

    if (asset == null) {
      throw Exception('Asset not found: $assetId');
    }

    final file = await asset.file;
    if (file == null) {
      throw Exception('Cannot get file for asset: $assetId');
    }

    // 返回本地文件 URL
    return file.uri.toString();
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async {
    // 解码 asset ID
    final assetId = _decodeId(path.split('/').last);
    final asset = _assetCache[assetId];

    if (asset == null) return null;

    // photo_manager 不支持缩略图 URL，返回 null
    // 使用者需要通过 asset.thumbnailData 获取缩略图
    return null;
  }

  /// 获取资源的缩略图数据
  Future<Uint8List?> getThumbnailData(String path, {fs.ThumbnailSize? size}) async {
    // 解码 asset ID
    final assetId = _decodeId(path.split('/').last);
    final asset = _assetCache[assetId];

    if (asset == null) return null;

    final thumbnailSize = size ?? fs.ThumbnailSize.medium;
    final pixelSize = thumbnailSize.pixels;
    return asset.thumbnailDataWithSize(
      pm.ThumbnailSize(pixelSize, pixelSize),
    );
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) {
    throw UnimplementedError('相册不支持 URL 流访问');
  }

  /// 获取资源实体
  Future<pm.AssetEntity?> getAsset(String assetId) async {
    if (_assetCache.containsKey(assetId)) {
      return _assetCache[assetId];
    }

    // 尝试从系统获取
    final asset = await pm.AssetEntity.fromId(assetId);
    if (asset != null) {
      _assetCache[assetId] = asset;
    }
    return asset;
  }

  // ==================== 不支持的写操作 ====================

  @override
  Future<void> createDirectory(String path) async {
    throw UnsupportedError('相册不支持创建目录');
  }

  @override
  Future<void> delete(String path) async {
    throw UnsupportedError('相册不支持删除操作（请使用系统相册App）');
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    throw UnsupportedError('相册不支持重命名');
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    throw UnsupportedError('相册不支持复制');
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    throw UnsupportedError('相册不支持移动');
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    throw UnsupportedError('相册不支持上传（请使用系统相册App）');
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    throw UnsupportedError('相册不支持写入');
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    // 简单实现：遍历所有资源搜索
    final albums = await _getAlbums();
    final allAlbum = albums.firstWhere((a) => a.isAll, orElse: () => albums.first);
    final count = await allAlbum.assetCountAsync;
    final assets = await allAlbum.getAssetListRange(start: 0, end: count);

    final results = <FileItem>[];
    final queryLower = query.toLowerCase();

    for (final asset in assets) {
      final assetTitle = asset.title;
      final titleLower = assetTitle?.toLowerCase() ?? '';
      if (titleLower.contains(queryLower)) {
        _assetCache[asset.id] = asset;
        final file = await asset.file;

        // 提取扩展名
        String? extension;
        if (assetTitle != null && assetTitle.contains('.')) {
          extension = assetTitle.split('.').last.toLowerCase();
        } else if (asset.mimeType != null) {
          final parts = asset.mimeType!.split('/');
          if (parts.length == 2) {
            extension = parts[1].toLowerCase();
          }
        }

        // 检测是否为 Live Photo
        final isLivePhoto = Platform.isIOS && (asset.subtype & 8) != 0;

        // 获取 Live Photo 的视频路径
        String? livePhotoVideoPath;
        if (isLivePhoto) {
          final videoFile = await asset.fileWithSubtype;
          livePhotoVideoPath = videoFile?.path;
        }

        // 对 asset ID 进行编码
        final encodedAssetId = _encodeId(asset.id);
        results.add(FileItem(
          name: assetTitle ?? asset.id,
          path: '/all/$encodedAssetId',
          isDirectory: false,
          size: file?.lengthSync() ?? 0,
          modifiedTime: asset.modifiedDateTime,
          extension: extension,
          mimeType: asset.mimeType,
          isLivePhoto: isLivePhoto,
          livePhotoVideoPath: livePhotoVideoPath,
        ));
      }
    }

    return results;
  }
}
