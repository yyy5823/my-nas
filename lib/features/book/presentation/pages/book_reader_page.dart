import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/network/http_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_content_processor.dart';
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

  /// 更新清理后的 HTML 内容
  void updateCleanedHtml(String cleanedHtml) {
    final current = state;
    if (current is TxtReaderLoaded) {
      state = current.copyWith(htmlContent: cleanedHtml);
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
  bool _showToc = false;
  List<BookChapter> _chapters = [];
  String _currentChapterTitle = '';
  final ScrollController _scrollController = ScrollController();

  // 分页相关
  PageController? _pageController;
  List<String> _pages = []; // 分页后的内容
  Map<int, int> _chapterPageMap = {}; // 章节索引 -> 页码映射
  int _currentPage = 0;
  bool _isPaginationReady = false;
  bool _isProcessing = false; // 内容处理中
  bool _isContentProcessed = false; // 内容是否已处理完成
  bool _isScrollPositionRestored = false; // 滚动位置是否已恢复

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
      // 更新当前章节标题
      _updateCurrentChapter(position, maxPosition);
    }
  }

  /// 根据滚动位置更新当前章节标题
  void _updateCurrentChapter(double position, double maxPosition) {
    if (_chapters.isEmpty || maxPosition <= 0) return;

    final state = ref.read(txtReaderProvider(widget.book));
    if (state is! TxtReaderLoaded || !state.hasHtml) return;

    final totalLength = state.htmlContent!.length.toDouble();

    // 找到当前位置对应的章节
    String? currentTitle;
    for (var i = _chapters.length - 1; i >= 0; i--) {
      final chapterPosition = _chapters[i].offset / totalLength * maxPosition;
      if (position >= chapterPosition - 50) {
        currentTitle = _chapters[i].title;
        break;
      }
    }

    if (currentTitle != null && currentTitle != _currentChapterTitle) {
      setState(() {
        _currentChapterTitle = currentTitle!;
      });
    }
  }

  /// 异步处理内容（提取章节、移除目录）
  Future<void> _processContentAsync(String htmlContent) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // 在 Isolate 中处理内容
      final result = await BookContentProcessor.processContent(htmlContent);

      if (!mounted) return;

      // 更新清理后的 HTML 内容
      ref
          .read(txtReaderProvider(widget.book).notifier)
          .updateCleanedHtml(result.cleanedHtml);

      setState(() {
        _chapters = result.chapters;
        _isProcessing = false;
        _isContentProcessed = true;
      });

      logger.i(
        '内容处理完成: ${result.chapters.length} 个章节, '
        '${result.removedTocSection ? "已移除目录页" : "无目录页"}',
      );
    } on Exception catch (e) {
      logger.e('内容处理失败', e);
      setState(() {
        _isProcessing = false;
        _isContentProcessed = true; // 即使失败也标记为已处理，避免重复
      });
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _pageController?.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) {
        _showToc = false;
      }
    });
  }


  /// 跳转到章节
  void _jumpToChapter(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) return;

    final chapter = _chapters[chapterIndex];
    final state = ref.read(txtReaderProvider(widget.book));
    final settings = ref.read(bookReaderSettingsProvider);

    // 判断是否使用分页模式
    final usePageMode = state is TxtReaderLoaded &&
        state.hasHtml &&
        settings.pageTurnMode != BookPageTurnMode.scroll;

    if (usePageMode && _isPaginationReady && _pages.isNotEmpty) {
      // 分页模式：使用章节页码映射
      final targetPage = _chapterPageMap[chapterIndex] ?? 0;

      _pageController?.animateToPage(
        targetPage.clamp(0, _pages.length - 1),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );

      setState(() {
        _currentPage = targetPage;
        _currentChapterTitle = chapter.title;
      });
    } else {
      // 滚动模式
      if (!_scrollController.hasClients) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      if (state is TxtReaderLoaded && state.hasHtml) {
        final totalLength = state.htmlContent!.length.toDouble();
        final targetPosition =
            (chapter.offset / totalLength * maxScroll).clamp(0.0, maxScroll);

        _scrollController.animateTo(
          targetPosition,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }

    setState(() {
      _showToc = false;
    });
  }

  void _showSettingsSheet() {
    showReaderSettingsSheet(
      context,
      title: '阅读设置',
      icon: Icons.auto_stories_rounded,
      iconColor: AppColors.info,
      contentBuilder: (context) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(bookReaderSettingsProvider);
          return _buildSettingsContent(settings);
        },
      ),
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

    // 首次加载时处理内容（提取章节、移除目录）
    if (state.hasHtml && !_isContentProcessed && !_isProcessing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _processContentAsync(state.htmlContent!);
      });
    }

    // 对于 MOBI/AZW3 等长文档，使用分页模式以提高性能
    final usePageMode = state.hasHtml && settings.pageTurnMode != BookPageTurnMode.scroll;

    // 初始化分页（如果需要且尚未完成）
    // 需要等内容处理完成后再分页，因为分页依赖清理后的 HTML
    if (usePageMode && !_isPaginationReady && state.hasHtml && _isContentProcessed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _paginateContentAsync(state.htmlContent!, settings);
      });
    }

    return Stack(
      children: [
        // 阅读内容
        ColoredBox(
          color: theme.backgroundColor,
          child: SafeArea(
            child: Column(
              children: [
                // 固定顶栏 - 避免摄像头遮挡内容
                _buildFixedHeader(theme, settings),
                Expanded(
                  child: usePageMode
                      ? _buildPagedContent(state, settings)
                      : _buildScrollContent(state, settings),
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
                          usePageMode ? _getPageProgressText() : _getProgressText(state),
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

        // 点击交互区域（始终显示，根据 tapToTurn 设置决定是否翻页）
        _buildTapZones(settings),

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

        // 目录抽屉
        if (_showToc) _buildTocDrawer(context, settings),
      ],
    );
  }

  /// 滚动模式内容
  Widget _buildScrollContent(TxtReaderLoaded state, BookReaderSettings settings) {
    // 在第一帧渲染后恢复滚动位置
    if (!_isScrollPositionRestored && state.scrollPosition > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScrollPosition(state.scrollPosition);
      });
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: settings.horizontalPadding,
        vertical: settings.verticalPadding,
      ),
      child: _buildContent(state, settings),
    );
  }

  /// 恢复滚动位置
  void _restoreScrollPosition(double savedPosition) {
    if (_isScrollPositionRestored) return;
    _isScrollPositionRestored = true;

    // 等待内容完全渲染后再恢复
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll <= 0) return;

      // savedPosition 是百分比位置 (0-1)，需要转换为实际像素
      final targetPosition = (savedPosition * maxScroll).clamp(0.0, maxScroll);

      _scrollController.jumpTo(targetPosition);
      logger.d('恢复滚动位置: $savedPosition -> $targetPosition px');
    });
  }

  /// 分页模式内容 - 用于 MOBI/AZW3 等长文档，提高性能
  Widget _buildPagedContent(TxtReaderLoaded state, BookReaderSettings settings) {
    final theme = settings.theme;

    // 如果分页尚未完成，显示加载中
    if (!_isPaginationReady || _pages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: theme.textColor.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              '正在分页...',
              style: TextStyle(color: theme.textColor.withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    _pageController ??= PageController(initialPage: _currentPage);

    return PageView.builder(
      controller: _pageController,
      itemCount: _pages.length,
      onPageChanged: (page) {
        setState(() {
          _currentPage = page;
          // 更新当前章节标题
          _updateChapterFromPage(page);
        });
        // 保存进度
        _savePageProgress(page);
      },
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: settings.horizontalPadding,
          vertical: settings.verticalPadding,
        ),
        child: _buildPageContent(_pages[index], settings),
      ),
    );
  }

  /// 构建单页内容
  Widget _buildPageContent(String pageHtml, BookReaderSettings settings) {
    final theme = settings.theme;
    return Html(
      data: pageHtml,
      style: _buildHtmlStyles(settings, theme),
    );
  }

  /// 异步分页（在 Isolate 中处理）
  Future<void> _paginateContentAsync(
    String htmlContent,
    BookReaderSettings settings,
  ) async {
    if (_isPaginationReady) return;

    try {
      // 在 Isolate 中执行分页
      final result = await BookContentProcessor.paginateContent(
        htmlContent: htmlContent,
        chapters: _chapters,
        charsPerPage: 1500,
      );

      if (!mounted) return;

      setState(() {
        _pages = result.pages;
        _chapterPageMap = result.chapterPageMap;
        _isPaginationReady = true;
        // 恢复之前的页码进度
        _restorePageProgress();
      });

      logger.i('内容分页完成: ${result.pages.length} 页');
    } catch (e) {
      logger.e('分页失败', e);
      // 失败时使用整个内容作为单页
      setState(() {
        _pages = [htmlContent];
        _isPaginationReady = true;
      });
    }
  }

  /// 保存分页进度
  Future<void> _savePageProgress(int page) async {
    final state = ref.read(txtReaderProvider(widget.book));
    if (state is! TxtReaderLoaded) return;

    final itemId = ReadingProgressService().generateItemId(
      widget.book.sourceId ?? 'local',
      widget.book.path,
    );
    await ReadingProgressService().saveProgress(ReadingProgress(
      itemId: itemId,
      itemType: 'txt',
      position: page.toDouble(),
      totalPositions: _pages.length,
      lastReadAt: DateTime.now(),
    ));
  }

  /// 恢复分页进度
  void _restorePageProgress() {
    final itemId = ReadingProgressService().generateItemId(
      widget.book.sourceId ?? 'local',
      widget.book.path,
    );
    final progress = ReadingProgressService().getProgress(itemId);
    if (progress != null && _pages.isNotEmpty) {
      _currentPage = progress.position.toInt().clamp(0, _pages.length - 1);
      _pageController?.jumpToPage(_currentPage);
    }
  }

  /// 从页码更新当前章节
  void _updateChapterFromPage(int page) {
    if (_chapters.isEmpty || _pages.isEmpty) return;

    // 计算当前进度百分比
    final progress = page / _pages.length;

    // 找到对应的章节
    String? title;
    for (var i = _chapters.length - 1; i >= 0; i--) {
      if (_chapters[i].offset <= progress) {
        title = _chapters[i].title;
        break;
      }
    }

    if (title != null && title != _currentChapterTitle) {
      setState(() {
        _currentChapterTitle = title!;
      });
    }
  }

  /// 获取分页进度文本
  String _getPageProgressText() {
    if (_pages.isEmpty) return '';
    return '${_currentPage + 1} / ${_pages.length}';
  }

  /// 构建固定顶栏，显示章节标题或书名
  Widget _buildFixedHeader(BookReaderTheme theme, BookReaderSettings settings) {
    // 显示当前章节标题，如果没有则显示书名
    final displayTitle = _currentChapterTitle.isNotEmpty
        ? _currentChapterTitle
        : widget.book.displayName;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: settings.horizontalPadding,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.textColor.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              displayTitle,
              style: TextStyle(
                color: theme.textColor.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建目录抽屉
  Widget _buildTocDrawer(BuildContext context, BookReaderSettings settings) {
    final theme = settings.theme;
    final isDark = theme == BookReaderTheme.dark || theme == BookReaderTheme.black;

    return Positioned(
      top: 0,
      bottom: 0,
      left: 0,
      child: GestureDetector(
        onTap: () {}, // 防止点击穿透
        child: Container(
          width: MediaQuery.of(context).size.width * 0.75,
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '目录',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                        onPressed: () => setState(() => _showToc = false),
                      ),
                    ],
                  ),
                ),
                // 章节列表
                Expanded(
                  child: _chapters.isEmpty
                      ? Center(
                          child: Text(
                            '暂无目录',
                            style: TextStyle(
                              color: isDark ? Colors.grey[500] : Colors.grey[600],
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _chapters.length,
                          itemBuilder: (context, index) {
                            final chapter = _chapters[index];
                            return ListTile(
                              title: Text(
                                chapter.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              onTap: () => _jumpToChapter(index),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
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
      data: htmlContent,
      style: style,
      onLinkTap: (url, attributes, element) {
        if (url != null) {
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      },
    );
  }

  /// 构建 HTML 样式（复用于分页和滚动模式）
  Map<String, Style> _buildHtmlStyles(BookReaderSettings settings, BookReaderTheme theme) => {
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

  Widget _buildTapZones(BookReaderSettings settings) {
    // 判断是否使用分页模式
    final state = ref.read(txtReaderProvider(widget.book));
    final usePageMode = state is TxtReaderLoaded &&
        state.hasHtml &&
        settings.pageTurnMode != BookPageTurnMode.scroll;

    return Positioned.fill(
      child: Row(
        children: [
          // 左侧 - 上一页/向上滚动（如果 tapToTurn 开启）
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!settings.tapToTurn) {
                  _toggleControls();
                  return;
                }

                if (usePageMode && _isPaginationReady) {
                  // 分页模式：上一页
                  if (_pageController != null && _currentPage > 0) {
                    _pageController!.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                } else if (_scrollController.hasClients) {
                  // 滚动模式：向上滚动
                  _scrollController.animateTo(
                    (_scrollController.offset -
                            MediaQuery.of(context).size.height * 0.8)
                        .clamp(0.0, _scrollController.position.maxScrollExtent),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              },
              behavior: HitTestBehavior.translucent,
              child: Container(),
            ),
          ),
          // 中间 - 显示/隐藏控制栏（只响应点击，不响应滑动）
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _toggleControls,
              behavior: HitTestBehavior.translucent,
              child: Container(),
            ),
          ),
          // 右侧 - 下一页/向下滚动（如果 tapToTurn 开启）
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!settings.tapToTurn) {
                  _toggleControls();
                  return;
                }

                if (usePageMode && _isPaginationReady) {
                  // 分页模式：下一页
                  if (_pageController != null && _currentPage < _pages.length - 1) {
                    _pageController!.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                } else if (_scrollController.hasClients) {
                  // 滚动模式：向下滚动
                  _scrollController.animateTo(
                    (_scrollController.offset +
                            MediaQuery.of(context).size.height * 0.8)
                        .clamp(0.0, _scrollController.position.maxScrollExtent),
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
  }

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
            // 目录按钮（仅当有章节时显示）
            if (_chapters.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.list_rounded, color: Colors.white),
                onPressed: () => setState(() => _showToc = !_showToc),
                tooltip: '目录',
              )
            else
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
                onPressed: _showSettingsSheet,
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
        const SizedBox(height: 24),

        // 字体选择
        SettingSectionTitle(
          title: '字体',
          trailing: AvailableFonts.getDisplayName(settings.fontFamily),
        ),
        SettingFontPicker(
          selectedFont: settings.fontFamily,
          onSelect: settingsNotifier.setFontFamily,
        ),
        const SizedBox(height: 24),

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
