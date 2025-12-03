import 'dart:io';

import 'package:my_nas/core/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_snapshot_generator/video_snapshot_generator.dart';

/// 视频缩略图服务
///
/// 用于在没有 TMDB/NFO 元数据时，通过提取视频帧生成缩略图
/// 类似于 Emby/Jellyfin 的 Screen Grabber 功能
class VideoThumbnailService {
  VideoThumbnailService._();

  static VideoThumbnailService? _instance;
  static VideoThumbnailService get instance =>
      _instance ??= VideoThumbnailService._();

  Directory? _cacheDir;
  final _generatingTasks = <String, Future<String?>>{};

  /// 初始化服务
  Future<void> init() async {
    if (_cacheDir != null) return;
    try {
      final appDir = await getApplicationSupportDirectory();
      _cacheDir = Directory(p.join(appDir.path, 'video_thumbnails'));
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      logger.i('VideoThumbnailService: 初始化完成，缓存目录: ${_cacheDir!.path}');
    } catch (e) {
      logger.e('VideoThumbnailService: 初始化失败', e);
    }
  }

  /// 获取缓存的缩略图路径
  String? getCachedThumbnailPath(String videoPath) {
    if (_cacheDir == null) return null;
    final cacheKey = _generateCacheKey(videoPath);
    final thumbnailPath = p.join(_cacheDir!.path, '$cacheKey.jpg');
    final file = File(thumbnailPath);
    if (file.existsSync()) {
      return thumbnailPath;
    }
    return null;
  }

  /// 获取缓存的缩略图 URL (file:// 格式)
  String? getCachedThumbnailUrl(String videoPath) {
    final path = getCachedThumbnailPath(videoPath);
    if (path != null) {
      return Uri.file(path).toString();
    }
    return null;
  }

  /// 从视频 URL 生成缩略图
  ///
  /// [videoUrl] 视频的 HTTP/HTTPS URL
  /// [videoPath] 视频在 NAS 上的路径（用于生成缓存键）
  /// [timeMs] 截取位置（毫秒，默认 5000 即 5 秒位置）
  Future<String?> generateThumbnail({
    required String videoUrl,
    required String videoPath,
    int timeMs = 5000,
  }) async {
    if (_cacheDir == null) {
      await init();
      if (_cacheDir == null) return null;
    }

    // 检查缓存
    final cachedPath = getCachedThumbnailPath(videoPath);
    if (cachedPath != null) {
      logger.d('VideoThumbnailService: 使用缓存缩略图 $cachedPath');
      return cachedPath;
    }

    // 防止重复生成
    final cacheKey = _generateCacheKey(videoPath);
    if (_generatingTasks.containsKey(cacheKey)) {
      logger.d('VideoThumbnailService: 等待正在生成的任务 $cacheKey');
      return _generatingTasks[cacheKey];
    }

    // 开始生成任务
    final task = _doGenerateThumbnail(
      videoUrl: videoUrl,
      cacheKey: cacheKey,
      timeMs: timeMs,
    );
    _generatingTasks[cacheKey] = task;

    try {
      final result = await task;
      return result;
    } finally {
      _generatingTasks.remove(cacheKey);
    }
  }

  Future<String?> _doGenerateThumbnail({
    required String videoUrl,
    required String cacheKey,
    required int timeMs,
  }) async {
    try {
      logger.d('VideoThumbnailService: 开始生成缩略图 $videoUrl');

      // 使用 video_snapshot_generator 提取帧
      final result = await VideoSnapshotGenerator.generateThumbnail(
        videoPath: videoUrl,
        options: ThumbnailOptions(
          videoPath: videoUrl,
          width: 480,
          height: 270,
          quality: 80,
          timeMs: timeMs,
          format: ThumbnailFormat.jpeg,
        ),
      );

      if (!result.success || result.path.isEmpty) {
        logger.w('VideoThumbnailService: 提取帧失败: ${result.errorMessage}');
        return null;
      }

      // 复制到我们的缓存目录
      final thumbnailPath = p.join(_cacheDir!.path, '$cacheKey.jpg');
      final sourceFile = File(result.path);
      if (await sourceFile.exists()) {
        await sourceFile.copy(thumbnailPath);
        // 可选：删除原始文件以节省空间
        // await sourceFile.delete();
      } else {
        logger.w('VideoThumbnailService: 生成的缩略图文件不存在 ${result.path}');
        return null;
      }

      logger.i('VideoThumbnailService: 缩略图生成成功 $thumbnailPath');
      return thumbnailPath;
    } catch (e, stackTrace) {
      logger.e('VideoThumbnailService: 生成缩略图失败', e, stackTrace);
      return null;
    }
  }

  /// 从本地视频文件生成缩略图
  Future<String?> generateFromLocalFile({
    required String localPath,
    int timeMs = 5000,
  }) async {
    if (_cacheDir == null) {
      await init();
      if (_cacheDir == null) return null;
    }

    // 检查缓存
    final cachedPath = getCachedThumbnailPath(localPath);
    if (cachedPath != null) {
      return cachedPath;
    }

    try {
      final cacheKey = _generateCacheKey(localPath);

      final result = await VideoSnapshotGenerator.generateThumbnail(
        videoPath: localPath,
        options: ThumbnailOptions(
          videoPath: localPath,
          width: 480,
          height: 270,
          quality: 80,
          timeMs: timeMs,
          format: ThumbnailFormat.jpeg,
        ),
      );

      if (!result.success || result.path.isEmpty) {
        logger.w('VideoThumbnailService: 从本地文件提取帧失败: ${result.errorMessage}');
        return null;
      }

      // 复制到我们的缓存目录
      final thumbnailPath = p.join(_cacheDir!.path, '$cacheKey.jpg');
      final sourceFile = File(result.path);
      if (await sourceFile.exists()) {
        await sourceFile.copy(thumbnailPath);
      } else {
        return null;
      }

      return thumbnailPath;
    } catch (e) {
      logger.e('VideoThumbnailService: 从本地文件生成缩略图失败', e);
      return null;
    }
  }

  /// 删除指定视频的缓存缩略图
  Future<void> deleteCached(String videoPath) async {
    final path = getCachedThumbnailPath(videoPath);
    if (path != null) {
      try {
        await File(path).delete();
      } catch (e) {
        logger.w('VideoThumbnailService: 删除缓存失败', e);
      }
    }
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    if (_cacheDir == null) return;
    try {
      if (await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
      logger.i('VideoThumbnailService: 缓存已清除');
    } catch (e) {
      logger.e('VideoThumbnailService: 清除缓存失败', e);
    }
  }

  /// 获取缓存大小（字节）
  Future<int> getCacheSize() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;
    int totalSize = 0;
    try {
      await for (final entity in _cacheDir!.list()) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    } catch (e) {
      logger.w('VideoThumbnailService: 计算缓存大小失败', e);
    }
    return totalSize;
  }

  /// 生成缓存键
  String _generateCacheKey(String videoPath) =>
      videoPath.hashCode.toRadixString(16);
}
