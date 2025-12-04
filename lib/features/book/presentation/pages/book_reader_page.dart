import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/network/http_client.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';
import 'package:path_provider/path_provider.dart';

/// 阅读器状态
final bookReaderProvider =
    StateNotifierProvider.family<BookReaderNotifier, BookReaderState, BookItem>(
      (ref, book) => BookReaderNotifier(book),
    );

sealed class BookReaderState {}

class BookReaderLoading extends BookReaderState {}

class BookReaderLoaded extends BookReaderState {
  BookReaderLoaded({
    required this.content,
    this.currentPage = 0,
    this.totalPages = 1,
    this.fontSize = 18.0,
    this.lineHeight = 1.6,
    this.backgroundColor = Colors.white,
    this.textColor = Colors.black87,
  });

  final String content;
  final int currentPage;
  final int totalPages;
  final double fontSize;
  final double lineHeight;
  final Color backgroundColor;
  final Color textColor;

  BookReaderLoaded copyWith({
    String? content,
    int? currentPage,
    int? totalPages,
    double? fontSize,
    double? lineHeight,
    Color? backgroundColor,
    Color? textColor,
  }) => BookReaderLoaded(
    content: content ?? this.content,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    textColor: textColor ?? this.textColor,
  );
}

class BookReaderError extends BookReaderState {
  BookReaderError(this.message);

  final String message;
}

class BookReaderNotifier extends StateNotifier<BookReaderState> {
  BookReaderNotifier(this.book) : super(BookReaderLoading()) {
    loadBook();
  }

  final BookItem book;

  Future<void> loadBook() async {
    state = BookReaderLoading();

    try {
      String content;

      switch (book.format) {
        case BookFormat.txt:
          content = await _loadTxtBook();
        case BookFormat.epub:
          content = await _loadEpubBook();
        case BookFormat.pdf:
          state = BookReaderError('PDF 阅读器正在开发中\n请使用系统应用打开');
          return;
        default:
          state = BookReaderError('暂不支持该格式');
          return;
      }

      state = BookReaderLoaded(content: content);
    } on Exception catch (e) {
      state = BookReaderError(e.toString());
    }
  }

  Future<String> _loadTxtBook() async {
    final uri = Uri.parse(book.url);
    List<int> bytes;

    // 检查是否为本地文件 (file:// 协议)
    if (uri.scheme == 'file') {
      final localFile = File(uri.toFilePath());
      if (!await localFile.exists()) {
        throw Exception('文件不存在');
      }
      bytes = await localFile.readAsBytes();
    } else {
      // 远程文件，使用 HTTP 下载
      final response = await InsecureHttpClient.get(uri);
      if (response.statusCode != 200) {
        throw Exception('加载失败: ${response.statusCode}');
      }
      bytes = response.bodyBytes;
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

  String _decodeGbk(List<int> bytes) {
    // 简单的回退处理，实际项目中可能需要 charset_converter 包
    return String.fromCharCodes(bytes);
  }

  Future<String> _loadEpubBook() async {
    final uri = Uri.parse(book.url);
    final tempDir = await getTemporaryDirectory();
    final epubFile = File('${tempDir.path}/${book.name}');

    // 检查是否为本地文件 (file:// 协议)
    if (uri.scheme == 'file') {
      final localFile = File(uri.toFilePath());
      if (!await localFile.exists()) {
        throw Exception('文件不存在');
      }
      // 复制到临时目录
      await localFile.copy(epubFile.path);
    } else {
      // 远程文件，使用 HTTP 下载
      final response = await InsecureHttpClient.get(uri);
      if (response.statusCode != 200) {
        throw Exception('下载失败: ${response.statusCode}');
      }
      await epubFile.writeAsBytes(response.bodyBytes);
    }

    // TODO: 使用 epubx 或 epub_view 解析 EPUB
    // 暂时返回提示信息
    return '《${book.displayName}》\n\nEPUB 完整阅读器正在开发中...\n\n'
        '文件已下载: ${epubFile.path}\n\n'
        '提示: 您可以使用系统应用打开此文件进行阅读。';
  }

  void setFontSize(double size) {
    final current = state;
    if (current is BookReaderLoaded) {
      state = current.copyWith(fontSize: size.clamp(12.0, 32.0));
    }
  }

  void setLineHeight(double height) {
    final current = state;
    if (current is BookReaderLoaded) {
      state = current.copyWith(lineHeight: height.clamp(1.2, 2.5));
    }
  }

  void setTheme({Color? backgroundColor, Color? textColor}) {
    final current = state;
    if (current is BookReaderLoaded) {
      state = current.copyWith(
        backgroundColor: backgroundColor,
        textColor: textColor,
      );
    }
  }

  void setPage(int page) {
    final current = state;
    if (current is BookReaderLoaded) {
      state = current.copyWith(
        currentPage: page.clamp(0, current.totalPages - 1),
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
  bool _showControls = true;
  bool _showSettings = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 隐藏系统 UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // 恢复系统 UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookReaderProvider(widget.book));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
      body: switch (state) {
        BookReaderLoading() => const LoadingWidget(message: '加载中...'),
        BookReaderError(:final message) => AppErrorWidget(
          message: message,
          onRetry: () =>
              ref.read(bookReaderProvider(widget.book).notifier).loadBook(),
        ),
        BookReaderLoaded() => _buildReader(context, state, isDark),
      },
    );
  }

  Widget _buildReader(
    BuildContext context,
    BookReaderLoaded state,
    bool isDark,
  ) => Stack(
      children: [
        // 阅读内容
        GestureDetector(
          onTap: () => setState(() => _showControls = !_showControls),
          child: Container(
            color: state.backgroundColor,
            child: SafeArea(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  state.content,
                  style: TextStyle(
                    fontSize: state.fontSize,
                    height: state.lineHeight,
                    color: state.textColor,
                  ),
                ),
              ),
            ),
          ),
        ),

        // 顶部控制栏
        if (_showControls)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(context, isDark),
          ),

        // 底部控制栏
        if (_showControls)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(context, state, isDark),
          ),

        // 设置面板
        if (_showSettings)
          Positioned(
            bottom: 80,
            left: 16,
            right: 16,
            child: _buildSettingsPanel(context, state, isDark),
          ),
      ],
    );

  Widget _buildTopBar(BuildContext context, bool isDark) => Container(
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
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                  size: 32,
                ),
                tooltip: '返回',
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '阅读中',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      widget.book.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(
                  Icons.bookmark_border_rounded,
                  color: Colors.white,
                ),
                tooltip: '书签',
              ),
            ],
          ),
        ),
      ),
    );

  Widget _buildBottomBar(
    BuildContext context,
    BookReaderLoaded state,
    bool isDark,
  ) {
    return Container(
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
                onPressed: () => ref
                    .read(bookReaderProvider(widget.book).notifier)
                    .setFontSize(state.fontSize - 2),
                icon: const Icon(
                  Icons.text_decrease_rounded,
                  color: Colors.white,
                ),
                tooltip: '缩小字体',
              ),
              IconButton(
                onPressed: () => ref
                    .read(bookReaderProvider(widget.book).notifier)
                    .setFontSize(state.fontSize + 2),
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
    BookReaderLoaded state,
    bool isDark,
  ) => Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '阅读设置',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : null,
            ),
          ),
          const SizedBox(height: 20),

          // 字体大小
          _buildSettingRow(
            context,
            label: '字体大小',
            value: '${state.fontSize.toInt()}',
            isDark: isDark,
            child: Slider(
              value: state.fontSize,
              min: 12,
              max: 32,
              divisions: 10,
              onChanged: (value) => ref
                  .read(bookReaderProvider(widget.book).notifier)
                  .setFontSize(value),
            ),
          ),

          const SizedBox(height: 16),

          // 行高
          _buildSettingRow(
            context,
            label: '行高',
            value: state.lineHeight.toStringAsFixed(1),
            isDark: isDark,
            child: Slider(
              value: state.lineHeight,
              min: 1.2,
              max: 2.5,
              divisions: 13,
              onChanged: (value) => ref
                  .read(bookReaderProvider(widget.book).notifier)
                  .setLineHeight(value),
            ),
          ),

          const SizedBox(height: 16),

          // 主题
          Text(
            '阅读主题',
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : null,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildThemeOption(
                color: Colors.white,
                textColor: Colors.black87,
                label: '白色',
                isSelected: state.backgroundColor == Colors.white,
                onTap: () => ref
                    .read(bookReaderProvider(widget.book).notifier)
                    .setTheme(
                      backgroundColor: Colors.white,
                      textColor: Colors.black87,
                    ),
              ),
              const SizedBox(width: 12),
              _buildThemeOption(
                color: const Color(0xFFF5F5DC),
                textColor: const Color(0xFF5D4E37),
                label: '护眼',
                isSelected: state.backgroundColor == const Color(0xFFF5F5DC),
                onTap: () => ref
                    .read(bookReaderProvider(widget.book).notifier)
                    .setTheme(
                      backgroundColor: const Color(0xFFF5F5DC),
                      textColor: const Color(0xFF5D4E37),
                    ),
              ),
              const SizedBox(width: 12),
              _buildThemeOption(
                color: const Color(0xFF1A1A1A),
                textColor: const Color(0xFFCCCCCC),
                label: '夜间',
                isSelected: state.backgroundColor == const Color(0xFF1A1A1A),
                onTap: () => ref
                    .read(bookReaderProvider(widget.book).notifier)
                    .setTheme(
                      backgroundColor: const Color(0xFF1A1A1A),
                      textColor: const Color(0xFFCCCCCC),
                    ),
              ),
            ],
          ),
        ],
      ),
    );

  Widget _buildSettingRow(
    BuildContext context, {
    required String label,
    required String value,
    required bool isDark,
    required Widget child,
  }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : null,
              ),
            ),
            Text(
              value,
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : null,
              ),
            ),
          ],
        ),
        child,
      ],
    );

  Widget _buildThemeOption({
    required Color color,
    required Color textColor,
    required String label,
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
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.primary : Colors.grey.shade300,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: Center(
              child: Text(
                'Aa',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? AppColors.primary : null,
            ),
          ),
        ],
      ),
    );
}
