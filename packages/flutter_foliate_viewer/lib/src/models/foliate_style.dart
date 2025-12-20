import 'dart:convert';

import 'package:flutter/material.dart';

/// Foliate 阅读器样式设置
///
/// 对应 foliate-js 的 window.style 配置
class FoliateStyle {
  const FoliateStyle({
    this.fontSize = 1.0,
    this.fontName = 'system',
    this.fontWeight = 400,
    this.letterSpacing = 0,
    this.lineHeight = 1.5,
    this.paragraphSpacing = 0,
    this.textIndent = 2,
    this.textColor,
    this.backgroundColor,
    this.justify = true,
    this.textAlign = FoliateTextAlign.auto,
    this.hyphenate = true,
    this.writingMode = FoliateWritingMode.auto,
    this.pageTurnStyle = FoliatePageTurnStyle.slide,
    this.topMargin = 20,
    this.bottomMargin = 20,
    this.sideMargin = 5,
    this.maxColumnCount = 1, // 默认单列显示，避免双页模式
    this.customCSS,
  });

  /// 从 BookReaderSettings 创建
  factory FoliateStyle.fromReaderSettings({
    required double fontSize,
    required double lineHeight,
    required double paragraphSpacing,
    required double horizontalPadding,
    required double verticalPadding,
    required Color backgroundColor,
    required Color textColor,
    String? fontFamily,
    FoliatePageTurnStyle pageTurnStyle = FoliatePageTurnStyle.slide,
    int extraTopMargin = 0, // 额外顶部边距（用于避开固定顶栏）
    int extraBottomMargin = 0, // 额外底部边距（用于避开固定底栏）
  }) => FoliateStyle(
      // foliate-js 的 fontSize 是倍数，18px 对应 1.0
      fontSize: fontSize / 18.0,
      fontName: fontFamily ?? 'system',
      lineHeight: lineHeight,
      // 段落间距：paragraphSpacing 是 em 单位，转换为像素时使用较小的倍数
      paragraphSpacing: (paragraphSpacing * 8).toInt(),
      textIndent: 2,
      backgroundColor: backgroundColor,
      textColor: textColor,
      // 添加额外边距以避开固定栏
      topMargin: verticalPadding.toInt() + extraTopMargin,
      bottomMargin: verticalPadding.toInt() + extraBottomMargin,
      sideMargin: (horizontalPadding / 4).toInt(), // foliate-js 使用百分比
      pageTurnStyle: pageTurnStyle,
    );

  /// 字体大小倍数 (1.0 = 100%)
  final double fontSize;

  /// 字体名称
  final String fontName;

  /// 字体粗细 (100-900)
  final int fontWeight;

  /// 字间距
  final double letterSpacing;

  /// 行高
  final double lineHeight;

  /// 段落间距 (像素)
  final int paragraphSpacing;

  /// 首行缩进 (em)
  final int textIndent;

  /// 文字颜色
  final Color? textColor;

  /// 背景颜色
  final Color? backgroundColor;

  /// 两端对齐
  final bool justify;

  /// 文本对齐方式
  final FoliateTextAlign textAlign;

  /// 启用连字符
  final bool hyphenate;

  /// 书写模式
  final FoliateWritingMode writingMode;

  /// 翻页风格
  final FoliatePageTurnStyle pageTurnStyle;

  /// 上边距 (像素)
  final int topMargin;

  /// 下边距 (像素)
  final int bottomMargin;

  /// 侧边距 (百分比)
  final int sideMargin;

  /// 最大分栏数
  final int maxColumnCount;

  /// 自定义 CSS
  final String? customCSS;

  FoliateStyle copyWith({
    double? fontSize,
    String? fontName,
    int? fontWeight,
    double? letterSpacing,
    double? lineHeight,
    int? paragraphSpacing,
    int? textIndent,
    Color? textColor,
    Color? backgroundColor,
    bool? justify,
    FoliateTextAlign? textAlign,
    bool? hyphenate,
    FoliateWritingMode? writingMode,
    FoliatePageTurnStyle? pageTurnStyle,
    int? topMargin,
    int? bottomMargin,
    int? sideMargin,
    int? maxColumnCount,
    String? customCSS,
  }) => FoliateStyle(
      fontSize: fontSize ?? this.fontSize,
      fontName: fontName ?? this.fontName,
      fontWeight: fontWeight ?? this.fontWeight,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      textIndent: textIndent ?? this.textIndent,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      justify: justify ?? this.justify,
      textAlign: textAlign ?? this.textAlign,
      hyphenate: hyphenate ?? this.hyphenate,
      writingMode: writingMode ?? this.writingMode,
      pageTurnStyle: pageTurnStyle ?? this.pageTurnStyle,
      topMargin: topMargin ?? this.topMargin,
      bottomMargin: bottomMargin ?? this.bottomMargin,
      sideMargin: sideMargin ?? this.sideMargin,
      maxColumnCount: maxColumnCount ?? this.maxColumnCount,
      customCSS: customCSS ?? this.customCSS,
    );

  /// 转换为 JSON 字符串供 JavaScript 使用
  String toJsonString() {
    final map = <String, dynamic>{
      'fontSize': fontSize,
      'fontName': fontName,
      'fontPath': '',
      'fontWeight': fontWeight,
      'letterSpacing': letterSpacing,
      'spacing': lineHeight,
      'paragraphSpacing': paragraphSpacing,
      'textIndent': textIndent,
      'fontColor': _colorToHex(textColor ?? const Color(0xFF000000)),
      'backgroundColor': _colorToHex(backgroundColor ?? const Color(0xFFFFFFFF)),
      'justify': justify,
      'textAlign': textAlign.value,
      'hyphenate': hyphenate,
      'writingMode': writingMode.value,
      'backgroundImage': 'none',
      'pageTurnStyle': pageTurnStyle.value,
      'topMargin': topMargin,
      'bottomMargin': bottomMargin,
      'sideMargin': sideMargin,
      'maxColumnCount': maxColumnCount,
      'customCSS': customCSS ?? '',
      'customCSSEnabled': customCSS != null && customCSS!.isNotEmpty,
    };
    return jsonEncode(map);
  }

  String _colorToHex(Color color) => '#${color.toARGB32().toRadixString(16).substring(2)}';
}

/// 文本对齐方式
enum FoliateTextAlign {
  auto('auto'),
  start('start'),
  end('end'),
  center('center'),
  justify('justify');

  const FoliateTextAlign(this.value);
  final String value;
}

/// 书写模式
enum FoliateWritingMode {
  auto('auto'),
  horizontalTb('horizontal-tb'),
  verticalRl('vertical-rl'),
  verticalLr('vertical-lr');

  const FoliateWritingMode(this.value);
  final String value;
}

/// 翻页风格
enum FoliatePageTurnStyle {
  slide('slide'),
  scroll('scroll'),
  noAnimation('noAnimation');

  const FoliatePageTurnStyle(this.value);
  final String value;

  /// 从 BookPageTurnMode 转换
  static FoliatePageTurnStyle fromPageTurnMode(int modeIndex) {
    // BookPageTurnMode: scroll=0, slide=1, simulation=2, cover=3, none=4
    switch (modeIndex) {
      case 0:
        return FoliatePageTurnStyle.scroll;
      case 4:
        return FoliatePageTurnStyle.noAnimation;
      default:
        return FoliatePageTurnStyle.slide;
    }
  }
}

/// 阅读规则
class FoliateReadingRules {
  const FoliateReadingRules({
    this.convertChineseMode = FoliateChineseMode.none,
    this.bionicReadingMode = false,
  });

  /// 简繁转换模式
  final FoliateChineseMode convertChineseMode;

  /// 仿生阅读模式
  final bool bionicReadingMode;

  String toJsonString() => jsonEncode({
      'convertChineseMode': convertChineseMode.value,
      'bionicReadingMode': bionicReadingMode,
    });
}

/// 简繁转换模式
enum FoliateChineseMode {
  none('none'),
  simplified('s2t'), // 简体转繁体
  traditional('t2s'); // 繁体转简体

  const FoliateChineseMode(this.value);
  final String value;
}
