import 'package:archive/archive.dart' as archive_lib;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// 漫画阅读模式
enum ComicReadingMode {
  singlePage, // 单页模式
  doublePage, // 双页模式
  webtoon, // 长条模式（从上到下）
}

/// 漫画页面项
class ComicPage {
  ComicPage({
    required this.index,
    this.url,
    this.bytes,
    this.fileName,
  });

  final int index;
  final String? url;
  final Uint8List? bytes;
  final String? fileName;

  bool get isLoaded => url != null || bytes != null;
}

/// 漫画阅读器状态
class ComicReaderState {
  ComicReaderState({
    required this.pages,
    required this.currentPage,
    required this.readingMode,
    this.isLoading = true,
    this.error,
    this.showControls = false,
  });

  final List<ComicPage> pages;
  final int currentPage;
  final ComicReadingMode readingMode;
  final bool isLoading;
  final String? error;
  final bool showControls;

  ComicReaderState copyWith({
    List<ComicPage>? pages,
    int? currentPage,
    ComicReadingMode? readingMode,
    bool? isLoading,
    String? error,
    bool? showControls,
  }) =>
      ComicReaderState(
        pages: pages ?? this.pages,
        currentPage: currentPage ?? this.currentPage,
        readingMode: readingMode ?? this.readingMode,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        showControls: showControls ?? this.showControls,
      );
}

/// 漫画阅读器 Notifier
class ComicReaderNotifier extends StateNotifier<ComicReaderState> {
  ComicReaderNotifier(this._ref, this._comic)
      : super(ComicReaderState(
          pages: [],
          currentPage: 0,
          readingMode: ComicReadingMode.singlePage,
        )) {
    _init();
  }

  final Ref _ref;
  final ComicItem _comic;
  final ReadingProgressService _progressService = ReadingProgressService.instance;

  // 支持的图片格式
  static const _imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];

  Future<void> _init() async {
    await _progressService.init();
    await _loadPages();
    await _restoreProgress();
  }

  Future<void> _loadPages() async {
    state = state.copyWith(isLoading: true);

    try {
      if (_comic.isArchive) {
        await _loadArchivePages();
      } else {
        await _loadFolderPages();
      }
    } on Exception catch (e) {
      logger.e('加载漫画页面失败', e);
      state = state.copyWith(isLoading: false, error: '加载失败: $e');
    }
  }

  Future<void> _loadFolderPages() async {
    final connections = _ref.read(activeConnectionsProvider);
    final conn = connections[_comic.sourceId];
    if (conn == null) {
      state = state.copyWith(isLoading: false, error: '连接不可用');
      return;
    }

    final fs = conn.adapter.fileSystem;
    final items = await fs.listDirectory(_comic.folderPath);

    final imageFiles = items.where((item) {
      if (item.isDirectory) return false;
      final ext = item.name.toLowerCase();
      return _imageExtensions.any((e) => ext.endsWith(e));
    }).toList()

    ..sort((a, b) => a.name.compareTo(b.name));

    final pages = <ComicPage>[];
    for (var i = 0; i < imageFiles.length; i++) {
      final file = imageFiles[i];
      final url = await fs.getFileUrl(file.path);
      pages.add(ComicPage(
        index: i,
        url: url,
        fileName: file.name,
      ));
    }

    state = state.copyWith(pages: pages, isLoading: false);
  }

  Future<void> _loadArchivePages() async {
    final connections = _ref.read(activeConnectionsProvider);
    final conn = connections[_comic.sourceId];
    if (conn == null) {
      state = state.copyWith(isLoading: false, error: '连接不可用');
      return;
    }

    final fs = conn.adapter.fileSystem;

    // 下载压缩包
    final stream = await fs.getFileStream(_comic.folderPath);
    final chunks = <List<int>>[];
    await for (final chunk in stream) {
      chunks.add(chunk);
    }
    final archiveBytes = Uint8List.fromList(chunks.expand((e) => e).toList());

    // 解析压缩包
    archive_lib.Archive archive;
    try {
      if (_comic.type == ComicType.cbz) {
        archive = archive_lib.ZipDecoder().decodeBytes(archiveBytes);
      } else if (_comic.type == ComicType.cbr) {
        // RAR 格式需要特殊处理，archive 包不支持 RAR
        // 暂时尝试当作 ZIP 处理（有些 cbr 实际是 zip）
        try {
          archive = archive_lib.ZipDecoder().decodeBytes(archiveBytes);
        } on Exception catch (_) {
          state = state.copyWith(
            isLoading: false,
            error: 'RAR 格式暂不支持，请使用 CBZ 格式',
          );
          return;
        }
      } else if (_comic.type == ComicType.cb7) {
        // 7z 格式需要特殊处理
        state = state.copyWith(
          isLoading: false,
          error: '7Z 格式暂不支持，请使用 CBZ 格式',
        );
        return;
      } else {
        archive = archive_lib.ZipDecoder().decodeBytes(archiveBytes);
      }
    } on Exception catch (e) {
      state = state.copyWith(isLoading: false, error: '解压失败: $e');
      return;
    }

    // 筛选图片文件
    final imageFiles = archive.files.where((file) {
      if (file.isFile) {
        final name = file.name.toLowerCase();
        return _imageExtensions.any(name.endsWith);
      }
      return false;
    }).toList()

    ..sort((a, b) => a.name.compareTo(b.name));

    final pages = <ComicPage>[];
    for (var i = 0; i < imageFiles.length; i++) {
      final file = imageFiles[i];
      final content = file.content as List<int>?;
      if (content != null) {
        pages.add(ComicPage(
          index: i,
          bytes: Uint8List.fromList(content),
          fileName: file.name,
        ));
      }
    }

    state = state.copyWith(pages: pages, isLoading: false);
  }

  Future<void> _restoreProgress() async {
    final itemId = _progressService.generateItemId(_comic.sourceId, _comic.folderPath);
    final progress = _progressService.getProgress(itemId);
    if (progress != null && state.pages.isNotEmpty) {
      final page = progress.position.toInt().clamp(0, state.pages.length - 1);
      state = state.copyWith(currentPage: page);
    }
  }

  void goToPage(int page) {
    if (page < 0 || page >= state.pages.length) return;
    state = state.copyWith(currentPage: page);
    _saveProgress();
  }

  void nextPage() {
    if (state.readingMode == ComicReadingMode.doublePage) {
      goToPage(state.currentPage + 2);
    } else {
      goToPage(state.currentPage + 1);
    }
  }

  void previousPage() {
    if (state.readingMode == ComicReadingMode.doublePage) {
      goToPage(state.currentPage - 2);
    } else {
      goToPage(state.currentPage - 1);
    }
  }

  void setReadingMode(ComicReadingMode mode) {
    state = state.copyWith(readingMode: mode);
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
    final itemId = _progressService.generateItemId(_comic.sourceId, _comic.folderPath);
    await _progressService.saveProgress(
      ReadingProgress(
        itemId: itemId,
        itemType: 'comic',
        position: state.currentPage.toDouble(),
        totalPositions: state.pages.length,
        lastReadAt: DateTime.now(),
      ),
    );
  }
}

/// 漫画阅读器页面
class ComicReaderPage extends ConsumerStatefulWidget {
  const ComicReaderPage({required this.comic, super.key});

  final ComicItem comic;

  @override
  ConsumerState<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends ConsumerState<ComicReaderPage> {
  late final StateNotifierProvider<ComicReaderNotifier, ComicReaderState> _provider;
  PageController? _pageController;
  ScrollController? _scrollController;

  @override
  void initState() {
    super.initState();
    _provider = StateNotifierProvider<ComicReaderNotifier, ComicReaderState>(
      (ref) => ComicReaderNotifier(ref, widget.comic),
    );

    // 进入全屏模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _scrollController?.dispose();
    // 退出全屏模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final notifier = ref.read(_provider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 主内容
          if (state.isLoading)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          else if (state.error != null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.white54),
                  const SizedBox(height: 16),
                  Text(
                    state.error!,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('返回'),
                  ),
                ],
              ),
            )
          else if (state.pages.isEmpty)
            const Center(
              child: Text(
                '没有找到图片',
                style: TextStyle(color: Colors.white70),
              ),
            )
          else
            GestureDetector(
              onTap: notifier.toggleControls,
              child: _buildReader(state, notifier),
            ),

          // 控制栏
          if (state.showControls) ...[
            // 顶部栏
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(context, state, isDark),
            ),
            // 底部栏
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomBar(context, state, notifier, isDark),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReader(ComicReaderState state, ComicReaderNotifier notifier) {
    switch (state.readingMode) {
      case ComicReadingMode.singlePage:
        return _buildSinglePageReader(state, notifier);
      case ComicReadingMode.doublePage:
        return _buildDoublePageReader(state, notifier);
      case ComicReadingMode.webtoon:
        return _buildWebtoonReader(state, notifier);
    }
  }

  Widget _buildSinglePageReader(ComicReaderState state, ComicReaderNotifier notifier) {
    _pageController ??= PageController(initialPage: state.currentPage);

    return PhotoViewGallery.builder(
      pageController: _pageController,
      itemCount: state.pages.length,
      builder: (context, index) {
        final page = state.pages[index];
        return PhotoViewGalleryPageOptions(
          imageProvider: _getImageProvider(page),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          initialScale: PhotoViewComputedScale.contained,
          heroAttributes: PhotoViewHeroAttributes(tag: 'comic_page_$index'),
        );
      },
      onPageChanged: (index) {
        notifier.goToPage(index);
      },
      scrollPhysics: const BouncingScrollPhysics(),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (context, event) => const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      ),
    );
  }

  Widget _buildDoublePageReader(ComicReaderState state, ComicReaderNotifier notifier) {
    // 双页模式：左右两页并排显示
    final totalDoublePages = (state.pages.length + 1) ~/ 2;
    final currentDoublePage = state.currentPage ~/ 2;

    _pageController ??= PageController(initialPage: currentDoublePage);

    return PageView.builder(
      controller: _pageController,
      itemCount: totalDoublePages,
      onPageChanged: (index) {
        notifier.goToPage(index * 2);
      },
      itemBuilder: (context, index) {
        final leftIndex = index * 2;
        final rightIndex = leftIndex + 1;

        return Row(
          children: [
            Expanded(
              child: leftIndex < state.pages.length
                  ? _buildPageImage(state.pages[leftIndex])
                  : const SizedBox(),
            ),
            Expanded(
              child: rightIndex < state.pages.length
                  ? _buildPageImage(state.pages[rightIndex])
                  : const SizedBox(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWebtoonReader(ComicReaderState state, ComicReaderNotifier notifier) {
    _scrollController ??= ScrollController();

    return ListView.builder(
      controller: _scrollController,
      itemCount: state.pages.length,
      itemBuilder: (context, index) {
        final page = state.pages[index];
        return _buildPageImage(page, fit: BoxFit.fitWidth);
      },
    );
  }

  Widget _buildPageImage(ComicPage page, {BoxFit fit = BoxFit.contain}) {
    if (page.bytes != null) {
      return Image.memory(
        page.bytes!,
        fit: fit,
        errorBuilder: (_, _, _) => _buildErrorPlaceholder(),
      );
    } else if (page.url != null) {
      return Image.network(
        page.url!,
        fit: fit,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          );
        },
        errorBuilder: (_, _, _) => _buildErrorPlaceholder(),
      );
    }
    return _buildErrorPlaceholder();
  }

  Widget _buildErrorPlaceholder() => const Center(
      child: Icon(Icons.broken_image, size: 48, color: Colors.white24),
    );

  ImageProvider _getImageProvider(ComicPage page) {
    if (page.bytes != null) {
      return MemoryImage(page.bytes!);
    } else if (page.url != null) {
      return NetworkImage(page.url!);
    }
    return const AssetImage('assets/images/placeholder.png');
  }

  Widget _buildTopBar(BuildContext context, ComicReaderState state, bool isDark) => DecoratedBox(
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  widget.comic.folderName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 阅读模式切换
              PopupMenuButton<ComicReadingMode>(
                icon: const Icon(Icons.view_carousel, color: Colors.white),
                color: isDark ? AppColors.darkSurface : Colors.white,
                onSelected: (mode) {
                  ref.read(_provider.notifier).setReadingMode(mode);
                  _pageController?.dispose();
                  _pageController = null;
                  _scrollController?.dispose();
                  _scrollController = null;
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: ComicReadingMode.singlePage,
                    child: Row(
                      children: [
                        Icon(
                          Icons.crop_portrait,
                          color: state.readingMode == ComicReadingMode.singlePage
                              ? AppColors.primary
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '单页模式',
                          style: TextStyle(
                            color: state.readingMode == ComicReadingMode.singlePage
                                ? AppColors.primary
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: ComicReadingMode.doublePage,
                    child: Row(
                      children: [
                        Icon(
                          Icons.menu_book,
                          color: state.readingMode == ComicReadingMode.doublePage
                              ? AppColors.primary
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '双页模式',
                          style: TextStyle(
                            color: state.readingMode == ComicReadingMode.doublePage
                                ? AppColors.primary
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: ComicReadingMode.webtoon,
                    child: Row(
                      children: [
                        Icon(
                          Icons.view_day,
                          color: state.readingMode == ComicReadingMode.webtoon
                              ? AppColors.primary
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '长条模式',
                          style: TextStyle(
                            color: state.readingMode == ComicReadingMode.webtoon
                                ? AppColors.primary
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

  Widget _buildBottomBar(
    BuildContext context,
    ComicReaderState state,
    ComicReaderNotifier notifier,
    bool isDark,
  ) => DecoratedBox(
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
              // 页码滑块
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
                      max: (state.pages.length - 1).toDouble(),
                      onChanged: (value) {
                        notifier.goToPage(value.round());
                        _pageController?.jumpToPage(
                          state.readingMode == ComicReadingMode.doublePage
                              ? value.round() ~/ 2
                              : value.round(),
                        );
                      },
                      activeColor: AppColors.primary,
                      inactiveColor: Colors.white24,
                    ),
                  ),
                  Text(
                    '${state.pages.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              // 翻页按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    onPressed: state.currentPage > 0
                        ? () {
                            notifier.previousPage();
                            _pageController?.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        : null,
                  ),
                  Text(
                    '${state.currentPage + 1} / ${state.pages.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    onPressed: state.currentPage < state.pages.length - 1
                        ? () {
                            notifier.nextPage();
                            _pageController?.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
}
