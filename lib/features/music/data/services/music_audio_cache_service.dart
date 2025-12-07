import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 音乐音频缓存服务 - 管理音乐文件的持久化缓存
/// 用于 LockCachingAudioSource 实现持久化缓存，避免重复下载
class MusicAudioCacheService {
  factory MusicAudioCacheService() => _instance ??= MusicAudioCacheService._();
  MusicAudioCacheService._();

  static MusicAudioCacheService? _instance;

  String? _cacheDir;
  bool _initialized = false;

  /// 缓存目录最大总大小（2GB）
  static const int maxTotalCacheSize = 2 * 1024 * 1024 * 1024;

  /// 初始化缓存目录
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      _cacheDir = p.join(documentsDir.path, 'music_audio_cache');

      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _initialized = true;
      logger.i('MusicAudioCacheService: 缓存目录初始化完成 $_cacheDir');
    } catch (e) {
      logger.e('MusicAudioCacheService: 初始化失败', e);
      rethrow;
    }
  }

  /// 生成缓存文件的唯一键
  /// 使用 sourceId 和 filePath 组合生成，确保同一文件只缓存一次
  String _generateCacheKey(String? sourceId, String filePath) {
    final key = sourceId != null ? '${sourceId}_$filePath' : filePath;
    return md5.convert(utf8.encode(key)).toString();
  }

  /// 获取音频缓存文件路径
  /// 即使文件不存在也返回路径（用于 LockCachingAudioSource 创建缓存）
  Future<File> getCacheFile(String? sourceId, String filePath) async {
    if (!_initialized) await init();

    final hash = _generateCacheKey(sourceId, filePath);
    final extension = p.extension(filePath).toLowerCase();
    // 保留原始扩展名，便于识别文件类型
    final filename = '$hash$extension';
    return File(p.join(_cacheDir!, filename));
  }

  /// 检查缓存文件是否存在且完整
  /// 完整性检查：文件存在且大小 > 0
  Future<bool> isCached(String? sourceId, String filePath) async {
    if (!_initialized) await init();

    try {
      final file = await getCacheFile(sourceId, filePath);
      if (await file.exists()) {
        final size = await file.length();
        return size > 0;
      }
    } on Exception catch (e) {
      logger.w('MusicAudioCacheService: 检查缓存失败', e);
    }
    return false;
  }

  /// 检查缓存文件是否正在下载中（有 .part 文件）
  Future<bool> isDownloading(String? sourceId, String filePath) async {
    if (!_initialized) await init();

    try {
      final file = await getCacheFile(sourceId, filePath);
      final partFile = File('${file.path}.part');
      return await partFile.exists();
    } on Exception catch (e) {
      logger.w('MusicAudioCacheService: 检查下载状态失败', e);
    }
    return false;
  }

  /// 删除指定音乐的缓存
  Future<void> deleteCache(String? sourceId, String filePath) async {
    if (!_initialized) await init();

    try {
      final file = await getCacheFile(sourceId, filePath);
      if (await file.exists()) {
        await file.delete();
        logger.d('MusicAudioCacheService: 已删除缓存 ${file.path}');
      }

      // 同时删除 .part 文件（如果存在）
      final partFile = File('${file.path}.part');
      if (await partFile.exists()) {
        await partFile.delete();
      }

      // 删除 .mime 文件（如果存在）
      final mimeFile = File('${file.path}.mime');
      if (await mimeFile.exists()) {
        await mimeFile.delete();
      }
    } on Exception catch (e) {
      logger.w('MusicAudioCacheService: 删除缓存失败', e);
    }
  }

  /// 确保缓存不超过配额，必要时清理最旧的文件
  Future<void> ensureCacheQuota({int? newFileSize}) async {
    if (!_initialized) await init();

    final requiredSize = newFileSize ?? 0;
    final currentSize = await getCacheSize();
    if (currentSize + requiredSize <= maxTotalCacheSize) return;

    try {
      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) return;

      // 获取所有缓存文件及其修改时间
      final files = <MapEntry<File, DateTime>>[];
      await for (final entity in dir.list()) {
        if (entity is File && !entity.path.endsWith('.part') && !entity.path.endsWith('.mime')) {
          final stat = await entity.stat();
          files.add(MapEntry(entity, stat.accessed));
        }
      }

      // 按访问时间排序（最旧的在前）
      files.sort((a, b) => a.value.compareTo(b.value));

      // 删除最旧的文件直到有足够空间
      var freedSize = 0;
      final targetFreeSize = (currentSize + requiredSize) - maxTotalCacheSize;
      for (final entry in files) {
        if (freedSize >= targetFreeSize) break;

        try {
          final fileSize = await entry.key.length();
          final basePath = entry.key.path;

          // 删除主文件
          await entry.key.delete();
          freedSize += fileSize;

          // 同时删除关联的 .part 和 .mime 文件
          final partFile = File('$basePath.part');
          if (await partFile.exists()) {
            await partFile.delete();
          }
          final mimeFile = File('$basePath.mime');
          if (await mimeFile.exists()) {
            await mimeFile.delete();
          }

          logger.d('MusicAudioCacheService: 清理旧缓存 ${entry.key.path}');
        } on Exception catch (_) {
          // 忽略单个文件删除失败
        }
      }

      if (freedSize > 0) {
        logger.i(
          'MusicAudioCacheService: 已清理 '
          '${(freedSize / 1024 / 1024).toStringAsFixed(2)}MB 缓存空间',
        );
      }
    } on Exception catch (e) {
      logger.w('MusicAudioCacheService: 清理缓存配额失败', e);
    }
  }

  /// 清空所有音频缓存
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
      logger.i('MusicAudioCacheService: 已清空所有音频缓存');
    } on Exception catch (e) {
      logger.e('MusicAudioCacheService: 清空缓存失败', e);
    }
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
    } on Exception catch (e) {
      logger.w('MusicAudioCacheService: 计算缓存大小失败', e);
    }
    return totalSize;
  }

  /// 获取格式化的缓存大小
  Future<String> getCacheSizeFormatted() async {
    final size = await getCacheSize();
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 获取缓存文件数量
  Future<int> getCacheCount() async {
    if (!_initialized) await init();

    var count = 0;
    try {
      final dir = Directory(_cacheDir!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && !entity.path.endsWith('.part') && !entity.path.endsWith('.mime')) {
            count++;
          }
        }
      }
    } on Exception catch (e) {
      logger.w('MusicAudioCacheService: 计算缓存数量失败', e);
    }
    return count;
  }

  /// 获取缓存目录路径
  String? get cacheDirectory => _cacheDir;
}
