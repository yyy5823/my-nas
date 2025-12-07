import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui
    show Color, Image, ImageByteFormat, PixelFormat, decodeImageFromPixels;

import 'package:epub_decoder/epub_decoder.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// 用于等待图片解码完成的辅助类
class _ImageCompleter {
  final _completer = Completer<ui.Image?>();

  Future<ui.Image?> get future => _completer.future;

  void complete(ui.Image image) {
    if (!_completer.isCompleted) {
      _completer.complete(image);
    }
  }
}

/// 图书封面提取服务
///
/// 支持从 EPUB 和 PDF 文件中提取封面图片
class BookCoverService {
  static const String _boxName = 'book_covers';
  static const String _coverDir = 'book_covers';

  Box<String>? _box;
  String? _coverDirPath;

  /// 初始化服务
  Future<void> init() async {
    if (_box != null) return;

    _box = await Hive.openBox<String>(_boxName);

    // 创建封面缓存目录
    final appDir = await getApplicationDocumentsDirectory();
    _coverDirPath = path.join(appDir.path, _coverDir);
    final dir = Directory(_coverDirPath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// 获取封面路径（如果已缓存）
  String? getCachedCoverPath(String bookPath, String sourceId) {
    final key = _generateKey(bookPath, sourceId);
    return _box?.get(key);
  }

  /// 提取并缓存封面
  Future<String?> extractAndCacheCover({
    required String bookPath,
    required String sourceId,
    required BookFormat format,
    required NasFileSystem fileSystem,
  }) async {
    await init();

    final key = _generateKey(bookPath, sourceId);

    // 检查是否已缓存
    final cached = _box?.get(key);
    if (cached != null && await File(cached).exists()) {
      return cached;
    }

    try {
      Uint8List? coverBytes;

      switch (format) {
        case BookFormat.epub:
          coverBytes = await _extractEpubCover(bookPath, fileSystem);
        case BookFormat.pdf:
          coverBytes = await _extractPdfCover(bookPath, fileSystem);
        case BookFormat.txt:
        case BookFormat.mobi:
        case BookFormat.azw3:
        case BookFormat.unknown:
          return null;
      }

      if (coverBytes == null || coverBytes.isEmpty) {
        return null;
      }

      // 保存封面到本地
      final coverPath = await _saveCover(key, coverBytes);
      if (coverPath != null) {
        await _box?.put(key, coverPath);
      }
      return coverPath;
    } on Exception catch (e) {
      logger.w('提取图书封面失败: $bookPath', e);
      return null;
    }
  }

  /// 从 EPUB 文件提取封面
  Future<Uint8List?> _extractEpubCover(
    String bookPath,
    NasFileSystem fileSystem,
  ) async {
    try {
      final stream = await fileSystem.getFileStream(bookPath);
      final bytes = <int>[];
      await for (final chunk in stream) {
        bytes.addAll(chunk);
        if (bytes.length > 50 * 1024 * 1024) {
          logger.w('EPUB 文件过大，跳过封面提取: $bookPath');
          return null;
        }
      }

      final epub = Epub.fromBytes(Uint8List.fromList(bytes));
      final cover = epub.cover;

      if (cover == null) {
        logger.d('EPUB 没有封面: $bookPath');
        return null;
      }

      // 安全获取封面内容
      // epub_decoder 在文件不存在时会抛出断言错误，需要捕获所有错误
      final Uint8List coverBytes;
      try {
        coverBytes = cover.fileContent;
        // ignore: avoid_catches_without_on_clauses
      } on Object catch (e) {
        // 捕获所有错误（包括 AssertionError，它是 Error 的子类）
        logger.w('EPUB 封面文件不存在或无法读取: $bookPath', e);
        return null;
      }

      // 验证是否为有效图片数据（检查常见图片格式的魔数）
      if (_isValidImageData(coverBytes)) {
        return coverBytes;
      }
      logger.w('EPUB 封面数据无效: $bookPath');
      return null;
    } on Exception catch (e) {
      logger.w('提取 EPUB 封面失败: $bookPath', e);
      return null;
    }
  }

  /// 从 PDF 文件提取封面（渲染第一页）
  Future<Uint8List?> _extractPdfCover(
    String bookPath,
    NasFileSystem fileSystem,
  ) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = path.basename(bookPath);
      final tempFile = File(path.join(tempDir.path, 'cover_$fileName'));

      final stream = await fileSystem.getFileStream(bookPath);
      final bytes = <int>[];
      await for (final chunk in stream) {
        bytes.addAll(chunk);
        if (bytes.length > 100 * 1024 * 1024) {
          logger.w('PDF 文件过大，跳过封面提取: $bookPath');
          return null;
        }
      }
      await tempFile.writeAsBytes(bytes);

      final doc = await PdfDocument.openFile(tempFile.path);
      if (doc.pages.isEmpty) {
        await tempFile.delete().catchError((_) => tempFile);
        return null;
      }

      final page = doc.pages[0];
      final pdfImage = await page.render(
        width: 300,
        height: 400,
        backgroundColor: const ui.Color(0xFFFFFFFF),
      );

      await tempFile.delete().catchError((_) => tempFile);

      if (pdfImage == null || pdfImage.pixels.isEmpty) {
        return null;
      }

      // 将原始像素数据转换为 PNG 格式
      final pngBytes = await _convertRgbaToPng(
        pdfImage.pixels,
        pdfImage.width,
        pdfImage.height,
      );
      return pngBytes;
    } on Exception catch (e) {
      logger.w('提取 PDF 封面失败: $bookPath', e);
      return null;
    }
  }

  /// 将 RGBA 像素数据转换为 PNG 格式
  Future<Uint8List?> _convertRgbaToPng(
    Uint8List pixels,
    int width,
    int height,
  ) async {
    try {
      // 使用 dart:ui 创建图片并编码为 PNG
      final completer = _ImageCompleter();
      ui.decodeImageFromPixels(
        pixels,
        width,
        height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final image = await completer.future;
      if (image == null) return null;

      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } on Exception catch (e) {
      logger.w('转换 PDF 封面为 PNG 失败', e);
      return null;
    }
  }

  /// 保存封面到本地文件
  Future<String?> _saveCover(String key, Uint8List bytes) async {
    try {
      final fileName = '${key.hashCode.abs()}.jpg';
      final filePath = path.join(_coverDirPath!, fileName);
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return filePath;
    } on Exception catch (e) {
      logger.w('保存封面失败: $key', e);
      return null;
    }
  }

  /// 生成缓存键
  String _generateKey(String bookPath, String sourceId) =>
      '${sourceId}_$bookPath';

  /// 清除所有缓存
  Future<void> clearCache() async {
    await init();
    await _box?.clear();

    if (_coverDirPath != null) {
      final dir = Directory(_coverDirPath!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    }
  }

  /// 删除指定源的所有封面缓存
  Future<void> deleteBySourceId(String sourceId) async {
    await init();

    final keysToDelete = <String>[];
    for (final key in _box?.keys ?? <String>[]) {
      if (key.toString().startsWith('${sourceId}_')) {
        keysToDelete.add(key.toString());
      }
    }

    for (final key in keysToDelete) {
      final coverPath = _box?.get(key);
      if (coverPath != null) {
        await File(coverPath).delete().catchError((_) => File(coverPath));
      }
      await _box?.delete(key);
    }
  }

  /// 验证是否为有效的图片数据
  ///
  /// 检查常见图片格式的魔数（文件头）
  bool _isValidImageData(Uint8List bytes) {
    if (bytes.length < 8) return false;

    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true;
    }

    // GIF: 47 49 46 38
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return true;
    }

    // WebP: 52 49 46 46 ... 57 45 42 50
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }

    // BMP: 42 4D
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return true;
    }

    return false;
  }
}
