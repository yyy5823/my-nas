import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
    this.onTocLoaded,
    this.onError,
    this.onFootnoteOpen,
    this.onFootnoteClose,
    this.style,
    this.backgroundColor,
    this.textColor,
    this.fontSize = 100,
    this.lineHeight = 1.5,
    this.loadingWidget,
    this.disableNativeGestures = false,
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

  /// 目录加载完成回调
  final void Function(List<FoliateTocItem> toc)? onTocLoaded;

  /// 错误回调
  final void Function(String error)? onError;

  /// 脚注打开回调
  final VoidCallback? onFootnoteOpen;

  /// 脚注关闭回调
  final VoidCallback? onFootnoteClose;

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

  /// 自定义加载指示器
  final Widget? loadingWidget;

  /// 是否禁用 WebView 原生手势处理（用于 Flutter 层面的翻页效果）
  final bool disableNativeGestures;

  @override
  State<FoliateViewer> createState() => _FoliateViewerState();
}

class _FoliateViewerState extends State<FoliateViewer> {
  final GlobalKey _webViewKey = GlobalKey();
  InAppWebViewController? _webViewController;

  /// 内联 HTML 内容（所有平台都使用内联 HTML）
  String? _inlineHtmlContent;
  bool _isLoading = true;
  bool _isWebViewReady = false;

  /// 资源基础路径
  static const String _assetBasePath =
      'packages/flutter_foliate_viewer/lib/assets/foliate-js';

  @override
  void initState() {
    super.initState();
    // 所有平台都使用内联 HTML 方式加载，确保跨平台一致性
    _loadInlineHtml();
  }

  /// 加载内联 HTML（所有平台统一使用）
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
      position: fixed;
      left: 5%;
      right: 5%;
      bottom: 10%;
      max-height: 50%;
      margin: 0;
      padding: 0;
      border: none;
      border-radius: 16px;
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.25), 0 2px 8px rgba(0, 0, 0, 0.15);
      background: var(--footnote-bg, #ffffff);
      z-index: 9999;
      overflow: hidden;
      animation: footnote-slide-up 0.25s ease-out;
    }
    #footnote-dialog.dark {
      background: var(--footnote-bg, #2d2d2d);
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5), 0 2px 8px rgba(0, 0, 0, 0.3);
    }
    @keyframes footnote-slide-up {
      from {
        opacity: 0;
        transform: translateY(20px);
      }
      to {
        opacity: 1;
        transform: translateY(0);
      }
    }
    #footnote-dialog .footnote-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 12px 16px;
      border-bottom: 1px solid rgba(128, 128, 128, 0.2);
      background: inherit;
    }
    #footnote-dialog .footnote-title {
      font-size: 14px;
      font-weight: 600;
      color: var(--footnote-text, #333);
      margin: 0;
    }
    #footnote-dialog.dark .footnote-title {
      color: var(--footnote-text, #e0e0e0);
    }
    #footnote-dialog .footnote-close {
      width: 28px;
      height: 28px;
      border: none;
      border-radius: 50%;
      background: rgba(128, 128, 128, 0.15);
      color: var(--footnote-text, #666);
      font-size: 18px;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: background 0.2s;
    }
    #footnote-dialog .footnote-close:hover {
      background: rgba(128, 128, 128, 0.25);
    }
    #footnote-dialog.dark .footnote-close {
      color: var(--footnote-text, #aaa);
    }
    #footnote-dialog main {
      padding: 16px;
      overflow-y: auto;
      max-height: calc(50vh - 60px);
    }
    #footnote-backdrop {
      display: none;
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background: rgba(0, 0, 0, 0.3);
      z-index: 9998;
      animation: footnote-fade-in 0.2s ease-out;
    }
    @keyframes footnote-fade-in {
      from { opacity: 0; }
      to { opacity: 1; }
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
      background: transparent;
    }
  </style>
</head>
<body>
  <div id="footnote-backdrop"></div>
  <div id="footnote-dialog">
    <div class="footnote-header">
      <span class="footnote-title">注释</span>
      <button class="footnote-close" aria-label="关闭">×</button>
    </div>
    <main></main>
  </div>
  <div id="loading"></div>

  <script>
    // 拦截 URL 参数，阻止 book.js 自动初始化
    window.__foliateManualInit = true;
    window.__foliateBookData = null;
    window.__foliateInitialCfi = null;
    window.__foliateStyle = null;

    // 禁用触摸导航的标志（用于 Flutter 处理手势时）
    window.__foliateDisableTouchNav = false;

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

    // 设置是否禁用触摸导航（Flutter 调用）
    window.setDisableTouchNav = function(disable) {
      window.__foliateDisableTouchNav = disable;
      console.log('setDisableTouchNav:', disable);
    };

    // 拦截触摸事件（在最高优先级捕获阶段阻止）
    document.addEventListener('touchstart', function(e) {
      if (window.__foliateDisableTouchNav) {
        e.stopPropagation();
      }
    }, { capture: true, passive: false });

    document.addEventListener('touchmove', function(e) {
      if (window.__foliateDisableTouchNav) {
        e.stopPropagation();
        e.preventDefault();
      }
    }, { capture: true, passive: false });

    document.addEventListener('touchend', function(e) {
      if (window.__foliateDisableTouchNav) {
        e.stopPropagation();
      }
    }, { capture: true, passive: false });
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
            maxColumnCount: 1, // 强制单列显示
            customCSS: '',
            customCSSEnabled: false
          };
        }

        window.readingRules = {
          convertChineseMode: 'none',
          bionicReadingMode: false
        };

        window.importing = false;

        // 设置模块级变量（book.js 中的 style, readingRules, importing）
        if (typeof window.setFoliateVars === 'function') {
          window.setFoliateVars(window.style, window.readingRules, window.importing);
        }

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
        if (args.isNotEmpty && widget.onTocLoaded != null) {
          try {
            List<dynamic> list;
            if (args[0] is List) {
              list = args[0] as List<dynamic>;
            } else if (args[0] is String) {
              list = jsonDecode(args[0] as String) as List<dynamic>;
            } else {
              list = [];
            }
            final toc = list
                .map(
                  (e) =>
                      FoliateTocItem.fromMap(Map<String, dynamic>.from(e as Map)),
                )
                .toList();
            widget.onTocLoaded?.call(toc);
            if (kDebugMode) {
              debugPrint('TOC loaded: ${toc.length} items');
            }
          } on Exception catch (e) {
            if (kDebugMode) {
              debugPrint('Failed to parse TOC: $e');
            }
          }
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

    // 脚注打开
    _webViewController?.addJavaScriptHandler(
      handlerName: 'onFootnoteOpen',
      callback: (args) {
        widget.onFootnoteOpen?.call();
      },
    );

    // 脚注关闭
    _webViewController?.addJavaScriptHandler(
      handlerName: 'onFootnoteClose',
      callback: (args) {
        widget.onFootnoteClose?.call();
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
          'maxColumnCount': 1, // 强制单列显示
          'customCSS': '',
          'customCSSEnabled': false,
        });
      }

      // 调用初始化函数
      final jsCode = '''
        window.initFoliateBook('$base64Data', '$bookType', '$initialCfi', '$styleJson');
      ''';

      await _webViewController?.evaluateJavascript(source: jsCode);

      // 如果禁用原生手势，阻止 WebView JavaScript 处理触摸导航
      if (widget.disableNativeGestures) {
        await _webViewController?.evaluateJavascript(
          source: 'window.setDisableTouchNav(true);',
        );
      }
    } on Exception catch (e) {
      widget.onError?.call('加载书籍失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 获取加载背景色
  Color get _loadingBackgroundColor {
    if (widget.style?.backgroundColor != null) {
      return widget.style!.backgroundColor!;
    }
    return widget.backgroundColor ?? Colors.white;
  }

  /// 构建默认加载指示器
  Widget _buildDefaultLoadingWidget() {
    final bgColor = _loadingBackgroundColor;
    final isDark = bgColor.computeLuminance() < 0.5;
    return ColoredBox(
      color: bgColor,
      child: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(
            isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 等待 HTML 加载完成
    if (_inlineHtmlContent == null) {
      return widget.loadingWidget ?? _buildDefaultLoadingWidget();
    }

    return Stack(
      children: [
        InAppWebView(
          key: _webViewKey,
          initialData: InAppWebViewInitialData(
            data: _inlineHtmlContent!,
            mimeType: 'text/html',
            encoding: 'utf-8',
            // 设置 baseUrl 以便相对路径资源能正确加载
            baseUrl: WebUri('about:blank'),
          ),
          // 当禁用原生手势时，传入空集合让 Flutter 层处理所有手势
          gestureRecognizers: widget.disableNativeGestures
              ? <Factory<OneSequenceGestureRecognizer>>{}
              : null,
          initialSettings: InAppWebViewSettings(
            isInspectable: kDebugMode,
            javaScriptEnabled: true,
            transparentBackground: true,
            supportZoom: false,
            verticalScrollBarEnabled: false,
            horizontalScrollBarEnabled: false,
            disableVerticalScroll: true,
            disableHorizontalScroll: widget.disableNativeGestures,
            // iOS 特定设置
            allowsInlineMediaPlayback: true,
            // Android 特定设置
            useHybridComposition: true,
          ),
          onWebViewCreated: (controller) {
            _webViewController = controller;
            widget.controller.setWebViewController(controller);
            _addJavaScriptHandlers();
          },
          onConsoleMessage: (controller, message) {
            if (kDebugMode) {
              debugPrint('Foliate JS: ${message.message}');
            }
          },
          onReceivedError: (controller, request, error) {
            debugPrint('Foliate WebView Error: ${error.type} - ${error.description}');
            if (error.type == WebResourceErrorType.UNKNOWN) {
              widget.onError?.call('加载错误: ${error.description}');
            }
          },
          onLoadStop: (controller, url) {
            if (kDebugMode) {
              debugPrint('Foliate WebView: Load completed');
            }
          },
        ),
        // 加载指示器
        if (_isLoading)
          widget.loadingWidget ?? _buildDefaultLoadingWidget(),
      ],
    );
  }

}
