import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 图书文件缓存服务 - 管理电子书文件的持久化缓存
/// 用于避免重复下载电子书文件，提升阅读体验
class BookFileCacheService {
  factory BookFileCacheService() => _instance ??= BookFileCacheService._();
  BookFileCacheService._();

  static BookFileCacheService? _instance;

  String? _cacheDir;
  bool _initialized = false;

  /// 缓存目录最大总大小（1GB）
  static const int maxTotalCacheSize = 1024 * 1024 * 1024;

  /// 初始化缓存目录
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      _cacheDir = p.join(documentsDir.path, 'book_file_cache');

      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _initialized = true;
      logger.i('BookFileCacheService: 缓存目录初始化完成 $_cacheDir');
    } catch (e, st) {
      AppError.handle(e, st, 'BookFileCacheService.init');
      rethrow;
    }
  }

  /// 生成缓存文件的唯一键
  String _generateCacheKey(String? sourceId, String filePath) {
    final key = sourceId != null ? '${sourceId}_$filePath' : filePath;
    return md5.convert(utf8.encode(key)).toString();
  }

  /// 获取缓存文件路径
  Future<File> getCacheFile(String? sourceId, String filePath) async {
    if (!_initialized) await init();

    final hash = _generateCacheKey(sourceId, filePath);
    final extension = p.extension(filePath).toLowerCase();
    final filename = '$hash$extension';
    return File(p.join(_cacheDir!, filename));
  }

  /// 检查缓存文件是否存在且完整
  Future<bool> isCached(String? sourceId, String filePath) async {
    if (!_initialized) await init();

    try {
      final file = await getCacheFile(sourceId, filePath);
      if (await file.exists()) {
        final size = await file.length();
        return size > 0;
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '检查缓存失败，非关键功能');
    }
    return false;
  }

  /// 保存文件到缓存
  Future<File?> saveToCache(
    String? sourceId,
    String filePath,
    List<int> bytes,
  ) async {
    if (!_initialized) await init();

    try {
      final file = await getCacheFile(sourceId, filePath);
      await file.writeAsBytes(bytes);
      logger.i('BookFileCacheService: 缓存文件成功 ${file.path}');

      // 异步清理过期缓存（不等待完成）
      unawaited(_cleanupIfNeeded());

      return file;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'BookFileCacheService.saveToCache');
      return null;
    }
  }

  /// 从流保存文件到缓存（避免大文件占用过多内存）
  Future<File?> saveToCacheFromStream(
    String? sourceId,
    String filePath,
    Future<Stream<List<int>>> Function() streamFactory,
  ) async {
    if (!_initialized) await init();

    try {
      final file = await getCacheFile(sourceId, filePath);
      final sink = file.openWrite();

      try {
        final stream = await streamFactory();
        await for (final chunk in stream) {
          sink.add(chunk);
        }
        await sink.flush();
        logger.i('BookFileCacheService: 流式缓存文件成功 ${file.path}');
      } finally {
        await sink.close();
      }

      // 异步清理过期缓存（不等待完成）
      unawaited(_cleanupIfNeeded());

      return file;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'BookFileCacheService.saveToCacheFromStream');
      return null;
    }
  }

  /// 获取缓存的文件（如果存在）
  Future<File?> getCachedFile(String? sourceId, String filePath) async {
    if (!_initialized) await init();

    try {
      final file = await getCacheFile(sourceId, filePath);
      if (await file.exists() && await file.length() > 0) {
        // 更新访问时间
        await file.setLastAccessed(DateTime.now());
        return file;
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '获取缓存失败，非关键功能');
    }
    return null;
  }

  /// 删除指定文件的缓存
  Future<void> removeFromCache(String? sourceId, String filePath) async {
    if (!_initialized) await init();

    try {
      final file = await getCacheFile(sourceId, filePath);
      if (await file.exists()) {
        await file.delete();
        logger.i('BookFileCacheService: 删除缓存成功 ${file.path}');
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '删除缓存失败，非关键功能');
    }
  }

  /// 获取缓存文件数量
  Future<int> getCacheCount() async {
    if (!_initialized) await init();

    var count = 0;
    try {
      final dir = Directory(_cacheDir!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            count++;
          }
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '计算缓存数量失败，非关键功能');
    }
    return count;
  }

  /// 获取缓存大小（字节）
  Future<int> getCacheSize() async {
    if (!_initialized) await init();

    var totalSize = 0;
    try {
      final dir = Directory(_cacheDir!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '计算缓存大小失败，非关键功能');
    }
    return totalSize;
  }

  /// 清空所有图书缓存
  Future<void> clearAll() async {
    if (!_initialized) await init();

    try {
      final dir = Directory(_cacheDir!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
      logger.i('BookFileCacheService: 已清空所有图书缓存');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'BookFileCacheService.clearAll');
    }
  }

  /// 清理过期缓存（LRU 策略）
  Future<void> _cleanupIfNeeded() async {
    try {
      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) return;

      final files = await dir.list().toList();
      var totalSize = 0;
      final fileStats = <(File, FileStat)>[];

      for (final entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
          fileStats.add((entity, stat));
        }
      }

      // 如果超过最大缓存大小，删除最旧的文件
      if (totalSize > maxTotalCacheSize) {
        // 按访问时间排序（最旧的在前）
        fileStats.sort(
          (a, b) => a.$2.accessed.compareTo(b.$2.accessed),
        );

        var freedSize = 0;
        final targetFreeSize = totalSize - maxTotalCacheSize ~/ 2;

        for (final (file, stat) in fileStats) {
          if (freedSize >= targetFreeSize) break;
          await file.delete();
          freedSize += stat.size;
          logger.d('BookFileCacheService: 清理缓存 ${file.path}');
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '清理缓存失败，非关键功能');
    }
  }
}
