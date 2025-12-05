import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/router/app_router.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/book/data/services/book_library_cache_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/book/presentation/pages/book_reader_page.dart';
import 'package:my_nas/features/book/presentation/pages/epub_reader_page.dart';
import 'package:my_nas/features/book/presentation/pages/pdf_reader_page.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
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

  String get name => file.name;
  String get path => file.path;
  int get size => file.size;
  DateTime? get modifiedTime => file.modifiedTime;
  String get displaySize => file.displaySize;

  BookLibraryCacheEntry toCacheEntry() => BookLibraryCacheEntry(
        sourceId: sourceId,
        filePath: path,
        fileName: name,
        size: size,
        modifiedTime: modifiedTime,
      );
}

/// 图书列表状态
final bookListProvider =
    StateNotifierProvider<BookListNotifier, BookListState>(
        (ref) => BookListNotifier(ref));

/// 图书排序方式
enum BookSortType { name, date, size, format }

/// 阅读内容类别
enum ReadingCategory {
  book('图书', Icons.menu_book_rounded),
  comic('漫画', Icons.collections_rounded),
  note('笔记', Icons.note_alt_rounded);

  const ReadingCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

sealed class BookListState {}

class BookListLoading extends BookListState {
  BookListLoading({this.progress = 0, this.currentFolder, this.fromCache = false});
  final double progress;
  final String? currentFolder;
  final bool fromCache;
}

class BookListNotConnected extends BookListState {}

/// 优化后的图书列表状态 - 使用预计算数据
class BookListLoaded extends BookListState {
  BookListLoaded({
    required this.totalCount,
    this.totalSize = 0,
    this.formatStats = const {},
    this.sortType = BookSortType.name,
    this.searchQuery = '',
    this.fromCache = false,
    // 分类数据 - 从 SQLite 预加载
    this.allBooks = const [],
    this.searchResults = const [],
    // 用于 O(1) 查找的 Map
    this.bookByPath = const {},
  });

  final int totalCount;
  final int totalSize;
  final Map<BookFormat, int> formatStats;  // 预计算的格式统计
  final BookSortType sortType;
  final String searchQuery;
  final bool fromCache;

  // 分类数据 - 已从 SQLite 预加载
  final List<BookEntity> allBooks;
  final List<BookEntity> searchResults;

  // 用于 O(1) 查找的 Map
  final Map<String, BookEntity> bookByPath;

  /// 当前显示的图书（搜索时返回搜索结果）
  List<BookEntity> get displayBooks =>
      searchQuery.isNotEmpty ? searchResults : allBooks;

  /// 兼容旧代码：返回 BookFileWithSource 列表
  List<BookFileWithSource> get books => allBooks
      .map((b) => BookFileWithSource(
            file: FileItem(
              name: b.fileName,
              path: b.filePath,
              size: b.size,
              isDirectory: false,
              modifiedTime: b.modifiedTime,
            ),
            sourceId: b.sourceId,
          ))
      .toList();

  /// 兼容旧代码：过滤后的图书
  List<BookFileWithSource> get filteredBooks => displayBooks
      .map((b) => BookFileWithSource(
            file: FileItem(
              name: b.fileName,
              path: b.filePath,
              size: b.size,
              isDirectory: false,
              modifiedTime: b.modifiedTime,
            ),
            sourceId: b.sourceId,
          ))
      .toList();

  /// 通过路径获取图书 - O(1) 查找
  BookFileWithSource? getBookByPath(String path) {
    final b = bookByPath[path];
    if (b == null) return null;
    return BookFileWithSource(
      file: FileItem(
        name: b.fileName,
        path: b.filePath,
        size: b.size,
        isDirectory: false,
        modifiedTime: b.modifiedTime,
      ),
      sourceId: b.sourceId,
    );
  }

  BookListLoaded copyWith({
    int? totalCount,
    int? totalSize,
    Map<BookFormat, int>? formatStats,
    BookSortType? sortType,
    String? searchQuery,
    bool? fromCache,
    List<BookEntity>? allBooks,
    List<BookEntity>? searchResults,
    Map<String, BookEntity>? bookByPath,
  }) =>
      BookListLoaded(
        totalCount: totalCount ?? this.totalCount,
        totalSize: totalSize ?? this.totalSize,
        formatStats: formatStats ?? this.formatStats,
        sortType: sortType ?? this.sortType,
        searchQuery: searchQuery ?? this.searchQuery,
        fromCache: fromCache ?? this.fromCache,
        allBooks: allBooks ?? this.allBooks,
        searchResults: searchResults ?? this.searchResults,
        bookByPath: bookByPath ?? this.bookByPath,
      );
}

class BookListError extends BookListState {
  BookListError(this.message);
  final String message;
}

class BookListNotifier extends StateNotifier<BookListState> {
  BookListNotifier(this._ref) : super(BookListLoading()) {
    _init();
  }

  final Ref _ref;
  final BookLibraryCacheService _cacheService = BookLibraryCacheService.instance;
  final BookDatabaseService _db = BookDatabaseService.instance;

  /// 支持的电子书扩展名
  static const _supportedExtensions = [
    '.epub',
    '.pdf',
    '.txt',
    '.mobi',
    '.azw3',
  ];

  Future<void> _init() async {
    try {
      await _db.init();
      await _cacheService.init();
      await _loadFromSqlite();

      // 监听连接状态变化
      _ref.listen<Map<String, SourceConnection>>(activeConnectionsProvider, (previous, next) {
        final prevConnected = previous?.values.where((c) => c.status == SourceStatus.connected).length ?? 0;
        final nextConnected = next.values.where((c) => c.status == SourceStatus.connected).length;

        if (nextConnected > prevConnected && state is BookListNotConnected) {
          loadBooks();
        }
      });
    } on Exception catch (e) {
      logger.e('BookListNotifier: 初始化失败', e);
      state = BookListLoaded(totalCount: 0, fromCache: false);
    }
  }

  /// 从 SQLite 加载数据
  Future<void> _loadFromSqlite() async {
    final count = await _db.getCount();
    if (count == 0) {
      // SQLite 为空，尝试从旧缓存迁移
      await _migrateFromOldCache();
      return;
    }

    state = BookListLoading(fromCache: true, currentFolder: '加载数据...');

    // 并行加载统计和数据
    final results = await Future.wait([
      _db.getStats(),
      _db.getAll(),
    ]);

    final stats = results[0] as Map<String, dynamic>;
    final allBooks = results[1] as List<BookEntity>;

    // 转换格式统计
    final rawFormatStats = stats['formatStats'] as Map<String, int>? ?? {};
    final formatStats = <BookFormat, int>{};
    for (final entry in rawFormatStats.entries) {
      final format = BookFormat.values.firstWhere(
        (f) => f.name == entry.key,
        orElse: () => BookFormat.unknown,
      );
      formatStats[format] = entry.value;
    }

    // 构建快速查找 Map
    final bookByPath = <String, BookEntity>{};
    for (final b in allBooks) {
      bookByPath[b.uniqueKey] = b;
    }

    state = BookListLoaded(
      totalCount: stats['total'] as int? ?? 0,
      totalSize: stats['totalSize'] as int? ?? 0,
      formatStats: formatStats,
      allBooks: allBooks,
      bookByPath: bookByPath,
      fromCache: true,
    );

    logger.i('BookListNotifier: 从 SQLite 加载了 ${allBooks.length} 本图书');
  }

  /// 从旧缓存迁移到 SQLite
  Future<void> _migrateFromOldCache() async {
    final cache = _cacheService.getCache();
    if (cache == null || cache.books.isEmpty) {
      state = BookListLoaded(totalCount: 0, fromCache: true);
      return;
    }

    logger.i('BookListNotifier: 开始从 Hive 迁移 ${cache.books.length} 本图书');
    state = BookListLoading(currentFolder: '正在迁移数据...', fromCache: true);

    final entities = cache.books
        .map((entry) => BookEntity(
              sourceId: entry.sourceId,
              filePath: entry.filePath,
              fileName: entry.fileName,
              format: BookItem.formatFromExtension(entry.fileName),
              size: entry.size,
              modifiedTime: entry.modifiedTime,
              lastUpdated: DateTime.now(),
            ))
        .toList();

    await _db.upsertBatch(entities);
    logger.i('BookListNotifier: 迁移完成');

    // 重新加载
    await _loadFromSqlite();
  }

  Future<void> loadBooks({bool forceRefresh = false, int maxDepth = 3}) async {
    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    var config = configAsync.valueOrNull;
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
        state = BookListLoaded(totalCount: 0);
        return;
      }
    }

    final bookPaths = config.getEnabledPathsForType(MediaType.book);

    if (bookPaths.isEmpty) {
      state = BookListLoaded(totalCount: 0);
      return;
    }

    final connectedPaths = bookPaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      final current = state;
      if (current is! BookListLoaded || current.totalCount == 0) {
        state = BookListNotConnected();
      }
      return;
    }

    // 如果不是强制刷新且 SQLite 有数据，直接使用
    if (!forceRefresh) {
      final count = await _db.getCount();
      if (count > 0) {
        await _loadFromSqlite();
        return;
      }
    }

    // 扫描文件系统
    state = BookListLoading();
    final books = <BookFileWithSource>[];
    var scannedFolders = 0;
    final totalFolders = connectedPaths.length;

    for (final mediaPath in connectedPaths) {
      final connection = connections[mediaPath.sourceId];
      if (connection == null) continue;

      state = BookListLoading(
        progress: scannedFolders / totalFolders,
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

      scannedFolders++;
    }

    logger.i('书籍扫描完成，共找到 ${books.length} 本书');

    // 保存到 SQLite
    state = BookListLoading(
      progress: 1.0,
      currentFolder: '保存数据...',
    );

    final entities = books
        .map((b) => BookEntity(
              sourceId: b.sourceId,
              filePath: b.path,
              fileName: b.name,
              format: BookItem.formatFromExtension(b.name),
              size: b.size,
              modifiedTime: b.modifiedTime,
              lastUpdated: DateTime.now(),
            ))
        .toList();

    await _db.clear();
    await _db.upsertBatch(entities);

    // 重新从 SQLite 加载（确保状态一致）
    await _loadFromSqlite();
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

  void setSearchQuery(String query) {
    final current = state;
    if (current is BookListLoaded) {
      if (query.isEmpty) {
        state = current.copyWith(searchQuery: '', searchResults: []);
      } else {
        // 使用 SQLite 搜索
        _db.search(query).then((results) {
          if (state is BookListLoaded) {
            state = (state as BookListLoaded).copyWith(
              searchQuery: query,
              searchResults: results,
            );
          }
        });
        // 先更新搜索词，结果异步返回
        state = current.copyWith(searchQuery: query);
      }
    }
  }

  void setSortType(BookSortType sortType) {
    final current = state;
    if (current is BookListLoaded) {
      state = current.copyWith(sortType: sortType);
    }
  }

  /// 强制刷新
  Future<void> forceRefresh() async {
    await _db.clear();
    await _cacheService.clearCache();
    await loadBooks(forceRefresh: true);
  }
}

class BookListPage extends ConsumerStatefulWidget {
  const BookListPage({super.key});

  @override
  ConsumerState<BookListPage> createState() => _BookListPageState();
}

class _BookListPageState extends ConsumerState<BookListPage> {
  final _searchController = TextEditingController();
  bool _showSearch = false;
  ReadingCategory _selectedCategory = ReadingCategory.book;

  // 图书主题色（琥珀色）
  static const _themeColor = Color(0xFFD97706);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 9) return '早安';
    if (hour < 12) return '上午好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    if (hour < 22) return '晚上好';
    return '夜深了';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          _buildHeader(context, ref, isDark, state),
          Expanded(
            child: switch (state) {
              BookListLoading(:final progress, :final currentFolder, :final fromCache) =>
                _buildLoadingState(progress, currentFolder, fromCache, isDark),
              BookListNotConnected() => const MediaSetupWidget(
                  mediaType: MediaType.book,
                  icon: Icons.menu_book_outlined,
                ),
              BookListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(bookListProvider.notifier).loadBooks(),
                ),
              BookListLoaded(:final filteredBooks) when filteredBooks.isEmpty =>
                _buildEmptyState(context, ref, isDark),
              BookListLoaded loaded => _buildBookContent(context, ref, loaded, isDark),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    BookListState state,
  ) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [AppColors.darkSurface, AppColors.darkBackground]
              : [_themeColor.withValues(alpha: 0.1), Colors.grey[50]!],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.appBarHorizontalPadding,
            AppSpacing.appBarVerticalPadding,
            AppSpacing.appBarHorizontalPadding,
            AppSpacing.lg,
          ),
          child: _showSearch
              ? _buildSearchBarContent(context, ref, isDark)
              : _buildGreetingHeader(context, ref, isDark, state),
        ),
      ),
    );

  /// 搜索栏内容（用于在 header 容器内显示）
  Widget _buildSearchBarContent(BuildContext context, WidgetRef ref, bool isDark) => Row(
      children: [
        IconButton(
          onPressed: () {
            setState(() => _showSearch = false);
            _searchController.clear();
            ref.read(bookListProvider.notifier).setSearchQuery('');
          },
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        Expanded(
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: '搜索图书、漫画、笔记...',
              hintStyle: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[400],
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onChanged: (value) {
              ref.read(bookListProvider.notifier).setSearchQuery(value);
            },
          ),
        ),
        if (_searchController.text.isNotEmpty)
          IconButton(
            onPressed: () {
              _searchController.clear();
              ref.read(bookListProvider.notifier).setSearchQuery('');
            },
            icon: Icon(
              Icons.close,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
      ],
    );

  Widget _buildGreetingHeader(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    BookListState state,
  ) {
    final greeting = _getGreeting();
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 600;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 第一行：问候语 + 操作按钮
        Row(
          children: [
            // 左侧问候语和统计
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    greeting,
                    style: context.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (state is BookListLoaded)
                    Row(
                      children: [
                        _buildStatChip(
                          icon: Icons.menu_book_rounded,
                          label: '${state.totalCount} 本图书',
                          color: _themeColor,
                          isDark: isDark,
                        ),
                        if (isWideScreen && state.formatStats.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          ...state.formatStats.entries.take(2).map(
                                (entry) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: _buildFormatChip(
                                      entry.key, entry.value, isDark),
                                ),
                              ),
                        ],
                      ],
                    )
                  else
                    Text(
                      '正在加载...',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
            // 右侧操作按钮（与音乐/视频页面风格一致）
            IconButton(
              onPressed: () => setState(() => _showSearch = true),
              icon: Icon(
                Icons.search_rounded,
                color: isDark ? Colors.white : Colors.black87,
              ),
              tooltip: '搜索',
            ),
            IconButton(
              onPressed: () => ref.read(bookListProvider.notifier).forceRefresh(),
              icon: Icon(
                Icons.refresh_rounded,
                color: isDark ? Colors.white : Colors.black87,
              ),
              tooltip: '刷新',
            ),
            IconButton(
              onPressed: () => _showSettingsMenu(context),
              icon: Icon(
                Icons.more_vert_rounded,
                color: isDark ? Colors.white : Colors.black87,
              ),
              tooltip: '更多',
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 第二行：类别Tab切换
        _buildCategoryTabs(isDark),
      ],
    );
  }

  /// 构建类别Tab切换
  Widget _buildCategoryTabs(bool isDark) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 400;

    return Row(
      children: ReadingCategory.values.map((category) {
        final isSelected = _selectedCategory == category;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() => _selectedCategory = category);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : _themeColor.withValues(alpha: 0.15))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    category.icon,
                    size: isCompact ? 16 : 18,
                    color: isSelected
                        ? (isDark ? Colors.white : _themeColor)
                        : (isDark ? Colors.grey[500] : Colors.grey[600]),
                  ),
                  if (!isCompact) ...[
                    const SizedBox(width: 6),
                    Text(
                      category.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? (isDark ? Colors.white : _themeColor)
                            : (isDark ? Colors.grey[500] : Colors.grey[600]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    );

  Widget _buildFormatChip(BookFormat format, int count, bool isDark) {
    final color = _getFormatColor(format);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${format.name.toUpperCase()} $count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Color _getFormatColor(BookFormat format) => switch (format) {
      BookFormat.epub => const Color(0xFF6366F1),
      BookFormat.pdf => const Color(0xFFEF4444),
      BookFormat.txt => const Color(0xFF6B7280),
      BookFormat.mobi || BookFormat.azw3 => const Color(0xFFF59E0B),
      BookFormat.unknown => const Color(0xFF6B7280),
    };

  /// 设置菜单
  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.settings_rounded),
              title: const Text('媒体库设置'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const MediaLibraryPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_rounded),
              title: const Text('连接源管理'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const SourcesPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(
    double progress,
    String? currentFolder,
    bool fromCache,
    bool isDark,
  ) => Center(
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
          Text(
            fromCache ? '加载缓存...' : '扫描图书中...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : null,
            ),
          ),
          if (currentFolder != null) ...[
            const SizedBox(height: 8),
            Text(
              currentFolder,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey,
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

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
  ) {
    // 获取缓存信息
    final cacheService = BookLibraryCacheService.instance;
    final cacheInfo = cacheService.getCacheInfo();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.menu_book_rounded,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '图书库为空',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请在媒体库设置中配置图书目录并扫描\n支持 EPUB、PDF、TXT 格式',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // 缓存信息
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.storage_rounded,
                    size: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cacheInfo,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const MediaLibraryPage()),
              ),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('媒体库设置'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
              ),
              icon: const Icon(Icons.cloud_rounded),
              label: const Text('连接管理'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookContent(
    BuildContext context,
    WidgetRef ref,
    BookListLoaded state,
    bool isDark,
  ) => RefreshIndicator(
      onRefresh: () => ref.read(bookListProvider.notifier).forceRefresh(),
      child: CustomScrollView(
        slivers: [
          // 缓存信息条
          _BookCacheInfoBar(state: state, isDark: isDark),
          // 图书网格
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.md),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                childAspectRatio: 0.65,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _BookGridItem(
                  book: state.filteredBooks[index],
                  isDark: isDark,
                ),
                childCount: state.filteredBooks.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
}

/// 缓存信息条
class _BookCacheInfoBar extends ConsumerWidget {
  const _BookCacheInfoBar({
    required this.state,
    required this.isDark,
  });

  final BookListLoaded state;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheService = BookLibraryCacheService.instance;
    final cache = cacheService.getCache();

    if (cache == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final bookCount = state.totalCount;
    final formatStats = state.formatStats;
    final cacheAge = DateTime.now().difference(cache.lastUpdated);
    final ageText = cacheAge.inHours < 1
        ? '${cacheAge.inMinutes} 分钟前'
        : cacheAge.inHours < 24
            ? '${cacheAge.inHours} 小时前'
            : '${cacheAge.inDays} 天前';

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 14,
              color: AppColors.fileDocument,
            ),
            const SizedBox(width: 4),
            Text(
              '$bookCount',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              '本图书',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 12),
            // 格式统计
            ...formatStats.entries.take(3).map((entry) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getFormatColor(entry.key).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${entry.key.name.toUpperCase()} ${entry.value}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: _getFormatColor(entry.key),
                      ),
                    ),
                  ),
                )),
            const Spacer(),
            Icon(
              Icons.update_rounded,
              size: 14,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              ageText,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => ref.read(bookListProvider.notifier).forceRefresh(),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.fileDocument.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: AppColors.fileDocument,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getFormatColor(BookFormat format) => switch (format) {
      BookFormat.epub => const Color(0xFF6366F1),
      BookFormat.pdf => const Color(0xFFEF4444),
      BookFormat.txt => const Color(0xFF6B7280),
      BookFormat.mobi || BookFormat.azw3 => const Color(0xFFF59E0B),
      BookFormat.unknown => const Color(0xFF6B7280),
    };
}

/// 图书列表内容组件（供阅读页面复用）
class BookListContent extends ConsumerStatefulWidget {
  const BookListContent({super.key});

  @override
  ConsumerState<BookListContent> createState() => _BookListContentState();
}

class _BookListContentState extends ConsumerState<BookListContent> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return switch (state) {
      BookListLoading(:final progress, :final currentFolder, :final fromCache) =>
        _buildLoadingState(progress, currentFolder, fromCache, isDark),
      BookListNotConnected() => const MediaSetupWidget(
          mediaType: MediaType.book,
          icon: Icons.menu_book_outlined,
        ),
      BookListError(:final message) => AppErrorWidget(
          message: message,
          onRetry: () => ref.read(bookListProvider.notifier).loadBooks(),
        ),
      BookListLoaded(:final filteredBooks) when filteredBooks.isEmpty =>
        _buildEmptyState(context, isDark),
      BookListLoaded loaded => _buildBookGrid(context, ref, loaded, isDark),
    };
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    // 获取缓存信息
    final cacheService = BookLibraryCacheService.instance;
    final cacheInfo = cacheService.getCacheInfo();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.menu_book_rounded,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '图书库为空',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请在媒体库设置中配置图书目录并扫描\n支持 EPUB、PDF、TXT 格式',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // 缓存信息
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.storage_rounded,
                    size: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cacheInfo,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const MediaLibraryPage()),
              ),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('媒体库设置'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
              ),
              icon: const Icon(Icons.cloud_rounded),
              label: const Text('连接管理'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(
    double progress,
    String? currentFolder,
    bool fromCache,
    bool isDark,
  ) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 3,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            fromCache ? '加载缓存...' : '扫描图书中...',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : null,
            ),
          ),
          if (currentFolder != null) ...[
            const SizedBox(height: 6),
            Text(
              currentFolder,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );

  Widget _buildBookGrid(
    BuildContext context,
    WidgetRef ref,
    BookListLoaded state,
    bool isDark,
  ) => RefreshIndicator(
      onRefresh: () => ref.read(bookListProvider.notifier).forceRefresh(),
      child: GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 0.65,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
        ),
        itemCount: state.filteredBooks.length,
        itemBuilder: (context, index) => _BookGridItem(
          book: state.filteredBooks[index],
          isDark: isDark,
        ),
      ),
    );
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
      child: DecoratedBox(
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
            Expanded(
              flex: 3,
              child: DecoratedBox(
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

  LinearGradient _getFormatGradient(BookFormat format) => switch (format) {
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

  IconData _getFormatIcon(BookFormat format) => switch (format) {
      BookFormat.epub => Icons.auto_stories_rounded,
      BookFormat.pdf => Icons.picture_as_pdf_rounded,
      BookFormat.txt => Icons.description_rounded,
      BookFormat.mobi || BookFormat.azw3 => Icons.book_rounded,
      BookFormat.unknown => Icons.insert_drive_file_rounded,
    };

  Future<void> _openBook(BuildContext context, WidgetRef ref) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[book.sourceId];
    if (connection == null) return;

    final file = book.file;
    final url = await connection.adapter.fileSystem.getFileUrl(file.path);
    final bookItem = BookItem.fromFileItem(file, url);

    if (!context.mounted) return;

    // 根据格式选择阅读器
    Widget readerPage;
    switch (bookItem.format) {
      case BookFormat.epub:
        readerPage = EpubReaderPage(book: bookItem);
      case BookFormat.pdf:
        readerPage = PdfReaderPage(book: bookItem);
      case BookFormat.txt:
      case BookFormat.mobi:
      case BookFormat.azw3:
      case BookFormat.unknown:
        readerPage = BookReaderPage(book: bookItem);
    }

    // 使用 rootNavigatorKey 确保阅读器全屏显示，不显示底部导航栏
    await Navigator.of(rootNavigatorKey.currentContext!).push(
      MaterialPageRoute<void>(
        builder: (context) => readerPage,
      ),
    );
  }
}
