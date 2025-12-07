import 'dart:convert';
import 'dart:io';

import 'package:epub_decoder/epub_decoder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/network/http_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// EPUB 阅读器状态
final epubReaderProvider =
    StateNotifierProvider.family<EpubReaderNotifier, EpubReaderState, BookItem>(
        (ref, book) => EpubReaderNotifier(book));

sealed class EpubReaderState {}

class EpubReaderLoading extends EpubReaderState {
  EpubReaderLoading({this.message = '加载中...'});
  final String message;
}

class EpubReaderLoaded extends EpubReaderState {
  EpubReaderLoaded({
    required this.epub,
    required this.chapters,
    required this.chapterContents,
    this.currentChapter = 0,
    this.scrollPosition = 0.0,
  });

  final Epub epub;
  final List<EpubChapter> chapters;
  final List<String> chapterContents;
  final int currentChapter;
  final double scrollPosition;

  String get title => epub.title.isNotEmpty ? epub.title : '未知书名';
  String get author =>
      epub.authors.isNotEmpty ? epub.authors.join(', ') : '未知作者';
  int get totalChapters => chapters.length;

  EpubReaderLoaded copyWith({
    Epub? epub,
    List<EpubChapter>? chapters,
    List<String>? chapterContents,
    int? currentChapter,
    double? scrollPosition,
  }) =>
      EpubReaderLoaded(
        epub: epub ?? this.epub,
        chapters: chapters ?? this.chapters,
        chapterContents: chapterContents ?? this.chapterContents,
        currentChapter: currentChapter ?? this.currentChapter,
        scrollPosition: scrollPosition ?? this.scrollPosition,
      );
}

class EpubReaderError extends EpubReaderState {
  EpubReaderError(this.message);
  final String message;
}

/// EPUB 章节
class EpubChapter {
  EpubChapter({
    required this.title,
    required this.href,
    this.content = '',
  });

  final String title;
  final String href;
  String content;
}

class EpubReaderNotifier extends StateNotifier<EpubReaderState> {
  EpubReaderNotifier(this.book) : super(EpubReaderLoading()) {
    _loadEpub();
  }

  final BookItem book;
  final ReadingProgressService _progressService = ReadingProgressService();

  Future<void> _loadEpub() async {
    try {
      state = EpubReaderLoading();

      final uri = Uri.parse(book.url);
      final tempDir = await getTemporaryDirectory();
      final epubFile = File('${tempDir.path}/${book.name}');

      // 检查是否为本地文件 (file:// 协议)
      if (uri.scheme == 'file') {
        state = EpubReaderLoading(message: '读取本地文件...');
        final localFile = File(uri.toFilePath());
        if (!await localFile.exists()) {
          state = EpubReaderError('文件不存在');
          return;
        }
        // 复制到临时目录
        await localFile.copy(epubFile.path);
      } else {
        // 远程文件，使用 HTTP 下载
        state = EpubReaderLoading(message: '下载中...');
        final response = await InsecureHttpClient.get(uri);
        if (response.statusCode != 200) {
          state = EpubReaderError('下载失败: ${response.statusCode}');
          return;
        }
        await epubFile.writeAsBytes(response.bodyBytes);
      }

      state = EpubReaderLoading(message: '解析中...');

      // 解析 EPUB
      final bytes = await epubFile.readAsBytes();
      final epub = Epub.fromBytes(bytes);

      // 获取章节列表
      final chapters = <EpubChapter>[];
      final chapterContents = <String>[];

      // 从 spine 获取阅读顺序
      for (final section in epub.sections) {
        final htmlContent = utf8.decode(section.content.fileContent);
        final title = _extractTitle(htmlContent) ?? '章节 ${chapters.length + 1}';
        final content = _extractTextContent(htmlContent);

        chapters.add(EpubChapter(
          title: title,
          href: section.content.href,
          content: content,
        ));
        chapterContents.add(content);
      }

      // 如果没有章节，尝试从目录获取
      if (chapters.isEmpty) {
        state = EpubReaderError('无法解析 EPUB 内容');
        return;
      }

      // 恢复阅读进度
      await _progressService.init();
      final itemId = _progressService.generateItemId(book.id, book.path);
      final progress = _progressService.getProgress(itemId);
      final startChapter = progress?.chapter ?? 0;

      state = EpubReaderLoaded(
        epub: epub,
        chapters: chapters,
        chapterContents: chapterContents,
        currentChapter: startChapter.clamp(0, chapters.length - 1),
      );

      logger.i('EPUB 加载完成: ${epub.title}, ${chapters.length} 章节');
    } on Exception catch (e, stackTrace) {
      logger.e('加载 EPUB 失败', e, stackTrace);
      state = EpubReaderError('加载失败: $e');
    }
  }

  String? _extractTitle(String htmlContent) {
    // 尝试从 HTML 中提取标题
    // 简单的标题提取
    final h1Match = RegExp('<h1[^>]*>([^<]+)</h1>', caseSensitive: false).firstMatch(htmlContent);
    if (h1Match != null) return h1Match.group(1)?.trim();

    final h2Match = RegExp('<h2[^>]*>([^<]+)</h2>', caseSensitive: false).firstMatch(htmlContent);
    if (h2Match != null) return h2Match.group(1)?.trim();

    final titleMatch = RegExp('<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(htmlContent);
    if (titleMatch != null) return titleMatch.group(1)?.trim();

    return null;
  }

  String _extractTextContent(String htmlContent) {
    // 移除 HTML 标签，保留文本
    final text = htmlContent
        // 保留段落换行
        .replaceAll(RegExp('</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp('</h[1-6]>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp('</div>', caseSensitive: false), '\n')
        // 移除所有其他标签
        .replaceAll(RegExp('<[^>]+>'), '')
        // 解码 HTML 实体
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        // 清理多余空白
        .replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n')
        .trim();

    return text;
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
      await _progressService.saveProgress(ReadingProgress(
        itemId: itemId,
        itemType: 'epub',
        position: chapter.toDouble(),
        totalPositions: current.chapters.length,
        chapter: chapter,
        chapterTitle: current.chapters[chapter].title,
        lastReadAt: DateTime.now(),
      ));
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
                Expanded(
                  child: _buildContent(state, settings),
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
    final theme = settings.theme;

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
            child: _buildChapterText(state, settings),
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
              ref.read(epubReaderProvider(widget.book).notifier).goToChapter(index);
            },
            itemBuilder: (context, index) => SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: settings.horizontalPadding,
                vertical: settings.verticalPadding,
              ),
              child: SelectableText(
                state.chapterContents[index],
                style: TextStyle(
                  fontSize: settings.fontSize,
                  height: settings.lineHeight,
                  color: theme.textColor,
                  fontFamily: settings.fontFamily,
                ),
              ),
            ),
          ),
        );
    }
  }

  Widget _buildChapterText(EpubReaderLoaded state, BookReaderSettings settings) {
    final theme = settings.theme;
    final content = state.chapterContents[state.currentChapter];

    // 处理段落间距
    final paragraphs = content.split('\n\n');
    final children = <Widget>[];

    for (var i = 0; i < paragraphs.length; i++) {
      if (paragraphs[i].trim().isEmpty) continue;
      children.add(
        Padding(
          padding: EdgeInsets.only(
            bottom: i < paragraphs.length - 1 ? settings.paragraphSpacing * 16 : 0,
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

  Widget _buildTapZones(EpubReaderLoaded state, BookReaderSettings settings) => Positioned.fill(
        child: Row(
          children: [
            // 左侧 - 上一章
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (settings.pageTurnMode == BookPageTurnMode.scroll) {
                    ref.read(epubReaderProvider(widget.book).notifier).previousChapter();
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
                    ref.read(epubReaderProvider(widget.book).notifier).nextChapter();
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

  Widget _buildTopBar(BuildContext context, EpubReaderLoaded state) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
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
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
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
  ) =>
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.transparent,
            ],
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
                              if (settings.pageTurnMode != BookPageTurnMode.scroll) {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                              }
                            }
                          : null,
                      icon: Icon(
                        Icons.skip_previous_rounded,
                        color: state.currentChapter > 0 ? Colors.white : Colors.white38,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: state.currentChapter.toDouble(),
                        max: (state.totalChapters - 1).toDouble(),
                        divisions: state.totalChapters > 1 ? state.totalChapters - 1 : null,
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
                              if (settings.pageTurnMode != BookPageTurnMode.scroll) {
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
                      selectedTileColor: AppColors.primary.withValues(alpha: 0.1),
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
                  min: 1.0,
                  max: 3.0,
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
                  min: 0.0,
                  max: 3.0,
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
                  settingsNotifier.setKeepScreenOn(value);
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
                onChanged: settingsNotifier.setTapToTurn,
              ),
              _buildSwitchTile(
                context,
                title: '显示进度',
                value: settings.showProgress,
                onChanged: settingsNotifier.setShowProgress,
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
  }) =>
      Column(
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
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      SwitchListTile(
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
  }) =>
      GestureDetector(
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
