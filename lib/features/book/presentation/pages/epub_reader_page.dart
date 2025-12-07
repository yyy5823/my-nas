import 'dart:io';

import 'package:epub_plus/epub_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/network/http_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// EPUB 阅读器状态
final epubReaderProvider =
    StateNotifierProvider.family<EpubReaderNotifier, EpubReaderState, BookItem>(
      (ref, book) => EpubReaderNotifier(book, ref),
    );

sealed class EpubReaderState {}

class EpubReaderLoading extends EpubReaderState {
  EpubReaderLoading({this.message = '加载中...'});

  final String message;
}

class EpubReaderLoaded extends EpubReaderState {
  EpubReaderLoaded({
    required this.title,
    required this.author,
    required this.chapters,
    this.currentChapter = 0,
    this.scrollPosition = 0.0,
    this.cssContent = '',
  });

  final String title;
  final String author;
  final List<BookChapterInfo> chapters;
  final int currentChapter;
  final double scrollPosition;
  final String cssContent;

  int get totalChapters => chapters.length;

  /// 获取当前章节的 HTML 内容
  String get currentHtmlContent {
    if (currentChapter >= 0 && currentChapter < chapters.length) {
      return chapters[currentChapter].htmlContent;
    }
    return '';
  }

  EpubReaderLoaded copyWith({
    String? title,
    String? author,
    List<BookChapterInfo>? chapters,
    int? currentChapter,
    double? scrollPosition,
    String? cssContent,
  }) => EpubReaderLoaded(
    title: title ?? this.title,
    author: author ?? this.author,
    chapters: chapters ?? this.chapters,
    currentChapter: currentChapter ?? this.currentChapter,
    scrollPosition: scrollPosition ?? this.scrollPosition,
    cssContent: cssContent ?? this.cssContent,
  );
}

class EpubReaderError extends EpubReaderState {
  EpubReaderError(this.message);

  final String message;
}

/// 图书章节信息（避免与 epub_plus 的 EpubChapter 冲突）
class BookChapterInfo {
  BookChapterInfo({
    required this.title,
    required this.href,
    this.htmlContent = '',
  });

  final String title;
  final String href;
  final String htmlContent;
}

/// EPUB 解析结果（用于 Isolate 传递）
class _EpubParseResult {
  _EpubParseResult({
    required this.title,
    required this.author,
    required this.chapters,
    this.cssContent = '',
  });

  final String title;
  final String author;
  final List<BookChapterInfo> chapters;
  final String cssContent;
}

class EpubReaderNotifier extends StateNotifier<EpubReaderState> {
  EpubReaderNotifier(this.book, this._ref) : super(EpubReaderLoading()) {
    _loadEpub();
  }

  final BookItem book;
  final Ref _ref;
  final ReadingProgressService _progressService = ReadingProgressService();

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

  Future<void> _loadEpub() async {
    try {
      state = EpubReaderLoading();

      final uri = Uri.parse(book.url);
      final tempDir = await getTemporaryDirectory();
      final epubFile = File('${tempDir.path}/${book.name}');

      // 优先使用流式加载（支持 SMB/WebDAV 等协议）
      final fileSystem = _getFileSystem();
      if (fileSystem != null) {
        state = EpubReaderLoading(message: '加载文件中...');
        final stream = await fileSystem.getFileStream(book.path);
        final bytes = await _readStreamBytes(stream);
        await epubFile.writeAsBytes(bytes);
      } else if (uri.scheme == 'file') {
        state = EpubReaderLoading(message: '读取本地文件...');
        final localFile = File(uri.toFilePath());
        if (!await localFile.exists()) {
          state = EpubReaderError('文件不存在');
          return;
        }
        await localFile.copy(epubFile.path);
      } else if (uri.scheme == 'http' || uri.scheme == 'https') {
        state = EpubReaderLoading(message: '下载中...');
        final response = await InsecureHttpClient.get(uri);
        if (response.statusCode != 200) {
          state = EpubReaderError('下载失败: ${response.statusCode}');
          return;
        }
        await epubFile.writeAsBytes(response.bodyBytes);
      } else {
        state = EpubReaderError('不支持的协议: ${uri.scheme}');
        return;
      }

      state = EpubReaderLoading(message: '解析中...');

      // 解析 EPUB
      final bytes = await epubFile.readAsBytes();
      final result = await _parseEpub(bytes);

      if (result.chapters.isEmpty) {
        state = EpubReaderError('无法解析 EPUB 内容');
        return;
      }

      // 恢复阅读进度
      await _progressService.init();
      final itemId = _progressService.generateItemId(book.id, book.path);
      final progress = _progressService.getProgress(itemId);
      final startChapter = progress?.chapter ?? 0;

      state = EpubReaderLoaded(
        title: result.title,
        author: result.author,
        chapters: result.chapters,
        cssContent: result.cssContent,
        currentChapter: startChapter.clamp(0, result.chapters.length - 1),
      );

      logger.i('EPUB 加载完成: ${result.title}, ${result.chapters.length} 章节');
    } on Exception catch (e, stackTrace) {
      logger.e('加载 EPUB 失败', e, stackTrace);
      state = EpubReaderError('加载失败: $e');
    }
  }

  /// 异步解析 EPUB
  Future<_EpubParseResult> _parseEpub(Uint8List bytes) async {
    final epubBook = await EpubReader.readBook(bytes);

    final chapters = <BookChapterInfo>[];

    // 收集 CSS 内容
    final cssBuffer = StringBuffer();
    if (epubBook.content?.css != null) {
      for (final css in epubBook.content!.css.values) {
        if (css.content != null) {
          cssBuffer.writeln(css.content);
        }
      }
    }

    // 从 epub_plus 的 chapters 获取章节
    void processChapters(List<EpubChapter> epubChapters) {
      for (final chapter in epubChapters) {
        final htmlContent = chapter.htmlContent;
        if (htmlContent == null || htmlContent.isEmpty) {
          if (chapter.subChapters.isNotEmpty) {
            processChapters(chapter.subChapters);
          }
          continue;
        }

        final title = chapter.title ?? '章节 ${chapters.length + 1}';

        // 检查是否有实际内容（不只是空白）
        final textContent = htmlContent
            .replaceAll(RegExp('<[^>]+>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (textContent.isEmpty) {
          if (chapter.subChapters.isNotEmpty) {
            processChapters(chapter.subChapters);
          }
          continue;
        }

        chapters.add(
          BookChapterInfo(
            title: title,
            href: chapter.contentFileName ?? '',
            htmlContent: htmlContent,
          ),
        );

        if (chapter.subChapters.isNotEmpty) {
          processChapters(chapter.subChapters);
        }
      }
    }

    processChapters(epubBook.chapters);

    // 如果没有章节，尝试从 HTML 内容获取
    if (chapters.isEmpty && epubBook.content?.html != null) {
      for (final entry in epubBook.content!.html.entries) {
        final htmlContent = entry.value.content;
        if (htmlContent == null || htmlContent.isEmpty) continue;

        // 提取标题
        String? title;
        final h1Match = RegExp(
          '<h1[^>]*>([^<]+)</h1>',
          caseSensitive: false,
        ).firstMatch(htmlContent);
        if (h1Match != null) {
          title = h1Match.group(1)?.trim();
        }
        final titleMatch = RegExp(
          '<title[^>]*>([^<]+)</title>',
          caseSensitive: false,
        ).firstMatch(htmlContent);
        if (title == null && titleMatch != null) {
          title = titleMatch.group(1)?.trim();
        }
        title ??= entry.key;

        // 检查是否有实际内容
        final textContent = htmlContent
            .replaceAll(RegExp('<[^>]+>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (textContent.isEmpty) continue;

        chapters.add(
          BookChapterInfo(
            title: title,
            href: entry.key,
            htmlContent: htmlContent,
          ),
        );
      }
    }

    return _EpubParseResult(
      title: epubBook.title ?? '未知书名',
      author: epubBook.author ?? '未知作者',
      chapters: chapters,
      cssContent: cssBuffer.toString(),
    );
  }

  void goToChapter(int index) {
    final current = state;
    if (current is EpubReaderLoaded) {
      final newIndex = index.clamp(0, current.chapters.length - 1);
      state = current.copyWith(currentChapter: newIndex);
      _saveProgress(newIndex);
    }
  }

  void nextChapter() {
    final current = state;
    if (current is EpubReaderLoaded) {
      if (current.currentChapter < current.chapters.length - 1) {
        goToChapter(current.currentChapter + 1);
      }
    }
  }

  void previousChapter() {
    final current = state;
    if (current is EpubReaderLoaded) {
      if (current.currentChapter > 0) {
        goToChapter(current.currentChapter - 1);
      }
    }
  }

  void setScrollPosition(double position) {
    final current = state;
    if (current is EpubReaderLoaded) {
      state = current.copyWith(scrollPosition: position);
    }
  }

  Future<void> _saveProgress(int chapter) async {
    final current = state;
    if (current is EpubReaderLoaded) {
      final itemId = _progressService.generateItemId(book.id, book.path);
      await _progressService.saveProgress(
        ReadingProgress(
          itemId: itemId,
          itemType: 'epub',
          position: chapter.toDouble(),
          totalPositions: current.chapters.length,
          chapter: chapter,
          chapterTitle: current.chapters[chapter].title,
          lastReadAt: DateTime.now(),
        ),
      );
    }
  }
}

class EpubReaderPage extends ConsumerStatefulWidget {
  const EpubReaderPage({required this.book, super.key});

  final BookItem book;

  @override
  ConsumerState<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends ConsumerState<EpubReaderPage> {
  bool _showControls = false;
  bool _showSettings = false;
  bool _showToc = false;
  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWakelock();
  }

  Future<void> _initWakelock() async {
    final settings = ref.read(bookReaderSettingsProvider);
    if (settings.keepScreenOn) {
      await WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(epubReaderProvider(widget.book));

    return Scaffold(
      body: switch (state) {
        EpubReaderLoading(:final message) => LoadingWidget(message: message),
        EpubReaderError(:final message) => _buildError(message),
        EpubReaderLoaded() => _buildReader(context, state),
      },
    );
  }

  Widget _buildError(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            label: const Text('返回'),
          ),
        ],
      ),
    ),
  );

  Widget _buildReader(BuildContext context, EpubReaderLoaded state) {
    final settings = ref.watch(bookReaderSettingsProvider);
    final theme = settings.theme;

    return Stack(
      children: [
        // 阅读内容
        ColoredBox(
          color: theme.backgroundColor,
          child: SafeArea(
            child: Column(
              children: [
                // 章节内容
                Expanded(child: _buildContent(state, settings)),
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
                          state.chapters[state.currentChapter].title,
                          style: TextStyle(
                            color: theme.textColor.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${state.currentChapter + 1}/${state.totalChapters} · ${((state.currentChapter + 1) / state.totalChapters * 100).toStringAsFixed(0)}%',
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
        if (settings.tapToTurn) _buildTapZones(state, settings),

        // 顶部控制栏
        if (_showControls)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(context, state),
          ),

        // 底部控制栏
        if (_showControls)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(context, state, settings),
          ),

        // 目录
        if (_showToc) _buildTocDrawer(context, state, settings),

        // 设置面板
        if (_showSettings) _buildSettingsPanel(context, state, settings),
      ],
    );
  }

  Widget _buildContent(EpubReaderLoaded state, BookReaderSettings settings) {
    switch (settings.pageTurnMode) {
      case BookPageTurnMode.scroll:
        return GestureDetector(
          onTap: _toggleControls,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.symmetric(
              horizontal: settings.horizontalPadding,
              vertical: settings.verticalPadding,
            ),
            child: _buildHtmlContent(state.currentHtmlContent, settings),
          ),
        );

      case BookPageTurnMode.slide:
      case BookPageTurnMode.cover:
      case BookPageTurnMode.simulation:
      case BookPageTurnMode.none:
        return GestureDetector(
          onTap: _toggleControls,
          child: PageView.builder(
            controller: _pageController,
            itemCount: state.chapters.length,
            onPageChanged: (index) {
              ref
                  .read(epubReaderProvider(widget.book).notifier)
                  .goToChapter(index);
            },
            itemBuilder: (context, index) => SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: settings.horizontalPadding,
                vertical: settings.verticalPadding,
              ),
              child: _buildHtmlContent(
                state.chapters[index].htmlContent,
                settings,
              ),
            ),
          ),
        );
    }
  }

  /// 使用 flutter_html 渲染 HTML 内容
  Widget _buildHtmlContent(String htmlContent, BookReaderSettings settings) {
    final theme = settings.theme;

    // 清理 HTML 中的无效 CSS 颜色值
    final cleanedHtml = _cleanInvalidCssColors(htmlContent);

    // 构建自定义样式
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
        fontSize: FontSize(settings.fontSize),
        lineHeight: LineHeight(settings.lineHeight),
        color: theme.textColor,
        margin: Margins.only(bottom: settings.paragraphSpacing * 16),
      ),
      'h1': Style(
        fontSize: FontSize(settings.fontSize * 1.5),
        fontWeight: FontWeight.bold,
        color: theme.textColor,
        margin: Margins.only(bottom: 16, top: 8),
      ),
      'h2': Style(
        fontSize: FontSize(settings.fontSize * 1.3),
        fontWeight: FontWeight.bold,
        color: theme.textColor,
        margin: Margins.only(bottom: 12, top: 8),
      ),
      'h3': Style(
        fontSize: FontSize(settings.fontSize * 1.15),
        fontWeight: FontWeight.bold,
        color: theme.textColor,
        margin: Margins.only(bottom: 8, top: 8),
      ),
      'h4, h5, h6': Style(
        fontSize: FontSize(settings.fontSize),
        fontWeight: FontWeight.bold,
        color: theme.textColor,
        margin: Margins.only(bottom: 8, top: 8),
      ),
      'blockquote': Style(
        fontStyle: FontStyle.italic,
        color: theme.textColor.withValues(alpha: 0.8),
        padding: HtmlPaddings.only(left: 16),
        border: Border(
          left: BorderSide(
            color: theme.textColor.withValues(alpha: 0.3),
            width: 3,
          ),
        ),
      ),
      'a': Style(
        color: AppColors.primary,
        textDecoration: TextDecoration.underline,
      ),
      'img': Style(
        display: Display.block,
        margin: Margins.symmetric(vertical: 8),
      ),
      'ul, ol': Style(
        margin: Margins.only(left: 16, bottom: 8),
      ),
      'li': Style(
        margin: Margins.only(bottom: 4),
      ),
      'pre, code': Style(
        fontFamily: 'monospace',
        backgroundColor: theme.textColor.withValues(alpha: 0.05),
        padding: HtmlPaddings.all(8),
      ),
    };

    return Html(
      data: cleanedHtml,
      style: style,
      onLinkTap: (url, attributes, element) {
        // 处理链接点击（可以跳转到其他章节或外部链接）
        logger.d('链接点击: $url');
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
  String _fixColorValuesInStyle(String style) => style.replaceAllMapped(
        RegExp(
          r'((?:background-)?color)\s*:\s*([^;]+)',
          caseSensitive: false,
        ),
        (match) {
          final property = match.group(1) ?? 'color';
          final colorValue = match.group(2)?.trim() ?? '';
          final fixedColor = _fixColorValue(colorValue);
          if (fixedColor == null) {
            return '';
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
      return value;
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
    var cleaned = hex.replaceAll(RegExp('^[0x#]+'), '');
    cleaned = cleaned.replaceAll(RegExp('[^0-9a-fA-F]'), '');

    if (cleaned.isEmpty) return null;

    if (cleaned.length == 3) return cleaned;
    if (cleaned.length == 4) {
      return '${cleaned[0]}${cleaned[0]}${cleaned[1]}${cleaned[1]}${cleaned[2]}${cleaned[2]}';
    }
    if (cleaned.length == 5) return '${cleaned}0';
    if (cleaned.length == 6) return cleaned;
    if (cleaned.length == 7) return '${cleaned}0';
    if (cleaned.length == 8) return cleaned;
    if (cleaned.length > 8) return cleaned.substring(0, 6);

    return null;
  }

  bool _isValidHexColor(String hex) {
    final length = hex.length;
    if (length != 3 && length != 4 && length != 6 && length != 8) {
      return false;
    }
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex);
  }

  bool _isValidColorName(String name) {
    const validColors = {
      'transparent', 'currentcolor', 'inherit',
      'black', 'white', 'red', 'green', 'blue', 'yellow', 'cyan', 'magenta',
      'gray', 'grey', 'silver', 'maroon', 'olive', 'lime', 'aqua', 'teal',
      'navy', 'fuchsia', 'purple', 'orange', 'pink', 'brown', 'gold',
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

  Widget _buildTapZones(EpubReaderLoaded state, BookReaderSettings settings) =>
      Positioned.fill(
        child: Row(
          children: [
            // 左侧 - 上一章
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (settings.pageTurnMode == BookPageTurnMode.scroll) {
                    ref
                        .read(epubReaderProvider(widget.book).notifier)
                        .previousChapter();
                  } else {
                    _pageController.previousPage(
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
            // 右侧 - 下一章
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (settings.pageTurnMode == BookPageTurnMode.scroll) {
                    ref
                        .read(epubReaderProvider(widget.book).notifier)
                        .nextChapter();
                  } else {
                    _pageController.nextPage(
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

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) {
        _showSettings = false;
        _showToc = false;
      }
    });
  }

  Widget _buildTopBar(BuildContext context, EpubReaderLoaded state) =>
      DecoratedBox(
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        state.author,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _showToc = !_showToc),
                  icon: const Icon(Icons.list_rounded, color: Colors.white),
                  tooltip: '目录',
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildBottomBar(
    BuildContext context,
    EpubReaderLoaded state,
    BookReaderSettings settings,
  ) => DecoratedBox(
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
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 章节进度条
            Row(
              children: [
                IconButton(
                  onPressed: state.currentChapter > 0
                      ? () {
                          ref
                              .read(epubReaderProvider(widget.book).notifier)
                              .previousChapter();
                          if (settings.pageTurnMode !=
                              BookPageTurnMode.scroll) {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        }
                      : null,
                  icon: Icon(
                    Icons.skip_previous_rounded,
                    color: state.currentChapter > 0
                        ? Colors.white
                        : Colors.white38,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: state.currentChapter.toDouble(),
                    max: (state.totalChapters - 1).toDouble(),
                    divisions: state.totalChapters > 1
                        ? state.totalChapters - 1
                        : null,
                    onChanged: (value) {
                      ref
                          .read(epubReaderProvider(widget.book).notifier)
                          .goToChapter(value.toInt());
                      if (settings.pageTurnMode != BookPageTurnMode.scroll) {
                        _pageController.jumpToPage(value.toInt());
                      }
                    },
                  ),
                ),
                IconButton(
                  onPressed: state.currentChapter < state.totalChapters - 1
                      ? () {
                          ref
                              .read(epubReaderProvider(widget.book).notifier)
                              .nextChapter();
                          if (settings.pageTurnMode !=
                              BookPageTurnMode.scroll) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        }
                      : null,
                  icon: Icon(
                    Icons.skip_next_rounded,
                    color: state.currentChapter < state.totalChapters - 1
                        ? Colors.white
                        : Colors.white38,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 功能按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildBottomButton(
                  icon: Icons.text_decrease_rounded,
                  label: '缩小',
                  onTap: () => ref
                      .read(bookReaderSettingsProvider.notifier)
                      .setFontSize(settings.fontSize - 2),
                ),
                _buildBottomButton(
                  icon: Icons.text_increase_rounded,
                  label: '放大',
                  onTap: () => ref
                      .read(bookReaderSettingsProvider.notifier)
                      .setFontSize(settings.fontSize + 2),
                ),
                _buildBottomButton(
                  icon: Icons.settings_rounded,
                  label: '设置',
                  onTap: () => setState(() => _showSettings = !_showSettings),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildBottomButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    ),
  );

  Widget _buildTocDrawer(
    BuildContext context,
    EpubReaderLoaded state,
    BookReaderSettings settings,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.75,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(-2, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      '目录',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => setState(() => _showToc = false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: state.chapters.length,
                  itemBuilder: (context, index) {
                    final isActive = index == state.currentChapter;
                    return ListTile(
                      dense: true,
                      selected: isActive,
                      selectedTileColor: AppColors.primary.withValues(
                        alpha: 0.1,
                      ),
                      leading: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isActive ? AppColors.primary : Colors.grey,
                          fontWeight: isActive ? FontWeight.bold : null,
                        ),
                      ),
                      title: Text(
                        state.chapters[index].title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isActive ? FontWeight.bold : null,
                          color: isActive ? AppColors.primary : null,
                        ),
                      ),
                      onTap: () {
                        ref
                            .read(epubReaderProvider(widget.book).notifier)
                            .goToChapter(index);
                        if (settings.pageTurnMode != BookPageTurnMode.scroll) {
                          _pageController.jumpToPage(index);
                        }
                        setState(() => _showToc = false);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsPanel(
    BuildContext context,
    EpubReaderLoaded state,
    BookReaderSettings settings,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settingsNotifier = ref.read(bookReaderSettingsProvider.notifier);

    return Positioned(
      bottom: 100,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '阅读设置',
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => setState(() => _showSettings = false),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 字体大小
              _buildSettingRow(
                context,
                label: '字体大小',
                value: '${settings.fontSize.toInt()}',
                child: Slider(
                  value: settings.fontSize,
                  min: 12,
                  max: 36,
                  divisions: 12,
                  onChanged: settingsNotifier.setFontSize,
                ),
              ),

              const SizedBox(height: 8),

              // 行高
              _buildSettingRow(
                context,
                label: '行高',
                value: settings.lineHeight.toStringAsFixed(1),
                child: Slider(
                  value: settings.lineHeight,
                  min: 1,
                  max: 3,
                  divisions: 20,
                  onChanged: settingsNotifier.setLineHeight,
                ),
              ),

              const SizedBox(height: 8),

              // 段落间距
              _buildSettingRow(
                context,
                label: '段落间距',
                value: settings.paragraphSpacing.toStringAsFixed(1),
                child: Slider(
                  value: settings.paragraphSpacing,
                  max: 3,
                  divisions: 15,
                  onChanged: settingsNotifier.setParagraphSpacing,
                ),
              ),

              const SizedBox(height: 8),

              // 页边距
              _buildSettingRow(
                context,
                label: '页边距',
                value: '${settings.horizontalPadding.toInt()}',
                child: Slider(
                  value: settings.horizontalPadding,
                  min: 8,
                  max: 64,
                  divisions: 14,
                  onChanged: settingsNotifier.setHorizontalPadding,
                ),
              ),

              const SizedBox(height: 16),

              // 翻页模式
              Text('翻页模式', style: context.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: BookPageTurnMode.values.map((mode) {
                  final isSelected = settings.pageTurnMode == mode;
                  return ChoiceChip(
                    label: Text(_getPageTurnModeLabel(mode)),
                    selected: isSelected,
                    onSelected: (_) => settingsNotifier.setPageTurnMode(mode),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // 主题
              Text('阅读主题', style: context.textTheme.bodyMedium),
              const SizedBox(height: 12),
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

              const SizedBox(height: 16),

              // 其他设置
              Text('其他设置', style: context.textTheme.bodyMedium),
              const SizedBox(height: 8),
              _buildSwitchTile(
                context,
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
              _buildSwitchTile(
                context,
                title: '点击翻页',
                subtitle: '左侧上一章，右侧下一章',
                value: settings.tapToTurn,
                onChanged: (value) {
                  settingsNotifier.setTapToTurn(value: value);
                },
              ),
              _buildSwitchTile(
                context,
                title: '显示进度',
                value: settings.showProgress,
                onChanged: (value) {
                  settingsNotifier.setShowProgress(value: value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getPageTurnModeLabel(BookPageTurnMode mode) => switch (mode) {
    BookPageTurnMode.scroll => '滚动',
    BookPageTurnMode.slide => '滑动',
    BookPageTurnMode.simulation => '仿真',
    BookPageTurnMode.cover => '覆盖',
    BookPageTurnMode.none => '无动画',
  };

  Widget _buildSettingRow(
    BuildContext context, {
    required String label,
    required String value,
    required Widget child,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.textTheme.bodyMedium),
          Text(
            value,
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      child,
    ],
  );

  Widget _buildSwitchTile(
    BuildContext context, {
    required String title,
    required bool value, required ValueChanged<bool> onChanged, String? subtitle,
  }) => SwitchListTile(
    title: Text(title, style: context.textTheme.bodyMedium),
    subtitle: subtitle != null
        ? Text(subtitle, style: context.textTheme.bodySmall)
        : null,
    value: value,
    onChanged: onChanged,
    dense: true,
    contentPadding: EdgeInsets.zero,
  );

  Widget _buildThemeOption({
    required BookReaderTheme theme,
    required bool isSelected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: theme.backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.grey.shade300,
              width: isSelected ? 3 : 1,
            ),
          ),
          child: Center(
            child: Text(
              'Aa',
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          theme.label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? AppColors.primary : null,
          ),
        ),
      ],
    ),
  );
}
