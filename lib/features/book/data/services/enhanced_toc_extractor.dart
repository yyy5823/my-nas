import 'dart:math';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_content_processor.dart';

/// 目录提取结果
class TocExtractionResult {
  TocExtractionResult({
    required this.confidence, required this.method, this.tocSection,
  });

  factory TocExtractionResult.empty() => TocExtractionResult(
        confidence: 0,
        method: 'none',
      );

  final TocSection? tocSection;
  final double confidence; // 0-1 置信度
  final String method; // 识别方法

  bool get hasValidToc => tocSection != null && confidence > 0.6;
}

/// 目录区域
class TocSection {
  TocSection({
    required this.startOffset,
    required this.endOffset,
    required this.content,
    required this.chapters,
  });

  final int startOffset;
  final int endOffset;
  final String content;
  final List<BookChapter> chapters;

  int get length => endOffset - startOffset;
}

/// 增强的目录提取器
/// 使用多种策略识别和提取电子书目录
class EnhancedTocExtractor {
  EnhancedTocExtractor._();

  /// 提取目录的多策略方法
  /// 综合使用多种识别策略,选择置信度最高的结果
  static TocExtractionResult extractToc(String htmlContent) {
    if (htmlContent.length < 1000) {
      return TocExtractionResult.empty();
    }

    final results = <TocExtractionResult>[]

    // 策略1: 基于关键词识别
    ..add(_extractByKeywords(htmlContent))

    // 策略2: 基于结构模式识别 (密集的超链接或标题)
    ..add(_extractByStructure(htmlContent))

    // 策略3: 基于语义标签识别 (nav/aside/div.toc)
    ..add(_extractBySemantic(htmlContent));

    // 选择置信度最高的结果
    return _selectBestResult(results);
  }

  /// 基于关键词识别目录
  static TocExtractionResult _extractByKeywords(String html) {
    // 常见目录关键词模式
    final tocPatterns = [
      r'<h[1-3][^>]*>\s*目\s*录\s*</h[1-3]>',
      r'<h[1-3][^>]*>\s*Table\s+of\s+Contents\s*</h[1-3]>',
      r'<h[1-3][^>]*>\s*Contents\s*</h[1-3]>',
      r'<h[1-3][^>]*>\s*目\s*次\s*</h[1-3]>',
      r'<p[^>]*>\s*目\s*录\s*</p>',
      r'<div[^>]*>\s*目\s*录\s*</div>',
    ];

    for (final pattern in tocPatterns) {
      final match = RegExp(pattern, caseSensitive: false).firstMatch(html);
      if (match != null) {
        final tocSection = _extractTocSection(html, match.start);

        // 验证提取的目录是否有效
        if (tocSection != null && _validateTocSection(tocSection, html)) {
          final confidence = _calculateConfidence(tocSection, html);
          logger.i('关键词识别到目录: offset=${match.start}, confidence=$confidence');

          return TocExtractionResult(
            tocSection: tocSection,
            confidence: confidence,
            method: 'keyword',
          );
        }
      }
    }

    return TocExtractionResult.empty();
  }

  /// 基于结构模式识别 (查找密集的章节标题或链接)
  static TocExtractionResult _extractByStructure(String html) {
    // 只在前 30% 内容中查找
    final searchEnd = (html.length * 0.3).toInt();
    final searchArea = html.substring(0, searchEnd);

    // 查找连续的标题或链接模式
    final linkPattern = RegExp(r'<a[^>]*href[^>]*>.*?</a>', dotAll: true);
    final headingPattern = RegExp(r'<h[4-6][^>]*>.*?</h[4-6]>', dotAll: true);

    var maxDensity = 0.0;
    var tocStart = -1;
    const blockSize = 800; // 分析块大小
    const step = 200; // 滑动步长

    // 滑动窗口分析密度
    for (var i = 0; i < searchArea.length - blockSize; i += step) {
      final block = searchArea.substring(
        i,
        min(i + blockSize, searchArea.length),
      );

      final linkCount = linkPattern.allMatches(block).length;
      final headingCount = headingPattern.allMatches(block).length;

      // 计算密度 (链接和小标题的密度)
      final density = (linkCount * 1.5 + headingCount * 2) / blockSize;

      // 找到密度最高的区域
      if (density > maxDensity && density > 0.08) {
        // 至少 8% 密度
        maxDensity = density;
        tocStart = i;
      }
    }

    if (tocStart >= 0) {
      final tocSection = _extractTocSection(html, tocStart);

      if (tocSection != null && _validateTocSection(tocSection, html)) {
        final confidence = min(maxDensity * 8, 0.95); // 密度转置信度
        logger.i('结构模式识别到目录: offset=$tocStart, density=$maxDensity');

        return TocExtractionResult(
          tocSection: tocSection,
          confidence: confidence,
          method: 'structure',
        );
      }
    }

    return TocExtractionResult.empty();
  }

  /// 基于语义标签识别 (nav/aside 等 HTML5 语义标签)
  static TocExtractionResult _extractBySemantic(String html) {
    // 查找语义化目录容器
    final semanticPatterns = [
      r'<nav[^>]*class="[^"]*toc[^"]*"[^>]*>.*?</nav>',
      r'<div[^>]*class="[^"]*toc[^"]*"[^>]*>.*?</div>',
      r'<div[^>]*id="[^"]*toc[^"]*"[^>]*>.*?</div>',
      r'<aside[^>]*>.*?</aside>',
      r'<nav[^>]*>.*?</nav>',
    ];

    for (final pattern in semanticPatterns) {
      final match = RegExp(pattern, caseSensitive: false, dotAll: true)
          .firstMatch(html);

      if (match != null) {
        final matchContent = match.group(0)!;

        // 检查是否包含章节链接或标题
        final hasLinks = RegExp(r'<a[^>]*href').hasMatch(matchContent);
        final hasHeadings = RegExp(r'<h[1-6]').hasMatch(matchContent);

        if (hasLinks || hasHeadings) {
          final tocSection = _extractTocSection(html, match.start);

          if (tocSection != null && _validateTocSection(tocSection, html)) {
            final confidence = 0.85; // 语义标签置信度较高
            logger.i('语义标签识别到目录: offset=${match.start}');

            return TocExtractionResult(
              tocSection: tocSection,
              confidence: confidence,
              method: 'semantic',
            );
          }
        }
      }
    }

    return TocExtractionResult.empty();
  }

  /// 提取目录区域
  static TocSection? _extractTocSection(String html, int startPos) {
    // 向前查找容器标签开始
    final sectionStart = _findContainerStart(html, startPos);

    // 向后查找目录结束
    final sectionEnd = _findTocEnd(html, startPos);

    if (sectionEnd <= sectionStart) return null;

    final content = html.substring(sectionStart, sectionEnd);

    // 从目录内容中提取章节列表
    final chapters = _extractChaptersFromToc(content, sectionStart);

    return TocSection(
      startOffset: sectionStart,
      endOffset: sectionEnd,
      content: content,
      chapters: chapters,
    );
  }

  /// 向前查找容器开始标签
  static int _findContainerStart(String html, int pos) {
    var searchPos = pos;

    // 向前最多查找1000个字符
    final searchStart = max(0, pos - 1000);

    // 查找最近的块级元素开始标签
    final containerPattern = RegExp(
      r'<(div|section|nav|aside|article)[^>]*>',
      caseSensitive: false,
    );

    final searchArea = html.substring(searchStart, pos);
    final matches = containerPattern.allMatches(searchArea);

    if (matches.isNotEmpty) {
      final lastMatch = matches.last;
      return searchStart + lastMatch.start;
    }

    // 如果没找到容器,向前查找最近的 < 符号
    while (searchPos > searchStart && html[searchPos] != '<') {
      searchPos--;
    }

    return searchPos;
  }

  /// 查找目录结束位置
  static int _findTocEnd(String html, int startPos) {
    // 只在前 30% 范围内查找
    final searchEnd = min((html.length * 0.3).toInt(), html.length);
    if (startPos >= searchEnd) return startPos + 500;

    // 策略1: 查找目录后第一个长段落 (>300字符)
    final longParaPattern = RegExp(
      r'<p[^>]*>(.{300,}?)</p>',
      dotAll: true,
    );

    final searchArea = html.substring(startPos, searchEnd);
    final match = longParaPattern.firstMatch(searchArea);

    if (match != null) {
      return startPos + match.start;
    }

    // 策略2: 查找连续的 h1/h2 标签 (正文章节)
    final mainHeadingPattern = RegExp(r'<h[1-2][^>]*>');
    var headingCount = 0;
    var lastHeadingPos = startPos;

    for (final heading in mainHeadingPattern.allMatches(searchArea)) {
      final pos = startPos + heading.start;

      if (pos - lastHeadingPos > 1000) {
        // 如果距离上一个标题超过1000字符,认为目录结束
        if (headingCount > 0) {
          return lastHeadingPos;
        }
      }

      headingCount++;
      lastHeadingPos = pos;
    }

    // 策略3: 默认取接下来的1500字符
    return min(startPos + 1500, searchEnd);
  }

  /// 从目录内容中提取章节
  static List<BookChapter> _extractChaptersFromToc(
    String tocContent,
    int baseOffset,
  ) {
    final chapters = <BookChapter>[];

    // 提取链接文本作为章节
    final linkPattern = RegExp(
      r'<a[^>]*>([^<]+)</a>',
      caseSensitive: false,
    );

    for (final match in linkPattern.allMatches(tocContent)) {
      final title = match.group(1)?.trim() ?? '';

      // 过滤有效章节标题
      if (title.isNotEmpty &&
          title.length < 100 &&
          !_isIgnoredTitle(title)) {
        chapters.add(
          BookChapter(
            title: title,
            offset: baseOffset + match.start,
            level: 2,
          ),
        );
      }
    }

    // 如果没有链接,尝试提取小标题
    if (chapters.isEmpty) {
      final headingPattern = RegExp(
        r'<h([4-6])[^>]*>([^<]+)</h[4-6]>',
        caseSensitive: false,
      );

      for (final match in headingPattern.allMatches(tocContent)) {
        final level = int.parse(match.group(1)!);
        final title = match.group(2)?.trim() ?? '';

        if (title.isNotEmpty &&
            title.length < 100 &&
            !_isIgnoredTitle(title)) {
          chapters.add(
            BookChapter(
              title: title,
              offset: baseOffset + match.start,
              level: level,
            ),
          );
        }
      }
    }

    return chapters;
  }

  /// 验证提取的目录是否有效
  static bool _validateTocSection(TocSection section, String fullHtml) {
    // 1. 目录不能太短或太长
    if (section.length < 100 || section.length > fullHtml.length * 0.25) {
      return false;
    }

    // 2. 必须包含一定数量的章节
    if (section.chapters.length < 3) {
      return false;
    }

    // 3. 章节标题不能过于相似 (避免误识别重复列表)
    if (_hasTooManyDuplicates(section.chapters)) {
      return false;
    }

    return true;
  }

  /// 检查是否有过多重复标题
  static bool _hasTooManyDuplicates(List<BookChapter> chapters) {
    if (chapters.length < 5) return false;

    final titleSet = <String>{};
    for (final chapter in chapters) {
      titleSet.add(chapter.title);
    }

    // 如果唯一标题数量少于总数的50%,认为重复过多
    return titleSet.length < chapters.length * 0.5;
  }

  /// 计算目录置信度
  static double _calculateConfidence(TocSection section, String fullHtml) {
    var confidence = 0.5; // 基础置信度

    // 1. 位置得分 (越靠前越好)
    final positionScore = 1.0 - (section.startOffset / fullHtml.length);
    confidence += positionScore * 0.2;

    // 2. 章节数量得分
    final chapterScore = min(section.chapters.length / 20.0, 1.0);
    confidence += chapterScore * 0.15;

    // 3. 目录长度得分 (不能太长也不能太短)
    final lengthRatio = section.length / fullHtml.length;
    final lengthScore = lengthRatio > 0.02 && lengthRatio < 0.15 ? 0.15 : 0;
    confidence += lengthScore;

    return confidence.clamp(0.0, 1.0);
  }

  /// 选择最佳结果
  static TocExtractionResult _selectBestResult(
    List<TocExtractionResult> results,
  ) {
    var bestResult = TocExtractionResult.empty();

    for (final result in results) {
      if (result.confidence > bestResult.confidence) {
        bestResult = result;
      }
    }

    if (bestResult.hasValidToc) {
      logger.i(
        '最佳目录识别结果: method=${bestResult.method}, '
        'confidence=${bestResult.confidence.toStringAsFixed(2)}, '
        'chapters=${bestResult.tocSection!.chapters.length}',
      );
    }

    return bestResult;
  }

  /// 忽略的标题关键词
  static bool _isIgnoredTitle(String title) {
    const ignored = [
      '返回',
      '下一页',
      '上一页',
      'back',
      'next',
      'previous',
      '首页',
      'home',
    ];

    final lower = title.toLowerCase();
    return ignored.any((keyword) => lower.contains(keyword));
  }
}
