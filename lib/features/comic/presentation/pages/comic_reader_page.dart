import 'package:archive/archive.dart' as archive_lib;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
    this.isLoading = true,
    this.error,
    this.showControls = false,
    this.showSettings = false,
  });

  final List<ComicPage> pages;
  final int currentPage;
  final bool isLoading;
  final String? error;
  final bool showControls;
  final bool showSettings;

  ComicReaderState copyWith({
    List<ComicPage>? pages,
    int? currentPage,
    bool? isLoading,
    String? error,
    bool? showControls,
    bool? showSettings,
  }) =>
      ComicReaderState(
        pages: pages ?? this.pages,
        currentPage: currentPage ?? this.currentPage,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        showControls: showControls ?? this.showControls,
        showSettings: showSettings ?? this.showSettings,
      );
}

/// 漫画阅读器 Notifier
class ComicReaderNotifier extends StateNotifier<ComicReaderState> {
  ComicReaderNotifier(this._ref, this._comic)
      : super(ComicReaderState(
          pages: [],
          currentPage: 0,
        )) {
    _init();
  }

  final Ref _ref;
  final ComicItem _comic;
  final ReadingProgressService _progressService = ReadingProgressService();

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
      return _imageExtensions.any(ext.endsWith);
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

  void nextPage(ComicReadingMode readingMode) {
    if (readingMode == ComicReadingMode.doublePage) {
      goToPage(state.currentPage + 2);
    } else {
      goToPage(state.currentPage + 1);
    }
  }

  void previousPage(ComicReadingMode readingMode) {
    if (readingMode == ComicReadingMode.doublePage) {
      goToPage(state.currentPage - 2);
    } else {
      goToPage(state.currentPage - 1);
    }
  }

  void toggleControls() {
    state = state.copyWith(showControls: !state.showControls, showSettings: false);
  }

  void toggleSettings() {
    state = state.copyWith(showSettings: !state.showSettings);
  }

  void hideControls() {
    if (state.showControls) {
      state = state.copyWith(showControls: false, showSettings: false);
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
    _initWakelock();
  }

  Future<void> _initWakelock() async {
    final settings = ref.read(comicReaderSettingsProvider);
    if (settings.keepScreenOn) {
      await WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _scrollController?.dispose();
    WakelockPlus.disable();
    // 退出全屏模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final notifier = ref.read(_provider.notifier);
    final settings = ref.watch(comicReaderSettingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: settings.backgroundColor.color,
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
            _buildReader(state, notifier, settings),

          // 点击翻页区域
          if (settings.tapToTurn && !state.isLoading && state.pages.isNotEmpty)
            _buildTapZones(state, notifier, settings),

          // 控制栏
          if (state.showControls) ...[
            // 顶部栏
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(context, state, settings, isDark),
            ),
            // 底部栏
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomBar(context, state, notifier, settings, isDark),
            ),
          ],

          // 设置面板
          if (state.showSettings)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: _buildSettingsPanel(context, settings, isDark),
            ),
        ],
      ),
    );
  }

  Widget _buildTapZones(
    ComicReaderState state,
    ComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    final isRtl = settings.readingDirection == ComicReadingDirection.rtl;

    return Positioned.fill(
      child: Row(
        children: [
          // 左侧区域
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (isRtl) {
                  notifier.nextPage(settings.readingMode);
                  _pageController?.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                } else {
                  notifier.previousPage(settings.readingMode);
                  _pageController?.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              },
              behavior: HitTestBehavior.translucent,
              child: Container(),
            ),
          ),
          // 中间区域 - 显示/隐藏控制栏
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: notifier.toggleControls,
              behavior: HitTestBehavior.translucent,
              child: Container(),
            ),
          ),
          // 右侧区域
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (isRtl) {
                  notifier.previousPage(settings.readingMode);
                  _pageController?.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                } else {
                  notifier.nextPage(settings.readingMode);
                  _pageController?.nextPage(
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

  Widget _buildReader(
    ComicReaderState state,
    ComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    switch (settings.readingMode) {
      case ComicReadingMode.singlePage:
        return _buildSinglePageReader(state, notifier, settings);
      case ComicReadingMode.doublePage:
        return _buildDoublePageReader(state, notifier, settings);
      case ComicReadingMode.webtoon:
        return _buildWebtoonReader(state, notifier, settings);
    }
  }

  Widget _buildSinglePageReader(
    ComicReaderState state,
    ComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    _pageController ??= PageController(initialPage: state.currentPage);
    final isRtl = settings.readingDirection == ComicReadingDirection.rtl;

    return PhotoViewGallery.builder(
      pageController: _pageController,
      itemCount: state.pages.length,
      reverse: isRtl,
      builder: (context, index) {
        final page = state.pages[index];
        return PhotoViewGalleryPageOptions(
          imageProvider: _getImageProvider(page),
          minScale: _getMinScale(settings.scaleMode),
          maxScale: PhotoViewComputedScale.covered * 3,
          initialScale: _getInitialScale(settings.scaleMode),
          heroAttributes: PhotoViewHeroAttributes(tag: 'comic_page_$index'),
        );
      },
      onPageChanged: (index) {
        notifier.goToPage(index);
      },
      scrollPhysics: const BouncingScrollPhysics(),
      backgroundDecoration: BoxDecoration(color: settings.backgroundColor.color),
      loadingBuilder: (context, event) => const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      ),
    );
  }

  PhotoViewComputedScale _getMinScale(ComicScaleMode mode) => switch (mode) {
        ComicScaleMode.fitWidth => PhotoViewComputedScale.contained,
        ComicScaleMode.fitHeight => PhotoViewComputedScale.contained,
        ComicScaleMode.fitScreen => PhotoViewComputedScale.contained,
        ComicScaleMode.original => PhotoViewComputedScale.contained,
      };

  PhotoViewComputedScale _getInitialScale(ComicScaleMode mode) => switch (mode) {
        ComicScaleMode.fitWidth => PhotoViewComputedScale.contained,
        ComicScaleMode.fitHeight => PhotoViewComputedScale.contained,
        ComicScaleMode.fitScreen => PhotoViewComputedScale.contained,
        ComicScaleMode.original => PhotoViewComputedScale.covered,
      };

  Widget _buildDoublePageReader(
    ComicReaderState state,
    ComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    // 双页模式：左右两页并排显示
    final totalDoublePages = (state.pages.length + 1) ~/ 2;
    final currentDoublePage = state.currentPage ~/ 2;
    final isRtl = settings.readingDirection == ComicReadingDirection.rtl;

    _pageController ??= PageController(initialPage: currentDoublePage);

    return PageView.builder(
      controller: _pageController,
      itemCount: totalDoublePages,
      reverse: isRtl,
      onPageChanged: (index) {
        notifier.goToPage(index * 2);
      },
      itemBuilder: (context, index) {
        final leftIndex = index * 2;
        final rightIndex = leftIndex + 1;

        // RTL 模式下交换左右页
        final firstIndex = isRtl ? rightIndex : leftIndex;
        final secondIndex = isRtl ? leftIndex : rightIndex;

        return Row(
          children: [
            Expanded(
              child: firstIndex < state.pages.length && firstIndex >= 0
                  ? _buildPageImage(state.pages[firstIndex], settings)
                  : const SizedBox(),
            ),
            Expanded(
              child: secondIndex < state.pages.length && secondIndex >= 0
                  ? _buildPageImage(state.pages[secondIndex], settings)
                  : const SizedBox(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWebtoonReader(
    ComicReaderState state,
    ComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    _scrollController ??= ScrollController();

    return ListView.builder(
      controller: _scrollController,
      itemCount: state.pages.length,
      itemBuilder: (context, index) {
        final page = state.pages[index];
        return Padding(
          padding: EdgeInsets.only(bottom: settings.webtoonPageGap),
          child: _buildPageImage(page, settings, fit: BoxFit.fitWidth),
        );
      },
    );
  }

  Widget _buildPageImage(
    ComicPage page,
    ComicReaderSettings settings, {
    BoxFit fit = BoxFit.contain,
  }) {
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

  Widget _buildTopBar(
    BuildContext context,
    ComicReaderState state,
    ComicReaderSettings settings,
    bool isDark,
  ) =>
      DecoratedBox(
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
                // 设置按钮
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: () => ref.read(_provider.notifier).toggleSettings(),
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
    ComicReaderSettings settings,
    bool isDark,
  ) {
    final isRtl = settings.readingDirection == ComicReadingDirection.rtl;

    return DecoratedBox(
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
                      max: (state.pages.length - 1).toDouble(),
                      onChanged: (value) {
                        notifier.goToPage(value.round());
                        _pageController?.jumpToPage(
                          settings.readingMode == ComicReadingMode.doublePage
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
                    icon: Icon(
                      isRtl ? Icons.skip_next : Icons.skip_previous,
                      color: Colors.white,
                    ),
                    onPressed: state.currentPage > 0
                        ? () {
                            notifier.previousPage(settings.readingMode);
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
                    icon: Icon(
                      isRtl ? Icons.skip_previous : Icons.skip_next,
                      color: Colors.white,
                    ),
                    onPressed: state.currentPage < state.pages.length - 1
                        ? () {
                            notifier.nextPage(settings.readingMode);
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

  Widget _buildSettingsPanel(
    BuildContext context,
    ComicReaderSettings settings,
    bool isDark,
  ) {
    final settingsNotifier = ref.read(comicReaderSettingsProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (isDark ? Colors.grey[900] : Colors.white)?.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 阅读模式
            _buildSettingSection(
              context,
              title: '阅读模式',
              isDark: isDark,
              child: Row(
                children: [
                  _buildModeButton(
                    context,
                    icon: Icons.crop_portrait,
                    label: '单页',
                    isSelected: settings.readingMode == ComicReadingMode.singlePage,
                    onTap: () {
                      settingsNotifier.setReadingMode(ComicReadingMode.singlePage);
                      _resetControllers();
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildModeButton(
                    context,
                    icon: Icons.menu_book,
                    label: '双页',
                    isSelected: settings.readingMode == ComicReadingMode.doublePage,
                    onTap: () {
                      settingsNotifier.setReadingMode(ComicReadingMode.doublePage);
                      _resetControllers();
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildModeButton(
                    context,
                    icon: Icons.view_day,
                    label: '长条',
                    isSelected: settings.readingMode == ComicReadingMode.webtoon,
                    onTap: () {
                      settingsNotifier.setReadingMode(ComicReadingMode.webtoon);
                      _resetControllers();
                    },
                    isDark: isDark,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 阅读方向
            _buildSettingSection(
              context,
              title: '阅读方向',
              isDark: isDark,
              child: Row(
                children: [
                  _buildModeButton(
                    context,
                    icon: Icons.arrow_forward,
                    label: '从左到右',
                    isSelected: settings.readingDirection == ComicReadingDirection.ltr,
                    onTap: () => settingsNotifier.setReadingDirection(ComicReadingDirection.ltr),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildModeButton(
                    context,
                    icon: Icons.arrow_back,
                    label: '从右到左',
                    isSelected: settings.readingDirection == ComicReadingDirection.rtl,
                    onTap: () => settingsNotifier.setReadingDirection(ComicReadingDirection.rtl),
                    isDark: isDark,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 缩放模式
            _buildSettingSection(
              context,
              title: '缩放模式',
              isDark: isDark,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildModeButton(
                    context,
                    icon: Icons.width_normal,
                    label: '适应宽度',
                    isSelected: settings.scaleMode == ComicScaleMode.fitWidth,
                    onTap: () => settingsNotifier.setScaleMode(ComicScaleMode.fitWidth),
                    isDark: isDark,
                  ),
                  _buildModeButton(
                    context,
                    icon: Icons.height,
                    label: '适应高度',
                    isSelected: settings.scaleMode == ComicScaleMode.fitHeight,
                    onTap: () => settingsNotifier.setScaleMode(ComicScaleMode.fitHeight),
                    isDark: isDark,
                  ),
                  _buildModeButton(
                    context,
                    icon: Icons.fit_screen,
                    label: '适应屏幕',
                    isSelected: settings.scaleMode == ComicScaleMode.fitScreen,
                    onTap: () => settingsNotifier.setScaleMode(ComicScaleMode.fitScreen),
                    isDark: isDark,
                  ),
                  _buildModeButton(
                    context,
                    icon: Icons.crop_original,
                    label: '原始大小',
                    isSelected: settings.scaleMode == ComicScaleMode.original,
                    onTap: () => settingsNotifier.setScaleMode(ComicScaleMode.original),
                    isDark: isDark,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 背景颜色
            _buildSettingSection(
              context,
              title: '背景颜色',
              isDark: isDark,
              child: Row(
                children: ComicBackgroundColor.values.map((color) {
                  final isSelected = settings.backgroundColor == color;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => settingsNotifier.setBackgroundColor(color),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? AppColors.primary : Colors.grey,
                            width: isSelected ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // 长条模式页间距
            if (settings.readingMode == ComicReadingMode.webtoon) ...[
              _buildSettingSection(
                context,
                title: '页间距: ${settings.webtoonPageGap.toInt()}',
                isDark: isDark,
                child: Slider(
                  value: settings.webtoonPageGap,
                  min: 0,
                  max: 50,
                  divisions: 10,
                  onChanged: (value) => settingsNotifier.setWebtoonPageGap(value),
                  activeColor: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 开关选项
            _buildSwitchRow(
              context,
              title: '显示页码',
              value: settings.showPageNumber,
              onChanged: (value) => settingsNotifier.setShowPageNumber(value),
              isDark: isDark,
            ),
            _buildSwitchRow(
              context,
              title: '保持屏幕常亮',
              value: settings.keepScreenOn,
              onChanged: (value) async {
                settingsNotifier.setKeepScreenOn(value);
                if (value) {
                  await WakelockPlus.enable();
                } else {
                  await WakelockPlus.disable();
                }
              },
              isDark: isDark,
            ),
            _buildSwitchRow(
              context,
              title: '点击翻页',
              value: settings.tapToTurn,
              onChanged: (value) => settingsNotifier.setTapToTurn(value),
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  void _resetControllers() {
    _pageController?.dispose();
    _pageController = null;
    _scrollController?.dispose();
    _scrollController = null;
  }

  Widget _buildSettingSection(
    BuildContext context, {
    required String title,
    required Widget child,
    required bool isDark,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      );

  Widget _buildModeButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.2)
                : (isDark ? Colors.grey[800] : Colors.grey[200]),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? AppColors.primary : (isDark ? Colors.white70 : Colors.black54),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? AppColors.primary : (isDark ? Colors.white70 : Colors.black54),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildSwitchRow(
    BuildContext context, {
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
              activeThumbColor: AppColors.primary,
            ),
          ],
        ),
      );
}
