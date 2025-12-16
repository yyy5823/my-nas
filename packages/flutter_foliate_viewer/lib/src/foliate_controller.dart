import 'dart:convert';

import 'package:flutter_foliate_viewer/src/models/foliate_book_info.dart';
import 'package:flutter_foliate_viewer/src/models/foliate_location.dart';
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

  /// 跳转到指定章节
  Future<void> goToSection(int index) async {
    await _webViewController?.evaluateJavascript(
      source: 'if (window.goToHref) window.reader?.view?.goTo({ index: $index }); else window.reader?.view?.goTo({ index: $index });',
    );
  }

  /// 跳转到指定进度 (0.0 - 1.0)
  Future<void> goToFraction(double fraction) async {
    await _webViewController?.evaluateJavascript(
      source: 'if (window.goToPercent) window.goToPercent($fraction); else window.reader?.view?.goToFraction($fraction);',
    );
  }

  /// 设置主题
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
          const toc = window.reader?.book?.toc;
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
