import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/network/http_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_file_cache_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// EPUB 阅读器状态
final epubReaderProvider =
    StateNotifierProvider.family<EpubReaderNotifier, EpubReaderState, BookItem>(
      (ref, book) => EpubReaderNotifier(book, ref),
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
  EpubReaderNotifier(this.book, this._ref) : super(EpubReaderLoading()) {
    _loadEpub();
  }

  final BookItem book;
  final Ref _ref;
  final ReadingProgressService _progressService = ReadingProgressService();
  final BookFileCacheService _cacheService = BookFileCacheService();

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
      await _progressService.init();
      final itemId = _progressService.generateItemId(book.id, book.path);
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
  Future<void> saveProgress(EpubLocation location) async {
    final itemId = _progressService.generateItemId(book.id, book.path);
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
  const EpubReaderPage({required this.book, super.key});

  final BookItem book;

  @override
  ConsumerState<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends ConsumerState<EpubReaderPage> {
  final EpubController _epubController = EpubController();
  bool _showControls = false;
  bool _showToc = false;
  List<EpubChapter> _chapters = [];
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWakelock();
  }

  Future<void> _initWakelock() async {
    await WakelockPlus.enable();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    super.dispose();
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
  /// 左侧 1/4: 上一页
  /// 右侧 1/4: 下一页
  /// 中间 1/2: 切换控制栏
  void _handleTapZone(Offset normalizedPosition) {
    final tapX = normalizedPosition.dx;

    if (tapX < 0.25) {
      // 左侧区域 - 上一页
      _epubController.prev();
    } else if (tapX > 0.75) {
      // 右侧区域 - 下一页
      _epubController.next();
    } else {
      // 中间区域 - 切换控制栏
      _toggleControls();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(epubReaderProvider(widget.book));

    return Scaffold(
      backgroundColor: Colors.white,
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

  Widget _buildReader(BuildContext context, EpubReaderLoaded state) => Stack(
    children: [
      // EPUB 阅读器
      EpubViewer(
        epubSource: EpubSource.fromFile(File(state.filePath)),
        epubController: _epubController,
        initialCfi: state.initialCfi,
        displaySettings: EpubDisplaySettings(
          allowScriptedContent: true,
        ),
        onChaptersLoaded: (chapters) {
          setState(() {
            _chapters = chapters;
          });
          ref
              .read(epubReaderProvider(widget.book).notifier)
              .updateChapters(chapters);
        },
        onEpubLoaded: () {
          logger.i('EPUB 渲染完成');
        },
        onRelocated: (location) {
          setState(() {
            _progress = location.progress;
          });
          // 保存阅读进度
          ref
              .read(epubReaderProvider(widget.book).notifier)
              .saveProgress(location);
        },
        // 使用原生触摸事件处理，避免 GestureDetector 拦截手势
        onTouchUp: (x, y) {
          _handleTapZone(Offset(x, y));
        },
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

  Widget _buildBottomBar(BuildContext context) => DecoratedBox(
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
                    onChanged: _epubController.toProgressPercentage,
                    activeColor: AppColors.primary,
                    inactiveColor: Colors.white30,
                  ),
                ),
              ],
            ),
            // 控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                  onPressed: _epubController.prev,
                  tooltip: '上一页',
                ),
                IconButton(
                  icon: const Icon(Icons.first_page, color: Colors.white),
                  onPressed: _epubController.moveToFistPage,
                  tooltip: '第一页',
                ),
                IconButton(
                  icon: const Icon(Icons.last_page, color: Colors.white),
                  onPressed: _epubController.moveToLastPage,
                  tooltip: '最后一页',
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                  onPressed: _epubController.next,
                  tooltip: '下一页',
                ),
              ],
            ),
          ],
        ),
      ),
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
                              _epubController.display(cfi: chapter.href);
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
    ),
  );
}
