import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/transfer/data/services/transfer_database_service.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 媒体缓存服务
/// 管理照片、音乐、图书、视频的缓存文件
class MediaCacheService {
  factory MediaCacheService() => _instance ??= MediaCacheService._();
  MediaCacheService._();

  static MediaCacheService? _instance;

  final _dbService = TransferDatabaseService();
  bool _initialized = false;

  String? _baseCacheDir;
  final Map<MediaType, String> _cacheDirs = {};

  /// 各类型缓存配额（字节）
  static const Map<MediaType, int> cacheQuotas = {
    MediaType.photo: 1024 * 1024 * 1024, // 1GB
    MediaType.music: 2 * 1024 * 1024 * 1024, // 2GB
    MediaType.video: 5 * 1024 * 1024 * 1024, // 5GB
    MediaType.book: 512 * 1024 * 1024, // 512MB
  };

  /// 初始化缓存服务
  Future<void> init() async {
    if (_initialized) return;

    try {
      await _dbService.init();

      final documentsDir = await getApplicationDocumentsDirectory();
      _baseCacheDir = p.join(documentsDir.path, 'media_cache');

      // 创建各类型缓存目录
      for (final type in MediaType.values) {
        final dirPath = p.join(_baseCacheDir!, type.name);
        _cacheDirs[type] = dirPath;

        final dir = Directory(dirPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      }

      _initialized = true;
      logger.i('MediaCacheService: 缓存服务初始化完成');
    } catch (e, st) {
      AppError.handle(e, st, 'MediaCacheService.init');
      rethrow;
    }
  }

  /// 生成缓存文件的唯一键
  String _generateCacheKey(String sourceId, String sourcePath) {
    final key = '${sourceId}_$sourcePath';
    return md5.convert(utf8.encode(key)).toString();
  }

  /// 获取缓存文件路径（不管是否存在）
  Future<String> getCacheFilePath(
    String sourceId,
    String sourcePath,
    MediaType mediaType,
  ) async {
    if (!_initialized) await init();

    final hash = _generateCacheKey(sourceId, sourcePath);
    final extension = p.extension(sourcePath).toLowerCase();
    final filename = '$hash$extension';
    return p.join(_cacheDirs[mediaType]!, filename);
  }

  /// 记录缓存
  Future<void> recordCache({
    required String sourceId,
    required String sourcePath,
    required MediaType mediaType,
    required String fileName,
    required int fileSize,
    required String cachePath,
    String? title,
    String? artist,
    String? album,
    String? thumbnailPath,
  }) async {
    if (!_initialized) await init();

    try {
      final item = CachedMediaItem(
        sourceId: sourceId,
        sourcePath: sourcePath,
        mediaType: mediaType,
        fileName: fileName,
        fileSize: fileSize,
        cachePath: cachePath,
        cachedAt: DateTime.now(),
        title: title,
        artist: artist,
        album: album,
        thumbnailPath: thumbnailPath,
      );

      await _dbService.recordCache(item);
      logger.d('MediaCacheService: 已记录缓存 $fileName');

      // 检查配额
      await _ensureQuota(mediaType);
    } catch (e, st) {
      AppError.handle(e, st, 'MediaCacheService.recordCache');
    }
  }

  /// 检查文件是否已缓存
  Future<bool> isCached(String sourceId, String sourcePath) async {
    if (!_initialized) await init();

    try {
      // 先检查数据库
      if (!await _dbService.isCached(sourceId, sourcePath)) {
        return false;
      }

      // 再检查文件是否存在
      final cachePath = await _dbService.getCachePath(sourceId, sourcePath);
      if (cachePath == null) return false;

      final file = File(cachePath);
      if (!await file.exists()) {
        // 文件不存在，清除数据库记录
        await _dbService.deleteCache(sourceId, sourcePath);
        return false;
      }

      return true;
    } catch (e, st) {
      AppError.ignore(e, st, '检查缓存状态失败');
      return false;
    }
  }

  /// 获取缓存文件路径（如果已缓存）
  Future<String?> getCachedPath(String sourceId, String sourcePath) async {
    if (!_initialized) await init();

    try {
      final cachePath = await _dbService.getCachePath(sourceId, sourcePath);
      if (cachePath == null) return null;

      final file = File(cachePath);
      if (!await file.exists()) {
        // 文件不存在，清除数据库记录
        await _dbService.deleteCache(sourceId, sourcePath);
        return null;
      }

      // 更新最后访问时间
      await _dbService.updateLastAccessed(sourceId, sourcePath);

      return cachePath;
    } catch (e, st) {
      AppError.ignore(e, st, '获取缓存路径失败');
      return null;
    }
  }

  /// 删除指定媒体的缓存
  Future<void> deleteCache(String sourceId, String sourcePath) async {
    if (!_initialized) await init();

    try {
      final cachePath = await _dbService.getCachePath(sourceId, sourcePath);
      if (cachePath != null) {
        final file = File(cachePath);
        if (await file.exists()) {
          await file.delete();
          logger.d('MediaCacheService: 已删除缓存文件 $cachePath');
        }

        // 删除缩略图
        final thumbnailPath = '${p.withoutExtension(cachePath)}_thumb.jpg';
        final thumbFile = File(thumbnailPath);
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      }

      await _dbService.deleteCache(sourceId, sourcePath);
    } catch (e, st) {
      AppError.ignore(e, st, '删除缓存失败');
    }
  }

  /// 获取缓存大小
  Future<int> getCacheSize({MediaType? mediaType}) async {
    if (!_initialized) await init();

    try {
      return await _dbService.getCacheSize(mediaType: mediaType?.name);
    } catch (e, st) {
      AppError.ignore(e, st, '获取缓存大小失败');
      return 0;
    }
  }

  /// 获取格式化的缓存大小
  Future<String> getCacheSizeFormatted({MediaType? mediaType}) async {
    final size = await getCacheSize(mediaType: mediaType);
    return _formatBytes(size);
  }

  /// 获取缓存数量
  Future<int> getCacheCount({MediaType? mediaType}) async {
    if (!_initialized) await init();

    try {
      return await _dbService.getCacheCount(mediaType: mediaType?.name);
    } catch (e, st) {
      AppError.ignore(e, st, '获取缓存数量失败');
      return 0;
    }
  }

  /// 获取所有缓存项
  Future<List<CachedMediaItem>> getCachedItems({
    MediaType? mediaType,
    int? limit,
    int? offset,
  }) async {
    if (!_initialized) await init();

    try {
      final items = await _dbService.getCachedItems(
        mediaType: mediaType?.name,
        limit: limit,
        offset: offset,
      );

      // 验证文件存在性
      final validItems = <CachedMediaItem>[];
      for (final item in items) {
        final file = File(item.cachePath);
        if (await file.exists()) {
          validItems.add(item);
        } else {
          // 清理无效记录
          await _dbService.deleteCache(item.sourceId, item.sourcePath);
        }
      }

      return validItems;
    } catch (e, st) {
      AppError.ignore(e, st, '获取缓存列表失败');
      return [];
    }
  }

  /// 清空缓存
  Future<void> clearCache({MediaType? mediaType}) async {
    if (!_initialized) await init();

    try {
      if (mediaType != null) {
        // 清空指定类型
        final items = await _dbService.getCachedItems(mediaType: mediaType.name);
        for (final item in items) {
          final file = File(item.cachePath);
          if (await file.exists()) {
            await file.delete();
          }
        }
        await _dbService.clearAllCache(mediaType: mediaType.name);
        logger.i('MediaCacheService: 已清空 ${mediaType.name} 缓存');
      } else {
        // 清空所有类型
        for (final type in MediaType.values) {
          final dir = Directory(_cacheDirs[type]!);
          if (await dir.exists()) {
            await for (final entity in dir.list()) {
              if (entity is File) {
                await entity.delete();
              }
            }
          }
        }
        await _dbService.clearAllCache();
        logger.i('MediaCacheService: 已清空所有缓存');
      }
    } catch (e, st) {
      AppError.handle(e, st, 'MediaCacheService.clearCache');
    }
  }

  /// 确保缓存不超过配额
  Future<void> _ensureQuota(MediaType mediaType) async {
    final quota = cacheQuotas[mediaType] ?? 1024 * 1024 * 1024;
    final currentSize = await getCacheSize(mediaType: mediaType);

    if (currentSize <= quota) return;

    try {
      // 获取该类型的所有缓存项，按最后访问时间排序
      final items = await _dbService.getCachedItems(mediaType: mediaType.name);

      // 按 cachedAt 或 lastAccessed 排序（最旧的在前）
      items.sort((a, b) {
        final timeA = a.lastAccessed ?? a.cachedAt;
        final timeB = b.lastAccessed ?? b.cachedAt;
        return timeA.compareTo(timeB);
      });

      // 删除最旧的文件直到满足配额
      var freedSize = 0;
      final targetFreeSize = currentSize - quota;

      for (final item in items) {
        if (freedSize >= targetFreeSize) break;

        try {
          final file = File(item.cachePath);
          if (await file.exists()) {
            await file.delete();
            freedSize += item.fileSize;
          }
          await _dbService.deleteCache(item.sourceId, item.sourcePath);
        } catch (_) {
          // 忽略单个文件删除失败
        }
      }

      if (freedSize > 0) {
        logger.i(
          'MediaCacheService: 清理 ${mediaType.name} 缓存 '
          '${_formatBytes(freedSize)}',
        );
      }
    } catch (e, st) {
      AppError.ignore(e, st, '清理缓存配额失败');
    }
  }

  /// 获取缓存目录路径
  String? getCacheDirectory(MediaType mediaType) => _cacheDirs[mediaType];

  /// 获取缓存统计信息
  Future<Map<MediaType, ({int count, int size})>> getCacheStats() async {
    if (!_initialized) await init();

    final stats = <MediaType, ({int count, int size})>{};

    for (final type in MediaType.values) {
      final count = await getCacheCount(mediaType: type);
      final size = await getCacheSize(mediaType: type);
      stats[type] = (count: count, size: size);
    }

    return stats;
  }

  /// 验证并清理无效缓存（文件已删除但数据库记录仍存在）
  Future<int> cleanupInvalidCache() async {
    if (!_initialized) await init();

    var cleanedCount = 0;

    try {
      final items = await _dbService.getCachedItems();

      for (final item in items) {
        final file = File(item.cachePath);
        if (!await file.exists()) {
          await _dbService.deleteCache(item.sourceId, item.sourcePath);
          cleanedCount++;
        }
      }

      if (cleanedCount > 0) {
        logger.i('MediaCacheService: 清理了 $cleanedCount 条无效缓存记录');
      }
    } catch (e, st) {
      AppError.ignore(e, st, '清理无效缓存失败');
    }

    return cleanedCount;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
