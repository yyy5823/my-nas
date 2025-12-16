import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/network/http_client.dart';
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

/// EPUB 阅读器参数（包含原始书籍路径用于进度追踪）
class EpubReaderParams {
  const EpubReaderParams({
    required this.book,
    this.originalBookPath,
    this.originalSourceId,
  });

  final BookItem book;
  /// 原始书籍路径（用于 MOBI/AZW3 转换后保持进度关联）
  final String? originalBookPath;
  /// 原始 sourceId（用于 MOBI/AZW3 转换后保持进度关联）
  final String? originalSourceId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EpubReaderParams &&
          runtimeType == other.runtimeType &&
          book.id == other.book.id &&
          book.path == other.book.path &&
          originalBookPath == other.originalBookPath &&
          originalSourceId == other.originalSourceId;

  @override
  int get hashCode =>
      book.id.hashCode ^
      book.path.hashCode ^
      originalBookPath.hashCode ^
      originalSourceId.hashCode;
}

/// EPUB 阅读器状态
final epubReaderProvider =
    StateNotifierProvider.family<EpubReaderNotifier, EpubReaderState, EpubReaderParams>(
      (ref, params) => EpubReaderNotifier(params, ref),
    );

sealed class EpubReaderState {}

class EpubReaderLoading extends EpubReaderState {
  EpubReaderLoading({this.message = '加载中...'});

  final String message;
}

class EpubReaderLoaded extends EpubReaderState {
  EpubReaderLoaded({
    required this.filePath,
    this.initialCfi,
    this.chapters = const [],
  });

  final String filePath;
  final String? initialCfi;
  final List<EpubChapter> chapters;

  EpubReaderLoaded copyWith({
    String? filePath,
    String? initialCfi,
    List<EpubChapter>? chapters,
  }) => EpubReaderLoaded(
    filePath: filePath ?? this.filePath,
    initialCfi: initialCfi ?? this.initialCfi,
    chapters: chapters ?? this.chapters,
  );
}

class EpubReaderError extends EpubReaderState {
  EpubReaderError(this.message);

  final String message;
}

class EpubReaderNotifier extends StateNotifier<EpubReaderState> {
  EpubReaderNotifier(this._params, this._ref) : super(EpubReaderLoading()) {
    _loadEpub();
  }

  final EpubReaderParams _params;
  final Ref _ref;
  final ReadingProgressService _progressService = ReadingProgressService();
  final BookFileCacheService _cacheService = BookFileCacheService();

  /// 获取当前书籍
  BookItem get book => _params.book;

  /// 获取用于进度追踪的路径（优先使用原始路径）
  String get _progressPath => _params.originalBookPath ?? book.path;

  /// 获取用于进度追踪的 sourceId（优先使用原始 sourceId）
  String get _progressSourceId => _params.originalSourceId ?? book.sourceId ?? 'local';

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

      // 初始化缓存服务
      await _cacheService.init();

      // 检查是否有缓存
      final cachedFile = await _cacheService.getCachedFile(
        book.sourceId,
        book.path,
      );

      File epubFile;
      if (cachedFile != null) {
        state = EpubReaderLoading(message: '使用缓存...');
        epubFile = cachedFile;
        logger.i('EPUB 使用缓存: ${cachedFile.path}');
      } else {
        // 需要下载文件
        final uri = Uri.parse(book.url);
        Uint8List bytes;

        final fileSystem = _getFileSystem();
        if (fileSystem != null) {
          state = EpubReaderLoading(message: '加载文件中...');
          final stream = await fileSystem.getFileStream(book.path);
          bytes = await _readStreamBytes(stream);
        } else if (uri.scheme == 'file') {
          state = EpubReaderLoading(message: '读取本地文件...');
          final localFile = File(uri.toFilePath());
          if (!await localFile.exists()) {
            state = EpubReaderError('文件不存在');
            return;
          }
          bytes = await localFile.readAsBytes();
        } else if (uri.scheme == 'http' || uri.scheme == 'https') {
          state = EpubReaderLoading(message: '下载中...');
          final response = await InsecureHttpClient.get(uri);
          if (response.statusCode != 200) {
            state = EpubReaderError('下载失败: ${response.statusCode}');
            return;
          }
          bytes = response.bodyBytes;
        } else {
          state = EpubReaderError('不支持的协议: ${uri.scheme}');
          return;
        }

        // 保存到缓存
        state = EpubReaderLoading(message: '缓存文件...');
        final savedFile = await _cacheService.saveToCache(
          book.sourceId,
          book.path,
          bytes,
        );
        if (savedFile == null) {
          state = EpubReaderError('缓存文件失败');
          return;
        }
        epubFile = savedFile;
      }

      // 恢复阅读进度（使用 CFI）
      // 注意：使用原始路径生成 itemId 以保持 MOBI/AZW3 转换后的进度关联
      await _progressService.init();
      final itemId = _progressService.generateItemId(_progressSourceId, _progressPath);
      final progress = _progressService.getProgress(itemId);
      final initialCfi = progress?.cfi;

      state = EpubReaderLoaded(
        filePath: epubFile.path,
        initialCfi: initialCfi,
      );

      logger.i('EPUB 加载完成: ${book.name}');
    } on Exception catch (e, stackTrace) {
      logger.e('加载 EPUB 失败', e, stackTrace);
      state = EpubReaderError('加载失败: $e');
    }
  }

  /// 更新章节列表
  void updateChapters(List<EpubChapter> chapters) {
    final current = state;
    if (current is EpubReaderLoaded) {
      state = current.copyWith(chapters: chapters);
    }
  }

  /// 保存阅读进度（使用 CFI）
  /// 注意：使用原始路径生成 itemId 以保持 MOBI/AZW3 转换后的进度关联
  Future<void> saveProgress(EpubLocation location) async {
    final itemId = _progressService.generateItemId(_progressSourceId, _progressPath);
    await _progressService.saveProgress(
      ReadingProgress(
        itemId: itemId,
        itemType: 'epub',
        position: location.progress,
        totalPositions: 1,
        lastReadAt: DateTime.now(),
        cfi: location.startCfi,
      ),
    );
  }
}

class EpubReaderPage extends ConsumerStatefulWidget {
  const EpubReaderPage({
    required this.book,
    this.originalBookPath,
    this.originalSourceId,
    super.key,
  });

  final BookItem book;

  /// 原始书籍路径（用于 MOBI/AZW3 转换后保持进度关联）
  final String? originalBookPath;

  /// 原始 sourceId（用于 MOBI/AZW3 转换后保持进度关联）
  final String? originalSourceId;

  @override
  ConsumerState<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends ConsumerState<EpubReaderPage> {
  final EpubController _epubController = EpubController();
  bool _showControls = false;
  bool _showToc = false;
  List<EpubChapter> _chapters = [];
  double _progress = 0;
  String _currentChapterTitle = '';
  bool _isEpubReady = false; // 标记 EPUB 是否已完全加载

  /// 阅读器参数（包含原始书籍路径用于进度追踪）
  /// 使用 late final 避免每次 build 重建
  late final EpubReaderParams _readerParams = EpubReaderParams(
    book: widget.book,
    originalBookPath: widget.originalBookPath,
    originalSourceId: widget.originalSourceId,
  );

  // 触摸检测：区分点击和滑动
  Offset? _touchDownPosition;
  // 点击阈值：屏幕宽度的 5%（规范化坐标 0-1）
  static const double _tapThreshold = 0.05;

  // 状态栏相关
  final Battery _battery = Battery();
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.unknown;
  String _currentTime = '';
  Timer? _timeTimer;

  // 进度保存防抖
  Timer? _saveProgressTimer;
  EpubLocation? _pendingLocation;
  static const _saveProgressDebounce = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWakelock();
    _initStatusBar();
  }

  Future<void> _initWakelock() async {
    await WakelockPlus.enable();
  }

  /// 初始化状态栏（电池和时间）
  Future<void> _initStatusBar() async {
    // 初始化时间
    _updateTime();
    // 每分钟更新一次时间
    _timeTimer = Timer.periodic(const Duration(minutes: 1), (_) => _updateTime());

    // 初始化电池信息
    try {
      _batteryLevel = await _battery.batteryLevel;
      _batteryState = await _battery.batteryState;
      if (mounted) setState(() {});

      // 监听电池状态变化
      _battery.onBatteryStateChanged.listen((state) {
        if (mounted) {
          setState(() => _batteryState = state);
          _battery.batteryLevel.then((level) {
            if (mounted) setState(() => _batteryLevel = level);
          });
        }
      });
    } on Exception catch (e, st) {
      // 某些平台可能不支持电池API
      logger.w('无法获取电池信息: $e $st');
    }
  }

  void _updateTime() {
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('HH:mm').format(DateTime.now());
      });
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
    _timeTimer?.cancel();
    super.dispose();
  }

  /// 防抖保存进度（800ms 内的多次变化只保存最后一次）
  void _saveProgressDebounced(EpubLocation location) {
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
  void _saveProgressImmediately(EpubLocation location) {
    ref.read(epubReaderProvider(_readerParams).notifier).saveProgress(location);
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) {
        _showToc = false;
      }
    });
  }

  /// 处理点击区域（使用规范化坐标 0-1）
  /// 左侧 25%: 上一页
  /// 右侧 25%: 下一页
  /// 中间 50%: 切换控制栏
  /// 与其他格式（TXT/MOBI/AZW3）保持一致
  void _handleTapZone(Offset normalizedPosition) {
    // 如果控制栏正在显示，先隐藏控制栏，本次点击不执行翻页
    if (_showControls) {
      setState(() {
        _showControls = false;
        _showToc = false;
      });
      return;
    }

    // 如果 EPUB 还没准备好，只允许切换控制栏
    if (!_isEpubReady) {
      _toggleControls();
      return;
    }

    final tapX = normalizedPosition.dx;

    try {
      if (tapX < 0.25) {
        // 左侧 25% 区域 - 上一页
        _epubController.prev();
      } else if (tapX > 0.75) {
        // 右侧 25% 区域 - 下一页
        _epubController.next();
      } else {
        // 中间 50% 区域 - 切换控制栏
        _toggleControls();
      }
    } on Exception catch (e) {
      logger.w('EPUB 翻页操作失败', e);
    }
  }

  /// 安全的跳转到第一页操作
  void _safeFirst() {
    try {
      _epubController.moveToFistPage();
    } on Exception catch (e) {
      logger.w('EPUB 跳转第一页操作失败', e);
    }
  }

  /// 安全的跳转到最后一页操作
  void _safeLast() {
    try {
      _epubController.moveToLastPage();
    } on Exception catch (e) {
      logger.w('EPUB 跳转最后一页操作失败', e);
    }
  }

  /// 安全的进度跳转操作
  void _safeProgressChange(double progress) {
    try {
      _epubController.toProgressPercentage(progress);
    } on Exception catch (e) {
      logger.w('EPUB 进度跳转操作失败', e);
    }
  }

  /// 显示设置面板
  void _showSettingsSheet() {
    showReaderSettingsSheet(
      context,
      title: 'EPUB 设置',
      icon: Icons.menu_book_rounded,
      iconColor: AppColors.info,
      contentBuilder: (context) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(bookReaderSettingsProvider);
          return _buildSettingsContent(settings);
        },
      ),
    );
  }

  /// 构建设置内容 - 与其他格式对齐
  Widget _buildSettingsContent(BookReaderSettings settings) {
    final settingsNotifier = ref.read(bookReaderSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          title: '显示进度',
          value: settings.showProgress,
          onChanged: (value) => settingsNotifier.setShowProgress(value: value),
        ),
        const SizedBox(height: 24),

        // 字体大小
        const SettingSectionTitle(title: '字体大小'),
        _buildFontSizeSlider(settings, settingsNotifier),
      ],
    );
  }

  /// 构建字体大小滑块
  Widget _buildFontSizeSlider(
    BookReaderSettings settings,
    BookReaderSettingsNotifier settingsNotifier,
  ) {
    // EPUB 使用独立的字体大小设置
    // 范围：80% - 200%（相当于 12-30 的比例）
    final currentSize = settings.fontSize.clamp(12.0, 30.0);
    final percentage = ((currentSize / 15.0) * 100).round();

    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.text_fields, size: 16),
            const SizedBox(width: 8),
            Text(
              '$percentage%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: currentSize > 12
                  ? () {
                      final newSize = (currentSize - 2).clamp(12.0, 30.0);
                      settingsNotifier.setFontSize(newSize);
                      _epubController.setFontSize(fontSize: newSize);
                    }
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: currentSize < 30
                  ? () {
                      final newSize = (currentSize + 2).clamp(12.0, 30.0);
                      settingsNotifier.setFontSize(newSize);
                      _epubController.setFontSize(fontSize: newSize);
                    }
                  : null,
            ),
          ],
        ),
        Slider(
          value: currentSize,
          min: 12,
          max: 30,
          divisions: 9,
          label: '$percentage%',
          onChanged: (value) {
            settingsNotifier.setFontSize(value);
            _epubController.setFontSize(fontSize: value);
          },
        ),
        Text(
          '调整 EPUB 阅读器字体大小',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  /// 构建主题选项
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

  /// 快速切换夜间模式
  void _toggleNightMode() {
    final settings = ref.read(bookReaderSettingsProvider);
    final currentTheme = settings.theme;

    // 在浅色和深色主题之间切换
    final newTheme = currentTheme == BookReaderTheme.light ||
            currentTheme == BookReaderTheme.sepia ||
            currentTheme == BookReaderTheme.green
        ? BookReaderTheme.dark
        : BookReaderTheme.light;

    ref.read(bookReaderSettingsProvider.notifier).setTheme(newTheme);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(epubReaderProvider(_readerParams));

    return Scaffold(
      backgroundColor: Colors.white,
      body: switch (state) {
        EpubReaderLoading(:final message) => LoadingWidget(message: message),
        EpubReaderError(:final message) => _buildError(message),
        EpubReaderLoaded() => _buildReader(context, state),
      },
    );
  }

  /// 将 BookReaderTheme 转换为 EpubTheme
  EpubTheme _getEpubTheme(BookReaderTheme theme) {
    // 根据背景色判断主题类型
    final brightness = ThemeData.estimateBrightnessForColor(theme.backgroundColor);
    if (brightness == Brightness.dark) {
      return EpubTheme.custom(
        backgroundDecoration: BoxDecoration(color: theme.backgroundColor),
        foregroundColor: theme.textColor,
      );
    } else {
      return EpubTheme.custom(
        backgroundDecoration: BoxDecoration(color: theme.backgroundColor),
        foregroundColor: theme.textColor,
      );
    }
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

  Widget _buildReader(BuildContext context, EpubReaderLoaded state) => Stack(
    children: [
      // EPUB 阅读器（带固定顶栏和底部状态栏）
      Column(
        children: [
          // 固定顶栏 - 避免摄像头遮挡内容
          _buildFixedHeader(),
          Expanded(
            // 注：已在 forked flutter_epub_viewer 中移除 VerticalDragGestureRecognizer
            child: EpubViewer(
              epubSource: EpubSource.fromFile(File(state.filePath)),
              epubController: _epubController,
              initialCfi: state.initialCfi,
              displaySettings: EpubDisplaySettings(
                allowScriptedContent: true,
                flow: EpubFlow.paginated, // 强制水平分页，禁止垂直滚动
                snap: true, // 页面对齐，防止中间停顿
                fontSize: ref.watch(bookReaderSettingsProvider).fontSize.toInt(),
                theme: _getEpubTheme(ref.watch(bookReaderSettingsProvider).theme),
              ),
              onChaptersLoaded: (chapters) {
                setState(() {
                  _chapters = chapters;
                });
                ref
                    .read(epubReaderProvider(_readerParams).notifier)
                    .updateChapters(chapters);
              },
              onEpubLoaded: () {
                logger.i('EPUB 渲染完成');
                setState(() {
                  _isEpubReady = true;
                });
              },
              onRelocated: (location) {
                setState(() {
                  _progress = location.progress;
                  // 更新当前章节标题
                  _updateCurrentChapter(location);
                });
                // 保存阅读进度（防抖）
                _saveProgressDebounced(location);
              },
              // 使用原生触摸事件处理，区分点击和滑动
              onTouchDown: (x, y) {
                _touchDownPosition = Offset(x, y);
              },
              onTouchUp: (x, y) {
                final upPosition = Offset(x, y);
                // 只有触摸移动距离小于阈值才视为点击
                if (_touchDownPosition != null) {
                  final distance = (upPosition - _touchDownPosition!).distance;
                  if (distance < _tapThreshold) {
                    _handleTapZone(upPosition);
                  }
                }
                _touchDownPosition = null;
              },
            ),
          ),
          // 底部状态栏（进度、电池、时间）
          _buildBottomStatusBar(),
        ],
      ),

      // 顶部控制栏
      if (_showControls)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTopBar(context),
        ),

      // 底部控制栏
      if (_showControls)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomBar(context),
        ),

      // 目录抽屉
      if (_showToc) _buildTocDrawer(context),
    ],
  );

  /// 根据位置更新当前章节标题
  void _updateCurrentChapter(EpubLocation location) {
    // 尝试从章节列表中找到当前章节
    if (_chapters.isEmpty) return;

    // EpubLocation 包含 startCfi，我们可以通过它来匹配章节
    // 简单策略：通过进度估算当前章节
    final estimatedChapterIndex = (_progress * _chapters.length).floor();
    if (estimatedChapterIndex >= 0 && estimatedChapterIndex < _chapters.length) {
      final chapter = _chapters[estimatedChapterIndex];
      if (chapter.title != _currentChapterTitle) {
        _currentChapterTitle = chapter.title;
      }
    }
  }

  /// 构建底部状态栏（进度、电池、时间）
  Widget _buildBottomStatusBar() {
    final textStyle = TextStyle(
      color: Colors.grey.shade600,
      fontSize: 11,
    );

    return Container(
      padding: const EdgeInsets.only(top: 4, bottom: 10, left: 16, right: 16),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // 进度
            Text(
              '${(_progress * 100).toStringAsFixed(1)}%',
              style: textStyle,
            ),
            const Spacer(),
            // 电池图标和电量
            _buildBatteryIndicator(),
            const SizedBox(width: 8),
            // 时间
            Text(_currentTime, style: textStyle),
          ],
        ),
      ),
    );
  }

  /// 构建电池指示器
  Widget _buildBatteryIndicator() {
    final color = Colors.grey.shade600;
    final isCharging = _batteryState == BatteryState.charging;

    // 根据电量选择图标
    IconData batteryIcon;
    if (isCharging) {
      batteryIcon = Icons.battery_charging_full_rounded;
    } else if (_batteryLevel >= 90) {
      batteryIcon = Icons.battery_full_rounded;
    } else if (_batteryLevel >= 70) {
      batteryIcon = Icons.battery_6_bar_rounded;
    } else if (_batteryLevel >= 50) {
      batteryIcon = Icons.battery_5_bar_rounded;
    } else if (_batteryLevel >= 30) {
      batteryIcon = Icons.battery_3_bar_rounded;
    } else if (_batteryLevel >= 15) {
      batteryIcon = Icons.battery_2_bar_rounded;
    } else {
      batteryIcon = Icons.battery_1_bar_rounded;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(batteryIcon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(
          '$_batteryLevel%',
          style: TextStyle(
            color: color,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  /// 构建固定顶栏，显示返回按钮和书名（左对齐）
  Widget _buildFixedHeader() {
    // 显示当前章节标题，如果没有则显示书名
    final displayTitle = _currentChapterTitle.isNotEmpty
        ? _currentChapterTitle
        : widget.book.name;

    return Container(
      padding: const EdgeInsets.only(left: 4, right: 16, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // 返回按钮
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.arrow_back_ios_rounded,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            // 书名（左对齐）
            Expanded(
              child: Text(
                displayTitle,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) => DecoratedBox(
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
                widget.book.name,
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
              icon: const Icon(Icons.list, color: Colors.white),
              onPressed: () => setState(() => _showToc = !_showToc),
              tooltip: '目录',
            ),
          ],
        ),
      ),
    ),
  );

  /// 构建底部操作按钮 - 与其他格式统一
  Widget _buildBottomActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool enabled = true,
  }) {
    final isEnabled = enabled && onPressed != null;
    return InkWell(
      onTap: isEnabled ? onPressed : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isEnabled ? Colors.white : Colors.white38,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isEnabled ? Colors.white : Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final settings = ref.watch(bookReaderSettingsProvider);

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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条
              Row(
                children: [
                  Text(
                    '${(_progress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Expanded(
                    child: Slider(
                      value: _progress.clamp(0.0, 1.0),
                      onChanged: _isEpubReady ? _safeProgressChange : null,
                      activeColor: AppColors.primary,
                      inactiveColor: Colors.white30,
                    ),
                  ),
                  const Text(
                    '100%',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
              // 功能按钮 - 与其他格式统一
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 目录
                  _buildBottomActionButton(
                    icon: Icons.list_rounded,
                    label: '目录',
                    enabled: _chapters.isNotEmpty,
                    onPressed: _chapters.isNotEmpty
                        ? () => setState(() => _showToc = !_showToc)
                        : null,
                  ),
                  // 夜间模式切换
                  _buildBottomActionButton(
                    icon: settings.theme == BookReaderTheme.dark ||
                            settings.theme == BookReaderTheme.black
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    label: settings.theme == BookReaderTheme.dark ||
                            settings.theme == BookReaderTheme.black
                        ? '日间'
                        : '夜间',
                    onPressed: _toggleNightMode,
                  ),
                  // 阅读设置
                  _buildBottomActionButton(
                    icon: Icons.settings_rounded,
                    label: '设置',
                    onPressed: _showSettingsSheet,
                  ),
                  // 书签功能 (TODO: 后续实现)
                  _buildBottomActionButton(
                    icon: Icons.bookmark_outline_rounded,
                    label: '书签',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('书签功能开发中...'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  // 更多菜单
                  _buildBottomActionButton(
                    icon: Icons.more_horiz_rounded,
                    label: '更多',
                    onPressed: () {
                      _showMoreMenu(context);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示更多菜单
  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.first_page_rounded, color: Colors.white),
              title: const Text('跳转到开头', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _safeFirst();
              },
            ),
            ListTile(
              leading: const Icon(Icons.last_page_rounded, color: Colors.white),
              title: const Text('跳转到结尾', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _safeLast();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: Colors.white),
              title: const Text('图书信息', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showBookInfo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded, color: Colors.white),
              title: const Text('刷新内容', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                ref.invalidate(epubReaderProvider(_readerParams));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('正在重新加载...'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 显示图书信息
  void _showBookInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('图书信息', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('书名', widget.book.displayName),
            _buildInfoRow('格式', 'EPUB'),
            _buildInfoRow(
              '大小',
              '${(widget.book.size / 1024 / 1024).toStringAsFixed(2)} MB',
            ),
            if (_chapters.isNotEmpty)
              _buildInfoRow('章节数', '${_chapters.length}'),
            _buildInfoRow('进度', '${(_progress * 100).toStringAsFixed(1)}%'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  /// 构建信息行
  Widget _buildInfoRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

  Widget _buildTocDrawer(BuildContext context) => Positioned(
    top: 0,
    bottom: 0,
    left: 0,
    child: GestureDetector(
      onTap: () {}, // 防止点击穿透
      child: Container(
        width: MediaQuery.of(context).size.width * 0.75,
        color: Colors.white,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      '目录',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _showToc = false),
                    ),
                  ],
                ),
              ),
              // 章节列表
              Expanded(
                child: _chapters.isEmpty
                    ? const Center(child: Text('暂无目录'))
                    : ListView.builder(
                        itemCount: _chapters.length,
                        itemBuilder: (context, index) {
                          final chapter = _chapters[index];
                          return ListTile(
                            title: Text(
                              chapter.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              if (!_isEpubReady) return;
                              try {
                                _epubController.display(cfi: chapter.href);
                                setState(() => _showToc = false);
                              } on Exception catch (e) {
                                logger.w('跳转章节失败: ${chapter.title}', e);
                              }
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
