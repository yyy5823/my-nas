import 'dart:async';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/book/data/services/book_file_cache_service.dart';
import 'package:my_nas/features/book/data/services/book_metadata_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 图书预加载服务
/// 在后台预下载 EPUB/MOBI 文件，提升打开速度
/// 同时提取元数据并保存到数据库
class BookPreloadService {
  factory BookPreloadService() => _instance ??= BookPreloadService._();
  BookPreloadService._();

  static BookPreloadService? _instance;

  final BookFileCacheService _cacheService = BookFileCacheService();
  final BookMetadataService _metadataService = BookMetadataService();
  final BookDatabaseService _db = BookDatabaseService();

  /// 当前预加载队列
  final List<_PreloadTask> _queue = [];

  /// 正在进行的预加载任务
  _PreloadTask? _currentTask;

  /// 是否正在运行
  bool _isRunning = false;

  /// 最大预加载文件大小（50MB）
  static const int maxPreloadSize = 50 * 1024 * 1024;

  /// 预加载优先级格式（EPUB 和 MOBI 需要完整下载才能阅读）
  static const _priorityFormats = [
    BookFormat.epub,
    BookFormat.mobi,
    BookFormat.azw3,
  ];

  /// 初始化服务
  Future<void> init() async {
    await _cacheService.init();
    await _metadataService.init();
    await _db.init();
  }

  /// 添加预加载任务
  /// [books] 要预加载的图书列表
  /// [fileSystemProvider] 获取文件系统的回调
  void enqueue(
    List<BookEntity> books,
    NasFileSystem? Function(String sourceId) fileSystemProvider,
  ) {
    // 过滤出需要预加载的图书
    final toPreload = books.where((book) {
      // 只预加载优先格式
      if (!_priorityFormats.contains(book.format)) return false;
      // 跳过太大的文件
      if (book.size > maxPreloadSize) return false;
      return true;
    }).toList();

    // 按格式优先级排序
    toPreload.sort((a, b) => _priorityFormats.indexOf(a.format).compareTo(
          _priorityFormats.indexOf(b.format),
        ));

    // 添加到队列
    for (final book in toPreload) {
      // 检查是否已在队列中
      final exists = _queue.any(
        (t) => t.book.sourceId == book.sourceId && t.book.filePath == book.filePath,
      );
      if (!exists) {
        _queue.add(_PreloadTask(
          book: book,
          fileSystemProvider: fileSystemProvider,
        ));
      }
    }

    logger.d('BookPreloadService: 添加 ${toPreload.length} 个预加载任务，队列长度: ${_queue.length}');

    // 启动预加载
    _startProcessing();
  }

  /// 清空队列
  void clearQueue() {
    _queue.clear();
    logger.d('BookPreloadService: 队列已清空');
  }

  /// 停止预加载
  void stop() {
    _isRunning = false;
    _queue.clear();
    _currentTask = null;
    logger.d('BookPreloadService: 已停止');
  }

  /// 开始处理队列
  void _startProcessing() {
    if (_isRunning) return;
    _isRunning = true;
    unawaited(_processQueue());
  }

  /// 处理队列
  Future<void> _processQueue() async {
    while (_isRunning && _queue.isNotEmpty) {
      _currentTask = _queue.removeAt(0);
      final task = _currentTask!;

      try {
        await _processTask(task);
      } on Exception catch (e) {
        logger.d('BookPreloadService: 预加载失败 ${task.book.fileName} - $e');
      }

      // 短暂延迟，避免占用太多资源
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    _isRunning = false;
    _currentTask = null;
    logger.d('BookPreloadService: 队列处理完成');
  }

  /// 处理单个任务
  Future<void> _processTask(_PreloadTask task) async {
    final book = task.book;

    // 检查是否已缓存
    final isCached = await _cacheService.isCached(book.sourceId, book.filePath);
    if (isCached) {
      logger.d('BookPreloadService: 已缓存，跳过 ${book.fileName}');
      return;
    }

    // 获取文件系统
    final fileSystem = task.fileSystemProvider(book.sourceId);
    if (fileSystem == null) {
      logger.d('BookPreloadService: 无法获取文件系统 ${book.sourceId}');
      return;
    }

    logger.d('BookPreloadService: 开始预加载 ${book.fileName}');

    // 下载文件
    final stream = await fileSystem.getFileStream(book.filePath);
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      // 检查是否超过大小限制
      if (bytes.length > maxPreloadSize) {
        logger.d('BookPreloadService: 文件过大，停止下载 ${book.fileName}');
        return;
      }
    }

    // 保存到缓存
    await _cacheService.saveToCache(book.sourceId, book.filePath, bytes);
    logger.i('BookPreloadService: 预加载完成 ${book.fileName} (${bytes.length} bytes)');
  }
}

/// 预加载任务
class _PreloadTask {
  _PreloadTask({
    required this.book,
    required this.fileSystemProvider,
  });

  final BookEntity book;
  final NasFileSystem? Function(String sourceId) fileSystemProvider;
}

