import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/network/http_client.dart';
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
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
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
  TxtReaderLoaded({required this.content, this.scrollPosition = 0.0});

  final String content;
  final double scrollPosition;

  TxtReaderLoaded copyWith({String? content, double? scrollPosition}) =>
      TxtReaderLoaded(
        content: content ?? this.content,
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
      String content;

      switch (book.format) {
        case BookFormat.txt:
          content = await _loadTxtBook();
        case BookFormat.epub:
          content = await _loadEpubBook();
        case BookFormat.pdf:
          state = TxtReaderError('PDF 阅读器正在开发中\n请使用系统应用打开');
          return;
        case BookFormat.mobi:
        case BookFormat.azw3:
          content = await _loadMobiBook();
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
  Future<String> _loadMobiBook() async {
    final uri = Uri.parse(book.url);
    Uint8List bytes;

    // 优先使用流式加载
    final fileSystem = _getFileSystem();
    if (fileSystem != null) {
      state = TxtReaderLoading(message: '流式加载中...');
      final stream = await fileSystem.getFileStream(book.path);
      bytes = await _readStreamBytes(stream);
    } else if (uri.scheme == 'file') {
      final localFile = File(uri.toFilePath());
      if (!await localFile.exists()) {
        throw Exception('文件不存在');
      }
      bytes = await localFile.readAsBytes();
    } else if (uri.scheme == 'http' || uri.scheme == 'https') {
      final response = await InsecureHttpClient.get(uri);
      if (response.statusCode != 200) {
        throw Exception('加载失败: ${response.statusCode}');
      }
      bytes = response.bodyBytes;
    } else {
      throw Exception('不支持的协议: ${uri.scheme}');
    }

    // 使用 MOBI 解析器
    final parser = MobiParserService();
    final fileName = path.basename(book.path);
    final result = await parser.parse(bytes, fileName);

    if (!result.success) {
      throw Exception(result.error ?? '解析失败');
    }

    return result.content ?? '';
  }

  Future<String> _loadEpubBook() async {
    final uri = Uri.parse(book.url);
    final tempDir = await getTemporaryDirectory();
    final epubFile = File('${tempDir.path}/${book.name}');

    // 优先使用流式加载
    final fileSystem = _getFileSystem();
    if (fileSystem != null) {
      state = TxtReaderLoading(message: '流式加载中...');
      final stream = await fileSystem.getFileStream(book.path);
      final bytes = await _readStreamBytes(stream);
      await epubFile.writeAsBytes(bytes);
    } else if (uri.scheme == 'file') {
      final localFile = File(uri.toFilePath());
      if (!await localFile.exists()) {
        throw Exception('文件不存在');
      }
      await localFile.copy(epubFile.path);
    } else if (uri.scheme == 'http' || uri.scheme == 'https') {
      final response = await InsecureHttpClient.get(uri);
      if (response.statusCode != 200) {
        throw Exception('下载失败: ${response.statusCode}');
      }
      await epubFile.writeAsBytes(response.bodyBytes);
    } else {
      throw Exception('不支持的协议: ${uri.scheme}');
    }

    // TODO: 使用 epubx 或 epub_view 解析 EPUB
    // 暂时返回提示信息
    return '《${book.displayName}》\n\nEPUB 完整阅读器正在开发中...\n\n'
        '文件已下载: ${epubFile.path}\n\n'
        '提示: 您可以使用系统应用打开此文件进行阅读。';
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
  bool _showSettings = false;
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
      if (!_showControls) {
        _showSettings = false;
      }
    });
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

        // 设置面板
        if (_showSettings)
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: _buildSettingsPanel(context, settings),
          ),
      ],
    );
  }

  Widget _buildContent(TxtReaderLoaded state, BookReaderSettings settings) {
    final theme = settings.theme;
    final content = state.content;

    // 处理段落间距
    final paragraphs = content.split('\n\n');
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
                onPressed: () => setState(() => _showSettings = !_showSettings),
                icon: Icon(
                  _showSettings ? Icons.settings : Icons.settings_outlined,
                  color: _showSettings ? Colors.white : Colors.white70,
                ),
                tooltip: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsPanel(
    BuildContext context,
    BookReaderSettings settings,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settingsNotifier = ref.read(bookReaderSettingsProvider.notifier);

    return Container(
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
              subtitle: '左侧上翻，右侧下翻',
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
    );
  }

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
