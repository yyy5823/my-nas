import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// EPUB WebView 内容加载器
///
/// 在桌面端，initialFile 可能无法正确加载 Flutter 资源。
/// 此类加载所有必要的 HTML/JS/CSS 文件并创建内联 HTML。
class EpubWebViewContentLoader {
  static final EpubWebViewContentLoader _instance = EpubWebViewContentLoader._();
  factory EpubWebViewContentLoader() => _instance;
  EpubWebViewContentLoader._();

  String? _cachedHtmlContent;
  Completer<String>? _loadingCompleter;

  /// 资源基础路径
  static const String _assetBasePath = 'packages/flutter_epub_viewer/lib/assets/webpage';

  /// 是否需要使用内联 HTML（桌面端）
  static bool get needsInlineHtml => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// 获取用于 initialFile 的路径
  static String get initialFilePath => '$_assetBasePath/html/swipe.html';

  /// 获取内联 HTML 内容（用于桌面端）
  Future<String> getInlineHtmlContent() async {
    // 已缓存，直接返回
    if (_cachedHtmlContent != null) {
      return _cachedHtmlContent!;
    }

    // 正在加载中，等待 Completer 完成
    if (_loadingCompleter != null) {
      return _loadingCompleter!.future;
    }

    // 开始加载
    _loadingCompleter = Completer<String>();
    try {
      // 加载所有资源文件
      final htmlTemplate = await rootBundle.loadString('$_assetBasePath/html/swipe.html');
      final jszipJs = await rootBundle.loadString('$_assetBasePath/dist/jszip.min.js');
      final epubJs = await rootBundle.loadString('$_assetBasePath/dist/epub.js');
      final epubViewJs = await rootBundle.loadString('$_assetBasePath/html/epubView.js');
      final examplesCss = await rootBundle.loadString('$_assetBasePath/html/examples.css');

      // 创建内联 HTML
      // 替换外部引用为内联内容
      var inlineHtml = htmlTemplate;

      // 替换 CSS 引用
      inlineHtml = inlineHtml.replaceAll(
        '<link rel="stylesheet" type="text/css" href="examples.css" />',
        '<style type="text/css">\n$examplesCss\n</style>',
      );

      // 替换 JS 引用
      inlineHtml = inlineHtml.replaceAll(
        '<script src="../dist/jszip.min.js"></script>',
        '<script type="text/javascript">\n$jszipJs\n</script>',
      );
      inlineHtml = inlineHtml.replaceAll(
        '<script src="../dist/epub.js"></script>',
        '<script type="text/javascript">\n$epubJs\n</script>',
      );
      inlineHtml = inlineHtml.replaceAll(
        '<script src="epubView.js"></script>',
        '<script type="text/javascript">\n$epubViewJs\n</script>',
      );

      _cachedHtmlContent = inlineHtml;
      _loadingCompleter!.complete(_cachedHtmlContent!);
      return _cachedHtmlContent!;
    } catch (e) {
      _loadingCompleter!.completeError(e);
      _loadingCompleter = null;
      rethrow;
    }
  }

  /// 清除缓存
  void clearCache() {
    _cachedHtmlContent = null;
    _loadingCompleter = null;
  }
}
