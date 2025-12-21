import 'dart:io';

import 'package:archive/archive.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';

/// 漫画检测服务
///
/// 检测电子书是否为漫画类型，支持多种检测策略：
/// 1. 路径关键词检测
/// 2. EPUB 内容分析（图片/文本比例）
class MangaDetector {
  MangaDetector._();
  static final MangaDetector instance = MangaDetector._();

  /// 漫画相关路径关键词
  static const _mangaKeywords = [
    '漫画',
    'manga',
    'comic',
    'comics',
    '漫畫',
    'コミック',
    'まんが',
    'マンガ',
    '동만',
    '만화',
  ];

  /// 图片文件扩展名
  static const _imageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
  ];

  /// 判断是否为漫画
  ///
  /// 优先使用路径检测（快速），如果不确定再分析内容
  Future<bool> isManga(BookItem book, {File? cachedFile}) async {
    // 1. 路径关键词检测（最快）
    if (detectByPath(book.path)) {
      logger.d('MangaDetector: 路径检测 - 是漫画: ${book.name}');
      return true;
    }

    // 2. 如果是 EPUB 且有缓存文件，分析内容
    if (book.format == BookFormat.epub && cachedFile != null) {
      try {
        final result = await detectByEpubContent(cachedFile);
        logger.d('MangaDetector: 内容检测 - ${result ? "是" : "不是"}漫画: ${book.name}');
        return result;
      } on Exception catch (e) {
        logger.w('MangaDetector: 内容检测失败: $e');
      }
    }

    // 3. 大文件 EPUB/MOBI 可能是漫画（启发式判断）
    // 超过 20MB 的电子书很可能是漫画
    if (_isLargeEbook(book)) {
      logger.d('MangaDetector: 大文件检测 - 可能是漫画: ${book.name} (${book.displaySize})');
      return true;
    }

    return false;
  }

  /// 通过路径关键词检测
  bool detectByPath(String path) {
    final lowerPath = path.toLowerCase();
    return _mangaKeywords.any((keyword) => lowerPath.contains(keyword.toLowerCase()));
  }

  /// 通过 EPUB 内容分析检测
  ///
  /// 分析 EPUB 中图片与文本文件的比例
  /// 如果图片占比超过 70%，则认为是漫画
  Future<bool> detectByEpubContent(File epubFile) async {
    try {
      final bytes = await epubFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      var imageCount = 0;
      var textCount = 0;
      var totalImageSize = 0;
      var totalTextSize = 0;

      for (final file in archive) {
        if (file.isFile) {
          final name = file.name.toLowerCase();
          final size = file.size;

          if (_isImageFile(name)) {
            imageCount++;
            totalImageSize += size;
          } else if (_isTextFile(name)) {
            textCount++;
            totalTextSize += size;
          }
        }
      }

      // 漫画特征判断：
      // 1. 图片数量 >= 10
      // 2. 图片大小占总内容 70% 以上
      // 3. 或者图片数量远超文本文件
      final totalSize = totalImageSize + totalTextSize;
      final imageRatio = totalSize > 0 ? totalImageSize / totalSize : 0;
      final isManga = (imageCount >= 10 && imageRatio > 0.7) || 
                      (imageCount >= 20 && imageCount > textCount * 3);

      logger.d('MangaDetector: EPUB 分析 - 图片:$imageCount 文本:$textCount '
               '图片占比:${(imageRatio * 100).toStringAsFixed(1)}%');

      return isManga;
    } on Exception catch (e) {
      logger.w('MangaDetector: 解析 EPUB 失败: $e');
      return false;
    }
  }

  /// 判断是否为大型电子书文件
  bool _isLargeEbook(BookItem book) {
    const largeSizeThreshold = 20 * 1024 * 1024; // 20MB
    return (book.format == BookFormat.epub ||
            book.format == BookFormat.mobi ||
            book.format == BookFormat.azw3) &&
           book.size > largeSizeThreshold;
  }

  /// 判断是否为图片文件
  bool _isImageFile(String filename) {
    return _imageExtensions.any((ext) => filename.endsWith(ext));
  }

  /// 判断是否为文本文件
  bool _isTextFile(String filename) {
    return filename.endsWith('.html') ||
           filename.endsWith('.xhtml') ||
           filename.endsWith('.htm') ||
           filename.endsWith('.xml');
  }
}
