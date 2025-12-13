import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_content_processor.dart';

/// 分块内容提供者
///
/// 将大型 HTML 内容分块管理，实现按需加载
/// 解决一次性加载导致的 WebView 渲染阻塞问题
class ChunkedContentProvider {
  ChunkedContentProvider({
    required this.fullContent,
    required this.chapters,
    this.maxChunkSize = 150000, // ~150KB per chunk, 约5万中文字符
    this.charsPerPage = 800, // 每页估计字符数
  }) {
    _initializeChunks();
  }

  final String fullContent;
  final List<BookChapter> chapters;
  final int maxChunkSize;
  final int charsPerPage;

  /// 分块边界列表 [start, end] 对应每个块的字符范围
  final List<_ChunkRange> _chunks = [];

  /// 估算的总页数
  late final int estimatedTotalPages;

  /// 总块数
  int get totalChunks => _chunks.length;

  /// 内容总长度
  int get totalLength => fullContent.length;

  /// 初始化分块
  void _initializeChunks() {
    final contentLength = fullContent.length;

    // 快速估算总页数
    estimatedTotalPages = (contentLength / charsPerPage).ceil().clamp(1, 100000);

    logger.i(
      'ChunkedContentProvider: 初始化 - '
      '总长度: $contentLength, '
      '估算页数: $estimatedTotalPages, '
      '块大小: $maxChunkSize',
    );

    // 如果内容较小，不分块
    if (contentLength <= maxChunkSize) {
      _chunks.add(_ChunkRange(0, contentLength));
      logger.d('ChunkedContentProvider: 内容较小，不分块');
      return;
    }

    // 按章节边界或固定大小分块
    var currentStart = 0;

    while (currentStart < contentLength) {
      var chunkEnd = currentStart + maxChunkSize;

      if (chunkEnd >= contentLength) {
        // 最后一块
        _chunks.add(_ChunkRange(currentStart, contentLength));
        break;
      }

      // 尝试在章节边界处分割
      final nearbyChapter = _findNearbyChapterBoundary(
        currentStart,
        chunkEnd,
      );

      if (nearbyChapter != null) {
        // 使用章节边界
        chunkEnd = nearbyChapter;
      } else {
        // 尝试在段落边界处分割（找最近的 </p> 或 </div>）
        final paragraphEnd = _findNearbyParagraphEnd(chunkEnd);
        if (paragraphEnd != null && paragraphEnd > currentStart) {
          chunkEnd = paragraphEnd;
        }
      }

      _chunks.add(_ChunkRange(currentStart, chunkEnd));
      currentStart = chunkEnd;
    }

    logger.i('ChunkedContentProvider: 分块完成 - ${_chunks.length} 个块');
  }

  /// 查找附近的章节边界
  int? _findNearbyChapterBoundary(int start, int end) {
    // 在当前块范围的后 20% 区域查找章节边界
    final searchStart = start + ((end - start) * 0.8).toInt();

    for (final chapter in chapters) {
      if (chapter.offset > searchStart && chapter.offset < end) {
        return chapter.offset;
      }
    }
    return null;
  }

  /// 查找附近的段落结束位置
  int? _findNearbyParagraphEnd(int position) {
    // 在位置前后 1000 字符内查找 </p> 或 </div>
    final searchStart = (position - 500).clamp(0, fullContent.length);
    final searchEnd = (position + 500).clamp(0, fullContent.length);

    final searchArea = fullContent.substring(searchStart, searchEnd);

    // 优先查找 </p>
    final pEnd = searchArea.lastIndexOf('</p>');
    if (pEnd != -1) {
      return searchStart + pEnd + 4; // 包含 </p>
    }

    // 其次查找 </div>
    final divEnd = searchArea.lastIndexOf('</div>');
    if (divEnd != -1) {
      return searchStart + divEnd + 6; // 包含 </div>
    }

    return null;
  }

  /// 获取指定块的内容
  String getChunk(int chunkIndex) {
    if (chunkIndex < 0 || chunkIndex >= _chunks.length) {
      logger.w('ChunkedContentProvider: 无效的块索引 $chunkIndex');
      return '';
    }

    final range = _chunks[chunkIndex];
    final content = fullContent.substring(range.start, range.end);

    logger.d(
      'ChunkedContentProvider: 获取块 $chunkIndex '
      '(${range.start}-${range.end}, ${content.length} 字符)',
    );

    return content;
  }

  /// 获取指定块及缓冲区的内容
  ///
  /// [chunkIndex] 当前块索引
  /// [bufferSize] 前后缓冲块数量，默认 1
  String getChunkWithBuffer(int chunkIndex, {int bufferSize = 1}) {
    final startChunk = (chunkIndex - bufferSize).clamp(0, _chunks.length - 1);
    final endChunk = (chunkIndex + bufferSize).clamp(0, _chunks.length - 1);

    final startRange = _chunks[startChunk];
    final endRange = _chunks[endChunk];

    return fullContent.substring(startRange.start, endRange.end);
  }

  /// 将页码转换为块索引
  int pageToChunkIndex(int page) {
    if (_chunks.isEmpty) return 0;

    // 估算每块的页数
    final pagesPerChunk = estimatedTotalPages / _chunks.length;
    final chunkIndex = (page / pagesPerChunk).floor();

    return chunkIndex.clamp(0, _chunks.length - 1);
  }

  /// 将字符偏移转换为块索引
  int offsetToChunkIndex(int offset) {
    for (var i = 0; i < _chunks.length; i++) {
      if (offset < _chunks[i].end) {
        return i;
      }
    }
    return _chunks.length - 1;
  }

  /// 获取块的页码范围 (估算)
  (int startPage, int endPage) getChunkPageRange(int chunkIndex) {
    if (_chunks.isEmpty) return (0, 0);

    final pagesPerChunk = estimatedTotalPages / _chunks.length;
    final startPage = (chunkIndex * pagesPerChunk).floor();
    final endPage = ((chunkIndex + 1) * pagesPerChunk).ceil() - 1;

    return (startPage, endPage.clamp(0, estimatedTotalPages - 1));
  }

  /// 获取块的字符范围
  (int start, int end) getChunkRange(int chunkIndex) {
    if (chunkIndex < 0 || chunkIndex >= _chunks.length) {
      return (0, 0);
    }
    final range = _chunks[chunkIndex];
    return (range.start, range.end);
  }

  /// 是否需要分块（内容是否足够大）
  bool get needsChunking => _chunks.length > 1;

  /// 获取用于初始显示的轻量内容
  /// 返回第一块内容，用于快速首次渲染
  String get initialChunk => getChunk(0);

  /// 获取估算的每块页数
  double get estimatedPagesPerChunk {
    if (_chunks.isEmpty) return estimatedTotalPages.toDouble();
    return estimatedTotalPages / _chunks.length;
  }
}

/// 块范围
class _ChunkRange {
  _ChunkRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;
}
