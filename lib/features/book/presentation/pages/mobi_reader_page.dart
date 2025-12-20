import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foliate_viewer/flutter_foliate_viewer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_file_cache_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
import 'package:my_nas/features/reading/presentation/widgets/page_flip_effect.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';
import 'package:my_nas/shared/widgets/reader_settings_sheet.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// MOBI/AZW3 阅读器状态
sealed class MobiReaderState {}

class MobiReaderLoading extends MobiReaderState {
  MobiReaderLoading({this.message = '加载中...'});

  final String message;
}

class MobiReaderLoaded extends MobiReaderState {
  MobiReaderLoaded({required this.filePath});

  final String filePath;
}

class MobiReaderError extends MobiReaderState {
  MobiReaderError(this.message);

  final String message;
}

/// MOBI/AZW3 阅读器 Provider
final mobiReaderProvider =
    StateNotifierProvider.family<MobiReaderNotifier, MobiReaderState, BookItem>(
      (ref, book) => MobiReaderNotifier(book, ref),
    );

class MobiReaderNotifier extends StateNotifier<MobiReaderState> {
  MobiReaderNotifier(this.book, this._ref) : super(MobiReaderLoading()) {
    _loadBook();
  }

  final BookItem book;
  final Ref _ref;
  final BookFileCacheService _cacheService = BookFileCacheService();

  Future<void> _loadBook() async {
    try {
      await _cacheService.init();

      // 检查缓存
      final cachedFile = await _cacheService.getCachedFile(
        book.sourceId,
        book.path,
      );

      if (cachedFile != null && await cachedFile.exists()) {
        state = MobiReaderLoaded(filePath: cachedFile.path);
        return;
      }

      // 从网络或本地加载
      final uri = Uri.parse(book.url);

      if (uri.scheme == 'file') {
        // 本地文件
        final localPath = uri.toFilePath();
        if (await File(localPath).exists()) {
          state = MobiReaderLoaded(filePath: localPath);
          return;
        }
        throw Exception('文件不存在');
      }

      // 网络文件 - 需要下载并缓存（流式写入避免内存问题）
      state = MobiReaderLoading(message: '下载中...');

      final fileSystem = _getFileSystem();
      if (fileSystem != null) {
        // 使用流式写入，避免大文件占用过多内存
        final savedFile = await _cacheService.saveToCacheFromStream(
          book.sourceId,
          book.path,
          () => fileSystem.getFileStream(book.path),
        );
        if (savedFile == null) {
          throw Exception('无法保存缓存文件');
        }
        state = MobiReaderLoaded(filePath: savedFile.path);
      } else {
        throw Exception('无法获取文件系统');
      }
    } on Exception catch (e, st) {
      logger.e('加载 MOBI/AZW3 失败', e, st);
      state = MobiReaderError('加载失败: $e');
    }
  }

  NasFileSystem? _getFileSystem() {
    if (book.sourceId == null) return null;
    final connections = _ref.read(activeConnectionsProvider);
    final connection = connections[book.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      return null;
    }
    return connection.adapter.fileSystem;
  }
}

/// MOBI/AZW3 阅读器页面
class MobiReaderPage extends ConsumerStatefulWidget {
  const MobiReaderPage({required this.book, super.key});

  final BookItem book;

  @override
  ConsumerState<MobiReaderPage> createState() => _MobiReaderPageState();
}

class _MobiReaderPageState extends ConsumerState<MobiReaderPage> {
  final FoliateController _controller = FoliateController();
  final ReadingProgressService _progressService = ReadingProgressService();

  FoliateBookInfo? _bookInfo;
  FoliateLocation? _currentLocation;
  bool _showControls = false;
  bool _showToc = false;
  String? _initialCfi;
  List<FoliateTocItem> _tocItems = [];

  /// 展平的目录列表（包含层级深度信息）
  List<(FoliateTocItem, int)> get _flattenedTocItems {
    final result = <(FoliateTocItem, int)>[];
    void flatten(List<FoliateTocItem> items, int depth) {
      for (final item in items) {
        result.add((item, depth));
        if (item.subitems.isNotEmpty) {
          flatten(item.subitems, depth + 1);
        }
      }
    }
    flatten(_tocItems, 0);
    return result;
  }

  // 进度保存防抖
  Timer? _saveProgressTimer;
  FoliateLocation? _pendingLocation;
  static const _saveProgressDebounce = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWakelock();
    _loadProgress();
  }

  Future<void> _initWakelock() async {
    final settings = ref.read(bookReaderSettingsProvider);
    if (settings.keepScreenOn) {
      await WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    // 页面关闭时立即保存待保存的进度
    _saveProgressTimer?.cancel();
    if (_pendingLocation != null) {
      _saveProgressImmediately(_pendingLocation!);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    await _progressService.init();
    final itemId = _progressService.generateItemId(
      widget.book.sourceId ?? 'local',
      widget.book.path,
    );
    final progress = _progressService.getProgress(itemId);
    if (progress?.cfi != null && progress!.cfi!.isNotEmpty) {
      setState(() {
        _initialCfi = progress.cfi;
      });
    }
  }

  /// 防抖保存进度（800ms 内的多次变化只保存最后一次）
  void _saveProgressDebounced(FoliateLocation location) {
    _pendingLocation = location;
    _saveProgressTimer?.cancel();
    _saveProgressTimer = Timer(_saveProgressDebounce, () {
      if (_pendingLocation != null) {
        _saveProgressImmediately(_pendingLocation!);
        _pendingLocation = null;
      }
    });
  }

  /// 立即保存进度
  Future<void> _saveProgressImmediately(FoliateLocation location) async {
    final itemId = _progressService.generateItemId(
      widget.book.sourceId ?? 'local',
      widget.book.path,
    );
    await _progressService.saveProgress(
      ReadingProgress(
        itemId: itemId,
        itemType: 'mobi',
        position: location.fraction,
        totalPositions: 1,
        lastReadAt: DateTime.now(),
        cfi: location.cfi,
      ),
    );
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) {
        _showToc = false;
      }
    });
  }

  /// 从 BookReaderSettings 创建 FoliateStyle
  FoliateStyle _createStyle(BookReaderSettings settings) => FoliateStyle.fromReaderSettings(
      fontSize: settings.fontSize,
      lineHeight: settings.lineHeight,
      paragraphSpacing: settings.paragraphSpacing,
      horizontalPadding: settings.horizontalPadding,
      verticalPadding: settings.verticalPadding,
      backgroundColor: settings.theme.backgroundColor,
      textColor: settings.theme.textColor,
      fontFamily: settings.fontFamily,
      pageTurnStyle: FoliatePageTurnStyle.fromPageTurnMode(
        settings.pageTurnMode.index,
      ),
      // 不需要额外边距，FoliateViewer 已在固定栏之间
    );

  /// 应用设置变化
  Future<void> _applySettings(BookReaderSettings settings) async {
    final style = _createStyle(settings);
    await _controller.applyStyle(style);
  }

  /// 显示设置面板
  void _showSettingsSheet() {
    showReaderSettingsSheet(
      context,
      title: '阅读设置',
      icon: Icons.settings,
      contentBuilder: (context) => Consumer(
          builder: (context, ref, _) {
            final settings = ref.watch(bookReaderSettingsProvider);
            return _buildSettingsContent(settings);
          },
        ),
    );
  }

  /// 将 BookPageTurnMode 映射到 FoliatePageTurnStyle
  /// - scroll: 水平翻页（分页模式，左右滑动切换页面）
  /// - slide: 连续滚动（无页面边界，上下拖动查看更多内容）
  /// - simulation/cover: Flutter 层实现，Foliate 使用分页模式
  FoliatePageTurnStyle _mapPageTurnMode(BookPageTurnMode mode) => switch (mode) {
        BookPageTurnMode.scroll => FoliatePageTurnStyle.slide, // 水平翻页
        BookPageTurnMode.slide => FoliatePageTurnStyle.scroll, // 连续滚动
        BookPageTurnMode.simulation => FoliatePageTurnStyle.slide, // Flutter 处理
        BookPageTurnMode.cover => FoliatePageTurnStyle.slide, // Flutter 处理
        BookPageTurnMode.none => FoliatePageTurnStyle.noAnimation,
      };

  // 所有翻页模式
  static const _allPageTurnModes = [
    (icon: Icons.swap_horiz_rounded, label: '翻页', mode: BookPageTurnMode.scroll),
    (icon: Icons.swap_vert_rounded, label: '滚动', mode: BookPageTurnMode.slide),
    (icon: Icons.auto_stories_rounded, label: '仿真', mode: BookPageTurnMode.simulation),
    (icon: Icons.flip_rounded, label: '覆盖', mode: BookPageTurnMode.cover),
    (icon: Icons.article_rounded, label: '无动画', mode: BookPageTurnMode.none),
  ];

  int _getPageTurnModeIndex(BookPageTurnMode mode) => switch (mode) {
        BookPageTurnMode.scroll => 0,
        BookPageTurnMode.slide => 1,
        BookPageTurnMode.simulation => 2,
        BookPageTurnMode.cover => 3,
        BookPageTurnMode.none => 4,
      };

  /// 判断是否使用 Flutter 层面的翻页效果
  bool _useFlutterPageFlip(BookPageTurnMode mode) =>
      mode == BookPageTurnMode.simulation || mode == BookPageTurnMode.cover;

  Widget _buildSettingsContent(BookReaderSettings settings) {
    final settingsNotifier = ref.read(bookReaderSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 翻页方式
        const SettingSectionTitle(title: '翻页方式'),
        SettingPageTurnModePicker(
          modes: _allPageTurnModes
              .map((m) => (icon: m.icon, label: m.label))
              .toList(),
          selectedIndex: _getPageTurnModeIndex(settings.pageTurnMode),
          onSelect: (index) {
            final mode = _allPageTurnModes[index].mode;
            settingsNotifier.setPageTurnMode(mode);
            // 仿真和覆盖翻页由 Flutter 处理，Foliate 使用滑动模式
            _controller.setPageTurnStyle(_mapPageTurnMode(mode));
          },
        ),
        const SizedBox(height: 24),

        // 字体选择（注意：Foliate 仅支持系统字体）
        SettingSectionTitle(
          title: '字体',
          trailing: AvailableFonts.getDisplayName(settings.fontFamily),
        ),
        SettingFontPicker(
          selectedFont: settings.fontFamily,
          onSelect: (fontFamily) {
            settingsNotifier.setFontFamily(fontFamily);
            // 同时调用 setFontFamily 和 applyStyle 确保字体生效
            _controller.setFontFamily(fontFamily);
            _applySettings(settings.copyWith(fontFamily: fontFamily));
          },
        ),
        const SizedBox(height: 24),

        // 字体大小
        SettingSliderRow(
          label: '字体大小',
          value: settings.fontSize,
          min: 12,
          max: 36,
          divisions: 12,
          valueLabel: '${settings.fontSize.toInt()}',
          onChanged: (value) {
            settingsNotifier.setFontSize(value);
            _controller.setFontSize(value / 18.0);
          },
        ),
        const SizedBox(height: 16),

        // 行高
        SettingSliderRow(
          label: '行高',
          value: settings.lineHeight,
          min: 1,
          max: 3,
          divisions: 20,
          onChanged: (value) {
            settingsNotifier.setLineHeight(value);
            _controller.setLineHeight(value);
          },
        ),
        const SizedBox(height: 16),

        // 段落间距
        SettingSliderRow(
          label: '段落间距',
          value: settings.paragraphSpacing,
          max: 3,
          divisions: 15,
          onChanged: (value) {
            settingsNotifier.setParagraphSpacing(value);
            _applySettings(settings.copyWith(paragraphSpacing: value));
          },
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
          onChanged: (value) {
            settingsNotifier.setHorizontalPadding(value);
            _applySettings(settings.copyWith(horizontalPadding: value));
          },
        ),
        const SizedBox(height: 24),

        // 阅读主题
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
                      onTap: () {
                        settingsNotifier.setTheme(theme);
                        _applySettings(settings.copyWith(theme: theme));
                      },
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
          title: '显示进度',
          value: settings.showProgress,
          onChanged: (value) => settingsNotifier.setShowProgress(value: value),
        ),

        // EPUB 引擎设置（仅 EPUB 格式显示）
        if (widget.book.format == BookFormat.epub) ...[
          const SizedBox(height: 24),
          const SettingSectionTitle(title: 'EPUB 引擎'),
          _buildEngineSelector(settings, settingsNotifier),
        ],
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
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? Colors.grey.shade600 : Colors.grey.shade300),
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
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? Colors.white70 : Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEngineSelector(
    BookReaderSettings settings,
    BookReaderSettingsNotifier settingsNotifier,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final engines = [
      (
        engine: EpubReaderEngine.foliate,
        icon: Icons.auto_awesome_rounded,
        label: 'Foliate',
        desc: '功能丰富，支持更多设置',
      ),
      (
        engine: EpubReaderEngine.native,
        icon: Icons.menu_book_rounded,
        label: '原生',
        desc: '简洁稳定',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...engines.map((item) {
          final isSelected = settings.epubEngine == item.engine;
          return GestureDetector(
            onTap: () {
              if (!isSelected) {
                settingsNotifier.setEpubEngine(item.engine);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('引擎切换将在下次打开时生效'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : (isDark ? Colors.grey.shade800 : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? Colors.white70 : Colors.black54),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                            color: isSelected
                                ? AppColors.primary
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        Text(
                          item.desc,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle, color: AppColors.primary),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mobiReaderProvider(widget.book));
    final settings = ref.watch(bookReaderSettingsProvider);

    return Scaffold(
      backgroundColor: settings.theme.backgroundColor,
      body: switch (state) {
        MobiReaderLoading(:final message) => LoadingWidget(message: message),
        MobiReaderError(:final message) => _buildError(message),
        MobiReaderLoaded(:final filePath) => _buildReader(filePath, settings),
      },
    );
  }

  Widget _buildError(String message) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: Colors.red),
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

  Widget _buildReader(String filePath, BookReaderSettings settings) {
    final style = _createStyle(settings);
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;
    final useFlutterFlip = _useFlutterPageFlip(settings.pageTurnMode);

    // 构建阅读器核心内容
    Widget readerContent = ColoredBox(
      color: settings.theme.backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            // 固定顶栏 - 显示书名，避免摄像头遮挡
            _buildFixedHeader(settings, isDark),
            // 阅读器内容
            Expanded(
              child: FoliateViewer(
                controller: _controller,
                bookSource: FileBookSource(File(filePath)),
                initialCfi: _initialCfi,
                style: style,
                onBookLoaded: (info) async {
                  setState(() {
                    _bookInfo = info;
                  });
                  // 延迟加载目录，确保书籍完全加载
                  await Future<void>.delayed(const Duration(milliseconds: 500));
                  if (!mounted) return;
                  // 尝试获取目录，如果失败则重试
                  var toc = await _controller.getToc();
                  if (toc.isEmpty) {
                    // 再次延迟重试
                    await Future<void>.delayed(const Duration(milliseconds: 500));
                    if (!mounted) return;
                    toc = await _controller.getToc();
                  }
                  if (mounted) {
                    setState(() {
                      _tocItems = toc;
                    });
                  }
                },
                onLocationChanged: (location) {
                  setState(() {
                    _currentLocation = location;
                  });
                  _saveProgressDebounced(location);
                },
                onError: (error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error)),
                  );
                },
              ),
            ),
            // 固定底栏 - 显示进度信息
            if (settings.showProgress) _buildFixedFooter(settings, isDark),
          ],
        ),
      ),
    );

    // 如果使用 Flutter 翻页效果，用 PageFlipEffect 包裹
    if (useFlutterFlip) {
      readerContent = PageFlipEffect(
        mode: settings.pageTurnMode == BookPageTurnMode.simulation
            ? PageFlipMode.simulation
            : PageFlipMode.cover,
        onNextPage: () async {
          await _controller.nextPage();
        },
        onPrevPage: () async {
          await _controller.prevPage();
        },
        onTap: (details) => _handleTapForFlipMode(details, settings),
        child: readerContent,
      );
    }

    return Stack(
      children: [
        // 主内容区域
        readerContent,

        // 透明点击层 - 仅在非 Flutter 翻页模式时使用
        if (!useFlutterFlip)
          Positioned.fill(
            child: _buildTapZones(settings),
          ),

        // 顶部控制栏（可隐藏）
        if (_showControls) _buildTopBar(settings),

        // 底部控制栏（可隐藏）
        if (_showControls) _buildBottomBar(settings),

        // 目录抽屉
        if (_showToc) _buildTocDrawer(settings),
      ],
    );
  }

  /// 处理 Flutter 翻页模式下的点击事件
  void _handleTapForFlipMode(TapUpDetails details, BookReaderSettings settings) {
    final screenWidth = MediaQuery.of(context).size.width;
    final tapX = details.localPosition.dx;
    final ratio = tapX / screenWidth;

    // 中间区域切换控制栏
    if (ratio >= 0.25 && ratio <= 0.75) {
      _toggleControls();
    }
    // 左右区域由 PageFlipEffect 处理翻页
  }

  /// 固定顶栏 - 显示书名
  Widget _buildFixedHeader(BookReaderSettings settings, bool isDark) => SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _bookInfo?.title ?? widget.book.name,
                style: TextStyle(
                  color: (isDark ? Colors.white : Colors.black87)
                      .withValues(alpha: 0.6),
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

  /// 固定底栏 - 显示进度信息
  Widget _buildFixedFooter(BookReaderSettings settings, bool isDark) {
    final progress = _currentLocation?.fraction ?? 0.0;
    return SizedBox(
      height: 24,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(progress * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                color: (isDark ? Colors.white : Colors.black87)
                    .withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
            Text(
              '${_currentLocation?.sectionIndex ?? 0}/${_currentLocation?.totalSections ?? 0}',
              style: TextStyle(
                color: (isDark ? Colors.white : Colors.black87)
                    .withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 判断是否需要点击区域翻页
  /// 滑动模式和滚动模式使用 WebView 内置手势，不需要点击翻页
  bool _needsTapToTurn(BookPageTurnMode mode) =>
      mode == BookPageTurnMode.none; // 只有无动画模式需要点击翻页

  /// 三区域点击处理
  /// 使用 Listener 只监听点击，不拦截滑动手势，让 WebView 正常处理滑动翻页
  Widget _buildTapZones(BookReaderSettings settings) => Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _tapDownPosition = event.localPosition;
        _tapDownTime = DateTime.now();
      },
      onPointerUp: (event) {
        if (_tapDownPosition == null || _tapDownTime == null) return;

        final distance = (event.localPosition - _tapDownPosition!).distance;
        final duration = DateTime.now().difference(_tapDownTime!);

        // 快速点击且移动距离小，才视为点击（不是滑动）
        if (distance < 15 && duration.inMilliseconds < 300) {
          final screenWidth = MediaQuery.of(context).size.width;
          final tapX = _tapDownPosition!.dx;
          final ratio = tapX / screenWidth;

          // 是否需要点击翻页（滑动/滚动模式由 WebView 处理翻页）
          final needsTapTurn = _needsTapToTurn(settings.pageTurnMode);

          if (needsTapTurn && ratio < 0.25) {
            // 左侧 25%: 上一页（仅在无动画模式）
            _controller.prevPage();
          } else if (needsTapTurn && ratio > 0.75) {
            // 右侧 25%: 下一页（仅在无动画模式）
            _controller.nextPage();
          } else if (ratio >= 0.25 && ratio <= 0.75) {
            // 中间 50%: 切换控制栏
            _toggleControls();
          }
        }
        _tapDownPosition = null;
        _tapDownTime = null;
      },
      onPointerCancel: (event) {
        _tapDownPosition = null;
        _tapDownTime = null;
      },
      child: Container(color: Colors.transparent),
    );

  // 点击检测相关变量
  Offset? _tapDownPosition;
  DateTime? _tapDownTime;

  Widget _buildTopBar(BookReaderSettings settings) {
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              (isDark ? Colors.black : Colors.white).withValues(alpha: 0.9),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  _bookInfo?.title ?? widget.book.name,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 占位，保持标题居中
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BookReaderSettings settings) {
    final progress = _currentLocation?.fraction ?? 0.0;
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              (isDark ? Colors.black : Colors.white).withValues(alpha: 0.9),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度信息
              if (settings.showProgress)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(progress * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${_currentLocation?.sectionIndex ?? 0}/${_currentLocation?.totalSections ?? 0}',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

              // 进度条
              Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: _controller.goToFraction,
                activeColor: isDark ? Colors.white : Colors.black87,
                inactiveColor: isDark ? Colors.white30 : Colors.black26,
              ),

              // 控制按钮
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _BottomBarButton(
                      icon: Icons.menu_book,
                      label: '目录',
                      isDark: isDark,
                      onPressed: () {
                        setState(() {
                          _showToc = !_showToc;
                        });
                      },
                    ),
                    _BottomBarButton(
                      icon: isDark ? Icons.light_mode : Icons.dark_mode,
                      label: isDark ? '日间' : '夜间',
                      isDark: isDark,
                      onPressed: () {
                        final notifier = ref.read(bookReaderSettingsProvider.notifier);
                        final newTheme = isDark
                            ? BookReaderTheme.light
                            : BookReaderTheme.dark;
                        notifier.setTheme(newTheme);
                        _applySettings(settings.copyWith(theme: newTheme));
                      },
                    ),
                    _BottomBarButton(
                      icon: Icons.settings,
                      label: '设置',
                      isDark: isDark,
                      onPressed: _showSettingsSheet,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTocDrawer(BookReaderSettings settings) {
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;

    return Positioned(
      top: 0,
      bottom: 0,
      left: 0,
      width: MediaQuery.of(context).size.width * 0.75,
      child: GestureDetector(
        onTap: () {}, // 阻止点击穿透
        child: Material(
          color: isDark ? Colors.grey[900] : Colors.white,
          elevation: 8,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.menu_book,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      const SizedBox(width: 8),
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
                        onPressed: () {
                          setState(() {
                            _showToc = false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _tocItems.isEmpty
                      ? Center(
                          child: Text(
                            '暂无目录',
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _flattenedTocItems.length,
                          itemBuilder: (context, index) {
                            final (item, depth) = _flattenedTocItems[index];
                            return ListTile(
                              contentPadding: EdgeInsets.only(
                                left: 16.0 + depth * 16.0, // 根据层级缩进
                                right: 16.0,
                              ),
                              title: Text(
                                item.label,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: depth > 0 ? 14 : 16, // 子目录字体稍小
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                if (item.href.isNotEmpty) {
                                  // 使用 goToHref 而不是 goToCfi
                                  _controller.goToHref(item.href);
                                }
                                setState(() {
                                  _showToc = false;
                                  _showControls = false;
                                });
                              },
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
}

/// 底部栏按钮
class _BottomBarButton extends StatelessWidget {
  const _BottomBarButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = isDark ? Colors.white : Colors.black87;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
