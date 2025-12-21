import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:path/path.dart' as path;

/// EPUB 图片页面
class EpubImagePage {
  const EpubImagePage({
    required this.index,
    required this.name,
    required this.data,
    required this.mimeType,
  });

  final int index;
  final String name;
  final Uint8List data;
  final String mimeType;
}

/// EPUB 图片提取器
///
/// 从 EPUB 文件中提取图片，用于漫画阅读器
class EpubImageExtractor {
  EpubImageExtractor._();
  static final EpubImageExtractor instance = EpubImageExtractor._();

  /// 支持的图片格式
  static const _imageExtensions = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.bmp': 'image/bmp',
  };

  /// 从 EPUB 文件提取所有图片
  Future<List<EpubImagePage>> extractImages(File epubFile) async {
    try {
      logger.d('EpubImageExtractor: 开始提取图片 ${epubFile.path}');
      
      final bytes = await epubFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final images = <EpubImagePage>[];
      var index = 0;

      // 提取所有图片文件
      final imageFiles = archive.files
          .where((f) => f.isFile && _isImageFile(f.name))
          .toList()
        // 按名称排序以保持页面顺序
        ..sort((a, b) => _naturalSort(a.name, b.name));

      for (final file in imageFiles) {
        final ext = path.extension(file.name).toLowerCase();
        final mimeType = _imageExtensions[ext] ?? 'image/jpeg';
        
        images.add(EpubImagePage(
          index: index++,
          name: path.basename(file.name),
          data: Uint8List.fromList(file.content as List<int>),
          mimeType: mimeType,
        ));
      }

      logger.i('EpubImageExtractor: 提取完成，共 ${images.length} 张图片');
      return images;
    } on Exception catch (e, st) {
      logger.e('EpubImageExtractor: 提取图片失败', e, st);
      rethrow;
    }
  }

  /// 分批提取图片（用于大文件）
  ///
  /// [startIndex] 起始索引
  /// [count] 提取数量
  Future<List<EpubImagePage>> extractImagesBatch(
    File epubFile, {
    required int startIndex,
    required int count,
  }) async {
    try {
      final bytes = await epubFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final imageFiles = archive.files
          .where((f) => f.isFile && _isImageFile(f.name))
          .toList()
        ..sort((a, b) => _naturalSort(a.name, b.name));

      final images = <EpubImagePage>[];
      final endIndex = (startIndex + count).clamp(0, imageFiles.length);

      for (var i = startIndex; i < endIndex; i++) {
        final file = imageFiles[i];
        final ext = path.extension(file.name).toLowerCase();
        final mimeType = _imageExtensions[ext] ?? 'image/jpeg';
        
        images.add(EpubImagePage(
          index: i,
          name: path.basename(file.name),
          data: Uint8List.fromList(file.content as List<int>),
          mimeType: mimeType,
        ));
      }

      return images;
    } on Exception catch (e, st) {
      logger.e('EpubImageExtractor: 分批提取图片失败', e, st);
      rethrow;
    }
  }

  /// 获取 EPUB 中的图片总数
  Future<int> getImageCount(File epubFile) async {
    try {
      final bytes = await epubFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      return archive.files
          .where((f) => f.isFile && _isImageFile(f.name))
          .length;
    } on Exception catch (e) {
      logger.w('EpubImageExtractor: 获取图片数量失败: $e');
      return 0;
    }
  }

  /// 获取单张图片
  Future<EpubImagePage?> getImage(File epubFile, int index) async {
    try {
      final bytes = await epubFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final imageFiles = archive.files
          .where((f) => f.isFile && _isImageFile(f.name))
          .toList()
        ..sort((a, b) => _naturalSort(a.name, b.name));

      if (index < 0 || index >= imageFiles.length) return null;

      final file = imageFiles[index];
      final ext = path.extension(file.name).toLowerCase();
      final mimeType = _imageExtensions[ext] ?? 'image/jpeg';

      return EpubImagePage(
        index: index,
        name: path.basename(file.name),
        data: Uint8List.fromList(file.content as List<int>),
        mimeType: mimeType,
      );
    } on Exception catch (e) {
      logger.w('EpubImageExtractor: 获取图片失败: $e');
      return null;
    }
  }

  /// 判断是否为图片文件
  bool _isImageFile(String filename) {
    final ext = path.extension(filename).toLowerCase();
    return _imageExtensions.containsKey(ext);
  }

  /// 自然排序比较（处理数字）
  int _naturalSort(String a, String b) {
    final regExp = RegExp(r'(\d+)');
    final aMatches = regExp.allMatches(a).toList();
    final bMatches = regExp.allMatches(b).toList();

    // 如果都没有数字，直接比较字符串
    if (aMatches.isEmpty && bMatches.isEmpty) {
      return a.compareTo(b);
    }

    // 提取最后一个数字进行比较
    if (aMatches.isNotEmpty && bMatches.isNotEmpty) {
      final aNum = int.tryParse(aMatches.last.group(0)!) ?? 0;
      final bNum = int.tryParse(bMatches.last.group(0)!) ?? 0;
      if (aNum != bNum) return aNum.compareTo(bNum);
    }

    return a.compareTo(b);
  }
}
