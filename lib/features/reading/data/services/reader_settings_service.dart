import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/utils/logger.dart';

/// EPUB 阅读器引擎
enum EpubReaderEngine {
  /// 原生引擎 (flutter_epub_viewer) - 功能简单但稳定
  native,

  /// Foliate 引擎 - 功能丰富，与 MOBI/AZW3 共享设置
  foliate,
}

/// 图书翻页模式
enum BookPageTurnMode {
  scroll, // 滚动模式
  slide, // 滑动翻页
  simulation, // 仿真翻页
  cover, // 覆盖翻页
  none, // 无动画
}

/// 图书阅读主题
enum BookReaderTheme {
  light(Color(0xFFFFFFFF), Color(0xFF212121), '白色'),
  sepia(Color(0xFFF5F5DC), Color(0xFF5D4E37), '护眼'),
  green(Color(0xFFCCE8CF), Color(0xFF2D4A32), '绿色'),
  dark(Color(0xFF1A1A1A), Color(0xFFCCCCCC), '夜间'),
  black(Color(0xFF000000), Color(0xFFB0B0B0), '纯黑');

  const BookReaderTheme(this.backgroundColor, this.textColor, this.label);
  final Color backgroundColor;
  final Color textColor;
  final String label;
}

/// 图书阅读设置
class BookReaderSettings {
  const BookReaderSettings({
    this.fontSize = 18.0,
    this.lineHeight = 1.8,
    this.paragraphSpacing = 1.0,
    this.horizontalPadding = 24.0,
    this.verticalPadding = 16.0,
    this.theme = BookReaderTheme.light,
    this.pageTurnMode = BookPageTurnMode.slide,
    this.keepScreenOn = true,
    this.tapToTurn = true,
    this.volumeKeyTurn = false,
    this.showProgress = true,
    this.fontFamily,
    this.epubEngine = EpubReaderEngine.foliate,
  });

  factory BookReaderSettings.fromJson(Map<String, dynamic> json) =>
      BookReaderSettings(
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
        lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.8,
        paragraphSpacing: (json['paragraphSpacing'] as num?)?.toDouble() ?? 1.0,
        horizontalPadding:
            (json['horizontalPadding'] as num?)?.toDouble() ?? 24.0,
        verticalPadding: (json['verticalPadding'] as num?)?.toDouble() ?? 16.0,
        theme: BookReaderTheme.values[(json['theme'] as int?) ?? 0],
        pageTurnMode:
            BookPageTurnMode.values[(json['pageTurnMode'] as int?) ?? 1],
        keepScreenOn: json['keepScreenOn'] as bool? ?? true,
        tapToTurn: json['tapToTurn'] as bool? ?? true,
        volumeKeyTurn: json['volumeKeyTurn'] as bool? ?? false,
        showProgress: json['showProgress'] as bool? ?? true,
        fontFamily: json['fontFamily'] as String?,
        epubEngine: EpubReaderEngine.values[(json['epubEngine'] as int?) ?? 1],
      );

  final double fontSize;
  final double lineHeight;
  final double paragraphSpacing;
  final double horizontalPadding;
  final double verticalPadding;
  final BookReaderTheme theme;
  final BookPageTurnMode pageTurnMode;
  final bool keepScreenOn;
  final bool tapToTurn;
  final bool volumeKeyTurn;
  final bool showProgress;
  final String? fontFamily;
  final EpubReaderEngine epubEngine;

  BookReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? horizontalPadding,
    double? verticalPadding,
    BookReaderTheme? theme,
    BookPageTurnMode? pageTurnMode,
    bool? keepScreenOn,
    bool? tapToTurn,
    bool? volumeKeyTurn,
    bool? showProgress,
    String? fontFamily,
    EpubReaderEngine? epubEngine,
  }) =>
      BookReaderSettings(
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
        horizontalPadding: horizontalPadding ?? this.horizontalPadding,
        verticalPadding: verticalPadding ?? this.verticalPadding,
        theme: theme ?? this.theme,
        pageTurnMode: pageTurnMode ?? this.pageTurnMode,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        tapToTurn: tapToTurn ?? this.tapToTurn,
        volumeKeyTurn: volumeKeyTurn ?? this.volumeKeyTurn,
        showProgress: showProgress ?? this.showProgress,
        fontFamily: fontFamily ?? this.fontFamily,
        epubEngine: epubEngine ?? this.epubEngine,
      );

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'paragraphSpacing': paragraphSpacing,
        'horizontalPadding': horizontalPadding,
        'verticalPadding': verticalPadding,
        'theme': theme.index,
        'pageTurnMode': pageTurnMode.index,
        'keepScreenOn': keepScreenOn,
        'tapToTurn': tapToTurn,
        'volumeKeyTurn': volumeKeyTurn,
        'showProgress': showProgress,
        'fontFamily': fontFamily,
        'epubEngine': epubEngine.index,
      };
}

/// 漫画翻页方向
enum ComicReadingDirection {
  ltr, // 从左到右 (西方漫画)
  rtl, // 从右到左 (日漫)
  vertical, // 垂直滚动
}

/// 漫画缩放模式
enum ComicScaleMode {
  fitWidth, // 适应宽度
  fitHeight, // 适应高度
  fitScreen, // 适应屏幕
  original, // 原始大小
}

/// 漫画背景色
enum ComicBackgroundColor {
  black(Color(0xFF000000), '黑色'),
  darkGray(Color(0xFF1A1A1A), '深灰'),
  gray(Color(0xFF333333), '灰色'),
  white(Color(0xFFFFFFFF), '白色');

  const ComicBackgroundColor(this.color, this.label);
  final Color color;
  final String label;
}

/// 漫画阅读模式
enum ComicReadingMode {
  singlePage, // 单页模式
  doublePage, // 双页模式
  webtoon, // 长条模式
}

/// 漫画阅读设置
class ComicReaderSettings {
  const ComicReaderSettings({
    this.readingMode = ComicReadingMode.singlePage,
    this.readingDirection = ComicReadingDirection.ltr,
    this.scaleMode = ComicScaleMode.fitWidth,
    this.backgroundColor = ComicBackgroundColor.black,
    this.webtoonPageGap = 0.0,
    this.keepScreenOn = true,
    this.tapToTurn = true,
    this.volumeKeyTurn = false,
    this.showPageNumber = true,
    this.preloadPages = 2,
    this.doubleTapToZoom = true,
  });

  factory ComicReaderSettings.fromJson(Map<String, dynamic> json) =>
      ComicReaderSettings(
        readingMode:
            ComicReadingMode.values[(json['readingMode'] as int?) ?? 0],
        readingDirection:
            ComicReadingDirection.values[(json['readingDirection'] as int?) ?? 0],
        scaleMode: ComicScaleMode.values[(json['scaleMode'] as int?) ?? 0],
        backgroundColor:
            ComicBackgroundColor.values[(json['backgroundColor'] as int?) ?? 0],
        webtoonPageGap: (json['webtoonPageGap'] as num?)?.toDouble() ?? 0.0,
        keepScreenOn: json['keepScreenOn'] as bool? ?? true,
        tapToTurn: json['tapToTurn'] as bool? ?? true,
        volumeKeyTurn: json['volumeKeyTurn'] as bool? ?? false,
        showPageNumber: json['showPageNumber'] as bool? ?? true,
        preloadPages: json['preloadPages'] as int? ?? 2,
        doubleTapToZoom: json['doubleTapToZoom'] as bool? ?? true,
      );

  final ComicReadingMode readingMode;
  final ComicReadingDirection readingDirection;
  final ComicScaleMode scaleMode;
  final ComicBackgroundColor backgroundColor;
  final double webtoonPageGap;
  final bool keepScreenOn;
  final bool tapToTurn;
  final bool volumeKeyTurn;
  final bool showPageNumber;
  final int preloadPages;
  final bool doubleTapToZoom;

  ComicReaderSettings copyWith({
    ComicReadingMode? readingMode,
    ComicReadingDirection? readingDirection,
    ComicScaleMode? scaleMode,
    ComicBackgroundColor? backgroundColor,
    double? webtoonPageGap,
    bool? keepScreenOn,
    bool? tapToTurn,
    bool? volumeKeyTurn,
    bool? showPageNumber,
    int? preloadPages,
    bool? doubleTapToZoom,
  }) =>
      ComicReaderSettings(
        readingMode: readingMode ?? this.readingMode,
        readingDirection: readingDirection ?? this.readingDirection,
        scaleMode: scaleMode ?? this.scaleMode,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        webtoonPageGap: webtoonPageGap ?? this.webtoonPageGap,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        tapToTurn: tapToTurn ?? this.tapToTurn,
        volumeKeyTurn: volumeKeyTurn ?? this.volumeKeyTurn,
        showPageNumber: showPageNumber ?? this.showPageNumber,
        preloadPages: preloadPages ?? this.preloadPages,
        doubleTapToZoom: doubleTapToZoom ?? this.doubleTapToZoom,
      );

  Map<String, dynamic> toJson() => {
        'readingMode': readingMode.index,
        'readingDirection': readingDirection.index,
        'scaleMode': scaleMode.index,
        'backgroundColor': backgroundColor.index,
        'webtoonPageGap': webtoonPageGap,
        'keepScreenOn': keepScreenOn,
        'tapToTurn': tapToTurn,
        'volumeKeyTurn': volumeKeyTurn,
        'showPageNumber': showPageNumber,
        'preloadPages': preloadPages,
        'doubleTapToZoom': doubleTapToZoom,
      };
}

/// 阅读设置服务
class ReaderSettingsService {
  factory ReaderSettingsService() => _instance ??= ReaderSettingsService._();
  ReaderSettingsService._();

  static ReaderSettingsService? _instance;

  static const String _boxName = 'reader_settings';
  static const String _bookSettingsKey = 'book_settings';
  static const String _comicSettingsKey = 'comic_settings';

  Box<String>? _box;

  /// 初始化
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    try {
      _box = await Hive.openBox<String>(_boxName);
      logger.i('ReaderSettingsService: 初始化完成');
    } on Exception catch (e) {
      logger.e('ReaderSettingsService: 初始化失败', e);
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox<String>(_boxName);
    }
  }

  /// 获取图书阅读设置
  BookReaderSettings getBookSettings() {
    if (_box == null) return const BookReaderSettings();
    final jsonStr = _box!.get(_bookSettingsKey);
    if (jsonStr == null) return const BookReaderSettings();
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return BookReaderSettings.fromJson(json);
    } on Exception catch (e) {
      logger.w('ReaderSettingsService: 解析图书设置失败', e);
      return const BookReaderSettings();
    }
  }

  /// 保存图书阅读设置
  Future<void> saveBookSettings(BookReaderSettings settings) async {
    if (_box == null) await init();
    try {
      await _box!.put(_bookSettingsKey, jsonEncode(settings.toJson()));
      logger.d('ReaderSettingsService: 保存图书设置成功');
    } on Exception catch (e) {
      logger.e('ReaderSettingsService: 保存图书设置失败', e);
    }
  }

  /// 获取漫画阅读设置
  ComicReaderSettings getComicSettings() {
    if (_box == null) return const ComicReaderSettings();
    final jsonStr = _box!.get(_comicSettingsKey);
    if (jsonStr == null) return const ComicReaderSettings();
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return ComicReaderSettings.fromJson(json);
    } on Exception catch (e) {
      logger.w('ReaderSettingsService: 解析漫画设置失败', e);
      return const ComicReaderSettings();
    }
  }

  /// 保存漫画阅读设置
  Future<void> saveComicSettings(ComicReaderSettings settings) async {
    if (_box == null) await init();
    try {
      await _box!.put(_comicSettingsKey, jsonEncode(settings.toJson()));
      logger.d('ReaderSettingsService: 保存漫画设置成功');
    } on Exception catch (e) {
      logger.e('ReaderSettingsService: 保存漫画设置失败', e);
    }
  }
}
