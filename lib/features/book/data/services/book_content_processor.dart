import 'dart:async';
import 'dart:isolate';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/enhanced_toc_extractor.dart';

/// 章节信息
class BookChapter {
  BookChapter({
    required this.title,
    required this.offset,
    this.level = 1,
  });

  final String title;
  final int offset; // HTML 中的字符偏移量
  final int level; // 标题级别 (1-6)
}

/// 内容处理结果
class ContentProcessResult {
  ContentProcessResult({
    required this.cleanedHtml,
    required this.chapters,
    this.removedTocSection = false,
  });

  final String cleanedHtml; // 清理后的 HTML（移除了目录页）
  final List<BookChapter> chapters; // 提取的章节列表
  final bool removedTocSection; // 是否移除了目录区域
}

/// 分页结果
class PaginationResult {
  PaginationResult({required this.pages, required this.chapterPageMap});

  final List<String> pages; // 分页后的 HTML 内容
  final Map<int, int> chapterPageMap; // 章节索引 -> 页码映射
}

/// 电子书内容处理服务
/// 在 Isolate 中处理大文本，避免阻塞 UI 线程
class BookContentProcessor {
  /// 在 Isolate 中处理书籍内容
  /// 包括：提取章节、移除目录页、清理 HTML
  static Future<ContentProcessResult> processContent(String htmlContent) async {
    try {
      // 使用 Isolate 进行后台处理
      final result = await Isolate.run<ContentProcessResult>(
        () => _processContentInIsolate(htmlContent),
      );
      return result;
    } on Exception catch (e) {
      logger.e('内容处理失败', e);
      // 失败时返回原始内容
      return ContentProcessResult(
        cleanedHtml: htmlContent,
        chapters: [],
      );
    }
  }

  /// 在 Isolate 中分页
  static Future<PaginationResult> paginateContent({
    required String htmlContent,
    required List<BookChapter> chapters,
    int charsPerPage = 1500,
  }) async {
    try {
      final result = await Isolate.run<PaginationResult>(
        () => _paginateInIsolate(htmlContent, chapters, charsPerPage),
      );
      return result;
    } on Exception catch (e) {
      logger.e('分页失败', e);
      // 失败时返回单页
      return PaginationResult(
        pages: [htmlContent],
        chapterPageMap: {},
      );
    }
  }

  // ========== Isolate 内部执行的函数 ==========

  /// 在 Isolate 中处理内容
  static ContentProcessResult _processContentInIsolate(String htmlContent) {
    // 1. 使用增强的目录提取器
    final tocResult = EnhancedTocExtractor.extractToc(htmlContent);

    // 2. 提取所有章节(包括目录中的和正文中的)
    final allChapters = _extractChapters(htmlContent);

    // 3. 如果识别到有效目录,移除目录区域
    var cleanedHtml = htmlContent;
    var removedToc = false;

    if (tocResult.hasValidToc) {
      final tocSection = tocResult.tocSection!;
      logger.i(
        '使用${tocResult.method}方法识别到目录: '
        '置信度=${tocResult.confidence.toStringAsFixed(2)}, '
        '章节数=${tocSection.chapters.length}',
      );

      // 移除目录区域
      final before = htmlContent.substring(0, tocSection.startOffset);
      final after = htmlContent.substring(tocSection.endOffset);
      cleanedHtml = before + after;
      removedToc = true;
    }

    // 4. 清理无效 CSS
    final finalHtml = _cleanInvalidCssColors(cleanedHtml);

    return ContentProcessResult(
      cleanedHtml: finalHtml,
      chapters: allChapters,
      removedTocSection: removedToc,
    );
  }

  /// 提取章节（优化版）
  static List<BookChapter> _extractChapters(String htmlContent) {
    final chapters = <BookChapter>[];

    // 使用 StringBuffer 进行高效处理
    final length = htmlContent.length;
    var i = 0;

    while (i < length) {
      // 查找 <h 标签
      final tagStart = htmlContent.indexOf('<h', i);
      if (tagStart == -1) break;

      // 检查是否是 h1-h6
      if (tagStart + 2 >= length) break;
      final levelChar = htmlContent[tagStart + 2];
      if (levelChar.codeUnitAt(0) < 49 || levelChar.codeUnitAt(0) > 54) {
        // 不是 1-6
        i = tagStart + 3;
        continue;
      }

      final level = int.parse(levelChar);

      // 查找标签结束
      final tagClose = htmlContent.indexOf('>', tagStart);
      if (tagClose == -1) break;

      // 查找内容结束
      final contentEnd = htmlContent.indexOf('</h$level>', tagClose);
      if (contentEnd == -1) {
        i = tagClose + 1;
        continue;
      }

      // 提取标题文本
      var title = htmlContent.substring(tagClose + 1, contentEnd);

      // 移除内部 HTML 标签
      title = title.replaceAll(RegExp('<[^>]*>'), '').trim();

      // 过滤有效章节标题
      if (title.isNotEmpty && title.length < 100) {
        chapters.add(
          BookChapter(
            title: title,
            offset: tagStart,
            level: level,
          ),
        );
      }

      i = contentEnd + 5 + level.toString().length;
    }

    return chapters;
  }

  /// 识别并移除目录区域
  /// 返回 (清理后的 HTML, 是否移除了目录)
  // ignore: unused_element
  static (String, bool) _removeTocSection(
    String htmlContent,
    List<BookChapter> chapters,
  ) {
    if (chapters.isEmpty || htmlContent.length < 1000) {
      return (htmlContent, false);
    }

    // 识别目录区域的启发式规则：
    // 1. 在文档前 20% 的位置
    // 2. 包含 "目录" 或 "Contents" 关键词
    // 3. 有密集的链接或标题标签

    final docLength = htmlContent.length;
    final searchEnd = (docLength * 0.2).toInt();
    final searchContent = htmlContent.substring(0, searchEnd);

    // 查找目录标识
    final tocKeywords = [
      '目录',
      'Table of Contents',
      'Contents',
      'TOC',
      '目　录',
      'CONTENTS',
    ];

    int? tocStart;
    for (final keyword in tocKeywords) {
      final index = searchContent.indexOf(keyword);
      if (index != -1) {
        tocStart = index;
        break;
      }
    }

    if (tocStart == null) {
      return (htmlContent, false);
    }

    // 向前查找最近的标签开始
    var sectionStart = tocStart;
    while (sectionStart > 0 && htmlContent[sectionStart] != '<') {
      sectionStart--;
    }

    // 计算目录区域可能的结束位置
    // 策略：查找目录后第一个正文段落（长度 > 200 字符的 <p> 标签）
    var sectionEnd = tocStart + 100;
    var consecutiveChapters = 0;

    for (final chapter in chapters) {
      if (chapter.offset < tocStart + 50) continue;
      if (chapter.offset > searchEnd) break;

      consecutiveChapters++;

      // 如果连续出现 3 个以上章节标题，认为这是目录区域
      if (consecutiveChapters >= 3) {
        sectionEnd = chapter.offset;
      } else if (consecutiveChapters > 0 && chapter.offset - sectionEnd > 500) {
        // 如果章节间距离较大，认为目录已结束
        break;
      }
    }

    // 查找目录区域后的第一个长段落
    final paragraphPattern = RegExp('<p[^>]*>(.{200,}?)</p>', dotAll: true);
    final match = paragraphPattern.firstMatch(
      htmlContent.substring(sectionEnd, searchEnd),
    );

    if (match != null) {
      sectionEnd += match.start;
    }

    // 确保移除的区域合理（不要移除太多内容）
    final removedLength = sectionEnd - sectionStart;
    if (removedLength > docLength * 0.15) {
      // 如果要移除超过 15% 的内容，可能识别错误，不移除
      return (htmlContent, false);
    }

    // 移除目录区域
    final before = htmlContent.substring(0, sectionStart);
    final after = htmlContent.substring(sectionEnd);

    return (before + after, true);
  }

  /// 清理无效 CSS 颜色值（优化版，减少正则操作）
  static String _cleanInvalidCssColors(String html) {
    // 简化实现：只处理包含 color 的 style 属性
    if (!html.contains('color')) return html;

    var cleaned = html;

    // 0. 首先移除所有 null 字符和控制字符（这些会导致解析失败）
    // 使用字符码点范围匹配控制字符
    cleaned = cleaned.replaceAll(
      RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'),
      '',
    );

    // 1. 移除明确会导致崩溃的无效 0x 颜色声明（针对 flutter_html 的已知崩溃）
    // 匹配 pattern: color: 0x0000c、color=0x0000c 等（包括不完整的hex值）
    // 更宽松的匹配：0x后面跟任意字符直到遇到有效终结符
    cleaned = cleaned.replaceAllMapped(
      RegExp('color\\s*[:=]\\s*["\']?0x[0-9a-fA-F]*[^0-9a-fA-F;"\\s>]*["\']?', caseSensitive: false),
      (match) {
        final fullMatch = match.group(0) ?? '';
        // 尝试提取 hex 部分修复
        final hexMatch = RegExp('0x([0-9a-fA-F]+)').firstMatch(fullMatch);
        if (hexMatch != null) {
          var hex = hexMatch.group(1) ?? '';
          // 移除任何非hex字符
          hex = hex.replaceAll(RegExp('[^0-9a-fA-F]'), '');
          if (hex.isEmpty || hex.length < 3) return ''; // 太短无法修复
          if (hex.length > 6) hex = hex.substring(0, 6);
          while (hex.length < 6) {
            // ignore: use_string_buffers - 简单循环，StringBuffer 过度设计
            hex += '0'; // 补齐到6位
          }
          return 'color: #$hex;';
        }
        return ''; // 无法修复则移除
      },
    );

    // 1a. 额外清理：移除所有残留的 0x 开头的颜色值（更激进的清理）
    cleaned = cleaned.replaceAll(
      RegExp('0x[0-9a-fA-F]{1,8}', caseSensitive: false),
      '#000000',
    );

    // 1b. 处理 font 标签中的 color 属性（如 <font color=0x0000c>）
    cleaned = cleaned.replaceAllMapped(
      RegExp('(<font[^>]*)\\s+color\\s*=\\s*["\']?0x[0-9a-fA-F]*[^"\\s>]*["\']?', caseSensitive: false),
      (match) => match.group(1) ?? '', // 直接移除无效的 color 属性，保留 font 标签其他部分
    );

    // 2. 正常化 hex 颜色 (以防万一)
    cleaned = cleaned.replaceAllMapped(
      // 使用标准字符串避免 raw string 的引号限制，需双重转义反斜杠
      RegExp('color\\s*:\\s*0x([0-9a-fA-F]{3,6})(?=[;\\s"\'<]|\$)', caseSensitive: false),
      (match) {
        final hex = match.group(1) ?? '';
        return 'color: #${hex.padRight(6, '0')}';
      },
    );

    // 正常的 style 属性处理
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'style\s*=\s*"([^"]*color[^"]*)"', caseSensitive: false),
      (match) {
        final styleContent = match.group(1) ?? '';
        final fixedStyle = _fixColorValuesInStyle(styleContent);
        if (fixedStyle.isEmpty) return '';
        return 'style="$fixedStyle"';
      },
    ).replaceAllMapped(
      RegExp(r"style\s*=\s*'([^']*color[^']*)'", caseSensitive: false),
      (match) {
        final styleContent = match.group(1) ?? '';
        final fixedStyle = _fixColorValuesInStyle(styleContent);
        if (fixedStyle.isEmpty) return '';
        return "style='$fixedStyle'";
      },
    );

    return cleaned;
  }

  /// 修复 style 中的颜色值
  static String _fixColorValuesInStyle(String style) {
    if (style.isEmpty) return style;

    // 只处理包含颜色的 style
    if (!style.contains('color')) return style;

    return style.replaceAllMapped(
      RegExp(
        r'((?:background-)?color)\s*:\s*([^;]+)',
        caseSensitive: false,
      ),
      (match) {
        final property = match.group(1) ?? 'color';
        final colorValue = match.group(2)?.trim() ?? '';
        final fixedColor = _fixColorValue(colorValue);
        if (fixedColor == null) {
          return ''; // 移除无法修复的颜色
        }
        return '$property: $fixedColor';
      },
    );
  }

  /// 修复颜色值
  static String? _fixColorValue(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return null;

    // 已经是有效格式
    if (trimmed.startsWith('#') ||
        trimmed.startsWith('rgb') ||
        _isValidColorName(trimmed)) {
      return trimmed;
    }

    // 0x 格式转换
    if (trimmed.startsWith('0x')) {
      final hex = trimmed.substring(2);
      final fixed = _fixHexColor(hex);
      return fixed != null ? '#$fixed' : null;
    }

    // 纯 hex 格式
    if (RegExp(r'^[0-9a-f]+$').hasMatch(trimmed)) {
      final fixed = _fixHexColor(trimmed);
      return fixed != null ? '#$fixed' : null;
    }

    return null;
  }

  /// 修复 hex 颜色值
  static String? _fixHexColor(String hex) {
    final cleaned = hex.replaceAll(RegExp('[^0-9a-fA-F]'), '');
    if (cleaned.isEmpty) return null;

    final length = cleaned.length;

    if (length == 3 || length == 6 || length == 8) {
      return cleaned;
    }

    if (length < 3) return null;

    if (length == 4 || length == 5) {
      // 补齐到 6 位
      return cleaned.substring(0, 3).padRight(6, '0');
    }

    if (length == 7) {
      return '${cleaned}0';
    }

    if (length > 8) {
      return cleaned.substring(0, 6);
    }

    return null;
  }

  /// 检查是否是有效颜色名称
  static bool _isValidColorName(String name) {
    const validColors = {
      'transparent', 'currentcolor', 'inherit',
      'black', 'white', 'red', 'green', 'blue', 'yellow', 'cyan', 'magenta',
      'gray', 'grey', 'silver', 'maroon', 'olive', 'lime', 'aqua', 'teal',
      'navy', 'fuchsia', 'purple', 'orange', 'pink', 'brown', 'gold',
    };
    return validColors.contains(name);
  }

  /// 在 Isolate 中分页
  static PaginationResult _paginateInIsolate(
    String htmlContent,
    List<BookChapter> chapters,
    int charsPerPage,
  ) {
    // 按段落分割
    final paragraphs = _splitHtmlIntoParagraphs(htmlContent);

    final pages = <String>[];
    final chapterPageMap = <int, int>{};

    var currentPageContent = StringBuffer();
    var currentCharCount = 0;
    var currentOffset = 0;

    // 记录每个章节对应的页码
    var chapterIndex = 0;

    for (final paragraph in paragraphs) {
      final paragraphLength = paragraph.length;

      // 检查是否有章节在当前段落之前
      while (chapterIndex < chapters.length &&
          chapters[chapterIndex].offset <= currentOffset) {
        chapterPageMap[chapterIndex] = pages.length;
        chapterIndex++;
      }

      // 如果当前页已满，开始新页
      if (currentCharCount > 0 &&
          currentCharCount + paragraphLength > charsPerPage) {
        pages.add(currentPageContent.toString());
        currentPageContent = StringBuffer();
        currentCharCount = 0;
      }

      currentPageContent.write(paragraph);
      currentCharCount += paragraphLength;
      currentOffset += paragraphLength;
    }

    // 添加最后一页
    if (currentCharCount > 0) {
      pages.add(currentPageContent.toString());
    }

    // 确保至少有一页
    if (pages.isEmpty) {
      pages.add(htmlContent);
    }

    return PaginationResult(
      pages: pages,
      chapterPageMap: chapterPageMap,
    );
  }

  /// 分割 HTML 为段落
  static List<String> _splitHtmlIntoParagraphs(String html) {
    final paragraphs = <String>[];

    // 匹配块级元素
    final blockPattern = RegExp(
      '<(?:p|div|h[1-6]|blockquote|li|tr)[^>]*>.*?</(?:p|div|h[1-6]|blockquote|li|tr)>',
      caseSensitive: false,
      dotAll: true,
    );

    final matches = blockPattern.allMatches(html);

    if (matches.isEmpty) {
      // 没有块级元素，按换行分割
      final lines = html.split(RegExp(r'<br\s*/?>\s*'));
      for (final line in lines) {
        if (line.trim().isNotEmpty) {
          paragraphs.add('<p>$line</p>');
        }
      }
    } else {
      for (final match in matches) {
        paragraphs.add(match.group(0)!);
      }
    }

    return paragraphs;
  }
}
