import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foliate_viewer/src/foliate_controller.dart';
import 'package:flutter_foliate_viewer/src/models/foliate_book_info.dart';
import 'package:flutter_foliate_viewer/src/models/foliate_location.dart';
import 'package:flutter_foliate_viewer/src/models/foliate_style.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 书籍文件类型
enum FoliateBookType {
  epub,
  mobi,
  azw3,
  fb2,
  cbz,
}

/// 书籍数据源
abstract class FoliateBookSource {
  /// 获取书籍字节数据
  Future<Uint8List> get bookData;

  /// 获取书籍类型
  FoliateBookType get bookType;
}

/// 从文件加载书籍
class FileBookSource implements FoliateBookSource {
  FileBookSource(this.file);

  final File file;

  @override
  Future<Uint8List> get bookData => file.readAsBytes();

  @override
  FoliateBookType get bookType {
    final ext = file.path.toLowerCase();
    if (ext.endsWith('.epub')) return FoliateBookType.epub;
    if (ext.endsWith('.mobi')) return FoliateBookType.mobi;
    if (ext.endsWith('.azw3') || ext.endsWith('.azw')) {
      return FoliateBookType.azw3;
    }
    if (ext.endsWith('.fb2')) return FoliateBookType.fb2;
    if (ext.endsWith('.cbz')) return FoliateBookType.cbz;
    return FoliateBookType.epub;
  }
}

/// 从内存加载书籍
class MemoryBookSource implements FoliateBookSource {
  MemoryBookSource(this._data, this.bookType);

  final Uint8List _data;

  @override
  final FoliateBookType bookType;

  @override
  Future<Uint8List> get bookData async => _data;
}

/// Foliate 阅读器 Widget
///
/// 使用 foliate-js 渲染 EPUB、MOBI、AZW3 等格式电子书
class FoliateViewer extends StatefulWidget {
  const FoliateViewer({
    required this.controller,
    required this.bookSource,
    this.initialCfi,
    this.onBookLoaded,
    this.onLocationChanged,
    this.onError,
    this.style,
    this.backgroundColor,
    this.textColor,
    this.fontSize = 100,
    this.lineHeight = 1.5,
    super.key,
  });

  /// 控制器
  final FoliateController controller;

  /// 书籍数据源
  final FoliateBookSource bookSource;

  /// 初始位置 (CFI)
  final String? initialCfi;

  /// 书籍加载完成回调
  final void Function(FoliateBookInfo info)? onBookLoaded;

  /// 位置变化回调
  final void Function(FoliateLocation location)? onLocationChanged;

  /// 错误回调
  final void Function(String error)? onError;

  /// 完整样式设置（优先级高于单独的样式参数）
  final FoliateStyle? style;

  /// 背景色（如果设置了 style 则忽略）
  final Color? backgroundColor;

  /// 文字颜色（如果设置了 style 则忽略）
  final Color? textColor;

  /// 字体大小百分比 (100 = 正常)（如果设置了 style 则忽略）
  final int fontSize;

  /// 行高（如果设置了 style 则忽略）
  final double lineHeight;

  @override
  State<FoliateViewer> createState() => _FoliateViewerState();
}

class _FoliateViewerState extends State<FoliateViewer> {
  final GlobalKey _webViewKey = GlobalKey();
  InAppWebViewController? _webViewController;

  /// 内联 HTML 内容（用于桌面端）
  String? _inlineHtmlContent;
  bool _isLoading = true;
  bool _isWebViewReady = false;

  /// 是否需要使用内联 HTML（桌面端）
  bool get _needsInlineHtml =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// 资源基础路径
  static const String _assetBasePath =
      'packages/flutter_foliate_viewer/lib/assets/foliate-js';

  @override
  void initState() {
    super.initState();
    if (_needsInlineHtml) {
      _loadInlineHtml();
    }
  }

  /// 加载桌面端内联 HTML
  Future<void> _loadInlineHtml() async {
    try {
      // 加载 bundle.js
      final bundleJs =
          await rootBundle.loadString('$_assetBasePath/dist/bundle.js');

      // 创建内联 HTML，包含自定义初始化逻辑
      final inlineHtml = _buildInlineHtml(bundleJs);

      if (mounted) {
        setState(() {
          _inlineHtmlContent = inlineHtml;
        });
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to load inline HTML: $e');
      }
      widget.onError?.call('加载阅读器失败: $e');
    }
  }

  /// 构建内联 HTML
  String _buildInlineHtml(String bundleJs) => '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
  <title>Foliate Reader</title>
  <style>
    html, body {
      margin: 0;
      padding: 0;
      height: 100vh;
      overflow: hidden;
      user-select: none;
    }
    #footnote-dialog {
      display: none;
    }
    #loading {
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      display: flex;
      align-items: center;
      justify-content: center;
      background: white;
    }
  </style>
</head>
<body>
  <div id="footnote-dialog"><main></main></div>
  <div id="loading">加载中...</div>

  <script>
    // 拦截 URL 参数，阻止 book.js 自动初始化
    window.__foliateManualInit = true;
    window.__foliateBookData = null;
    window.__foliateInitialCfi = null;
    window.__foliateStyle = null;

    // 覆盖 URLSearchParams 以返回空值，防止自动初始化
    const OriginalURLSearchParams = URLSearchParams;
    window.URLSearchParams = function(search) {
      const params = new OriginalURLSearchParams(search);
      const originalGet = params.get.bind(params);
      params.get = function(key) {
        // 如果是手动初始化模式，返回特殊值让 book.js 跳过自动加载
        if (window.__foliateManualInit) {
          if (key === 'url') return null;
        }
        return originalGet(key);
      };
      return params;
    };
  </script>

  <script type="module">
$bundleJs

    // 等待 Flutter 调用初始化
    window.initFoliateBook = async function(base64Data, bookType, initialCfi, styleJson) {
      try {
        document.getElementById('loading').style.display = 'flex';

        // 解码 base64 数据
        const binaryString = atob(base64Data);
        const bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
          bytes[i] = binaryString.charCodeAt(i);
        }
        const blob = new Blob([bytes]);
        const file = new File([blob], 'book.' + bookType);

        // 设置样式
        if (styleJson) {
          window.style = JSON.parse(styleJson);
        } else {
          window.style = {
            fontSize: 1.0,
            fontName: 'system',
            fontPath: '',
            fontWeight: 400,
            letterSpacing: 0,
            spacing: 1.5,
            paragraphSpacing: 0,
            textIndent: 2,
            fontColor: '#000000',
            backgroundColor: '#ffffff',
            justify: true,
            textAlign: 'auto',
            hyphenate: true,
            writingMode: 'auto',
            backgroundImage: 'none',
            pageTurnStyle: 'slide',
            topMargin: 20,
            bottomMargin: 20,
            sideMargin: 5,
            maxColumnCount: 2,
            customCSS: '',
            customCSSEnabled: false
          };
        }

        window.readingRules = {
          convertChineseMode: 'none',
          bionicReadingMode: false
        };

        window.importing = false;

        // 使用 foliateOpen 函数打开书籍（book.js 暴露的全局函数）
        if (typeof window.foliateOpen === 'function') {
          await window.foliateOpen(file, initialCfi || null);
        } else {
          // 回退：检查原始的 open 函数（模块作用域）
          throw new Error('Reader not available - foliateOpen not found');
        }

        document.getElementById('loading').style.display = 'none';

      } catch (error) {
        console.error('Init book error:', error);
        document.getElementById('loading').innerHTML = '加载失败: ' + error.message;
        window.flutter_inappwebview.callHandler('onError', error.message || '加载失败');
      }
    };

    // 通知 Flutter WebView 已准备好
    window.flutter_inappwebview.callHandler('onWebViewReady');
  </script>
</body>
</html>
''';

  /// 添加 JavaScript 处理器
  void _addJavaScriptHandlers() {
    // WebView 准备好
    _webViewController?.addJavaScriptHandler(
      handlerName: 'onWebViewReady',
      callback: (args) {
        _isWebViewReady = true;
        // 加载书籍
        _loadBook();
      },
    );

    // 加载完成
    _webViewController?.addJavaScriptHandler(
      handlerName: 'onLoadEnd',
      callback: (args) {
        setState(() {
          _isLoading = false;
        });
      },
    );

    // 书籍元数据
    _webViewController?.addJavaScriptHandler(
      handlerName: 'onMetadata',
      callback: (args) {
        if (args.isNotEmpty) {
          try {
            final map = args[0] is Map<String, dynamic>
                ? args[0] as Map<String, dynamic>
                : jsonDecode(args[0].toString()) as Map<String, dynamic>;
            final info = FoliateBookInfo.fromMap(map);
            widget.onBookLoaded?.call(info);
          } on Exception catch (e) {
            if (kDebugMode) {
              debugPrint('Failed to parse book info: $e');
            }
          }
        }
        setState(() {
          _isLoading = false;
        });
      },
    );

    // 位置变化
    _webViewController?.addJavaScriptHandler(
      handlerName: 'onRelocated',
      callback: (args) {
        if (args.isNotEmpty) {
          try {
            final map = args[0] is Map<String, dynamic>
                ? args[0] as Map<String, dynamic>
                : jsonDecode(args[0].toString()) as Map<String, dynamic>;
            final location = FoliateLocation.fromMap(map);
            widget.onLocationChanged?.call(location);
          } on Exception catch (e) {
            if (kDebugMode) {
              debugPrint('Failed to parse location: $e');
            }
          }
        }
      },
    );

    // 目录
    _webViewController?.addJavaScriptHandler(
      handlerName: 'onSetToc',
      callback: (args) {
        // TOC 数据可通过 controller 获取
        if (kDebugMode) {
          debugPrint('TOC received');
        }
      },
    );

    // 错误处理
    _webViewController?.addJavaScriptHandler(
      handlerName: 'onError',
      callback: (args) {
        final error = args.isNotEmpty ? args[0].toString() : '未知错误';
        widget.onError?.call(error);
        setState(() {
          _isLoading = false;
        });
      },
    );

    // 点击事件
    _webViewController?.addJavaScriptHandler(
      handlerName: 'onClick',
      callback: (args) {
        // 可通过 controller 处理点击事件
      },
    );
  }

  /// 加载书籍
  Future<void> _loadBook() async {
    if (!_isWebViewReady) return;

    try {
      final data = await widget.bookSource.bookData;
      final base64Data = base64Encode(data);
      final bookType = widget.bookSource.bookType.name;
      final initialCfi = widget.initialCfi ?? '';

      // 构建样式 JSON - 优先使用完整的 FoliateStyle
      final String styleJson;
      if (widget.style != null) {
        styleJson = widget.style!.toJsonString();
      } else {
        // 兼容旧的简单参数
        final bgColor = widget.backgroundColor != null
            ? '#${widget.backgroundColor!.toARGB32().toRadixString(16).substring(2)}'
            : '#ffffff';
        final txtColor = widget.textColor != null
            ? '#${widget.textColor!.toARGB32().toRadixString(16).substring(2)}'
            : '#000000';

        styleJson = jsonEncode({
          'fontSize': widget.fontSize / 100.0,
          'fontName': 'system',
          'fontPath': '',
          'fontWeight': 400,
          'letterSpacing': 0,
          'spacing': widget.lineHeight,
          'paragraphSpacing': 0,
          'textIndent': 2,
          'fontColor': txtColor,
          'backgroundColor': bgColor,
          'justify': true,
          'textAlign': 'auto',
          'hyphenate': true,
          'writingMode': 'auto',
          'backgroundImage': 'none',
          'pageTurnStyle': 'slide',
          'topMargin': 20,
          'bottomMargin': 20,
          'sideMargin': 5,
          'maxColumnCount': 2,
          'customCSS': '',
          'customCSSEnabled': false,
        });
      }

      // 调用初始化函数
      final jsCode = '''
        window.initFoliateBook('$base64Data', '$bookType', '$initialCfi', '$styleJson');
      ''';

      await _webViewController?.evaluateJavascript(source: jsCode);
    } on Exception catch (e) {
      widget.onError?.call('加载书籍失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 桌面端等待 HTML 加载
    if (_needsInlineHtml && _inlineHtmlContent == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        InAppWebView(
          key: _webViewKey,
          initialFile: _needsInlineHtml ? null : '$_assetBasePath/index.html',
          initialData: _needsInlineHtml && _inlineHtmlContent != null
              ? InAppWebViewInitialData(
                  data: _inlineHtmlContent!,
                  mimeType: 'text/html',
                  encoding: 'utf-8',
                )
              : null,
          initialSettings: InAppWebViewSettings(
            isInspectable: kDebugMode,
            javaScriptEnabled: true,
            transparentBackground: true,
            supportZoom: false,
            verticalScrollBarEnabled: false,
            horizontalScrollBarEnabled: false,
            disableVerticalScroll: true,
          ),
          onWebViewCreated: (controller) {
            _webViewController = controller;
            widget.controller.setWebViewController(controller);
            _addJavaScriptHandlers();
          },
          onLoadStop: (controller, url) async {
            // 移动端：HTML 加载完成后，等待 book.js 初始化完成再加载书籍
            if (!_needsInlineHtml) {
              // 移动端需要等待 book.js 准备好
              // 通过定时检查 reader 对象是否存在
              await _waitForReaderAndLoadBook();
            }
          },
          onConsoleMessage: (controller, message) {
            if (kDebugMode) {
              debugPrint('Foliate JS: ${message.message}');
            }
          },
        ),
        // 加载指示器
        if (_isLoading)
          ColoredBox(
            color: widget.backgroundColor ?? Colors.white,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  /// 移动端等待 reader 准备好并加载书籍
  Future<void> _waitForReaderAndLoadBook() async {
    // 移动端使用原生的 book.js 逻辑，通过 URL 参数初始化
    // 但我们需要通过 JavaScript 注入书籍数据

    // 等待 WebView 完全加载
    await Future<void>.delayed(const Duration(milliseconds: 500));

    _isWebViewReady = true;

    // 注入初始化函数（如果不存在）
    await _webViewController?.evaluateJavascript(source: '''
      if (!window.initFoliateBook) {
        window.initFoliateBook = async function(base64Data, bookType, initialCfi, styleJson) {
          try {
            // 解码 base64 数据
            const binaryString = atob(base64Data);
            const bytes = new Uint8Array(binaryString.length);
            for (let i = 0; i < binaryString.length; i++) {
              bytes[i] = binaryString.charCodeAt(i);
            }
            const blob = new Blob([bytes]);
            const file = new File([blob], 'book.' + bookType);

            // 设置样式
            if (styleJson && !window.style) {
              window.style = JSON.parse(styleJson);
            }

            if (!window.readingRules) {
              window.readingRules = {
                convertChineseMode: 'none',
                bionicReadingMode: false
              };
            }

            window.importing = false;

            // 使用 foliateOpen 函数打开书籍
            if (typeof window.foliateOpen === 'function') {
              await window.foliateOpen(file, initialCfi || null);
            } else if (typeof open === 'function') {
              // 回退：尝试模块作用域的 open 函数
              await open(file, initialCfi || null);
            } else {
              throw new Error('Reader not initialized');
            }

          } catch (error) {
            console.error('Init book error:', error);
            window.flutter_inappwebview.callHandler('onError', error.message || '加载失败');
          }
        };
      }
    ''');

    // 加载书籍
    await _loadBook();
  }
}
