import 'dart:convert';

import 'package:flutter_foliate_viewer/src/models/foliate_book_info.dart';
import 'package:flutter_foliate_viewer/src/models/foliate_location.dart';
import 'package:flutter_foliate_viewer/src/models/foliate_style.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Foliate 阅读器控制器
///
/// 用于控制 FoliateViewer 的操作，如翻页、跳转等
class FoliateController {
  InAppWebViewController? _webViewController;

  /// 设置 WebView 控制器
  void setWebViewController(InAppWebViewController controller) {
    _webViewController = controller;
  }

  /// 下一页
  Future<void> nextPage() async {
    // 使用 book.js 定义的全局函数
    await _webViewController?.evaluateJavascript(
      source: 'if (window.nextPage) window.nextPage(); else window.reader?.view?.next();',
    );
  }

  /// 上一页
  Future<void> prevPage() async {
    await _webViewController?.evaluateJavascript(
      source: 'if (window.prevPage) window.prevPage(); else window.reader?.view?.prev();',
    );
  }

  /// 跳转到指定位置 (CFI)
  Future<void> goToCfi(String cfi) async {
    await _webViewController?.evaluateJavascript(
      source: 'if (window.goToCfi) window.goToCfi("$cfi"); else window.reader?.view?.goTo("$cfi");',
    );
  }

  /// 跳转到指定链接（用于目录跳转）
  /// [href] 可以是相对路径如 "chapter1.xhtml" 或带锚点 "chapter1.xhtml#section1"
  Future<void> goToHref(String href) async {
    // foliate-js 使用 goTo 方法，传入 href 对象
    await _webViewController?.evaluateJavascript(
      source: '''
        (function() {
          if (window.reader && window.reader.view) {
            window.reader.view.goTo("$href");
          }
        })()
      ''',
    );
  }

  /// 跳转到指定章节
  Future<void> goToSection(int index) async {
    await _webViewController?.evaluateJavascript(
      source: 'if (window.goToHref) window.reader?.view?.goTo({ index: $index }); else window.reader?.view?.goTo({ index: $index });',
    );
  }

  /// 跳转到上一章节
  Future<bool> goToPreviousSection() async {
    final result = await _webViewController?.evaluateJavascript(
      source: '''
        (function() {
          const view = window.reader?.view;
          if (!view || !view.lastLocation) return false;
          const currentIndex = view.lastLocation.index ?? 0;
          if (currentIndex <= 0) return false;
          view.goTo({ index: currentIndex - 1 });
          return true;
        })()
      ''',
    );
    return result == true || result == 'true';
  }

  /// 跳转到下一章节
  Future<bool> goToNextSection() async {
    final result = await _webViewController?.evaluateJavascript(
      source: '''
        (function() {
          const view = window.reader?.view;
          if (!view || !view.lastLocation) return false;
          const totalSections = view.book?.sections?.length || 0;
          const currentIndex = view.lastLocation.index ?? 0;
          if (currentIndex >= totalSections - 1) return false;
          view.goTo({ index: currentIndex + 1 });
          return true;
        })()
      ''',
    );
    return result == true || result == 'true';
  }

  /// 跳转到指定进度 (0.0 - 1.0)
  Future<void> goToFraction(double fraction) async {
    await _webViewController?.evaluateJavascript(
      source: 'if (window.goToPercent) window.goToPercent($fraction); else window.reader?.view?.goToFraction($fraction);',
    );
  }

  /// 设置主题（简化版本）
  Future<void> setTheme({
    String? backgroundColor,
    String? textColor,
    int? fontSize,
    double? lineHeight,
  }) async {
    // 使用 book.js 定义的 changeStyle 函数
    final jsCode = '''
      if (window.changeStyle) {
        window.changeStyle({
          ${backgroundColor != null ? "backgroundColor: '$backgroundColor'," : ''}
          ${textColor != null ? "fontColor: '$textColor'," : ''}
          ${fontSize != null ? "fontSize: ${fontSize / 100}," : ''}
          ${lineHeight != null ? "spacing: $lineHeight," : ''}
        });
      }
    ''';
    await _webViewController?.evaluateJavascript(source: jsCode);
  }

  /// 应用完整样式设置
  Future<void> applyStyle(FoliateStyle style) async {
    final styleJson = style.toJsonString();
    final jsCode = '''
      if (window.changeStyle) {
        const newStyle = $styleJson;
        window.changeStyle(newStyle);
      }
    ''';
    await _webViewController?.evaluateJavascript(source: jsCode);
  }

  /// 设置字体大小
  Future<void> setFontSize(double size) async {
    await _webViewController?.evaluateJavascript(
      source: 'if (window.changeStyle) window.changeStyle({ fontSize: $size });',
    );
  }

  /// 设置行高
  Future<void> setLineHeight(double height) async {
    await _webViewController?.evaluateJavascript(
      source: 'if (window.changeStyle) window.changeStyle({ spacing: $height });',
    );
  }

  /// 设置背景色
  Future<void> setBackgroundColor(String hexColor) async {
    await _webViewController?.evaluateJavascript(
      source: "if (window.changeStyle) window.changeStyle({ backgroundColor: '$hexColor' });",
    );
  }

  /// 设置文字颜色
  Future<void> setTextColor(String hexColor) async {
    await _webViewController?.evaluateJavascript(
      source: "if (window.changeStyle) window.changeStyle({ fontColor: '$hexColor' });",
    );
  }

  /// 设置翻页模式
  Future<void> setPageTurnStyle(FoliatePageTurnStyle style) async {
    await _webViewController?.evaluateJavascript(
      source: "if (window.changeStyle) window.changeStyle({ pageTurnStyle: '${style.value}' });",
    );
  }

  /// 设置字体
  /// [fontFamily] 字体名称，'system' 表示系统默认字体
  Future<void> setFontFamily(String? fontFamily) async {
    final fontName = fontFamily ?? 'system';
    await _webViewController?.evaluateJavascript(
      source: "if (window.changeStyle) window.changeStyle({ fontName: '$fontName' });",
    );
  }

  /// 设置边距
  Future<void> setMargins({int? top, int? bottom, int? side}) async {
    final parts = <String>[];
    if (top != null) parts.add('topMargin: $top');
    if (bottom != null) parts.add('bottomMargin: $bottom');
    if (side != null) parts.add('sideMargin: $side');
    if (parts.isEmpty) return;
    await _webViewController?.evaluateJavascript(
      source: 'if (window.changeStyle) window.changeStyle({ ${parts.join(', ')} });',
    );
  }

  /// 设置两端对齐
  Future<void> setJustify(bool justify) async {
    await _webViewController?.evaluateJavascript(
      source: 'if (window.changeStyle) window.changeStyle({ justify: $justify });',
    );
  }

  /// 设置简繁转换
  Future<void> setChineseConversion(FoliateChineseMode mode) async {
    await _webViewController?.evaluateJavascript(
      source: "if (window.changeReadingRules) window.changeReadingRules({ convertChineseMode: '${mode.value}' });",
    );
  }

  /// 设置仿生阅读模式
  Future<void> setBionicReading(bool enabled) async {
    await _webViewController?.evaluateJavascript(
      source: 'if (window.changeReadingRules) window.changeReadingRules({ bionicReadingMode: $enabled });',
    );
  }

  /// 获取当前位置
  Future<FoliateLocation?> getCurrentLocation() async {
    final result = await _webViewController?.evaluateJavascript(
      source: '''
        (function() {
          const loc = window.reader?.currentLocation;
          if (!loc) return null;
          return JSON.stringify({
            cfi: loc.cfi || '',
            fraction: loc.fraction || 0,
            sectionIndex: loc.index || 0,
            sectionFraction: loc.sectionFraction || 0,
            totalSections: window.reader?.book?.sections?.length || 0
          });
        })()
      ''',
    );
    if (result == null || result == 'null') return null;
    try {
      Map<String, dynamic> map;
      if (result is String) {
        map = jsonDecode(result) as Map<String, dynamic>;
      } else if (result is Map) {
        map = Map<String, dynamic>.from(result);
      } else {
        return null;
      }
      return FoliateLocation.fromMap(map);
    } on Exception catch (_) {
      return null;
    }
  }

  /// 获取书籍信息
  Future<FoliateBookInfo?> getBookInfo() async {
    final result = await _webViewController?.evaluateJavascript(
      source: '''
        (function() {
          const book = window.reader?.book;
          if (!book) return null;
          const metadata = book.metadata || {};
          return JSON.stringify({
            title: metadata.title || '',
            author: metadata.author || metadata.creator || '',
            language: metadata.language || '',
            identifier: metadata.identifier || '',
            description: metadata.description || '',
            publisher: metadata.publisher || '',
            published: metadata.published || '',
            totalSections: book.sections?.length || 0
          });
        })()
      ''',
    );
    if (result == null || result == 'null') return null;
    try {
      Map<String, dynamic> map;
      if (result is String) {
        map = jsonDecode(result) as Map<String, dynamic>;
      } else if (result is Map) {
        map = Map<String, dynamic>.from(result);
      } else {
        return null;
      }
      return FoliateBookInfo.fromMap(map);
    } on Exception catch (_) {
      return null;
    }
  }

  /// 获取目录
  Future<List<FoliateTocItem>> getToc() async {
    final result = await _webViewController?.evaluateJavascript(
      source: '''
        (function() {
          // 优先使用 reader.toc（格式化后的目录）
          // 如果没有，尝试使用原始的 book.toc
          let toc = window.reader?.toc;
          if (!toc || toc.length === 0) {
            toc = window.reader?.view?.book?.toc;
          }
          if (!toc) return '[]';
          return JSON.stringify(toc);
        })()
      ''',
    );
    if (result == null || result == 'null' || result == '[]') return [];
    try {
      List<dynamic> list;
      if (result is String) {
        list = jsonDecode(result) as List<dynamic>;
      } else if (result is List) {
        list = result;
      } else {
        return [];
      }
      return list
          .map((e) => FoliateTocItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on Exception catch (_) {
      return [];
    }
  }
}
