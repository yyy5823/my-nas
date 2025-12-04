import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/comic/data/services/comic_library_cache_service.dart';
import 'package:my_nas/features/connection/presentation/providers/connection_provider.dart';
import 'package:my_nas/features/reading/presentation/pages/reading_page.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_reader_page.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/media_setup_widget.dart';

/// 漫画类型
enum ComicType {
  folder, // 文件夹形式（包含图片文件）
  cbz,    // CBZ 压缩包
  cbr,    // CBR 压缩包
  cb7,    // CB7 压缩包
}

/// 漫画项目（代表一个漫画文件夹或压缩包）
class ComicItem {
  ComicItem({
    required this.folderPath,
    required this.folderName,
    required this.sourceId,
    this.coverPath,
    this.pageCount = 0,
    this.modifiedTime,
    this.type = ComicType.folder,
    this.fileSize,
  });

  final String folderPath;
  final String folderName;
  final String sourceId;
  final String? coverPath;
  final int pageCount;
  final DateTime? modifiedTime;
  final ComicType type;
  final int? fileSize;

  /// 是否是压缩包格式
  bool get isArchive => type != ComicType.folder;

  /// 获取漫画格式图标
  IconData get formatIcon => switch (type) {
    ComicType.folder => Icons.folder_rounded,
    ComicType.cbz => Icons.archive_rounded,
    ComicType.cbr => Icons.archive_rounded,
    ComicType.cb7 => Icons.archive_rounded,
  };

  /// 格式化文件大小
  String get displaySize {
    if (fileSize == null) return '';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    if (fileSize! < 1024 * 1024 * 1024) {
      return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize! / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 从文件扩展名获取漫画类型
  static ComicType? typeFromExtension(String fileName) {
    final ext = fileName.toLowerCase();
    if (ext.endsWith('.cbz') || ext.endsWith('.zip')) return ComicType.cbz;
    if (ext.endsWith('.cbr') || ext.endsWith('.rar')) return ComicType.cbr;
    if (ext.endsWith('.cb7') || ext.endsWith('.7z')) return ComicType.cb7;
    return null;
  }

  ComicLibraryCacheEntry toCacheEntry() => ComicLibraryCacheEntry(
        sourceId: sourceId,
        folderPath: folderPath,
        folderName: folderName,
        coverPath: coverPath,
        pageCount: pageCount,
        modifiedTime: modifiedTime,
        comicType: type.name,
        fileSize: fileSize,
      );

  factory ComicItem.fromCacheEntry(ComicLibraryCacheEntry entry) => ComicItem(
      folderPath: entry.folderPath,
      folderName: entry.folderName,
      sourceId: entry.sourceId,
      coverPath: entry.coverPath,
      pageCount: entry.pageCount,
      modifiedTime: entry.modifiedTime,
      type: ComicType.values.firstWhere(
        (t) => t.name == entry.comicType,
        orElse: () => ComicType.folder,
      ),
      fileSize: entry.fileSize,
    );
}

/// 漫画列表状态
final comicListProvider =
    StateNotifierProvider<ComicListNotifier, ComicListState>(
        (ref) => ComicListNotifier(ref));

sealed class ComicListState {}

class ComicListLoading extends ComicListState {
  ComicListLoading({this.progress = 0, this.currentFolder, this.fromCache = false});
  final double progress;
  final String? currentFolder;
  final bool fromCache;
}

class ComicListNotConnected extends ComicListState {}

class ComicListLoaded extends ComicListState {
  ComicListLoaded({
    required this.comics,
    this.fromCache = false,
    this.searchQuery = '',
  });
  final List<ComicItem> comics;
  final bool fromCache;
  final String searchQuery;

  List<ComicItem> get filteredComics {
    if (searchQuery.isEmpty) return comics;
    return comics
        .where((c) => c.folderName.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();
  }

  ComicListLoaded copyWith({
    List<ComicItem>? comics,
    bool? fromCache,
    String? searchQuery,
  }) =>
      ComicListLoaded(
        comics: comics ?? this.comics,
        fromCache: fromCache ?? this.fromCache,
        searchQuery: searchQuery ?? this.searchQuery,
      );
}

class ComicListError extends ComicListState {
  ComicListError(this.message);
  final String message;
}

class ComicListNotifier extends StateNotifier<ComicListState> {
  ComicListNotifier(this._ref) : super(ComicListLoading()) {
    _init();
  }

  final Ref _ref;
  final ComicLibraryCacheService _cacheService = ComicLibraryCacheService.instance;

  // 支持的图片格式
  static const _imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];

  Future<void> _init() async {
    try {
      await _cacheService.init();
      await _loadFromCacheImmediately();

      _ref.listen<Map<String, SourceConnection>>(activeConnectionsProvider, (previous, next) {
        final prevConnected = previous?.values.where((c) => c.status == SourceStatus.connected).length ?? 0;
        final nextConnected = next.values.where((c) => c.status == SourceStatus.connected).length;

        if (nextConnected > prevConnected && state is ComicListNotConnected) {
          loadComics();
        }
      });
    } catch (e) {
      logger.e('ComicListNotifier: 初始化失败', e);
      state = ComicListLoaded(comics: [], fromCache: false);
    }
  }

  Future<void> _loadFromCacheImmediately() async {
    final cache = _cacheService.getCache();
    if (cache != null && cache.comics.isNotEmpty) {
      state = ComicListLoading(fromCache: true, currentFolder: '加载缓存...');

      final comics = cache.comics.map(ComicItem.fromCacheEntry).toList();

      state = ComicListLoaded(comics: comics, fromCache: true);
      logger.i('从缓存加载了 ${comics.length} 本漫画');
    } else {
      state = ComicListLoaded(comics: [], fromCache: true);
    }
  }

  Future<void> loadComics({bool forceRefresh = false}) async {
    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    MediaLibraryConfig? config = configAsync.valueOrNull;
    if (config == null) {
      state = ComicListLoading(currentFolder: '正在加载配置...');
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final updated = _ref.read(mediaLibraryConfigProvider);
        config = updated.valueOrNull;
        if (config != null) break;
        if (updated.hasError) {
          state = ComicListError('加载媒体库配置失败');
          return;
        }
      }
      if (config == null) {
        state = ComicListLoaded(comics: []);
        return;
      }
    }

    final comicPaths = config.getEnabledPathsForType(MediaType.comic);
    if (comicPaths.isEmpty) {
      state = ComicListLoaded(comics: []);
      return;
    }

    final connectedPaths = comicPaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      if (state is! ComicListLoaded || (state as ComicListLoaded).comics.isEmpty) {
        state = ComicListNotConnected();
      }
      return;
    }

    final sourceIds = connectedPaths.map((p) => p.sourceId).toList();

    // 尝试使用缓存
    if (!forceRefresh && _cacheService.isCacheValid(sourceIds)) {
      final cache = _cacheService.getCache();
      if (cache != null) {
        state = ComicListLoading(fromCache: true, currentFolder: '加载缓存...');

        final comics = cache.comics.map(ComicItem.fromCacheEntry).toList();

        state = ComicListLoaded(comics: comics, fromCache: true);
        logger.i('从缓存加载了 ${comics.length} 本漫画');
        return;
      }
    }

    // 扫描文件系统
    state = ComicListLoading();
    final comics = <ComicItem>[];
    var scannedFolders = 0;
    final totalFolders = connectedPaths.length;

    for (final mediaPath in connectedPaths) {
      final connection = connections[mediaPath.sourceId];
      if (connection == null) continue;

      state = ComicListLoading(
        progress: scannedFolders / totalFolders,
        currentFolder: mediaPath.displayName,
      );

      try {
        await _scanForComics(
          connection.adapter.fileSystem,
          mediaPath.path,
          comics,
          sourceId: mediaPath.sourceId,
        );
      } on Exception catch (e) {
        logger.w('扫描漫画文件夹失败: ${mediaPath.path} - $e');
      }

      scannedFolders++;
    }

    logger.i('漫画扫描完成，共找到 ${comics.length} 本漫画');

    // 保存到缓存
    final cacheEntries = comics.map((c) => c.toCacheEntry()).toList();
    await _cacheService.saveCache(ComicLibraryCache(
      comics: cacheEntries,
      lastUpdated: DateTime.now(),
      sourceIds: sourceIds,
    ));

    state = ComicListLoaded(comics: comics);
  }

  Future<void> _scanForComics(
    NasFileSystem fs,
    String path,
    List<ComicItem> comics, {
    required String sourceId,
  }) async {
    try {
      final items = await fs.listDirectory(path);

      for (final item in items) {
        if (item.name.startsWith('.') || item.name.startsWith('@') || item.name == '#recycle') {
          continue;
        }

        if (item.isDirectory) {
          // 检查这个文件夹是否是漫画（包含图片文件）
          final comicInfo = await _checkIfComicFolder(fs, item.path);
          if (comicInfo != null) {
            comics.add(ComicItem(
              folderPath: item.path,
              folderName: item.name,
              sourceId: sourceId,
              coverPath: comicInfo.coverPath,
              pageCount: comicInfo.pageCount,
              modifiedTime: item.modifiedTime,
              type: ComicType.folder,
            ));
          }
        } else {
          // 检查是否是漫画压缩包
          final comicType = ComicItem.typeFromExtension(item.name);
          if (comicType != null) {
            // 去掉扩展名作为漫画名称
            final nameWithoutExt = _removeExtension(item.name);
            comics.add(ComicItem(
              folderPath: item.path,
              folderName: nameWithoutExt,
              sourceId: sourceId,
              modifiedTime: item.modifiedTime,
              type: comicType,
              fileSize: item.size,
            ));
          }
        }
      }
    } on Exception catch (e) {
      logger.w('扫描漫画目录失败: $path - $e');
    }
  }

  /// 移除文件扩展名
  String _removeExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot > 0) {
      return fileName.substring(0, lastDot);
    }
    return fileName;
  }

  Future<({String? coverPath, int pageCount})?> _checkIfComicFolder(
    NasFileSystem fs,
    String folderPath,
  ) async {
    try {
      final items = await fs.listDirectory(folderPath);
      final imageFiles = items.where((item) {
        if (item.isDirectory) return false;
        final ext = item.name.toLowerCase();
        return _imageExtensions.any((e) => ext.endsWith(e));
      }).toList();

      if (imageFiles.isEmpty) return null;

      // 按名称排序，取第一张作为封面
      imageFiles.sort((a, b) => a.name.compareTo(b.name));

      return (
        coverPath: imageFiles.first.path,
        pageCount: imageFiles.length,
      );
    } catch (e) {
      return null;
    }
  }

  void setSearchQuery(String query) {
    final current = state;
    if (current is ComicListLoaded) {
      state = current.copyWith(searchQuery: query);
    }
  }

  Future<void> forceRefresh() async {
    await _cacheService.clearCache();
    await loadComics(forceRefresh: true);
  }
}

/// 漫画列表内容（供 ReadingPage 使用）
class ComicListContent extends ConsumerStatefulWidget {
  const ComicListContent({super.key});

  @override
  ConsumerState<ComicListContent> createState() => _ComicListContentState();
}

class _ComicListContentState extends ConsumerState<ComicListContent> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(comicListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return switch (state) {
      ComicListLoading(:final progress, :final currentFolder, :final fromCache) =>
        _buildLoadingState(progress, currentFolder, fromCache, isDark),
      ComicListNotConnected() => const MediaSetupWidget(
          mediaType: MediaType.comic,
          icon: Icons.collections_bookmark_outlined,
        ),
      ComicListError(:final message) => AppErrorWidget(
          message: message,
          onRetry: () => ref.read(comicListProvider.notifier).loadComics(),
        ),
      ComicListLoaded(:final filteredComics) when filteredComics.isEmpty =>
        _buildEmptyState(context, ref, isDark),
      ComicListLoaded loaded => _buildComicGrid(context, loaded, isDark),
    };
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref, bool isDark) {
    final cacheService = ComicLibraryCacheService.instance;
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
                Icons.collections_bookmark_rounded,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '漫画库为空',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请在媒体库设置中配置漫画目录并扫描',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
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

  Widget _buildToolbar(BuildContext context, bool isDark, ComicListState state) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.1)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // 类型切换按钮
          _buildTypeSwitcher(context, ref, isDark),
          const SizedBox(width: 8),
          if (_showSearch)
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '搜索漫画...',
                  hintStyle: TextStyle(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : context.colorScheme.onSurfaceVariant,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: TextStyle(
                  color: isDark ? AppColors.darkOnSurface : null,
                ),
                onChanged: (v) =>
                    ref.read(comicListProvider.notifier).setSearchQuery(v),
              ),
            )
          else ...[
            if (state is ComicListLoaded)
              Text(
                '${state.comics.length} 本漫画',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600],
                ),
              ),
            if (state is ComicListLoaded && state.fromCache)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '缓存',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
          const Spacer(),
          _buildIconButton(
            icon: _showSearch ? Icons.close : Icons.search_rounded,
            onTap: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  ref.read(comicListProvider.notifier).setSearchQuery('');
                }
              });
            },
            isDark: isDark,
          ),
          _buildIconButton(
            icon: Icons.refresh_rounded,
            onTap: () => ref.read(comicListProvider.notifier).forceRefresh(),
            isDark: isDark,
          ),
        ],
      ),
    );

  Widget _buildTypeSwitcher(BuildContext context, WidgetRef ref, bool isDark) {
    final currentIndex = ref.watch(readingTabProvider);
    final currentType = ReadingContentType.values[currentIndex];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showTypeMenu(context, ref, isDark, currentIndex),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                currentType.icon,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                currentType.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkOnSurface : Colors.black87,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 20,
                color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTypeMenu(BuildContext context, WidgetRef ref, bool isDark, int currentIndex) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<int>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? AppColors.darkSurface : Colors.white,
      items: ReadingContentType.values.asMap().entries.map((entry) {
        final index = entry.key;
        final type = entry.value;
        final isSelected = index == currentIndex;

        return PopupMenuItem<int>(
          value: index,
          child: Row(
            children: [
              Icon(
                type.icon,
                size: 20,
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600]),
              ),
              const SizedBox(width: 12),
              Text(
                type.label,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkOnSurface : Colors.black87),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
              ],
            ],
          ),
        );
      }).toList(),
    ).then((selectedIndex) {
      if (selectedIndex != null && selectedIndex != currentIndex) {
        ref.read(readingTabProvider.notifier).state = selectedIndex;
      }
    });
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: isDark ? AppColors.darkOnSurfaceVariant : null,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(
    double progress,
    String? currentFolder,
    bool fromCache,
    bool isDark,
  ) {
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
          Text(
            fromCache ? '加载缓存...' : '扫描漫画中...',
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
        ],
      ),
    );
  }

  Widget _buildComicGrid(BuildContext context, ComicListLoaded state, bool isDark) {
    return RefreshIndicator(
      onRefresh: () => ref.read(comicListProvider.notifier).forceRefresh(),
      child: GridView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.65,
        ),
        itemCount: state.filteredComics.length,
        itemBuilder: (context, index) {
          final comic = state.filteredComics[index];
          return _ComicCard(comic: comic, isDark: isDark);
        },
      ),
    );
  }
}

class _ComicCard extends ConsumerWidget {
  const _ComicCard({required this.comic, required this.isDark});

  final ComicItem comic;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openComic(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? AppColors.darkOutline.withOpacity(0.2)
                  : Colors.grey[300]!,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 封面
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Container(
                    color: isDark ? Colors.grey[800] : Colors.grey[200],
                    child: comic.coverPath != null
                        ? _buildCover(ref)
                        : _buildPlaceholder(),
                  ),
                ),
              ),
              // 标题和信息
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comic.folderName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppColors.darkOnSurface : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // 格式图标
                        Icon(
                          comic.formatIcon,
                          size: 12,
                          color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            comic.isArchive
                                ? comic.displaySize.isNotEmpty
                                    ? comic.displaySize
                                    : comic.type.name.toUpperCase()
                                : '${comic.pageCount} 页',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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

  Widget _buildCover(WidgetRef ref) {
    final adapter = ref.watch(activeAdapterProvider);
    if (adapter == null) return _buildPlaceholder();

    return FutureBuilder<String>(
      future: adapter.fileSystem.getFileUrl(comic.coverPath!),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Image.network(
            snapshot.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildPlaceholder(),
          );
        }
        return _buildPlaceholder();
      },
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        Icons.collections_bookmark_outlined,
        size: 40,
        color: isDark ? Colors.grey[600] : Colors.grey[400],
      ),
    );
  }

  void _openComic(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ComicReaderPage(comic: comic),
      ),
    );
  }
}
