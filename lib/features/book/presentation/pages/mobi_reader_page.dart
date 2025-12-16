import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foliate_viewer/flutter_foliate_viewer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_file_cache_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';
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
  String? _initialCfi;

  // 进度保存防抖
  Timer? _saveProgressTimer;
  FoliateLocation? _pendingLocation;
  static const _saveProgressDebounce = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _loadProgress();
  }

  @override
  void dispose() {
    // 页面关闭时立即保存待保存的进度
    _saveProgressTimer?.cancel();
    if (_pendingLocation != null) {
      _saveProgressImmediately(_pendingLocation!);
    }
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mobiReaderProvider(widget.book));

    return Scaffold(
      backgroundColor: Colors.white,
      body: switch (state) {
        MobiReaderLoading(:final message) => LoadingWidget(message: message),
        MobiReaderError(:final message) => _buildError(message),
        MobiReaderLoaded(:final filePath) => _buildReader(filePath),
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

  Widget _buildReader(String filePath) => GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        children: [
          // 阅读器
          FoliateViewer(
            controller: _controller,
            bookSource: FileBookSource(File(filePath)),
            initialCfi: _initialCfi,
            onBookLoaded: (info) {
              setState(() {
                _bookInfo = info;
              });
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
          if (_showControls) _buildTopBar(),

          // 底部进度条
          if (_showControls) _buildBottomBar(),
        ],
      ),
    );

  Widget _buildTopBar() => Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
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
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  _bookInfo?.title ?? widget.book.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );

  Widget _buildBottomBar() {
    final progress = _currentLocation?.fraction ?? 0.0;

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
              Colors.black.withValues(alpha: 0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(progress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      '${_currentLocation?.sectionIndex ?? 0}/${_currentLocation?.totalSections ?? 0}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: _controller.goToFraction,
                activeColor: Colors.white,
                inactiveColor: Colors.white30,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous, color: Colors.white),
                      onPressed: _controller.prevPage,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white),
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
}
