import 'dart:async';
import 'dart:io';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 音频缓存服务
/// 将 NAS 音频文件下载到本地临时目录，支持自动清理
class AudioCacheService {
  factory AudioCacheService() => _instance ??= AudioCacheService._();
  AudioCacheService._();

  static AudioCacheService? _instance;

  /// 缓存目录
  Directory? _cacheDir;

  /// 最大缓存大小（默认 500MB）
  static const int maxCacheSizeBytes = 500 * 1024 * 1024;

  /// 单个文件最大大小（超过此大小使用流式播放，默认 100MB）
  static const int maxSingleFileSizeBytes = 100 * 1024 * 1024;

  /// 缓存文件最大保留时间（默认 7 天）
  static const Duration maxCacheAge = Duration(days: 7);

  /// 当前正在下载的文件（防止重复下载）
  final Map<String, Completer<File?>> _downloadingFiles = {};

  /// 已缓存文件的元数据
  final Map<String, _CacheEntry> _cacheEntries = {};

  bool _initialized = false;

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;

    final appDir = await getApplicationCacheDirectory();
    _cacheDir = Directory(p.join(appDir.path, 'audio_cache'));

    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }

    // 加载现有缓存文件的元数据
    await _loadCacheEntries();

    // 启动时清理过期和超量的缓存
    await _cleanupCache();

    _initialized = true;
    logger.i('AudioCacheService: 初始化完成，缓存目录: ${_cacheDir!.path}');
  }

  /// 获取缓存目录路径
  String get cacheDirPath => _cacheDir?.path ?? '';

  /// 检查文件是否应该使用缓存（基于文件大小）
  bool shouldUseCache(int fileSize) {
    return fileSize <= maxSingleFileSizeBytes;
  }

  /// 获取缓存的本地文件路径
  /// 如果文件已缓存，返回本地路径；否则下载后返回
  ///
  /// [fileSystem] NAS 文件系统
  /// [remotePath] 远程文件路径
  /// [sourceId] 数据源 ID（用于区分不同 NAS）
  /// [onProgress] 下载进度回调 (0.0 - 1.0)
  Future<File?> getCachedFile({
    required NasFileSystem fileSystem,
    required String remotePath,
    required String sourceId,
    void Function(double progress)? onProgress,
  }) async {
    if (!_initialized) await init();

    final cacheKey = _getCacheKey(sourceId, remotePath);
    final cachedFile = _getCachedFileIfValid(cacheKey);

    if (cachedFile != null) {
      logger.d('AudioCacheService: 使用缓存文件: $cacheKey');
      // 更新访问时间
      _updateAccessTime(cacheKey);
      return cachedFile;
    }

    // 检查是否正在下载
    if (_downloadingFiles.containsKey(cacheKey)) {
      logger.d('AudioCacheService: 等待正在进行的下载: $cacheKey');
      return _downloadingFiles[cacheKey]!.future;
    }

    // 开始下载
    final completer = Completer<File?>();
    _downloadingFiles[cacheKey] = completer;

    try {
      final file = await _downloadFile(
        fileSystem: fileSystem,
        remotePath: remotePath,
        cacheKey: cacheKey,
        onProgress: onProgress,
      );
      completer.complete(file);
      return file;
    } catch (e, stackTrace) {
      logger.e('AudioCacheService: 下载失败: $cacheKey', e, stackTrace);
      completer.complete(null);
      return null;
    } finally {
      _downloadingFiles.remove(cacheKey);
    }
  }

  /// 下载文件到缓存
  Future<File?> _downloadFile({
    required NasFileSystem fileSystem,
    required String remotePath,
    required String cacheKey,
    void Function(double progress)? onProgress,
  }) async {
    logger.i('AudioCacheService: 开始下载: $remotePath');

    try {
      // 获取文件信息
      final fileInfo = await fileSystem.getFileInfo(remotePath);
      final fileSize = fileInfo.size;

      // 检查文件大小
      if (fileSize > maxSingleFileSizeBytes) {
        logger.w('AudioCacheService: 文件过大 (${_formatSize(fileSize)})，跳过缓存');
        return null;
      }

      // 确保有足够空间
      await _ensureCacheSpace(fileSize);

      // 生成缓存文件路径
      final ext = p.extension(remotePath).toLowerCase();
      final fileName = '${cacheKey.hashCode.toRadixString(16)}$ext';
      final cacheFile = File(p.join(_cacheDir!.path, fileName));

      // 下载文件
      final stream = await fileSystem.getFileStream(remotePath);
      final sink = cacheFile.openWrite();

      var bytesReceived = 0;
      await for (final chunk in stream) {
        sink.add(chunk);
        bytesReceived += chunk.length;

        if (onProgress != null && fileSize > 0) {
          onProgress(bytesReceived / fileSize);
        }
      }

      await sink.close();

      // 验证文件完整性
      final downloadedSize = await cacheFile.length();
      if (downloadedSize != fileSize) {
        logger.w('AudioCacheService: 文件大小不匹配 (期望: $fileSize, 实际: $downloadedSize)');
        await cacheFile.delete();
        return null;
      }

      // 记录缓存条目
      _cacheEntries[cacheKey] = _CacheEntry(
        cacheKey: cacheKey,
        filePath: cacheFile.path,
        fileSize: fileSize,
        createdAt: DateTime.now(),
        lastAccessedAt: DateTime.now(),
      );

      logger.i('AudioCacheService: 下载完成: ${_formatSize(fileSize)}');
      return cacheFile;
    } catch (e, stackTrace) {
      logger.e('AudioCacheService: 下载失败', e, stackTrace);
      rethrow;
    }
  }

  /// 生成缓存键
  String _getCacheKey(String sourceId, String remotePath) {
    return '${sourceId}_$remotePath';
  }

  /// 获取有效的缓存文件
  File? _getCachedFileIfValid(String cacheKey) {
    final entry = _cacheEntries[cacheKey];
    if (entry == null) return null;

    final file = File(entry.filePath);
    if (!file.existsSync()) {
      _cacheEntries.remove(cacheKey);
      return null;
    }

    // 检查是否过期
    if (DateTime.now().difference(entry.createdAt) > maxCacheAge) {
      _removeCacheEntry(cacheKey);
      return null;
    }

    return file;
  }

  /// 更新访问时间
  void _updateAccessTime(String cacheKey) {
    final entry = _cacheEntries[cacheKey];
    if (entry != null) {
      _cacheEntries[cacheKey] = entry.copyWith(
        lastAccessedAt: DateTime.now(),
      );
    }
  }

  /// 加载现有缓存文件
  Future<void> _loadCacheEntries() async {
    if (_cacheDir == null || !await _cacheDir!.exists()) return;

    try {
      final files = _cacheDir!.listSync();
      for (final entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          final cacheKey = p.basenameWithoutExtension(entity.path);
          _cacheEntries[cacheKey] = _CacheEntry(
            cacheKey: cacheKey,
            filePath: entity.path,
            fileSize: stat.size,
            createdAt: stat.modified,
            lastAccessedAt: stat.accessed,
          );
        }
      }
      logger.d('AudioCacheService: 加载了 ${_cacheEntries.length} 个缓存条目');
    } catch (e) {
      logger.w('AudioCacheService: 加载缓存条目失败: $e');
    }
  }

  /// 确保有足够的缓存空间
  Future<void> _ensureCacheSpace(int requiredBytes) async {
    var currentSize = _calculateTotalCacheSize();

    // 如果当前大小加上需要的空间超过限制，清理旧文件
    while (currentSize + requiredBytes > maxCacheSizeBytes && _cacheEntries.isNotEmpty) {
      // 找到最久未访问的文件
      String? oldestKey;
      DateTime? oldestTime;

      for (final entry in _cacheEntries.entries) {
        if (oldestTime == null || entry.value.lastAccessedAt.isBefore(oldestTime)) {
          oldestKey = entry.key;
          oldestTime = entry.value.lastAccessedAt;
        }
      }

      if (oldestKey != null) {
        final removedSize = _cacheEntries[oldestKey]?.fileSize ?? 0;
        await _removeCacheEntry(oldestKey);
        currentSize -= removedSize;
        logger.d('AudioCacheService: 清理旧缓存以腾出空间: ${_formatSize(removedSize)}');
      } else {
        break;
      }
    }
  }

  /// 计算当前缓存总大小
  int _calculateTotalCacheSize() {
    var total = 0;
    for (final entry in _cacheEntries.values) {
      total += entry.fileSize;
    }
    return total;
  }

  /// 删除缓存条目
  Future<void> _removeCacheEntry(String cacheKey) async {
    final entry = _cacheEntries.remove(cacheKey);
    if (entry != null) {
      try {
        final file = File(entry.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        logger.w('AudioCacheService: 删除缓存文件失败: $e');
      }
    }
  }

  /// 清理过期和超量的缓存
  Future<void> _cleanupCache() async {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    // 找出过期的条目
    for (final entry in _cacheEntries.entries) {
      if (now.difference(entry.value.createdAt) > maxCacheAge) {
        expiredKeys.add(entry.key);
      }
    }

    // 删除过期条目
    for (final key in expiredKeys) {
      await _removeCacheEntry(key);
    }

    if (expiredKeys.isNotEmpty) {
      logger.i('AudioCacheService: 清理了 ${expiredKeys.length} 个过期缓存');
    }

    // 如果仍然超过大小限制，继续清理
    await _ensureCacheSpace(0);
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    if (!_initialized) await init();

    try {
      if (_cacheDir != null && await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
      _cacheEntries.clear();
      logger.i('AudioCacheService: 已清除所有缓存');
    } catch (e) {
      logger.e('AudioCacheService: 清除缓存失败: $e');
    }
  }

  /// 获取缓存统计信息
  Future<CacheStats> getCacheStats() async {
    if (!_initialized) await init();

    return CacheStats(
      totalSize: _calculateTotalCacheSize(),
      fileCount: _cacheEntries.length,
      maxSize: maxCacheSizeBytes,
    );
  }

  /// 格式化文件大小
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}

/// 缓存条目
class _CacheEntry {
  const _CacheEntry({
    required this.cacheKey,
    required this.filePath,
    required this.fileSize,
    required this.createdAt,
    required this.lastAccessedAt,
  });

  final String cacheKey;
  final String filePath;
  final int fileSize;
  final DateTime createdAt;
  final DateTime lastAccessedAt;

  _CacheEntry copyWith({
    String? cacheKey,
    String? filePath,
    int? fileSize,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
  }) => _CacheEntry(
      cacheKey: cacheKey ?? this.cacheKey,
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      createdAt: createdAt ?? this.createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
}

/// 缓存统计信息
class CacheStats {
  const CacheStats({
    required this.totalSize,
    required this.fileCount,
    required this.maxSize,
  });

  final int totalSize;
  final int fileCount;
  final int maxSize;

  double get usagePercent => maxSize > 0 ? totalSize / maxSize : 0;

  String get totalSizeFormatted {
    if (totalSize < 1024) return '$totalSize B';
    if (totalSize < 1024 * 1024) return '${(totalSize / 1024).toStringAsFixed(1)} KB';
    if (totalSize < 1024 * 1024 * 1024) {
      return '${(totalSize / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(totalSize / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  String get maxSizeFormatted {
    if (maxSize < 1024) return '$maxSize B';
    if (maxSize < 1024 * 1024) return '${(maxSize / 1024).toStringAsFixed(1)} KB';
    if (maxSize < 1024 * 1024 * 1024) {
      return '${(maxSize / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(maxSize / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}
