import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 视频库缓存条目
class VideoLibraryCacheEntry {
  VideoLibraryCacheEntry({
    required this.sourceId,
    required this.filePath,
    required this.fileName,
    this.thumbnailUrl,
    this.size = 0,
    this.modifiedTime,
  });

  final String sourceId;
  final String filePath;
  final String fileName;
  final String? thumbnailUrl;
  final int size;
  final DateTime? modifiedTime;

  String get uniqueKey => '${sourceId}_$filePath';

  Map<String, dynamic> toMap() => {
        'sourceId': sourceId,
        'filePath': filePath,
        'fileName': fileName,
        'thumbnailUrl': thumbnailUrl,
        'size': size,
        'modifiedTime': modifiedTime?.millisecondsSinceEpoch,
      };

  factory VideoLibraryCacheEntry.fromMap(Map<dynamic, dynamic> map) {
    return VideoLibraryCacheEntry(
      sourceId: map['sourceId'] as String,
      filePath: map['filePath'] as String,
      fileName: map['fileName'] as String,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      size: map['size'] as int? ?? 0,
      modifiedTime: map['modifiedTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['modifiedTime'] as int)
          : null,
    );
  }
}

/// 视频库缓存
class VideoLibraryCache {
  VideoLibraryCache({
    required this.videos,
    required this.lastUpdated,
    this.sourceIds = const [],
  });

  final List<VideoLibraryCacheEntry> videos;
  final DateTime lastUpdated;
  final List<String> sourceIds;

  /// 缓存是否过期（默认24小时）
  bool get isExpired =>
      DateTime.now().difference(lastUpdated).inHours > 24;

  Map<String, dynamic> toMap() => {
        'videos': videos.map((v) => v.toMap()).toList(),
        'lastUpdated': lastUpdated.millisecondsSinceEpoch,
        'sourceIds': sourceIds,
      };

  factory VideoLibraryCache.fromMap(Map<dynamic, dynamic> map) {
    final videosList = (map['videos'] as List<dynamic>?)
            ?.map((v) => VideoLibraryCacheEntry.fromMap(v as Map<dynamic, dynamic>))
            .toList() ??
        [];
    return VideoLibraryCache(
      videos: videosList,
      lastUpdated:
          DateTime.fromMillisecondsSinceEpoch(map['lastUpdated'] as int),
      sourceIds: (map['sourceIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }
}

/// 视频库缓存服务
/// 缓存视频文件列表，避免每次启动都扫描 NAS
class VideoLibraryCacheService {
  VideoLibraryCacheService._();

  static VideoLibraryCacheService? _instance;
  static VideoLibraryCacheService get instance =>
      _instance ??= VideoLibraryCacheService._();

  static const String _boxName = 'video_library_cache';
  static const String _cacheKey = 'library_cache';

  Box<dynamic>? _box;

  /// 初始化
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    try {
      _box = await Hive.openBox(_boxName);
      logger.i('VideoLibraryCacheService: 初始化完成');
    } on Exception catch (e) {
      logger.e('VideoLibraryCacheService: 打开缓存失败，尝试删除并重建', e);
      // 删除损坏的 box 并重新创建
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName);
      logger.i('VideoLibraryCacheService: 重建缓存完成');
    }
  }

  /// 获取缓存（同步版本，用于快速检查）
  VideoLibraryCache? getCache() {
    final data = _box?.get(_cacheKey);
    if (data == null) return null;
    try {
      return VideoLibraryCache.fromMap(data as Map<dynamic, dynamic>);
    } on Exception catch (e) {
      logger.e('VideoLibraryCacheService: 解析缓存失败', e);
      return null;
    }
  }

  /// 异步获取缓存（在 isolate 中反序列化大量数据，避免阻塞 UI）
  Future<VideoLibraryCache?> getCacheAsync() async {
    final data = _box?.get(_cacheKey);
    if (data == null) return null;
    try {
      // 直接传递 Map 数据到 isolate 进行解析
      // Hive 返回的 Map 是可序列化的，可以直接跨 isolate 传递
      return compute(_parseCacheFromMap, Map<String, dynamic>.from(data as Map));
    } on Exception catch (e) {
      logger.e('VideoLibraryCacheService: 异步解析缓存失败', e);
      return null;
    }
  }

  /// 检查缓存是否有效（未过期且源ID匹配）
  bool isCacheValid(List<String> currentSourceIds) {
    final cache = getCache();
    if (cache == null) return false;
    if (cache.isExpired) return false;

    // 检查源ID是否一致
    final cachedSourceIds = Set.of(cache.sourceIds);
    final currentIds = Set.of(currentSourceIds);
    return cachedSourceIds.containsAll(currentIds) &&
           currentIds.containsAll(cachedSourceIds);
  }

  /// 保存缓存
  Future<void> saveCache(VideoLibraryCache cache) async {
    await _box?.put(_cacheKey, cache.toMap());
    logger.i('VideoLibraryCacheService: 保存缓存，${cache.videos.length} 个视频');
  }

  /// 清除缓存
  Future<void> clearCache() async {
    await _box?.delete(_cacheKey);
    logger.i('VideoLibraryCacheService: 缓存已清除');
  }

  /// 获取缓存大小（字节）
  int getCacheSize() {
    final data = _box?.get(_cacheKey);
    if (data == null) return 0;
    try {
      final jsonStr = jsonEncode(data);
      return jsonStr.length;
    } on Exception {
      return 0;
    }
  }

  /// 获取缓存信息文本
  String getCacheInfo() {
    final cache = getCache();
    if (cache == null) return '无缓存';

    final size = getCacheSize();
    final sizeText = size < 1024
        ? '$size B'
        : size < 1024 * 1024
            ? '${(size / 1024).toStringAsFixed(1)} KB'
            : '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';

    final age = DateTime.now().difference(cache.lastUpdated);
    final ageText = age.inHours < 1
        ? '${age.inMinutes} 分钟前'
        : age.inHours < 24
            ? '${age.inHours} 小时前'
            : '${age.inDays} 天前';

    return '${cache.videos.length} 个视频 · $sizeText · $ageText更新';
  }
}

/// 在 isolate 中解析缓存数据（顶级函数，供 compute 使用）
VideoLibraryCache _parseCacheFromMap(Map<String, dynamic> data) {
  return VideoLibraryCache.fromMap(data);
}
