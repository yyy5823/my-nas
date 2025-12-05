import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 漫画缓存条目
class ComicLibraryCacheEntry {
  ComicLibraryCacheEntry({
    required this.sourceId,
    required this.folderPath,
    required this.folderName,
    this.coverPath,
    this.pageCount = 0,
    this.modifiedTime,
    this.comicType = 'folder',
    this.fileSize,
  });

  final String sourceId;
  final String folderPath;
  final String folderName;
  final String? coverPath;
  final int pageCount;
  final DateTime? modifiedTime;
  final String comicType;
  final int? fileSize;

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'folderPath': folderPath,
        'folderName': folderName,
        'coverPath': coverPath,
        'pageCount': pageCount,
        'modifiedTime': modifiedTime?.toIso8601String(),
        'comicType': comicType,
        'fileSize': fileSize,
      };

  factory ComicLibraryCacheEntry.fromJson(Map<String, dynamic> json) =>
      ComicLibraryCacheEntry(
        sourceId: json['sourceId'] as String,
        folderPath: json['folderPath'] as String,
        folderName: json['folderName'] as String,
        coverPath: json['coverPath'] as String?,
        pageCount: json['pageCount'] as int? ?? 0,
        modifiedTime: json['modifiedTime'] != null
            ? DateTime.parse(json['modifiedTime'] as String)
            : null,
        comicType: json['comicType'] as String? ?? 'folder',
        fileSize: json['fileSize'] as int?,
      );
}

/// 漫画库缓存
class ComicLibraryCache {
  ComicLibraryCache({
    required this.comics,
    required this.lastUpdated,
    required this.sourceIds,
  });

  final List<ComicLibraryCacheEntry> comics;
  final DateTime lastUpdated;
  final List<String> sourceIds;

  Map<String, dynamic> toJson() => {
        'comics': comics.map((c) => c.toJson()).toList(),
        'lastUpdated': lastUpdated.toIso8601String(),
        'sourceIds': sourceIds,
      };

  factory ComicLibraryCache.fromJson(Map<String, dynamic> json) =>
      ComicLibraryCache(
        comics: (json['comics'] as List<dynamic>)
            .map((e) =>
                ComicLibraryCacheEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        lastUpdated: DateTime.parse(json['lastUpdated'] as String),
        sourceIds: List<String>.from(json['sourceIds'] as List),
      );
}

/// 漫画库缓存服务
class ComicLibraryCacheService {
  ComicLibraryCacheService._();
  static final instance = ComicLibraryCacheService._();

  static const _cacheKey = 'comic_library_cache';
  static const _cacheDuration = Duration(hours: 24);

  final _storage = const FlutterSecureStorage();
  ComicLibraryCache? _cache;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    try {
      final data = await _storage.read(key: _cacheKey);
      if (data != null) {
        _cache = ComicLibraryCache.fromJson(
            Map<String, dynamic>.from(jsonDecode(data) as Map));
        logger.i('ComicLibraryCacheService: 加载缓存成功，共 ${_cache!.comics.length} 本漫画');
      }
    } on Exception catch (e) {
      logger.w('ComicLibraryCacheService: 加载缓存失败', e);
      _cache = null;
    }

    _initialized = true;
  }

  ComicLibraryCache? getCache() => _cache;

  bool isCacheValid(List<String> sourceIds) {
    if (_cache == null) return false;

    final now = DateTime.now();
    final cacheAge = now.difference(_cache!.lastUpdated);
    if (cacheAge > _cacheDuration) return false;

    final cachedSourceIds = Set<String>.from(_cache!.sourceIds);
    final currentSourceIds = Set<String>.from(sourceIds);
    return cachedSourceIds.containsAll(currentSourceIds) &&
        currentSourceIds.containsAll(cachedSourceIds);
  }

  Future<void> saveCache(ComicLibraryCache cache) async {
    _cache = cache;
    try {
      await _storage.write(key: _cacheKey, value: jsonEncode(cache.toJson()));
      logger.i('ComicLibraryCacheService: 保存缓存成功，共 ${cache.comics.length} 本漫画');
    } on Exception catch (e) {
      logger.e('ComicLibraryCacheService: 保存缓存失败', e);
    }
  }

  Future<void> clearCache() async {
    _cache = null;
    try {
      await _storage.delete(key: _cacheKey);
      logger.i('ComicLibraryCacheService: 清除缓存成功');
    } on Exception catch (e) {
      logger.e('ComicLibraryCacheService: 清除缓存失败', e);
    }
  }

  /// 获取缓存大小（字节）
  int getCacheSize() {
    if (_cache == null) return 0;
    try {
      final jsonStr = jsonEncode(_cache!.toJson());
      return jsonStr.length;
    } on Exception catch (e) {
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

    return '${cache.comics.length} 本漫画 · $sizeText · $ageText更新';
  }
}
