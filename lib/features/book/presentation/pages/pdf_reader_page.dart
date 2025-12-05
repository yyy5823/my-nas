import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/network/http_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDF 阅读器状态
final pdfReaderProvider =
    StateNotifierProvider.family<PdfReaderNotifier, PdfReaderState, BookItem>(
        (ref, book) => PdfReaderNotifier(book));

sealed class PdfReaderState {}

class PdfReaderLoading extends PdfReaderState {
  PdfReaderLoading({this.message = '加载中...'});
  final String message;
}

class PdfReaderLoaded extends PdfReaderState {
  PdfReaderLoaded({
    required this.filePath,
    required this.document,
    this.currentPage = 1,
    this.totalPages = 0,
    this.isDarkMode = false,
  });

  final String filePath;
  final PdfDocument document;
  final int currentPage;
  final int totalPages;
  final bool isDarkMode;

  PdfReaderLoaded copyWith({
    String? filePath,
    PdfDocument? document,
    int? currentPage,
    int? totalPages,
    bool? isDarkMode,
  }) => PdfReaderLoaded(
      filePath: filePath ?? this.filePath,
      document: document ?? this.document,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      isDarkMode: isDarkMode ?? this.isDarkMode,
    );
}

class PdfReaderError extends PdfReaderState {
  PdfReaderError(this.message);
  final String message;
}

class PdfReaderNotifier extends StateNotifier<PdfReaderState> {
  PdfReaderNotifier(this.book) : super(PdfReaderLoading()) {
    _loadPdf();
  }

  final BookItem book;
  final ReadingProgressService _progressService = ReadingProgressService.instance;

  Future<void> _loadPdf() async {
    try {
      state = PdfReaderLoading();

      final uri = Uri.parse(book.url);
      final tempDir = await getTemporaryDirectory();
      final pdfFile = File('${tempDir.path}/${book.name}');

      // 检查是否为本地文件 (file:// 协议)
      if (uri.scheme == 'file') {
        state = PdfReaderLoading(message: '读取本地文件...');
        final localFile = File(uri.toFilePath());
        if (!await localFile.exists()) {
          state = PdfReaderError('文件不存在');
          return;
        }
        // 复制到临时目录
        await localFile.copy(pdfFile.path);
      } else {
        // 远程文件，使用 HTTP 下载
        state = PdfReaderLoading(message: '下载中...');
        final response = await InsecureHttpClient.get(uri);
        if (response.statusCode != 200) {
          state = PdfReaderError('下载失败: ${response.statusCode}');
          return;
        }
        await pdfFile.writeAsBytes(response.bodyBytes);
      }

      state = PdfReaderLoading(message: '解析中...');

      // 打开 PDF
      final document = await PdfDocument.openFile(pdfFile.path);

      // 恢复阅读进度
      await _progressService.init();
      final itemId = _progressService.generateItemId(book.id, book.path);
      final progress = _progressService.getProgress(itemId);
      final startPage = progress?.position.toInt() ?? 1;

      state = PdfReaderLoaded(
        filePath: pdfFile.path,
        document: document,
        currentPage: startPage.clamp(1, document.pages.length),
        totalPages: document.pages.length,
      );

      logger.i('PDF 加载完成: ${book.name}, ${document.pages.length} 页');
    } on Exception catch (e, stackTrace) {
      logger.e('加载 PDF 失败', e, stackTrace);
      state = PdfReaderError('加载失败: $e');
    }
  }

  void setPage(int page) {
    final current = state;
    if (current is PdfReaderLoaded) {
      final newPage = page.clamp(1, current.totalPages);
      state = current.copyWith(currentPage: newPage);
      _saveProgress(newPage, current.totalPages);
    }
  }

  void toggleDarkMode() {
    final current = state;
    if (current is PdfReaderLoaded) {
      state = current.copyWith(isDarkMode: !current.isDarkMode);
    }
  }

  Future<void> _saveProgress(int page, int total) async {
    final itemId = _progressService.generateItemId(book.id, book.path);
    await _progressService.saveProgress(ReadingProgress(
      itemId: itemId,
      itemType: 'pdf',
      position: page.toDouble(),
      totalPositions: total,
      lastReadAt: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    final current = state;
    if (current is PdfReaderLoaded) {
      current.document.dispose();
    }
    super.dispose();
  }
}

class PdfReaderPage extends ConsumerStatefulWidget {
  const PdfReaderPage({required this.book, super.key});

  final BookItem book;

  @override
  ConsumerState<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends ConsumerState<PdfReaderPage> {
  bool _showControls = true;
  bool _showThumbnails = false;
  final PdfViewerController _controller = PdfViewerController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfReaderProvider(widget.book));

    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      body: switch (state) {
        PdfReaderLoading(:final message) => LoadingWidget(message: message),
        PdfReaderError(:final message) => _buildError(message),
        PdfReaderLoaded() => _buildReader(context, state),
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
              style: const TextStyle(fontSize: 16, color: Colors.white),
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

  Widget _buildReader(BuildContext context, PdfReaderLoaded state) => Stack(
      children: [
        // PDF 内容
        GestureDetector(
          onTap: () => setState(() {
            _showControls = !_showControls;
            _showThumbnails = false;
          }),
          child: PdfViewer.file(
            state.filePath,
            controller: _controller,
            params: PdfViewerParams(
              backgroundColor: state.isDarkMode ? Colors.black : Colors.grey.shade200,
              pageDropShadow: BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(2, 2),
              ),
              onPageChanged: (pageNumber) {
                if (pageNumber != null) {
                  ref.read(pdfReaderProvider(widget.book).notifier).setPage(pageNumber);
                }
              },
            ),
          ),
        ),

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
            child: _buildBottomBar(context, state),
          ),

        // 缩略图面板
        if (_showThumbnails) _buildThumbnailPanel(context, state),
      ],
    );

  Widget _buildTopBar(BuildContext context, PdfReaderLoaded state) => DecoratedBox(
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
                child: Text(
                  widget.book.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () {
                  ref.read(pdfReaderProvider(widget.book).notifier).toggleDarkMode();
                },
                icon: Icon(
                  state.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  color: Colors.white,
                ),
                tooltip: state.isDarkMode ? '浅色模式' : '深色模式',
              ),
              IconButton(
                onPressed: () => setState(() => _showThumbnails = !_showThumbnails),
                icon: const Icon(Icons.grid_view_rounded, color: Colors.white),
                tooltip: '页面缩略图',
              ),
            ],
          ),
        ),
      ),
    );

  Widget _buildBottomBar(BuildContext context, PdfReaderLoaded state) => DecoratedBox(
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
              // 页码指示器
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${state.currentPage} / ${state.totalPages}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${((state.currentPage / state.totalPages) * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 页码滑块
              Row(
                children: [
                  IconButton(
                    onPressed: state.currentPage > 1
                        ? () {
                            final newPage = state.currentPage - 1;
                            _controller.goToPage(pageNumber: newPage);
                            ref.read(pdfReaderProvider(widget.book).notifier).setPage(newPage);
                          }
                        : null,
                    icon: Icon(
                      Icons.chevron_left_rounded,
                      color: state.currentPage > 1 ? Colors.white : Colors.white38,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: state.currentPage.toDouble(),
                      min: 1,
                      max: state.totalPages.toDouble(),
                      divisions: state.totalPages > 1 ? state.totalPages - 1 : null,
                      onChanged: (value) {
                        final page = value.toInt();
                        _controller.goToPage(pageNumber: page);
                        ref.read(pdfReaderProvider(widget.book).notifier).setPage(page);
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: state.currentPage < state.totalPages
                        ? () {
                            final newPage = state.currentPage + 1;
                            _controller.goToPage(pageNumber: newPage);
                            ref.read(pdfReaderProvider(widget.book).notifier).setPage(newPage);
                          }
                        : null,
                    icon: Icon(
                      Icons.chevron_right_rounded,
                      color: state.currentPage < state.totalPages ? Colors.white : Colors.white38,
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
                    icon: Icons.first_page_rounded,
                    label: '首页',
                    onTap: () {
                      _controller.goToPage(pageNumber: 1);
                      ref.read(pdfReaderProvider(widget.book).notifier).setPage(1);
                    },
                  ),
                  _buildBottomButton(
                    icon: Icons.zoom_out_rounded,
                    label: '缩小',
                    onTap: _controller.zoomDown,
                  ),
                  _buildBottomButton(
                    icon: Icons.zoom_in_rounded,
                    label: '放大',
                    onTap: _controller.zoomUp,
                  ),
                  _buildBottomButton(
                    icon: Icons.last_page_rounded,
                    label: '末页',
                    onTap: () {
                      _controller.goToPage(pageNumber: state.totalPages);
                      ref.read(pdfReaderProvider(widget.book).notifier).setPage(state.totalPages);
                    },
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

  Widget _buildThumbnailPanel(BuildContext context, PdfReaderLoaded state) => Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.25,
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
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
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Text(
                      '页面',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => setState(() => _showThumbnails = false),
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: state.totalPages,
                  itemBuilder: (context, index) {
                    final pageNumber = index + 1;
                    final isActive = pageNumber == state.currentPage;
                    return GestureDetector(
                      onTap: () {
                        _controller.goToPage(pageNumber: pageNumber);
                        ref.read(pdfReaderProvider(widget.book).notifier).setPage(pageNumber);
                        setState(() => _showThumbnails = false);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.primary : Colors.grey.shade800,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isActive ? AppColors.primary : Colors.grey.shade700,
                            width: isActive ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '第 $pageNumber 页',
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.grey.shade400,
                              fontSize: 14,
                              fontWeight: isActive ? FontWeight.bold : null,
                            ),
                          ),
                        ),
                      ),
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
