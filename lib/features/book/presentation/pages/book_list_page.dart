import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/book/presentation/pages/book_reader_page.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/empty_widget.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/media_setup_widget.dart';

/// 图书文件及其来源
class BookFileWithSource {
  BookFileWithSource({
    required this.file,
    required this.sourceId,
  });

  final FileItem file;
  final String sourceId;
}

/// 图书列表状态
final bookListProvider =
    StateNotifierProvider<BookListNotifier, BookListState>(
        (ref) => BookListNotifier(ref));

sealed class BookListState {}

class BookListLoading extends BookListState {
  BookListLoading({this.progress = 0, this.currentFolder});
  final double progress;
  final String? currentFolder;
}

class BookListNotConnected extends BookListState {}

class BookListLoaded extends BookListState {
  BookListLoaded(this.books);
  final List<BookFileWithSource> books;
}

class BookListError extends BookListState {
  BookListError(this.message);
  final String message;
}

class BookListNotifier extends StateNotifier<BookListState> {
  BookListNotifier(this._ref) : super(BookListLoading()) {
    loadBooks();
  }

  final Ref _ref;

  /// 支持的电子书扩展名
  static const _supportedExtensions = [
    '.epub',
    '.pdf',
    '.txt',
    '.mobi',
    '.azw3',
  ];

  Future<void> loadBooks({int maxDepth = 3}) async {
    state = BookListLoading();

    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    // 等待配置加载完成
    MediaLibraryConfig? config = configAsync.valueOrNull;
    if (config == null) {
      state = BookListLoading(progress: 0, currentFolder: '正在加载配置...');

      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final updated = _ref.read(mediaLibraryConfigProvider);
        config = updated.valueOrNull;
        if (config != null) break;

        if (updated.hasError) {
          state = BookListError('加载媒体库配置失败');
          return;
        }
      }

      if (config == null) {
        state = BookListLoaded([]);
        return;
      }
    }

    // 获取已启用的书籍路径
    final bookPaths = config.getEnabledPathsForType(MediaType.book);

    if (bookPaths.isEmpty) {
      state = BookListLoaded([]);
      return;
    }

    // 过滤出已连接的路径
    final connectedPaths = bookPaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      state = BookListNotConnected();
      return;
    }

    try {
      final books = <BookFileWithSource>[];

      for (var i = 0; i < connectedPaths.length; i++) {
        final mediaPath = connectedPaths[i];
        final connection = connections[mediaPath.sourceId];
        if (connection == null) continue;

        state = BookListLoading(
          progress: i / connectedPaths.length,
          currentFolder: mediaPath.displayName,
        );

        try {
          await _scanForBooks(
            connection.adapter.fileSystem,
            mediaPath.path,
            books,
            sourceId: mediaPath.sourceId,
            depth: 0,
            maxDepth: maxDepth,
          );
        } on Exception catch (e) {
          logger.w('扫描书籍文件夹失败: ${mediaPath.path} - $e');
        }
      }

      logger.i('书籍扫描完成，共找到 ${books.length} 本书');
      state = BookListLoaded(books);
    } on Exception catch (e) {
      state = BookListError(e.toString());
    }
  }

  Future<void> _scanForBooks(
    NasFileSystem fs,
    String path,
    List<BookFileWithSource> books, {
    required String sourceId,
    required int depth,
    int maxDepth = 3,
  }) async {
    if (depth > maxDepth) return;

    try {
      final items = await fs.listDirectory(path);
      for (final item in items) {
        // 跳过隐藏文件夹和系统文件夹
        if (item.name.startsWith('.') ||
            item.name.startsWith('@') ||
            item.name == '#recycle') {
          continue;
        }

        if (item.isDirectory) {
          await _scanForBooks(
            fs,
            item.path,
            books,
            sourceId: sourceId,
            depth: depth + 1,
            maxDepth: maxDepth,
          );
        } else if (_isBookFile(item.name)) {
          books.add(BookFileWithSource(file: item, sourceId: sourceId));
        }
      }
    } on Exception catch (e) {
      logger.w('扫描子文件夹失败: $path - $e');
    }
  }

  bool _isBookFile(String filename) {
    final lower = filename.toLowerCase();
    return _supportedExtensions.any((ext) => lower.endsWith(ext));
  }
}

class BookListPage extends ConsumerWidget {
  const BookListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bookListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          _buildAppBar(context, ref, isDark),
          Expanded(
            child: switch (state) {
              BookListLoading(:final progress, :final currentFolder) =>
                _buildLoadingState(progress, currentFolder),
              BookListNotConnected() => const MediaSetupWidget(
                  mediaType: MediaType.book,
                  icon: Icons.menu_book_outlined,
                ),
              BookListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(bookListProvider.notifier).loadBooks(),
                ),
              BookListLoaded(:final books) when books.isEmpty => const EmptyWidget(
                  icon: Icons.menu_book_outlined,
                  title: '暂无图书',
                  message: '在配置的目录中添加电子书后将显示在这里\n支持 EPUB、PDF、TXT 格式',
                ),
              BookListLoaded(:final books) => _buildBookGrid(context, ref, books, isDark),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(double progress, String? currentFolder) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 4,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '扫描图书中...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (currentFolder != null) ...[
            const SizedBox(height: 8),
            Text(
              currentFolder,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
          if (progress > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, WidgetRef ref, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text(
                '图书',
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : null,
                ),
              ),
              const Spacer(),
              _buildIconButton(
                icon: Icons.refresh_rounded,
                onTap: () => ref.read(bookListProvider.notifier).loadBooks(),
                isDark: isDark,
                tooltip: '刷新',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isDark ? AppColors.darkOnSurfaceVariant : null,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookGrid(
    BuildContext context,
    WidgetRef ref,
    List<BookFileWithSource> books,
    bool isDark,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.65,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) => _BookGridItem(
        book: books[index],
        isDark: isDark,
      ),
    );
  }
}

class _BookGridItem extends ConsumerWidget {
  const _BookGridItem({
    required this.book,
    required this.isDark,
  });

  final BookFileWithSource book;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = book.file;
    final format = BookItem.formatFromExtension(file.name);
    final displayName = _getDisplayName(file.name);

    return GestureDetector(
      onTap: () => _openBook(context, ref),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : context.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 封面区域
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  gradient: _getFormatGradient(format),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        _getFormatIcon(format),
                        size: 48,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    // 格式标签
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          format.name.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 信息区域
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkOnSurface : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      file.displaySize,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDisplayName(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    return dotIndex > 0 ? filename.substring(0, dotIndex) : filename;
  }

  LinearGradient _getFormatGradient(BookFormat format) {
    return switch (format) {
      BookFormat.epub => const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      BookFormat.pdf => const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFF97316)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      BookFormat.txt => const LinearGradient(
          colors: [Color(0xFF6B7280), Color(0xFF9CA3AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      BookFormat.mobi || BookFormat.azw3 => const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      BookFormat.unknown => const LinearGradient(
          colors: [Color(0xFF6B7280), Color(0xFF9CA3AF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
    };
  }

  IconData _getFormatIcon(BookFormat format) {
    return switch (format) {
      BookFormat.epub => Icons.auto_stories_rounded,
      BookFormat.pdf => Icons.picture_as_pdf_rounded,
      BookFormat.txt => Icons.description_rounded,
      BookFormat.mobi || BookFormat.azw3 => Icons.book_rounded,
      BookFormat.unknown => Icons.insert_drive_file_rounded,
    };
  }

  Future<void> _openBook(BuildContext context, WidgetRef ref) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[book.sourceId];
    if (connection == null) return;

    final file = book.file;
    final url = await connection.adapter.fileSystem.getFileUrl(file.path);
    final bookItem = BookItem.fromFileItem(file, url);

    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => BookReaderPage(book: bookItem),
      ),
    );
  }
}
