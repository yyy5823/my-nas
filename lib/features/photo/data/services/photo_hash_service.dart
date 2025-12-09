import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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
        final futures = <Future<PhotoEntity?>>[];
        for (final photo in photos) {
          if (_shouldCancel) break;
          futures.add(_processPhoto(photo, fileSystem));
        }

        final results = await Future.wait(futures);
        final successfulPhotos = results.whereType<PhotoEntity>().toList();

        if (successfulPhotos.isNotEmpty) {
          await _db.updateHashBatch(successfulPhotos);
          processed += successfulPhotos.length;
        }

        failed += results.where((r) => r == null).length;

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
    } on Exception catch (e) {
      logger.e('PhotoHashService: 处理失败', e);
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
  Future<PhotoEntity?> _processPhoto(
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
      if (bytes.isEmpty) return null;

      // 计算 MD5 哈希
      final fileHash = _computeMD5(bytes);

      // 计算感知哈希
      final perceptualHash = await compute(_computePerceptualHash, bytes);

      return photo.copyWith(
        fileHash: fileHash,
        perceptualHash: perceptualHash,
      );
    } on Exception catch (e) {
      logger.w('PhotoHashService: 处理照片失败 ${photo.filePath}: $e');
      return null;
    }
  }

  /// 计算 MD5 哈希
  String _computeMD5(Uint8List bytes) {
    final digest = md5.convert(bytes);
    return digest.toString();
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
