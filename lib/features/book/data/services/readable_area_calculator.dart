import 'package:flutter/material.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';

/// 精确的可视区域计算器
/// 用于计算阅读器中真实可用于显示内容的区域大小
class ReadableAreaCalculator {
  ReadableAreaCalculator._();

  /// 固定顶栏高度 (返回按钮 + 书名/章节名)
  static const double fixedHeaderHeight = 40.0;

  /// 底部状态栏高度 (进度、电池、时间)
  static const double bottomStatusBarHeight = 24.0;

  /// 计算可用于阅读内容的高度
  /// 考虑了所有固定UI元素和安全区域
  static double calculateAvailableHeight(
    BuildContext context,
    BookReaderSettings settings,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final topPadding = mediaQuery.padding.top; // 刘海屏、状态栏
    final bottomPadding = mediaQuery.padding.bottom; // 虚拟导航栏

    // 计算可用高度 = 屏幕总高度 - 各种固定元素
    final availableHeight = screenHeight -
        topPadding -
        bottomPadding -
        fixedHeaderHeight -
        bottomStatusBarHeight -
        settings.verticalPadding * 2; // 上下内边距

    return availableHeight.clamp(100.0, double.infinity); // 确保至少100px
  }

  /// 估算每页可容纳的行数
  /// 基于字体大小、行高和段落间距
  static int estimateVisibleLines(
    double availableHeight,
    BookReaderSettings settings,
  ) {
    // 单行像素高度
    final linePixelHeight = settings.fontSize * settings.lineHeight;

    // 段落间距(平均到每行)
    // 假设每3行有一个段落间距
    final avgParagraphGapPerLine = settings.paragraphSpacing * 16 / 3;

    // 有效行高 = 行高 + 均摊的段落间距
    final effectiveLineHeight = linePixelHeight + avgParagraphGapPerLine;

    // 保守估算,避免溢出
    return (availableHeight / effectiveLineHeight * 0.95).floor();
  }

  /// 估算每页字符数
  /// 用于快速分页估算
  static int estimateCharsPerPage(
    BuildContext context,
    BookReaderSettings settings,
  ) {
    final availableHeight = calculateAvailableHeight(context, settings);
    final visibleLines = estimateVisibleLines(availableHeight, settings);

    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - settings.horizontalPadding * 2;

    // 中英文混排平均每行字符数
    // 中文字符约等于字体大小,英文字符约为字体大小的0.6倍
    // 这里使用1.8作为混排系数
    final charsPerLine = (availableWidth / settings.fontSize * 1.8).floor();

    // 总字符数 = 行数 × 每行字符数
    // 再乘以0.75安全系数,避免内容溢出页面
    final totalChars = (visibleLines * charsPerLine * 0.75).toInt();

    return totalChars.clamp(200, 5000); // 限制在合理范围
  }

  /// 估算段落的渲染高度
  /// 用于更精确的分页计算
  static double estimateParagraphHeight(
    String paragraphHtml,
    double availableWidth,
    BookReaderSettings settings,
  ) {
    // 移除 HTML 标签,获取纯文本
    final plainText = paragraphHtml.replaceAll(RegExp('<[^>]+>'), '');
    if (plainText.trim().isEmpty) return 0;

    // 估算文本行数
    final charsPerLine = (availableWidth / settings.fontSize * 1.8).floor();
    final estimatedLines =
        (plainText.length / charsPerLine.toDouble()).ceil().clamp(1, 100);

    // 行高
    final lineHeight = settings.fontSize * settings.lineHeight;

    // 总高度 = 行数 × 行高 + 段落间距
    return estimatedLines * lineHeight + settings.paragraphSpacing * 16;
  }

  /// 计算可用宽度
  static double calculateAvailableWidth(
    BuildContext context,
    BookReaderSettings settings,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    return screenWidth - settings.horizontalPadding * 2;
  }

  /// 检查当前页面是否会溢出
  /// 返回溢出百分比 (>0 表示溢出, <0 表示空余)
  static double checkPageOverflow(
    String pageHtml,
    BuildContext context,
    BookReaderSettings settings,
  ) {
    final availableHeight = calculateAvailableHeight(context, settings);
    final availableWidth = calculateAvailableWidth(context, settings);

    // 分割为段落并估算总高度
    final paragraphs = _splitHtmlIntoParagraphs(pageHtml);
    var totalHeight = 0.0;

    for (final paragraph in paragraphs) {
      totalHeight += estimateParagraphHeight(
        paragraph,
        availableWidth,
        settings,
      );
    }

    // 计算溢出比例
    return (totalHeight - availableHeight) / availableHeight;
  }

  /// 简单的 HTML 段落分割
  static List<String> _splitHtmlIntoParagraphs(String html) {
    final blockPattern = RegExp(
      '<(?:p|div|h[1-6]|blockquote|li)[^>]*>.*?</(?:p|div|h[1-6]|blockquote|li)>',
      caseSensitive: false,
      dotAll: true,
    );

    final matches = blockPattern.allMatches(html);
    if (matches.isEmpty) return [html];

    return matches.map((m) => m.group(0)!).toList();
  }
}
