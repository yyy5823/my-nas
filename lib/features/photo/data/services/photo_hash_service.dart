import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 照片哈希计算服务
/// 支持两种哈希：
/// 1. MD5 文件哈希 - 用于检测完全相同的文件
/// 2. 感知哈希 (pHash) - 用于检测视觉相似的图片
class PhotoHashService {
  factory PhotoHashService() => _instance ??= PhotoHashService._();
  PhotoHashService._();

  static PhotoHashService? _instance;

  final PhotoDatabaseService _db = PhotoDatabaseService();

  // 进度流控制器
  final _progressController = StreamController<HashProgress>.broadcast();

  /// 哈希计算进度流
  Stream<HashProgress> get progressStream => _progressController.stream;

  bool _isProcessing = false;
  bool _shouldCancel = false;

  /// 是否正在处理中
  bool get isProcessing => _isProcessing;

  /// 取消当前处理
  void cancel() {
    _shouldCancel = true;
  }

  /// 计算所有未处理照片的哈希值
  /// [fileSystem] 用于读取文件内容
  /// [batchSize] 每批处理的照片数量
  Future<void> processAllPhotos(
    NasFileSystem fileSystem, {
    int batchSize = 20,
  }) async {
    if (_isProcessing) {
      logger.w('PhotoHashService: 已有任务在处理中');
      return;
    }

    _isProcessing = true;
    _shouldCancel = false;

    try {
      var processed = 0;
      var failed = 0;

      while (!_shouldCancel) {
        // 获取一批未处理的照片
        final photos = await _db.getPhotosWithoutHash(limit: batchSize);
        if (photos.isEmpty) break;

        final total = await _db.getCount();
        final remaining = photos.length;

        _progressController.add(HashProgress(
          processed: processed,
          total: total,
          currentFile: photos.first.fileName,
          status: HashStatus.processing,
        ));

        // 并行处理这批照片（限制并发数）
        final futures = <Future<PhotoEntity>>[];
        for (final photo in photos) {
          if (_shouldCancel) break;
          futures.add(_processPhoto(photo, fileSystem));
        }

        final results = await Future.wait(futures);

        // 更新数据库（包括成功和失败的都更新，失败的会标记为空字符串）
        await _db.updateHashBatch(results);

        // 统计成功和失败的数量
        final successCount = results.where((r) => r.fileHash?.isNotEmpty ?? false).length;
        final failCount = results.length - successCount;
        processed += successCount;
        failed += failCount;

        _progressController.add(HashProgress(
          processed: processed,
          total: total,
          failed: failed,
          currentFile: '',
          status: HashStatus.processing,
        ));

        // 如果处理的数量少于批次大小，说明已经处理完了
        if (remaining < batchSize) break;
      }

      _progressController.add(HashProgress(
        processed: processed,
        total: processed + failed,
        failed: failed,
        currentFile: '',
        status: _shouldCancel ? HashStatus.cancelled : HashStatus.completed,
      ));

      logger.i('PhotoHashService: 处理完成，成功 $processed 张，失败 $failed 张');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'PhotoHashService.processAllPhotos');
      _progressController.add(HashProgress(
        processed: 0,
        total: 0,
        currentFile: '',
        status: HashStatus.error,
        error: e.toString(),
      ));
    } finally {
      _isProcessing = false;
      _shouldCancel = false;
    }
  }

  /// 处理单张照片
  /// 返回更新后的 PhotoEntity，失败时返回带有空字符串哈希的实体（标记为已处理）
  Future<PhotoEntity> _processPhoto(
    PhotoEntity photo,
    NasFileSystem fileSystem,
  ) async {
    try {
      // 通过流读取文件内容
      final stream = await fileSystem.getFileStream(photo.filePath);
      final chunks = <List<int>>[];
      await for (final chunk in stream) {
        chunks.add(chunk);
      }
      final bytes = Uint8List.fromList(chunks.expand((c) => c).toList());
      if (bytes.isEmpty) {
        logger.w('PhotoHashService: 文件内容为空 - ${photo.filePath}');
        // 标记为已处理（失败），使用空字符串避免重复查询
        return photo.copyWith(fileHash: '', perceptualHash: '');
      }

      // 计算 MD5 哈希
      final fileHash = _computeMD5(bytes);

      // 计算感知哈希
      // 注意：失败时保留空字符串 '' 而不是 null，避免被 getPhotosWithoutHash 重复查询
      final perceptualHash = await compute(_computePerceptualHash, bytes);

      if (perceptualHash.isEmpty) {
        logger.w('PhotoHashService: pHash 计算失败 - ${photo.filePath}');
      }

      return photo.copyWith(
        fileHash: fileHash,
        perceptualHash: perceptualHash.isEmpty ? '' : perceptualHash,
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '单张照片处理失败: ${photo.filePath}');
      // 标记为已处理（失败），使用空字符串避免重复查询
      return photo.copyWith(fileHash: '', perceptualHash: '');
    }
  }

  /// 计算 MD5 哈希
  String _computeMD5(Uint8List bytes) {
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// 查找相似照片组
  /// [threshold] 汉明距离阈值，越小越严格（推荐 5-10）
  /// 返回相似照片组列表，每组包含相似的照片
  Future<List<List<PhotoEntity>>> findSimilarPhotos({
    int threshold = 8,
    void Function(int processed, int total)? onProgress,
  }) async {
    logger.i('PhotoHashService: 开始查找相似照片，阈值=$threshold');

    // 获取所有有 pHash 的照片
    final photos = await _db.getPhotosWithPerceptualHash();
    if (photos.length < 2) return [];

    logger.i('PhotoHashService: 共 ${photos.length} 张照片待比较');

    // 使用 Union-Find 算法分组
    final parent = <String, String>{};
    final rank = <String, int>{};

    String find(String x) {
      if (parent[x] != x) {
        parent[x] = find(parent[x]!);
      }
      return parent[x]!;
    }

    void union(String x, String y) {
      final rootX = find(x);
      final rootY = find(y);
      if (rootX == rootY) return;

      final rankX = rank[rootX] ?? 0;
      final rankY = rank[rootY] ?? 0;
      if (rankX < rankY) {
        parent[rootX] = rootY;
      } else if (rankX > rankY) {
        parent[rootY] = rootX;
      } else {
        parent[rootY] = rootX;
        rank[rootX] = rankX + 1;
      }
    }

    // 初始化并查集
    for (final photo in photos) {
      parent[photo.uniqueKey] = photo.uniqueKey;
      rank[photo.uniqueKey] = 0;
    }

    // 按 pHash 前缀分桶，减少比较次数
    // 使用前 2 个字符（256 个桶）
    final buckets = <String, List<PhotoEntity>>{};
    for (final photo in photos) {
      final hash = photo.perceptualHash!;
      if (hash.length >= 2) {
        final prefix = hash.substring(0, 2);
        buckets.putIfAbsent(prefix, () => []).add(photo);
      }
    }

    // 生成需要比较的相邻前缀（汉明距离 1-2 的前缀）
    Set<String> getNeighborPrefixes(String prefix) {
      final neighbors = <String>{prefix};
      final prefixValue = int.parse(prefix, radix: 16);

      // 单 bit 翻转（汉明距离 1）
      for (var i = 0; i < 8; i++) {
        final neighbor = prefixValue ^ (1 << i);
        neighbors.add(neighbor.toRadixString(16).padLeft(2, '0'));
      }

      return neighbors;
    }

    var processed = 0;
    final totalBuckets = buckets.length;

    // 比较桶内和相邻桶的照片
    for (final entry in buckets.entries) {
      final currentBucket = entry.value;
      final neighborPrefixes = getNeighborPrefixes(entry.key);

      // 收集当前桶和相邻桶的所有照片
      final photosToCompare = <PhotoEntity>[];
      for (final prefix in neighborPrefixes) {
        if (buckets.containsKey(prefix)) {
          photosToCompare.addAll(buckets[prefix]!);
        }
      }

      // 比较当前桶内的照片与所有相关照片
      for (final photo1 in currentBucket) {
        for (final photo2 in photosToCompare) {
          if (photo1.uniqueKey == photo2.uniqueKey) continue;
          if (find(photo1.uniqueKey) == find(photo2.uniqueKey)) continue;

          final distance = hammingDistance(
            photo1.perceptualHash!,
            photo2.perceptualHash!,
          );

          if (distance >= 0 && distance <= threshold) {
            union(photo1.uniqueKey, photo2.uniqueKey);
          }
        }
      }

      processed++;
      onProgress?.call(processed, totalBuckets);
    }

    // 收集分组结果
    final groups = <String, List<PhotoEntity>>{};
    for (final photo in photos) {
      final root = find(photo.uniqueKey);
      groups.putIfAbsent(root, () => []).add(photo);
    }

    // 只返回有多个照片的组，按组大小排序
    final result = groups.values
        .where((g) => g.length > 1)
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    logger.i('PhotoHashService: 找到 ${result.length} 组相似照片');
    return result;
  }

  /// 释放资源
  void dispose() {
    _progressController.close();
  }
}

/// 计算感知哈希（在 isolate 中运行）
/// 使用 dHash (Difference Hash) 算法，对旋转、缩放不太敏感
String _computePerceptualHash(Uint8List bytes) {
  try {
    // 解码图片
    final image = img.decodeImage(bytes);
    if (image == null) return '';

    // 缩放到 9x8（dHash 需要 9 列来计算 8 个差值）
    final resized = img.copyResize(image, width: 9, height: 8);

    // 转换为灰度
    final grayscale = img.grayscale(resized);

    // 计算 dHash
    final hash = StringBuffer();
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final left = grayscale.getPixel(x, y);
        final right = grayscale.getPixel(x + 1, y);
        // 比较相邻像素的亮度
        final leftLuminance = img.getLuminance(left);
        final rightLuminance = img.getLuminance(right);
        hash.write(leftLuminance < rightLuminance ? '1' : '0');
      }
    }

    // 将二进制字符串转换为十六进制
    final binary = hash.toString();
    final hexHash = StringBuffer();
    for (var i = 0; i < binary.length; i += 4) {
      final nibble = binary.substring(i, i + 4);
      hexHash.write(int.parse(nibble, radix: 2).toRadixString(16));
    }

    return hexHash.toString();
  } on Exception {
    return '';
  }
}

/// 计算两个感知哈希之间的汉明距离
/// 距离越小表示越相似
int hammingDistance(String hash1, String hash2) {
  if (hash1.length != hash2.length) return -1;
  if (hash1.isEmpty || hash2.isEmpty) return -1;

  var distance = 0;
  for (var i = 0; i < hash1.length; i++) {
    final int1 = int.parse(hash1[i], radix: 16);
    final int2 = int.parse(hash2[i], radix: 16);
    // 计算二进制位差异
    var xor = int1 ^ int2;
    while (xor > 0) {
      distance += xor & 1;
      xor >>= 1;
    }
  }
  return distance;
}

/// 判断两个哈希是否表示相似图片
/// [threshold] 汉明距离阈值，越小越严格（0=完全相同，推荐5-10）
bool areSimilar(String hash1, String hash2, {int threshold = 5}) {
  final distance = hammingDistance(hash1, hash2);
  return distance >= 0 && distance <= threshold;
}

/// 哈希计算进度
class HashProgress {
  const HashProgress({
    required this.processed,
    required this.total,
    required this.currentFile,
    required this.status,
    this.failed = 0,
    this.error,
  });

  final int processed;
  final int total;
  final int failed;
  final String currentFile;
  final HashStatus status;
  final String? error;

  double get progress => total > 0 ? processed / total : 0;
}

/// 哈希计算状态
enum HashStatus {
  idle,
  processing,
  completed,
  cancelled,
  error,
}
