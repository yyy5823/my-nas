import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/network/http_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_file_cache_service.dart';
import 'package:my_nas/features/book/data/services/mobi_parser_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';
import 'package:my_nas/shared/widgets/reader_settings_sheet.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 阅读器状态
final txtReaderProvider =
    StateNotifierProvider.family<TxtReaderNotifier, TxtReaderState, BookItem>(
      (ref, book) => TxtReaderNotifier(book, ref),
    );

sealed class TxtReaderState {}

class TxtReaderLoading extends TxtReaderState {
  TxtReaderLoading({this.message = '加载中...'});

  final String message;
}

class TxtReaderLoaded extends TxtReaderState {
  TxtReaderLoaded({
    required this.content,
    this.htmlContent,
    this.scrollPosition = 0.0,
  });

  final String content;
  final String? htmlContent; // 原始 HTML 内容（用于 MOBI 等格式）
  final double scrollPosition;

  /// 是否有 HTML 内容可用
  bool get hasHtml => htmlContent != null && htmlContent!.isNotEmpty;

  TxtReaderLoaded copyWith({
    String? content,
    String? htmlContent,
    double? scrollPosition,
  }) =>
      TxtReaderLoaded(
        content: content ?? this.content,
        htmlContent: htmlContent ?? this.htmlContent,
        scrollPosition: scrollPosition ?? this.scrollPosition,
      );
}

class TxtReaderError extends TxtReaderState {
  TxtReaderError(this.message);

  final String message;
}

class TxtReaderNotifier extends StateNotifier<TxtReaderState> {
  TxtReaderNotifier(this.book, this._ref) : super(TxtReaderLoading()) {
    loadBook();
  }

  final BookItem book;
  final Ref _ref;
  final ReadingProgressService _progressService = ReadingProgressService();
  final BookFileCacheService _cacheService = BookFileCacheService();

  /// 获取文件系统（如果有 sourceId）
  NasFileSystem? _getFileSystem() {
    if (book.sourceId == null) return null;
    final connections = _ref.read(activeConnectionsProvider);
    final connection = connections[book.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      return null;
    }
    return connection.adapter.fileSystem;
  }

  Future<void> loadBook() async {
    state = TxtReaderLoading();

    try {
      // 初始化缓存服务
      await _cacheService.init();

      String content;
      String? htmlContent;

      switch (book.format) {
        case BookFormat.txt:
          content = await _loadTxtBook();
        case BookFormat.epub:
          // EPUB 使用专门的 EpubReaderPage
          state = TxtReaderError('请使用 EPUB 阅读器');
          return;
        case BookFormat.pdf:
          // PDF 使用专门的 PdfReaderPage
          state = TxtReaderError('请使用 PDF 阅读器');
          return;
        case BookFormat.mobi:
        case BookFormat.azw3:
          final result = await _loadMobiBook();
          content = result.content;
          htmlContent = result.htmlContent;
        case BookFormat.unknown:
          state = TxtReaderError('未知的电子书格式');
          return;
      }

      // 恢复阅读进度
      await _progressService.init();
      final itemId = _progressService.generateItemId(book.id, book.path);
      final progress = _progressService.getProgress(itemId);

      state = TxtReaderLoaded(
        content: content,
        htmlContent: htmlContent,
        scrollPosition: progress?.position ?? 0.0,
      );
    } on Exception catch (e) {
      state = TxtReaderError(e.toString());
    }
  }

  /// 从流中读取所有字节
  Future<Uint8List> _readStreamBytes(Stream<List<int>> stream) async {
    final chunks = <List<int>>[];
    await for (final chunk in stream) {
      chunks.add(chunk);
    }
    final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final result = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }

  Future<String> _loadTxtBook() async {
    final uri = Uri.parse(book.url);
    List<int> bytes;

    // 优先使用流式加载（支持 SMB/WebDAV 等协议）
    final fileSystem = _getFileSystem();
    if (fileSystem != null) {
      state = TxtReaderLoading(message: '流式加载中...');
      final stream = await fileSystem.getFileStream(book.path);
      bytes = await _readStreamBytes(stream);
    } else if (uri.scheme == 'file') {
      // 本地文件
      final localFile = File(uri.toFilePath());
      if (!await localFile.exists()) {
        throw Exception('文件不存在');
      }
      bytes = await localFile.readAsBytes();
    } else if (uri.scheme == 'http' || uri.scheme == 'https') {
      // HTTP 远程文件
      final response = await InsecureHttpClient.get(uri);
      if (response.statusCode != 200) {
        throw Exception('加载失败: ${response.statusCode}');
      }
      bytes = response.bodyBytes;
    } else {
      throw Exception('不支持的协议: ${uri.scheme}');
    }

    // 尝试检测编码
    String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      // 尝试 GBK/GB2312
      content = _decodeGbk(bytes);
    }

    return content;
  }

  String _decodeGbk(List<int> bytes) => String.fromCharCodes(bytes);

  /// 加载 MOBI/AZW3 电子书
  Future<({String content, String? htmlContent})> _loadMobiBook() async {
    Uint8List bytes;

    // 检查是否有缓存
    final cachedFile = await _cacheService.getCachedFile(
      book.sourceId,
      book.path,
    );

    if (cachedFile != null) {
      state = TxtReaderLoading(message: '使用缓存...');
      bytes = await cachedFile.readAsBytes();
      logger.i('MOBI 使用缓存: ${cachedFile.path}');
    } else {
      // 需要下载文件
      final uri = Uri.parse(book.url);

      final fileSystem = _getFileSystem();
      if (fileSystem != null) {
        state = TxtReaderLoading(message: '加载文件中...');
        final stream = await fileSystem.getFileStream(book.path);
        bytes = await _readStreamBytes(stream);
      } else if (uri.scheme == 'file') {
        final localFile = File(uri.toFilePath());
        if (!await localFile.exists()) {
          throw Exception('文件不存在');
        }
        bytes = await localFile.readAsBytes();
      } else if (uri.scheme == 'http' || uri.scheme == 'https') {
        state = TxtReaderLoading(message: '下载中...');
        final response = await InsecureHttpClient.get(uri);
        if (response.statusCode != 200) {
          throw Exception('加载失败: ${response.statusCode}');
        }
        bytes = response.bodyBytes;
      } else {
        throw Exception('不支持的协议: ${uri.scheme}');
      }

      // 保存到缓存
      state = TxtReaderLoading(message: '缓存文件...');
      await _cacheService.saveToCache(book.sourceId, book.path, bytes);
    }

    // 使用 MOBI 解析器
    state = TxtReaderLoading(message: '解析中...');
    final parser = MobiParserService();
    final fileName = path.basename(book.path);
    final result = await parser.parse(bytes, fileName);

    if (!result.success) {
      throw Exception(result.error ?? '解析失败');
    }

    return (content: result.content ?? '', htmlContent: result.htmlContent);
  }

  void setScrollPosition(double position) {
    final current = state;
    if (current is TxtReaderLoaded) {
      state = current.copyWith(scrollPosition: position);
    }
  }

  Future<void> saveProgress(double position, double maxPosition) async {
    final current = state;
    if (current is TxtReaderLoaded) {
      final itemId = _progressService.generateItemId(book.id, book.path);
      await _progressService.saveProgress(
        ReadingProgress(
          itemId: itemId,
          itemType: 'txt',
          position: position,
          totalPositions: maxPosition.toInt(),
          lastReadAt: DateTime.now(),
        ),
      );
    }
  }
}

class BookReaderPage extends ConsumerStatefulWidget {
  const BookReaderPage({required this.book, super.key});

  final BookItem book;

  @override
  ConsumerState<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends ConsumerState<BookReaderPage> {
  bool _showControls = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWakelock();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initWakelock() async {
    final settings = ref.read(bookReaderSettingsProvider);
    if (settings.keepScreenOn) {
      await WakelockPlus.enable();
    }
  }

  void _onScroll() {
    // 保存滚动位置
    if (_scrollController.hasClients) {
      final position = _scrollController.position.pixels;
      final maxPosition = _scrollController.position.maxScrollExtent;
      ref
          .read(txtReaderProvider(widget.book).notifier)
          .setScrollPosition(position);
      // 定期保存进度
      if (position % 500 < 10) {
        ref
            .read(txtReaderProvider(widget.book).notifier)
            .saveProgress(position, maxPosition);
      }
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    _scrollController..removeListener(_onScroll)
    ..dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _showSettingsSheet(BookReaderSettings settings) {
    showReaderSettingsSheet(
      context,
      title: '阅读设置',
      icon: Icons.auto_stories_rounded,
      iconColor: AppColors.info,
      content: _buildSettingsContent(settings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(txtReaderProvider(widget.book));
    final settings = ref.watch(bookReaderSettingsProvider);

    return Scaffold(
      backgroundColor: settings.theme.backgroundColor,
      body: switch (state) {
        TxtReaderLoading(:final message) => LoadingWidget(message: message),
        TxtReaderError(:final message) => AppErrorWidget(
          message: message,
          onRetry: () =>
              ref.read(txtReaderProvider(widget.book).notifier).loadBook(),
        ),
        TxtReaderLoaded() => _buildReader(context, state, settings),
      },
    );
  }

  Widget _buildReader(
    BuildContext context,
    TxtReaderLoaded state,
    BookReaderSettings settings,
  ) {
    final theme = settings.theme;

    return Stack(
      children: [
        // 阅读内容
        ColoredBox(
          color: theme.backgroundColor,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _toggleControls,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: EdgeInsets.symmetric(
                        horizontal: settings.horizontalPadding,
                        vertical: settings.verticalPadding,
                      ),
                      child: _buildContent(state, settings),
                    ),
                  ),
                ),
                // 进度指示器
                if (settings.showProgress)
                  Container(
                    padding: EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: settings.horizontalPadding,
                    ),
                    color: theme.backgroundColor,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.book.displayName,
                          style: TextStyle(
                            color: theme.textColor.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _getProgressText(state),
                          style: TextStyle(
                            color: theme.textColor.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 点击翻页区域
        if (settings.tapToTurn) _buildTapZones(settings),

        // 顶部控制栏
        if (_showControls)
          Positioned(top: 0, left: 0, right: 0, child: _buildTopBar(context)),

        // 底部控制栏
        if (_showControls)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(context, settings),
          ),
      ],
    );
  }

  Widget _buildContent(TxtReaderLoaded state, BookReaderSettings settings) {
    // 如果有 HTML 内容，使用 flutter_html 渲染
    if (state.hasHtml) {
      return _buildHtmlContent(state.htmlContent!, settings);
    }

    // 否则使用纯文本渲染
    return _buildTextContent(state.content, settings);
  }

  /// 使用 flutter_html 渲染 HTML 内容
  Widget _buildHtmlContent(String htmlContent, BookReaderSettings settings) {
    final theme = settings.theme;

    // 清理 HTML 中的无效 CSS 颜色值
    final cleanedHtml = _cleanInvalidCssColors(htmlContent);

    // 构建 HTML 样式
    final style = {
      'body': Style(
        fontSize: FontSize(settings.fontSize),
        lineHeight: LineHeight(settings.lineHeight),
        color: theme.textColor,
        fontFamily: settings.fontFamily,
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
      ),
      'p': Style(
        margin: Margins.only(bottom: settings.paragraphSpacing * 16),
        textAlign: TextAlign.justify,
      ),
      'h1': Style(
        fontSize: FontSize(settings.fontSize * 1.5),
        fontWeight: FontWeight.bold,
        margin: Margins.only(top: 24, bottom: 16),
      ),
      'h2': Style(
        fontSize: FontSize(settings.fontSize * 1.3),
        fontWeight: FontWeight.bold,
        margin: Margins.only(top: 20, bottom: 12),
      ),
      'h3': Style(
        fontSize: FontSize(settings.fontSize * 1.15),
        fontWeight: FontWeight.bold,
        margin: Margins.only(top: 16, bottom: 8),
      ),
      'h4': Style(
        fontSize: FontSize(settings.fontSize * 1.05),
        fontWeight: FontWeight.bold,
        margin: Margins.only(top: 12, bottom: 6),
      ),
      'h5': Style(
        fontSize: FontSize(settings.fontSize),
        fontWeight: FontWeight.bold,
        margin: Margins.only(top: 8, bottom: 4),
      ),
      'h6': Style(
        fontSize: FontSize(settings.fontSize * 0.9),
        fontWeight: FontWeight.bold,
        margin: Margins.only(top: 8, bottom: 4),
      ),
      'blockquote': Style(
        margin: Margins.symmetric(vertical: 12, horizontal: 16),
        padding: HtmlPaddings.only(left: 12),
        border: Border(
          left: BorderSide(
            color: theme.textColor.withValues(alpha: 0.3),
            width: 3,
          ),
        ),
        fontStyle: FontStyle.italic,
      ),
      'a': Style(
        color: Colors.blue,
        textDecoration: TextDecoration.underline,
      ),
      'img': Style(
        display: Display.none, // 隐藏图片，避免加载问题
      ),
      'ul': Style(
        margin: Margins.only(bottom: 12),
        padding: HtmlPaddings.only(left: 20),
      ),
      'ol': Style(
        margin: Margins.only(bottom: 12),
        padding: HtmlPaddings.only(left: 20),
      ),
      'li': Style(
        margin: Margins.only(bottom: 4),
      ),
      'pre': Style(
        backgroundColor: theme.textColor.withValues(alpha: 0.05),
        padding: HtmlPaddings.all(12),
        margin: Margins.symmetric(vertical: 8),
      ),
      'code': Style(
        backgroundColor: theme.textColor.withValues(alpha: 0.05),
        fontFamily: 'monospace',
        fontSize: FontSize(settings.fontSize * 0.9),
      ),
    };

    return Html(
      data: cleanedHtml,
      style: style,
      onLinkTap: (url, attributes, element) {
        if (url != null) {
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      },
    );
  }

  /// 修复 HTML 中的无效 CSS 颜色值
  /// flutter_html 无法解析某些格式不正确的颜色值（如 0x0000c 应该是 #0000cc）
  String _cleanInvalidCssColors(String html) {
    var cleaned = html;

    // 修复 style 属性中的颜色值
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'style\s*=\s*"([^"]*)"', caseSensitive: false),
      (match) {
        final styleContent = match.group(1) ?? '';
        final fixedStyle = _fixColorValuesInStyle(styleContent);
        if (fixedStyle.isEmpty) {
          return '';
        }
        return 'style="$fixedStyle"';
      },
    );

    // 同样处理单引号的 style 属性
    cleaned = cleaned.replaceAllMapped(
      RegExp(r"style\s*=\s*'([^']*)'", caseSensitive: false),
      (match) {
        final styleContent = match.group(1) ?? '';
        final fixedStyle = _fixColorValuesInStyle(styleContent);
        if (fixedStyle.isEmpty) {
          return '';
        }
        return "style='$fixedStyle'";
      },
    );

    // 修复 <font color="..."> 标签的 color 属性
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'color\s*=\s*"([^"]*)"', caseSensitive: false),
      (match) {
        final colorValue = match.group(1) ?? '';
        final fixedColor = _fixColorValue(colorValue);
        if (fixedColor == null) {
          return '';
        }
        return 'color="$fixedColor"';
      },
    );

    cleaned = cleaned.replaceAllMapped(
      RegExp(r"color\s*=\s*'([^']*)'", caseSensitive: false),
      (match) {
        final colorValue = match.group(1) ?? '';
        final fixedColor = _fixColorValue(colorValue);
        if (fixedColor == null) {
          return '';
        }
        return "color='$fixedColor'";
      },
    );

    // 修复 bgcolor 属性
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'bgcolor\s*=\s*"([^"]*)"', caseSensitive: false),
      (match) {
        final colorValue = match.group(1) ?? '';
        final fixedColor = _fixColorValue(colorValue);
        if (fixedColor == null) {
          return '';
        }
        return 'bgcolor="$fixedColor"';
      },
    );

    cleaned = cleaned.replaceAllMapped(
      RegExp(r"bgcolor\s*=\s*'([^']*)'", caseSensitive: false),
      (match) {
        final colorValue = match.group(1) ?? '';
        final fixedColor = _fixColorValue(colorValue);
        if (fixedColor == null) {
          return '';
        }
        return "bgcolor='$fixedColor'";
      },
    );

    return cleaned;
  }

  /// 修复 style 属性中的颜色值
  String _fixColorValuesInStyle(String style) =>
      // 匹配 color: xxx 或 background-color: xxx 或 background: xxx
      style.replaceAllMapped(
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

  /// 修复单个颜色值，返回 null 表示无法修复
  String? _fixColorValue(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return null;

    // 已经是有效的颜色名称
    if (_isValidColorName(trimmed)) {
      return trimmed;
    }

    // 已经是有效的 # 格式
    if (trimmed.startsWith('#')) {
      final hex = trimmed.substring(1);
      if (_isValidHexColor(hex)) {
        return trimmed;
      }
      // 尝试修复不完整的 hex
      final fixed = _fixHexColor(hex);
      return fixed != null ? '#$fixed' : null;
    }

    // 0x 格式转换为 # 格式
    if (trimmed.startsWith('0x')) {
      final hex = trimmed.substring(2);
      final fixed = _fixHexColor(hex);
      return fixed != null ? '#$fixed' : null;
    }

    // rgb/rgba 格式
    if (trimmed.startsWith('rgb')) {
      return value; // 假设 rgb/rgba 格式是有效的
    }

    // 其他格式尝试当作 hex 处理
    if (RegExp(r'^[0-9a-f]+$').hasMatch(trimmed)) {
      final fixed = _fixHexColor(trimmed);
      return fixed != null ? '#$fixed' : null;
    }

    return null;
  }

  /// 修复不完整的 hex 颜色值
  String? _fixHexColor(String hex) {
    // 移除可能的前缀
    var cleaned = hex.replaceAll(RegExp('^[0x#]+'), '');

    // 只保留有效的 hex 字符
    cleaned = cleaned.replaceAll(RegExp('[^0-9a-fA-F]'), '');

    if (cleaned.isEmpty) return null;

    // 3位 -> 有效
    if (cleaned.length == 3) {
      return cleaned;
    }

    // 4位 -> 补齐到6位（可能是 RGBA 的缩写，取前3位扩展）
    if (cleaned.length == 4) {
      return '${cleaned[0]}${cleaned[0]}${cleaned[1]}${cleaned[1]}${cleaned[2]}${cleaned[2]}';
    }

    // 5位 -> 补齐到6位
    if (cleaned.length == 5) {
      return '${cleaned}0';
    }

    // 6位 -> 有效
    if (cleaned.length == 6) {
      return cleaned;
    }

    // 7位 -> 补齐到8位
    if (cleaned.length == 7) {
      return '${cleaned}0';
    }

    // 8位 -> 有效 (RRGGBBAA)
    if (cleaned.length == 8) {
      return cleaned;
    }

    // 超过8位，截取前6位
    if (cleaned.length > 8) {
      return cleaned.substring(0, 6);
    }

    // 少于3位，无法修复
    return null;
  }

  /// 检查是否是有效的 hex 颜色
  bool _isValidHexColor(String hex) {
    final length = hex.length;
    if (length != 3 && length != 4 && length != 6 && length != 8) {
      return false;
    }
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex);
  }

  /// 检查是否是有效的颜色名称
  bool _isValidColorName(String name) {
    const validColors = {
      'transparent', 'currentcolor', 'inherit',
      // 基本颜色
      'black', 'white', 'red', 'green', 'blue', 'yellow', 'cyan', 'magenta',
      'gray', 'grey', 'silver', 'maroon', 'olive', 'lime', 'aqua', 'teal',
      'navy', 'fuchsia', 'purple', 'orange', 'pink', 'brown', 'gold',
      // 扩展颜色
      'aliceblue', 'antiquewhite', 'aquamarine', 'azure', 'beige', 'bisque',
      'blanchedalmond', 'blueviolet', 'burlywood', 'cadetblue', 'chartreuse',
      'chocolate', 'coral', 'cornflowerblue', 'cornsilk', 'crimson',
      'darkblue', 'darkcyan', 'darkgoldenrod', 'darkgray', 'darkgreen',
      'darkgrey', 'darkkhaki', 'darkmagenta', 'darkolivegreen', 'darkorange',
      'darkorchid', 'darkred', 'darksalmon', 'darkseagreen', 'darkslateblue',
      'darkslategray', 'darkslategrey', 'darkturquoise', 'darkviolet',
      'deeppink', 'deepskyblue', 'dimgray', 'dimgrey', 'dodgerblue',
      'firebrick', 'floralwhite', 'forestgreen', 'gainsboro', 'ghostwhite',
      'goldenrod', 'greenyellow', 'honeydew', 'hotpink', 'indianred',
      'indigo', 'ivory', 'khaki', 'lavender', 'lavenderblush', 'lawngreen',
      'lemonchiffon', 'lightblue', 'lightcoral', 'lightcyan',
      'lightgoldenrodyellow', 'lightgray', 'lightgreen', 'lightgrey',
      'lightpink', 'lightsalmon', 'lightseagreen', 'lightskyblue',
      'lightslategray', 'lightslategrey', 'lightsteelblue', 'lightyellow',
      'limegreen', 'linen', 'mediumaquamarine', 'mediumblue', 'mediumorchid',
      'mediumpurple', 'mediumseagreen', 'mediumslateblue', 'mediumspringgreen',
      'mediumturquoise', 'mediumvioletred', 'midnightblue', 'mintcream',
      'mistyrose', 'moccasin', 'navajowhite', 'oldlace', 'olivedrab',
      'orangered', 'orchid', 'palegoldenrod', 'palegreen', 'paleturquoise',
      'palevioletred', 'papayawhip', 'peachpuff', 'peru', 'plum', 'powderblue',
      'rosybrown', 'royalblue', 'saddlebrown', 'salmon', 'sandybrown',
      'seagreen', 'seashell', 'sienna', 'skyblue', 'slateblue', 'slategray',
      'slategrey', 'snow', 'springgreen', 'steelblue', 'tan', 'thistle',
      'tomato', 'turquoise', 'violet', 'wheat', 'whitesmoke', 'yellowgreen',
    };
    return validColors.contains(name.toLowerCase());
  }

  /// 使用纯文本渲染
  Widget _buildTextContent(String content, BookReaderSettings settings) {
    final theme = settings.theme;

    // 智能段落检测
    final paragraphs = _splitIntoParagraphs(content);
    final children = <Widget>[];

    for (var i = 0; i < paragraphs.length; i++) {
      if (paragraphs[i].trim().isEmpty) continue;
      children.add(
        Padding(
          padding: EdgeInsets.only(
            bottom: i < paragraphs.length - 1
                ? settings.paragraphSpacing * 16
                : 0,
          ),
          child: SelectableText(
            paragraphs[i].trim(),
            style: TextStyle(
              fontSize: settings.fontSize,
              height: settings.lineHeight,
              color: theme.textColor,
              fontFamily: settings.fontFamily,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// 智能段落分割
  /// 支持多种段落格式：
  /// 1. 双换行分隔 (\n\n)
  /// 2. 中文段落缩进（以全角空格或两个空格开头）
  /// 3. 单换行但下一行有缩进
  List<String> _splitIntoParagraphs(String content) {
    // 首先尝试按双换行分割
    final doubleNewlineParagraphs = content.split(RegExp(r'\n\s*\n'));
    if (doubleNewlineParagraphs.length > 10) {
      // 如果有足够多的双换行段落，使用这种方式
      return doubleNewlineParagraphs;
    }

    // 否则尝试智能分割
    final lines = content.split('\n');
    final paragraphs = <String>[];
    final currentParagraph = StringBuffer();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmedLine = line.trim();

      if (trimmedLine.isEmpty) {
        // 空行表示段落结束
        if (currentParagraph.isNotEmpty) {
          paragraphs.add(currentParagraph.toString().trim());
          currentParagraph.clear();
        }
        continue;
      }

      // 检测是否是新段落的开始
      final isNewParagraph = _isNewParagraphStart(line, trimmedLine);

      if (isNewParagraph && currentParagraph.isNotEmpty) {
        // 保存当前段落，开始新段落
        paragraphs.add(currentParagraph.toString().trim());
        currentParagraph.clear();
      }

      if (currentParagraph.isNotEmpty) {
        currentParagraph.write(' ');
      }
      currentParagraph.write(trimmedLine);
    }

    // 添加最后一个段落
    if (currentParagraph.isNotEmpty) {
      paragraphs.add(currentParagraph.toString().trim());
    }

    return paragraphs.isEmpty ? [content] : paragraphs;
  }

  /// 检测是否是新段落的开始
  bool _isNewParagraphStart(String line, String trimmedLine) {
    // 1. 以全角空格开头（中文段落缩进）
    if (line.startsWith('\u3000') || line.startsWith('　')) {
      return true;
    }

    // 2. 以两个或更多空格开头
    if (line.startsWith('  ')) {
      return true;
    }

    // 3. 以章节标题开头（第X章、Chapter X 等）
    if (RegExp(r'^(第[一二三四五六七八九十百千万\d]+[章节回篇卷集部]|Chapter\s*\d+|CHAPTER\s*\d+)', caseSensitive: false)
        .hasMatch(trimmedLine)) {
      return true;
    }

    // 4. 以数字序号开头（1. 2. 等）
    if (RegExp(r'^\d+[.、．]\s').hasMatch(trimmedLine)) {
      return true;
    }

    return false;
  }

  String _getProgressText(TxtReaderLoaded state) {
    if (!_scrollController.hasClients) return '0%';
    final position = _scrollController.position.pixels;
    final maxPosition = _scrollController.position.maxScrollExtent;
    if (maxPosition <= 0) return '0%';
    final progress = (position / maxPosition * 100).clamp(0, 100);
    return '${progress.toStringAsFixed(0)}%';
  }

  Widget _buildTapZones(BookReaderSettings settings) => Positioned.fill(
    child: Row(
      children: [
        // 左侧 - 向上滚动
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  (_scrollController.offset -
                          MediaQuery.of(context).size.height * 0.8)
                      .clamp(0, _scrollController.position.maxScrollExtent),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            },
            behavior: HitTestBehavior.translucent,
            child: Container(),
          ),
        ),
        // 中间 - 显示/隐藏控制栏
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: _toggleControls,
            behavior: HitTestBehavior.translucent,
            child: Container(),
          ),
        ),
        // 右侧 - 向下滚动
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  (_scrollController.offset +
                          MediaQuery.of(context).size.height * 0.8)
                      .clamp(0, _scrollController.position.maxScrollExtent),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            },
            behavior: HitTestBehavior.translucent,
            child: Container(),
          ),
        ),
      ],
    ),
  );

  Widget _buildTopBar(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              tooltip: '返回',
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.book.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 48), // 平衡布局
          ],
        ),
      ),
    ),
  );

  Widget _buildBottomBar(BuildContext context, BookReaderSettings settings) {
    final settingsNotifier = ref.read(bookReaderSettingsProvider.notifier);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () =>
                    settingsNotifier.setFontSize(settings.fontSize - 2),
                icon: const Icon(
                  Icons.text_decrease_rounded,
                  color: Colors.white,
                ),
                tooltip: '缩小字体',
              ),
              IconButton(
                onPressed: () =>
                    settingsNotifier.setFontSize(settings.fontSize + 2),
                icon: const Icon(
                  Icons.text_increase_rounded,
                  color: Colors.white,
                ),
                tooltip: '放大字体',
              ),
              IconButton(
                onPressed: () => _showSettingsSheet(settings),
                icon: const Icon(
                  Icons.settings_outlined,
                  color: Colors.white70,
                ),
                tooltip: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsContent(BookReaderSettings settings) {
    final settingsNotifier = ref.read(bookReaderSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 字体大小
        SettingSliderRow(
          label: '字体大小',
          value: settings.fontSize,
          min: 12,
          max: 36,
          divisions: 12,
          valueLabel: '${settings.fontSize.toInt()}',
          onChanged: settingsNotifier.setFontSize,
        ),
        const SizedBox(height: 16),

        // 行高
        SettingSliderRow(
          label: '行高',
          value: settings.lineHeight,
          min: 1,
          max: 3,
          divisions: 20,
          onChanged: settingsNotifier.setLineHeight,
        ),
        const SizedBox(height: 16),

        // 段落间距
        SettingSliderRow(
          label: '段落间距',
          value: settings.paragraphSpacing,
          max: 3,
          divisions: 15,
          onChanged: settingsNotifier.setParagraphSpacing,
        ),
        const SizedBox(height: 16),

        // 页边距
        SettingSliderRow(
          label: '页边距',
          value: settings.horizontalPadding,
          min: 8,
          max: 64,
          divisions: 14,
          valueLabel: '${settings.horizontalPadding.toInt()}',
          onChanged: settingsNotifier.setHorizontalPadding,
        ),
        const SizedBox(height: 24),

        // 主题
        const SettingSectionTitle(title: '阅读主题'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: BookReaderTheme.values
                .map(
                  (theme) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _buildThemeOption(
                      theme: theme,
                      isSelected: settings.theme == theme,
                      onTap: () => settingsNotifier.setTheme(theme),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 24),

        // 其他设置
        const SettingSectionTitle(title: '其他设置'),
        SettingSwitchRow(
          title: '屏幕常亮',
          value: settings.keepScreenOn,
          onChanged: (value) {
            settingsNotifier.setKeepScreenOn(value: value);
            if (value) {
              WakelockPlus.enable();
            } else {
              WakelockPlus.disable();
            }
          },
        ),
        SettingSwitchRow(
          title: '点击翻页',
          subtitle: '左侧上翻，右侧下翻',
          value: settings.tapToTurn,
          onChanged: (value) => settingsNotifier.setTapToTurn(value: value),
        ),
        SettingSwitchRow(
          title: '显示进度',
          value: settings.showProgress,
          onChanged: (value) => settingsNotifier.setShowProgress(value: value),
        ),
      ],
    );
  }

  Widget _buildThemeOption({
    required BookReaderTheme theme,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.backgroundColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppColors.primary : (isDark ? Colors.grey.shade600 : Colors.grey.shade300),
                width: isSelected ? 3 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                'Aa',
                style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            theme.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? AppColors.primary : (isDark ? Colors.white70 : Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}
