import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:epub_plus/epub_plus.dart';
import 'package:image/image.dart' as img;
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/mobi_parser_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// 图书元数据
class BookMetadata {
  const BookMetadata({
    this.title,
    this.author,
    this.description,
    this.coverData,
    this.totalPages,
  });

  final String? title;
  final String? author;
  final String? description;
  final Uint8List? coverData;
  final int? totalPages;

  bool get hasCover => coverData != null && coverData!.isNotEmpty;
}

/// 图书元数据服务
/// 用于从各种格式的图书中提取元数据（标题、作者、封面等）
class BookMetadataService {
  factory BookMetadataService() => _instance ??= BookMetadataService._();
  BookMetadataService._();

  static BookMetadataService? _instance;

  late Directory _coverCacheDir;
  bool _initialized = false;

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;

    final appDir = await getApplicationSupportDirectory();
    _coverCacheDir = Directory(p.join(appDir.path, 'book_covers'));
    if (!await _coverCacheDir.exists()) {
      await _coverCacheDir.create(recursive: true);
    }

    _initialized = true;
    logger.i('BookMetadataService: 初始化完成，封面缓存目录: ${_coverCacheDir.path}');
  }

  /// 从 NAS 文件提取元数据
  Future<BookMetadata?> extractFromNasFile(
    NasFileSystem fileSystem,
    String filePath,
    BookFormat format,
  ) async {
    if (!_initialized) await init();

    try {
      switch (format) {
        case BookFormat.epub:
          return _extractEpubMetadata(fileSystem, filePath);
        case BookFormat.pdf:
          return _extractPdfMetadata(fileSystem, filePath);
        case BookFormat.mobi:
        case BookFormat.azw3:
          return _extractMobiMetadata(fileSystem, filePath);
        case BookFormat.txt:
          return const BookMetadata();
        case BookFormat.unknown:
          return null;
      }
    } on Exception catch (e, stackTrace) {
      logger.w('BookMetadataService: 提取元数据失败: $filePath', e, stackTrace);
      return null;
    }
  }

  /// 提取 EPUB 元数据
  Future<BookMetadata?> _extractEpubMetadata(
    NasFileSystem fileSystem,
    String filePath,
  ) async {
    try {
      final stream = await fileSystem.getFileStream(
        filePath,
        range: const FileRange(start: 0, end: 5 * 1024 * 1024),
      );

      final bytes = <int>[];
      await for (final chunk in stream) {
        bytes.addAll(chunk);
      }

      final epubBook = await EpubReader.readBook(bytes);

      Uint8List? coverData;
      final coverImage = epubBook.coverImage;
      if (coverImage != null) {
        final pngBytes = img.encodePng(coverImage);
        coverData = Uint8List.fromList(pngBytes);
      }

      // 尝试从 OPF 元数据中获取描述
      String? description;
      try {
        final dcDescription = epubBook.schema?.package?.metadata?.description;
        if (dcDescription != null && dcDescription.isNotEmpty) {
          description = dcDescription;
        }
      } on Exception catch (_) {
        // 忽略描述提取错误
      }

      return BookMetadata(
        title: epubBook.title,
        author: epubBook.authors.isNotEmpty
            ? epubBook.authors.whereType<String>().join(', ')
            : null,
        description: description,
        coverData: coverData,
      );
    } on Exception catch (e) {
      logger.d('BookMetadataService: EPUB 元数据提取失败: $filePath - $e');
      return null;
    }
  }

  /// 提取 PDF 元数据
  Future<BookMetadata?> _extractPdfMetadata(
    NasFileSystem fileSystem,
    String filePath,
  ) async {
    try {
      final url = await fileSystem.getFileUrl(filePath);
      final uri = Uri.parse(url);

      final documentRef = PdfDocumentRefUri(uri, preferRangeAccess: true);
      final listenable = documentRef.resolveListenable();
      final completer = Completer<PdfDocument?>();

      void listener() {
        final doc = listenable.document;
        if (doc != null && !completer.isCompleted) {
          completer.complete(doc);
        }
      }

      listenable
        ..addListener(listener)
        // 触发加载
        ..document;

      final document = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );

      listenable.removeListener(listener);

      if (document == null) return null;

      // pdfrx 不支持直接获取 PDF 元数据（标题、作者）
      // 只能获取页数
      return BookMetadata(
        totalPages: document.pages.length,
      );
    } on Exception catch (e) {
      logger.d('BookMetadataService: PDF 元数据提取失败: $filePath - $e');
      return null;
    }
  }

  /// 提取 MOBI/AZW3 元数据
  Future<BookMetadata?> _extractMobiMetadata(
    NasFileSystem fileSystem,
    String filePath,
  ) async {
    try {
      final stream = await fileSystem.getFileStream(
        filePath,
        range: const FileRange(start: 0, end: 1024 * 1024),
      );

      final bytes = <int>[];
      await for (final chunk in stream) {
        bytes.addAll(chunk);
      }

      final mobiParser = MobiParserService();
      final result = await mobiParser.parse(
        Uint8List.fromList(bytes),
        p.basename(filePath),
      );

      if (!result.success) return null;

      final coverData = await mobiParser.extractCover(Uint8List.fromList(bytes));

      return BookMetadata(
        title: result.title,
        author: result.author,
        coverData: coverData,
      );
    } on Exception catch (e) {
      logger.d('BookMetadataService: MOBI 元数据提取失败: $filePath - $e');
      return null;
    }
  }

  /// 保存封面到缓存
  Future<String?> saveCoverToCache(
    String sourceId,
    String filePath,
    Uint8List coverData,
  ) async {
    if (!_initialized) await init();

    try {
      final hash = filePath.hashCode.toRadixString(16);
      final coverPath = p.join(
        _coverCacheDir.path,
        '${sourceId}_$hash.png',
      );

      final file = File(coverPath);
      await file.writeAsBytes(coverData);

      return coverPath;
    } on Exception catch (e) {
      logger.w('BookMetadataService: 保存封面失败', e);
      return null;
    }
  }

  /// 获取缓存的封面路径
  String? getCachedCoverPath(String sourceId, String filePath) {
    if (!_initialized) return null;

    final hash = filePath.hashCode.toRadixString(16);
    final coverPath = p.join(
      _coverCacheDir.path,
      '${sourceId}_$hash.png',
    );

    final file = File(coverPath);
    if (file.existsSync()) {
      return coverPath;
    }
    return null;
  }

  /// 清理封面缓存
  Future<void> clearCoverCache() async {
    if (!_initialized) await init();

    try {
      final files = _coverCacheDir.listSync();
      for (final file in files) {
        if (file is File) {
          await file.delete();
        }
      }
      logger.i('BookMetadataService: 封面缓存已清理');
    } on Exception catch (e) {
      logger.w('BookMetadataService: 清理封面缓存失败', e);
    }
  }
}
