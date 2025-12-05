import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:my_nas/core/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 音乐封面缓存服务 - 将封面存储在磁盘而非内存
class MusicCoverCacheService {
  MusicCoverCacheService._();

  static MusicCoverCacheService? _instance;
  static MusicCoverCacheService get instance =>
      _instance ??= MusicCoverCacheService._();

  String? _cacheDir;
  bool _initialized = false;

  /// 初始化缓存目录
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      _cacheDir = p.join(documentsDir.path, 'music_covers');

      final dir = Directory(_cacheDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _initialized = true;
      logger.i('MusicCoverCacheService: 缓存目录初始化完成 $_cacheDir');
    } catch (e) {
      logger.e('MusicCoverCacheService: 初始化失败', e);
      rethrow;
    }
  }

  /// 获取封面缓存路径
  String _getCoverPath(String uniqueKey) {
    // 使用 MD5 哈希生成文件名，避免特殊字符问题
    final hash = md5.convert(utf8.encode(uniqueKey)).toString();
    return p.join(_cacheDir!, '$hash.jpg');
  }

  /// 保存封面到磁盘
  Future<String?> saveCover(String uniqueKey, Uint8List coverData) async {
    if (!_initialized) await init();
    if (coverData.isEmpty) return null;

    try {
      final path = _getCoverPath(uniqueKey);
      final file = File(path);
      await file.writeAsBytes(coverData);
      return path;
    } on Exception catch (e) {
      logger.w('MusicCoverCacheService: 保存封面失败 $uniqueKey', e);
      return null;
    }
  }

  /// 保存 Base64 编码的封面到磁盘
  Future<String?> saveCoverFromBase64(String uniqueKey, String base64Data) async {
    if (!_initialized) await init();
    if (base64Data.isEmpty) return null;

    try {
      final data = base64Decode(base64Data);
      return saveCover(uniqueKey, Uint8List.fromList(data));
    } on Exception catch (e) {
      logger.w('MusicCoverCacheService: 解码 Base64 封面失败', e);
      return null;
    }
  }

  /// 获取封面数据
  Future<Uint8List?> getCover(String uniqueKey) async {
    if (!_initialized) await init();

    try {
      final path = _getCoverPath(uniqueKey);
      final file = File(path);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } on Exception catch (e) {
      logger.w('MusicCoverCacheService: 读取封面失败 $uniqueKey', e);
    }
    return null;
  }

  /// 检查封面是否存在
  Future<bool> hasCover(String uniqueKey) async {
    if (!_initialized) await init();

    final path = _getCoverPath(uniqueKey);
    return File(path).exists();
  }

  /// 获取封面文件路径（如果存在）
  Future<String?> getCoverPath(String uniqueKey) async {
    if (!_initialized) await init();

    final path = _getCoverPath(uniqueKey);
    if (await File(path).exists()) {
      return path;
    }
    return null;
  }

  /// 删除封面
  Future<void> deleteCover(String uniqueKey) async {
    if (!_initialized) await init();

    try {
      final path = _getCoverPath(uniqueKey);
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on Exception catch (e) {
      logger.w('MusicCoverCacheService: 删除封面失败 $uniqueKey', e);
    }
  }

  /// 清空所有封面缓存
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
      logger.i('MusicCoverCacheService: 已清空所有封面缓存');
    } on Exception catch (e) {
      logger.e('MusicCoverCacheService: 清空缓存失败', e);
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
      logger.w('MusicCoverCacheService: 计算缓存大小失败', e);
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

  /// 获取缓存目录路径
  String? get cacheDirectory => _cacheDir;
}
