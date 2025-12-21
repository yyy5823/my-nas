import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/widgets/keyboard_shortcuts.dart';
import 'package:my_nas/features/book/data/services/epub_image_extractor.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/comic/presentation/providers/comic_settings_provider.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';
import 'package:my_nas/shared/widgets/reader_settings_sheet.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// EPUB 漫画阅读器状态
class EpubComicReaderState {
  const EpubComicReaderState({
    this.pages = const [],
    this.currentPage = 0,
    this.isLoading = true,
    this.error,
    this.showControls = false,
    this.totalPages = 0,
  });

  final List<EpubImagePage> pages;
  final int currentPage;
  final bool isLoading;
  final String? error;
  final bool showControls;
  final int totalPages;

  EpubComicReaderState copyWith({
    List<EpubImagePage>? pages,
    int? currentPage,
    bool? isLoading,
    String? error,
    bool? showControls,
    int? totalPages,
  }) =>
      EpubComicReaderState(
        pages: pages ?? this.pages,
        currentPage: currentPage ?? this.currentPage,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        showControls: showControls ?? this.showControls,
        totalPages: totalPages ?? this.totalPages,
      );
}

/// EPUB 漫画阅读器 Notifier
class EpubComicReaderNotifier extends StateNotifier<EpubComicReaderState> {
  EpubComicReaderNotifier(this._book, this._epubFile)
      : super(const EpubComicReaderState()) {
    _init();
  }

  final BookItem _book;
  final File _epubFile;
  final EpubImageExtractor _extractor = EpubImageExtractor.instance;
  final ReadingProgressService _progressService = ReadingProgressService();

  Future<void> _init() async {
    await _progressService.init();
    await _loadPages();
    await _restoreProgress();
  }

  Future<void> _loadPages() async {
    try {
      state = state.copyWith(isLoading: true);

      // 获取图片总数
      final totalPages = await _extractor.getImageCount(_epubFile);
      
      // 提取所有图片
      final pages = await _extractor.extractImages(_epubFile);

      state = state.copyWith(
        pages: pages,
        totalPages: totalPages,
        isLoading: false,
      );

      logger.i('EpubComicReader: 加载完成，共 $totalPages 页');
    } on Exception catch (e, st) {
      logger.e('EpubComicReader: 加载失败', e, st);
      state = state.copyWith(
        isLoading: false,
        error: '加载失败: $e',
      );
    }
  }

  Future<void> _restoreProgress() async {
    try {
      final sourceId = _book.sourceId ?? 'local';
      final itemId = _progressService.generateItemId(sourceId, _book.path);
      final progress = _progressService.getProgress(itemId);

      if (progress != null && progress.position > 0) {
        final page = progress.position.toInt().clamp(0, state.totalPages - 1);
        state = state.copyWith(currentPage: page);
        logger.d('EpubComicReader: 恢复进度到第 ${page + 1} 页');
      }
    } on Exception catch (e) {
      logger.w('EpubComicReader: 恢复进度失败: $e');
    }
  }

  void goToPage(int page) {
    if (page < 0 || page >= state.totalPages) return;
    state = state.copyWith(currentPage: page);
    _saveProgress();
  }

  void nextPage(ComicReadingMode readingMode) {
    final delta = readingMode == ComicReadingMode.rightToLeft ? -1 : 1;
    goToPage(state.currentPage + delta);
  }

  void previousPage(ComicReadingMode readingMode) {
    final delta = readingMode == ComicReadingMode.rightToLeft ? 1 : -1;
    goToPage(state.currentPage + delta);
  }

  void toggleControls() {
    state = state.copyWith(showControls: !state.showControls);
  }

  void hideControls() {
    if (state.showControls) {
      state = state.copyWith(showControls: false);
    }
  }

  Future<void> _saveProgress() async {
    try {
      final sourceId = _book.sourceId ?? 'local';
      final itemId = _progressService.generateItemId(sourceId, _book.path);

      await _progressService.saveProgress(
        ReadingProgress(
          itemId: itemId,
          itemType: 'epub_comic',
          position: state.currentPage.toDouble(),
          totalPositions: state.totalPages,
          lastReadAt: DateTime.now(),
        ),
      );
    } on Exception catch (e) {
      logger.w('EpubComicReader: 保存进度失败: $e');
    }
  }
}

/// EPUB 漫画阅读器 Provider
final epubComicReaderProvider = StateNotifierProvider.autoDispose
    .family<EpubComicReaderNotifier, EpubComicReaderState, (BookItem, File)>(
  (ref, params) => EpubComicReaderNotifier(params.$1, params.$2),
);

/// EPUB 漫画阅读器页面
///
/// 使用 PhotoViewGallery 渲染 EPUB 中的图片
/// 适用于漫画类型的 EPUB 文件
class EpubComicReaderPage extends ConsumerStatefulWidget {
  const EpubComicReaderPage({
    required this.book,
    required this.epubFile,
    super.key,
  });

  final BookItem book;
  final File epubFile;

  @override
  ConsumerState<EpubComicReaderPage> createState() => _EpubComicReaderPageState();
}

class _EpubComicReaderPageState extends ConsumerState<EpubComicReaderPage> {
  late PageController _pageController;
  bool _isPageControllerReady = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWakelock();
  }

  Future<void> _initWakelock() async {
    await WakelockPlus.enable();
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    super.dispose();
  }

  void _updatePageController(int currentPage) {
    if (!_isPageControllerReady && _pageController.hasClients) {
      _isPageControllerReady = true;
      if (currentPage > 0) {
        _pageController.jumpToPage(currentPage);
      }
    }
  }

  Map<ShortcutActivator, VoidCallback> _buildKeyboardShortcuts(
    EpubComicReaderState state,
    EpubComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    void goToPrevious() => notifier.previousPage(settings.readingMode);
    void goToNext() => notifier.nextPage(settings.readingMode);

    return {
      const SingleActivator(LogicalKeyboardKey.arrowLeft): goToPrevious,
      const SingleActivator(LogicalKeyboardKey.arrowRight): goToNext,
      const SingleActivator(LogicalKeyboardKey.arrowUp): goToPrevious,
      const SingleActivator(LogicalKeyboardKey.arrowDown): goToNext,
      const SingleActivator(LogicalKeyboardKey.pageUp): goToPrevious,
      const SingleActivator(LogicalKeyboardKey.pageDown): goToNext,
      const SingleActivator(LogicalKeyboardKey.space): goToNext,
      const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
      const SingleActivator(LogicalKeyboardKey.keyQ): () => Navigator.pop(context),
    };
  }

  @override
  Widget build(BuildContext context) {
    final params = (widget.book, widget.epubFile);
    final state = ref.watch(epubComicReaderProvider(params));
    final notifier = ref.read(epubComicReaderProvider(params).notifier);
    final settings = ref.watch(comicReaderSettingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 更新 PageController
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePageController(state.currentPage);
    });

    return KeyboardShortcuts(
      shortcuts: _buildKeyboardShortcuts(state, notifier, settings),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: state.isLoading
            ? const LoadingWidget(message: '加载漫画中...')
            : state.error != null
                ? _buildErrorView(state.error!)
                : Stack(
                    children: [
                      // 漫画内容
                      _buildGallery(state, notifier, settings),
                      // 控制栏
                      if (state.showControls) ...[
                        _buildTopBar(context, state, isDark),
                        _buildBottomBar(context, state, notifier, settings, isDark),
                      ],
                    ],
                  ),
      ),
    );
  }

  Widget _buildErrorView(String error) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              error,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      );

  Widget _buildGallery(
    EpubComicReaderState state,
    EpubComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    final isRtl = settings.readingMode == ComicReadingMode.rightToLeft;

    return GestureDetector(
      onTap: notifier.toggleControls,
      child: PhotoViewGallery.builder(
        pageController: _pageController,
        itemCount: state.pages.length,
        reverse: isRtl,
        builder: (context, index) {
          final page = state.pages[index];
          return PhotoViewGalleryPageOptions(
            imageProvider: MemoryImage(page.data),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
            initialScale: PhotoViewComputedScale.contained,
            heroAttributes: PhotoViewHeroAttributes(tag: 'page_$index'),
          );
        },
        scrollPhysics: const BouncingScrollPhysics(),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (context, event) => const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
        onPageChanged: (index) {
          notifier.goToPage(isRtl ? state.pages.length - 1 - index : index);
        },
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, EpubComicReaderState state, bool isDark) =>
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
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
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    widget.book.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: () => _showSettingsSheet(context),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildBottomBar(
    BuildContext context,
    EpubComicReaderState state,
    EpubComicReaderNotifier notifier,
    ComicReaderSettings settings,
    bool isDark,
  ) =>
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 进度条
                  Row(
                    children: [
                      Text(
                        '${state.currentPage + 1}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Expanded(
                        child: Slider(
                          value: state.currentPage.toDouble(),
                          min: 0,
                          max: (state.totalPages - 1).toDouble().clamp(0, double.infinity),
                          onChanged: (value) {
                            notifier.goToPage(value.toInt());
                            _pageController.jumpToPage(value.toInt());
                          },
                          activeColor: AppColors.primary,
                          inactiveColor: Colors.white24,
                        ),
                      ),
                      Text(
                        '${state.totalPages}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  // 控制按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.first_page, color: Colors.white),
                        onPressed: () {
                          notifier.goToPage(0);
                          _pageController.jumpToPage(0);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
                        onPressed: () {
                          notifier.previousPage(settings.readingMode);
                          final targetPage = settings.readingMode == ComicReadingMode.rightToLeft
                              ? state.currentPage + 1
                              : state.currentPage - 1;
                          if (targetPage >= 0 && targetPage < state.totalPages) {
                            _pageController.animateToPage(
                              targetPage,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, color: Colors.white, size: 32),
                        onPressed: () {
                          notifier.nextPage(settings.readingMode);
                          final targetPage = settings.readingMode == ComicReadingMode.rightToLeft
                              ? state.currentPage - 1
                              : state.currentPage + 1;
                          if (targetPage >= 0 && targetPage < state.totalPages) {
                            _pageController.animateToPage(
                              targetPage,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.last_page, color: Colors.white),
                        onPressed: () {
                          final lastPage = state.totalPages - 1;
                          notifier.goToPage(lastPage);
                          _pageController.jumpToPage(lastPage);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  void _showSettingsSheet(BuildContext context) {
    showReaderSettingsSheet(
      context,
      title: '漫画设置',
      icon: Icons.auto_stories_rounded,
      iconColor: AppColors.primary,
      contentBuilder: (context) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(comicReaderSettingsProvider);
          return _buildSettingsContent(settings);
        },
      ),
    );
  }

  Widget _buildSettingsContent(ComicReaderSettings settings) {
    final settingsNotifier = ref.read(comicReaderSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingSectionTitle(title: '阅读方向'),
        Wrap(
          spacing: 8,
          children: ComicReadingMode.values.map((mode) {
            final isSelected = settings.readingMode == mode;
            return ChoiceChip(
              label: Text(mode.label),
              selected: isSelected,
              onSelected: (_) => settingsNotifier.setReadingMode(mode),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
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
          title: '显示进度',
          value: settings.showProgress,
          onChanged: (value) => settingsNotifier.setShowProgress(value: value),
        ),
      ],
    );
  }
}
