import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foliate_viewer/flutter_foliate_viewer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_file_cache_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
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

  Widget _buildSettingsContent(BookReaderSettings settings) {
    final settingsNotifier = ref.read(bookReaderSettingsProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主题选择
          Text('主题', style: context.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: BookReaderTheme.values.map((theme) => _ThemeButton(
                theme: theme,
                isSelected: settings.theme == theme,
                onTap: () {
                  settingsNotifier.setTheme(theme);
                  _applySettings(settings.copyWith(theme: theme));
                },
              )).toList(),
          ),
          const SizedBox(height: 16),

          // 屏幕常亮
          SwitchListTile(
            title: const Text('屏幕常亮'),
            contentPadding: EdgeInsets.zero,
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

          // 显示进度
          SwitchListTile(
            title: const Text('显示进度'),
            contentPadding: EdgeInsets.zero,
            value: settings.showProgress,
            onChanged: (value) => settingsNotifier.setShowProgress(value: value),
          ),

          const Divider(),

          // 字体大小
          _buildFontSizeSlider(settings, settingsNotifier),

          const SizedBox(height: 16),

          // 行高
          _buildLineHeightSlider(settings, settingsNotifier),

          const SizedBox(height: 16),

          // 段落间距
          _buildParagraphSpacingSlider(settings, settingsNotifier),

          const Divider(),

          // 翻页模式
          Text('翻页模式', style: context.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _PageTurnButton(
                label: '滑动',
                isSelected: settings.pageTurnMode == BookPageTurnMode.slide,
                onTap: () {
                  settingsNotifier.setPageTurnMode(BookPageTurnMode.slide);
                  _controller.setPageTurnStyle(FoliatePageTurnStyle.slide);
                },
              ),
              _PageTurnButton(
                label: '滚动',
                isSelected: settings.pageTurnMode == BookPageTurnMode.scroll,
                onTap: () {
                  settingsNotifier.setPageTurnMode(BookPageTurnMode.scroll);
                  _controller.setPageTurnStyle(FoliatePageTurnStyle.scroll);
                },
              ),
              _PageTurnButton(
                label: '无动画',
                isSelected: settings.pageTurnMode == BookPageTurnMode.none,
                onTap: () {
                  settingsNotifier.setPageTurnMode(BookPageTurnMode.none);
                  _controller.setPageTurnStyle(FoliatePageTurnStyle.noAnimation);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFontSizeSlider(
    BookReaderSettings settings,
    BookReaderSettingsNotifier settingsNotifier,
  ) {
    final currentSize = settings.fontSize.clamp(12.0, 30.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('字体大小', style: context.textTheme.titleSmall),
            Text('${currentSize.toInt()}'),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.text_decrease),
              onPressed: currentSize > 12
                  ? () {
                      final newSize = (currentSize - 1).clamp(12.0, 30.0);
                      settingsNotifier.setFontSize(newSize);
                      _controller.setFontSize(newSize / 18.0);
                    }
                  : null,
            ),
            Expanded(
              child: Slider(
                value: currentSize,
                min: 12,
                max: 30,
                divisions: 18,
                onChanged: (value) {
                  settingsNotifier.setFontSize(value);
                  _controller.setFontSize(value / 18.0);
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.text_increase),
              onPressed: currentSize < 30
                  ? () {
                      final newSize = (currentSize + 1).clamp(12.0, 30.0);
                      settingsNotifier.setFontSize(newSize);
                      _controller.setFontSize(newSize / 18.0);
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLineHeightSlider(
    BookReaderSettings settings,
    BookReaderSettingsNotifier settingsNotifier,
  ) {
    final currentHeight = settings.lineHeight.clamp(1.0, 3.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('行高', style: context.textTheme.titleSmall),
            Text(currentHeight.toStringAsFixed(1)),
          ],
        ),
        Slider(
          value: currentHeight,
          min: 1.0,
          max: 3.0,
          divisions: 20,
          onChanged: (value) {
            settingsNotifier.setLineHeight(value);
            _controller.setLineHeight(value);
          },
        ),
      ],
    );
  }

  Widget _buildParagraphSpacingSlider(
    BookReaderSettings settings,
    BookReaderSettingsNotifier settingsNotifier,
  ) {
    final currentSpacing = settings.paragraphSpacing.clamp(0.0, 3.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('段落间距', style: context.textTheme.titleSmall),
            Text(currentSpacing.toStringAsFixed(1)),
          ],
        ),
        Slider(
          value: currentSpacing,
          min: 0.0,
          max: 3.0,
          divisions: 30,
          onChanged: (value) {
            settingsNotifier.setParagraphSpacing(value);
            // 段落间距需要通过完整样式更新
            final newSettings = settings.copyWith(paragraphSpacing: value);
            _applySettings(newSettings);
          },
        ),
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

    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        children: [
          // 阅读器
          FoliateViewer(
            controller: _controller,
            bookSource: FileBookSource(File(filePath)),
            initialCfi: _initialCfi,
            style: style,
            onBookLoaded: (info) async {
              setState(() {
                _bookInfo = info;
              });
              // 加载目录
              final toc = await _controller.getToc();
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

          // 顶部控制栏
          if (_showControls) _buildTopBar(settings),

          // 底部控制栏
          if (_showControls) _buildBottomBar(settings),

          // 目录抽屉
          if (_showToc) _buildTocDrawer(settings),
        ],
      ),
    );
  }

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
              IconButton(
                icon: Icon(
                  Icons.menu_book,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: () {
                  setState(() {
                    _showToc = !_showToc;
                  });
                },
              ),
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
                      icon: Icons.skip_previous,
                      label: '上一页',
                      isDark: isDark,
                      onPressed: _controller.prevPage,
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
                    _BottomBarButton(
                      icon: Icons.skip_next,
                      label: '下一页',
                      isDark: isDark,
                      onPressed: _controller.nextPage,
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
                          itemCount: _tocItems.length,
                          itemBuilder: (context, index) {
                            final item = _tocItems[index];
                            return ListTile(
                              title: Text(
                                item.label,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                if (item.href.isNotEmpty) {
                                  _controller.goToCfi(item.href);
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

/// 主题选择按钮
class _ThemeButton extends StatelessWidget {
  const _ThemeButton({
    required this.theme,
    required this.isSelected,
    required this.onTap,
  });

  final BookReaderTheme theme;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: theme.backgroundColor,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            theme.label.substring(0, 1),
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
}

/// 翻页模式按钮
class _PageTurnButton extends StatelessWidget {
  const _PageTurnButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
    );
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
