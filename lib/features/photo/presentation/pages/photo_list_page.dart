import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/router/app_router.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/photo/data/services/photo_library_cache_service.dart';
import 'package:my_nas/features/photo/domain/entities/photo_item.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_viewer_page.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/animated_list_item.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 照片文件及其来源
class PhotoFileWithSource {
  PhotoFileWithSource({
    required this.file,
    required this.sourceId,
  });

  final FileItem file;
  final String sourceId;

  String get name => file.name;
  String get path => file.path;
  int get size => file.size;
  DateTime? get modifiedTime => file.modifiedTime;
  String? get thumbnailUrl => file.thumbnailUrl;

  PhotoLibraryCacheEntry toCacheEntry() => PhotoLibraryCacheEntry(
        sourceId: sourceId,
        filePath: path,
        fileName: name,
        thumbnailUrl: thumbnailUrl,
        size: size,
        modifiedTime: modifiedTime,
      );
}

/// 照片列表状态
final photoListProvider =
    StateNotifierProvider<PhotoListNotifier, PhotoListState>((ref) {
  return PhotoListNotifier(ref);
});

/// 照片排序方式
enum PhotoSortType { date, name, size }

/// 照片视图模式
enum PhotoViewMode { grid, timeline }

sealed class PhotoListState {}

class PhotoListLoading extends PhotoListState {
  PhotoListLoading({
    this.progress = 0,
    this.currentFolder,
    this.fromCache = false,
    this.partialPhotos = const [],
    this.scannedCount = 0,
  });
  final double progress;
  final String? currentFolder;
  final bool fromCache;
  final List<PhotoFileWithSource> partialPhotos;
  final int scannedCount;
}

class PhotoListLoaded extends PhotoListState {
  PhotoListLoaded({
    required this.photos,
    this.sortType = PhotoSortType.date,
    this.viewMode = PhotoViewMode.grid,
    this.searchQuery = '',
    this.fromCache = false,
  });

  final List<PhotoFileWithSource> photos;
  final PhotoSortType sortType;
  final PhotoViewMode viewMode;
  final String searchQuery;
  final bool fromCache;

  List<PhotoFileWithSource> get filteredPhotos {
    var result = List<PhotoFileWithSource>.from(photos);

    // 搜索过滤
    if (searchQuery.isNotEmpty) {
      result = result
          .where((p) => p.name.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
    }

    // 排序
    switch (sortType) {
      case PhotoSortType.date:
        result.sort((a, b) => (b.modifiedTime ?? DateTime(1970))
            .compareTo(a.modifiedTime ?? DateTime(1970)));
      case PhotoSortType.name:
        result.sort((a, b) => a.name.compareTo(b.name));
      case PhotoSortType.size:
        result.sort((a, b) => b.size.compareTo(a.size));
    }

    return result;
  }

  /// 按日期分组的照片
  List<PhotoGroup> get groupedPhotos {
    final filtered = filteredPhotos;
    final groups = <DateTime, List<PhotoItem>>{};
    final unknownDateKey = DateTime(1970); // 用于没有时间信息的照片

    for (final photo in filtered) {
      // 如果照片有有效的修改时间（不是空或1970年之前的日期）
      final hasValidTime = photo.modifiedTime != null &&
          photo.modifiedTime!.year > 1970;

      final dateKey = hasValidTime
          ? DateTime(photo.modifiedTime!.year, photo.modifiedTime!.month, photo.modifiedTime!.day)
          : unknownDateKey;

      groups.putIfAbsent(dateKey, () => []);
      groups[dateKey]!.add(PhotoItem(
        name: photo.name,
        path: photo.path,
        url: '',
        thumbnailUrl: photo.thumbnailUrl,
        size: photo.size,
        modifiedAt: hasValidTime ? photo.modifiedTime : null,
      ));
    }

    // 排序时将未知日期放到最后
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a == unknownDateKey) return 1;
        if (b == unknownDateKey) return -1;
        return b.compareTo(a);
      });

    return sortedKeys
        .map((date) => PhotoGroup(date: date, photos: groups[date]!))
        .toList();
  }

  PhotoListLoaded copyWith({
    List<PhotoFileWithSource>? photos,
    PhotoSortType? sortType,
    PhotoViewMode? viewMode,
    String? searchQuery,
    bool? fromCache,
  }) =>
      PhotoListLoaded(
        photos: photos ?? this.photos,
        sortType: sortType ?? this.sortType,
        viewMode: viewMode ?? this.viewMode,
        searchQuery: searchQuery ?? this.searchQuery,
        fromCache: fromCache ?? this.fromCache,
      );
}

class PhotoListError extends PhotoListState {
  PhotoListError(this.message);
  final String message;
}

class PhotoListNotConnected extends PhotoListState {}

class PhotoListNotifier extends StateNotifier<PhotoListState> {
  PhotoListNotifier(this._ref) : super(PhotoListLoading()) {
    _init();
  }

  final Ref _ref;
  final PhotoLibraryCacheService _cacheService = PhotoLibraryCacheService.instance;

  Future<void> _init() async {
    try {
      await _cacheService.init();
      await _loadFromCacheImmediately();

      // 监听连接状态变化
      _ref.listen<Map<String, SourceConnection>>(activeConnectionsProvider, (previous, next) {
        final prevConnected = previous?.values.where((c) => c.status == SourceStatus.connected).length ?? 0;
        final nextConnected = next.values.where((c) => c.status == SourceStatus.connected).length;

        if (nextConnected > prevConnected && state is PhotoListNotConnected) {
          loadPhotos();
        }
      });
    } catch (e) {
      logger.e('PhotoListNotifier: 初始化失败', e);
      state = PhotoListLoaded(photos: [], fromCache: false);
    }
  }

  /// 立即从缓存加载
  Future<void> _loadFromCacheImmediately() async {
    final cache = _cacheService.getCache();
    if (cache != null && cache.photos.isNotEmpty) {
      state = PhotoListLoading(fromCache: true, currentFolder: '加载缓存...');

      final photos = cache.photos.map((entry) {
        return PhotoFileWithSource(
          file: FileItem(
            name: entry.fileName,
            path: entry.filePath,
            size: entry.size,
            isDirectory: false,
            modifiedTime: entry.modifiedTime,
            thumbnailUrl: entry.thumbnailUrl,
          ),
          sourceId: entry.sourceId,
        );
      }).toList();

      state = PhotoListLoaded(photos: photos, fromCache: true);
      logger.i('从缓存加载了 ${photos.length} 张照片');
    } else {
      state = PhotoListLoaded(photos: [], fromCache: true);
    }
  }

  Future<void> loadPhotos({bool forceRefresh = false, int maxDepth = 3}) async {
    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    MediaLibraryConfig? config = configAsync.valueOrNull;
    if (config == null) {
      state = PhotoListLoading(progress: 0, currentFolder: '正在加载配置...');

      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final updated = _ref.read(mediaLibraryConfigProvider);
        config = updated.valueOrNull;
        if (config != null) break;

        if (updated.hasError) {
          state = PhotoListError('加载媒体库配置失败');
          return;
        }
      }

      if (config == null) {
        state = PhotoListLoaded(photos: []);
        return;
      }
    }

    final photoPaths = config.getEnabledPathsForType(MediaType.photo);

    if (photoPaths.isEmpty) {
      state = PhotoListLoaded(photos: []);
      return;
    }

    final connectedPaths = photoPaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      if (state is! PhotoListLoaded || (state as PhotoListLoaded).photos.isEmpty) {
        state = PhotoListNotConnected();
      }
      return;
    }

    final sourceIds = connectedPaths.map((p) => p.sourceId).toList();

    // 尝试使用缓存
    if (!forceRefresh && _cacheService.isCacheValid(sourceIds)) {
      final cache = _cacheService.getCache();
      if (cache != null) {
        state = PhotoListLoading(fromCache: true, currentFolder: '加载缓存...');

        final photos = cache.photos.map((entry) {
          return PhotoFileWithSource(
            file: FileItem(
              name: entry.fileName,
              path: entry.filePath,
              size: entry.size,
              isDirectory: false,
              modifiedTime: entry.modifiedTime,
              thumbnailUrl: entry.thumbnailUrl,
            ),
            sourceId: entry.sourceId,
          );
        }).toList();

        state = PhotoListLoaded(photos: photos, fromCache: true);
        logger.i('从缓存加载了 ${photos.length} 张照片');
        return;
      }
    }

    // 扫描文件系统
    state = PhotoListLoading();
    final photos = <PhotoFileWithSource>[];
    var scannedFolders = 0;
    final totalFolders = connectedPaths.length;
    var lastUpdateCount = 0;

    for (final mediaPath in connectedPaths) {
      final connection = connections[mediaPath.sourceId];
      if (connection == null) continue;

      final fileSystem = connection.adapter.fileSystem;
      state = PhotoListLoading(
        progress: scannedFolders / totalFolders,
        currentFolder: mediaPath.displayName,
        partialPhotos: List.from(photos),
        scannedCount: photos.length,
      );

      try {
        await _scanFolderRecursively(
          fileSystem,
          mediaPath.path,
          photos,
          sourceId: mediaPath.sourceId,
          currentDepth: 0,
          maxDepth: maxDepth,
          onBatchFound: () {
            if (photos.length - lastUpdateCount >= 20) {
              lastUpdateCount = photos.length;
              state = PhotoListLoading(
                progress: scannedFolders / totalFolders,
                currentFolder: mediaPath.displayName,
                partialPhotos: List.from(photos),
                scannedCount: photos.length,
              );
            }
          },
        );
      } on Exception catch (e) {
        logger.w('扫描文件夹失败: ${mediaPath.path} - $e');
      }

      scannedFolders++;

      state = PhotoListLoading(
        progress: scannedFolders / totalFolders,
        currentFolder: scannedFolders < totalFolders ? '继续扫描...' : '扫描完成',
        partialPhotos: List.from(photos),
        scannedCount: photos.length,
      );
    }

    logger.i('照片扫描完成，共找到 ${photos.length} 张照片');

    // 保存到缓存
    final cacheEntries = photos.map((p) => p.toCacheEntry()).toList();
    await _cacheService.saveCache(PhotoLibraryCache(
      photos: cacheEntries,
      lastUpdated: DateTime.now(),
      sourceIds: sourceIds,
    ));

    state = PhotoListLoaded(photos: photos);
  }

  Future<void> _scanFolderRecursively(
    NasFileSystem fileSystem,
    String path,
    List<PhotoFileWithSource> photos, {
    required String sourceId,
    required int currentDepth,
    required int maxDepth,
    VoidCallback? onBatchFound,
  }) async {
    if (currentDepth > maxDepth) return;

    try {
      final files = await fileSystem.listDirectory(path);

      for (final file in files) {
        if (file.type == FileType.image) {
          // 尝试获取缩略图 URL（使用 medium 尺寸以提高清晰度）
          String? thumbnailUrl = file.thumbnailUrl;
          if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
            try {
              thumbnailUrl = await fileSystem.getThumbnailUrl(
                file.path,
                size: ThumbnailSize.medium,
              );
            } catch (e) {
              // 忽略缩略图获取失败
            }
          }

          // 如果没有缩略图，尝试获取原图 URL
          if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
            try {
              thumbnailUrl = await fileSystem.getFileUrl(file.path);
            } catch (e) {
              // 忽略
            }
          }

          final fileWithThumbnail = FileItem(
            name: file.name,
            path: file.path,
            isDirectory: file.isDirectory,
            size: file.size,
            modifiedTime: file.modifiedTime,
            createdTime: file.createdTime,
            mimeType: file.mimeType,
            extension: file.extension,
            thumbnailUrl: thumbnailUrl,
            isHidden: file.isHidden,
            isReadOnly: file.isReadOnly,
          );

          photos.add(PhotoFileWithSource(file: fileWithThumbnail, sourceId: sourceId));
          onBatchFound?.call();
        } else if (file.isDirectory && currentDepth < maxDepth) {
          if (file.name.startsWith('.') ||
              file.name.startsWith('@') ||
              file.name == '#recycle') {
            continue;
          }

          await _scanFolderRecursively(
            fileSystem,
            file.path,
            photos,
            sourceId: sourceId,
            currentDepth: currentDepth + 1,
            maxDepth: maxDepth,
            onBatchFound: onBatchFound,
          );
        }
      }
    } on Exception catch (e) {
      logger.w('扫描子文件夹失败: $path - $e');
    }
  }

  void setSearchQuery(String query) {
    final current = state;
    if (current is PhotoListLoaded) {
      state = current.copyWith(searchQuery: query);
    }
  }

  void setSortType(PhotoSortType sortType) {
    final current = state;
    if (current is PhotoListLoaded) {
      state = current.copyWith(sortType: sortType);
    }
  }

  void toggleViewMode() {
    final current = state;
    if (current is PhotoListLoaded) {
      final nextMode = current.viewMode == PhotoViewMode.grid
          ? PhotoViewMode.timeline
          : PhotoViewMode.grid;
      state = current.copyWith(viewMode: nextMode);
    }
  }

  /// 强制刷新
  Future<void> forceRefresh() async {
    await _cacheService.clearCache();
    await loadPhotos(forceRefresh: true);
  }
}

class PhotoListPage extends ConsumerStatefulWidget {
  const PhotoListPage({super.key});

  @override
  ConsumerState<PhotoListPage> createState() => _PhotoListPageState();
}

class _PhotoListPageState extends ConsumerState<PhotoListPage> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 获取问候语
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 12) return '早上好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      body: Column(
        children: [
          _buildHeader(context, ref, isDark, state),
          Expanded(
            child: switch (state) {
              PhotoListLoading(
                :final progress,
                :final currentFolder,
                :final fromCache,
                :final partialPhotos,
                :final scannedCount,
              ) =>
                _buildLoadingState(
                  context,
                  progress,
                  currentFolder,
                  fromCache,
                  partialPhotos,
                  scannedCount,
                  isDark,
                ),
              PhotoListNotConnected() => _buildNotConnectedPrompt(context, isDark),
              PhotoListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(photoListProvider.notifier).loadPhotos(),
                ),
              PhotoListLoaded loaded => loaded.filteredPhotos.isEmpty
                  ? _buildEmptyState(context, ref, isDark)
                  : _buildPhotoContent(context, ref, loaded, isDark),
            },
          ),
        ],
      ),
    );
  }

  /// 构建顶部区域
  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    PhotoListState state,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF1A2E1A), AppColors.darkBackground]
              : [Colors.green.withValues(alpha: 0.08), Colors.grey[50]!],
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
              ? _buildSearchBar(context, ref, isDark)
              : _buildGreetingHeader(context, ref, isDark, state),
        ),
      ),
    );
  }

  /// 问候语头部
  Widget _buildGreetingHeader(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    PhotoListState state,
  ) {
    final photoCount = state is PhotoListLoaded ? state.photos.length : 0;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getGreeting(),
                style: context.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              if (photoCount > 0)
                Row(
                  children: [
                    Icon(
                      Icons.photo_library_rounded,
                      size: 14,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$photoCount 张照片',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        // 操作按钮
        _buildHeaderButton(
          icon: Icons.search_rounded,
          onTap: () => setState(() => _showSearch = true),
          isDark: isDark,
          tooltip: '搜索',
        ),
        const SizedBox(width: 8),
        if (state is PhotoListLoaded) ...[
          _buildHeaderButton(
            icon: state.viewMode == PhotoViewMode.grid
                ? Icons.view_timeline_rounded
                : Icons.grid_view_rounded,
            onTap: () => ref.read(photoListProvider.notifier).toggleViewMode(),
            isDark: isDark,
            tooltip: state.viewMode == PhotoViewMode.grid ? '时间线' : '网格',
          ),
          const SizedBox(width: 8),
        ],
        _buildHeaderButton(
          icon: Icons.refresh_rounded,
          onTap: () => ref.read(photoListProvider.notifier).forceRefresh(),
          isDark: isDark,
          tooltip: '刷新',
        ),
      ],
    );
  }

  /// 搜索栏
  Widget _buildSearchBar(BuildContext context, WidgetRef ref, bool isDark) {
    return Row(
      children: [
        IconButton(
          onPressed: () {
            setState(() => _showSearch = false);
            _searchController.clear();
            ref.read(photoListProvider.notifier).setSearchQuery('');
          },
          icon: Icon(
            Icons.arrow_back_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          tooltip: '返回',
        ),
        Expanded(
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 16,
            ),
            decoration: InputDecoration(
              hintText: '搜索照片...',
              hintStyle: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[400],
                fontSize: 16,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            onChanged: (value) {
              ref.read(photoListProvider.notifier).setSearchQuery(value);
            },
          ),
        ),
        if (_searchController.text.isNotEmpty)
          IconButton(
            onPressed: () {
              _searchController.clear();
              ref.read(photoListProvider.notifier).setSearchQuery('');
            },
            icon: Icon(
              Icons.close_rounded,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            tooltip: '清除',
          ),
      ],
    );
  }

  /// 头部按钮
  Widget _buildHeaderButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.grey[700]!.withValues(alpha: 0.5)
                    : Colors.grey[200]!,
              ),
            ),
            child: Icon(
              icon,
              color: isDark ? Colors.white : Colors.grey[700],
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(
    BuildContext context,
    double progress,
    String? currentFolder,
    bool fromCache,
    List<PhotoFileWithSource> partialPhotos,
    int scannedCount,
    bool isDark,
  ) {
    // 如果有部分结果，显示带进度条的网格视图
    if (partialPhotos.isNotEmpty && !fromCache) {
      final width = MediaQuery.of(context).size.width;
      final crossAxisCount = width > 600 ? 5 : 3;

      return Column(
        children: [
          // 扫描进度条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.grey[100],
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress > 0 ? progress : null,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '正在扫描... 已找到 $scannedCount 张照片',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (currentFolder != null)
                        Text(
                          currentFolder,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (progress > 0)
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
          // 部分结果网格
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: partialPhotos.length,
              itemBuilder: (context, index) {
                final photo = partialPhotos[index];
                final connections = ref.read(activeConnectionsProvider);
                final connection = connections[photo.sourceId];
                final fileSystem = connection?.adapter.fileSystem;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    StreamImage(
                      url: photo.thumbnailUrl,
                      path: photo.path,
                      fileSystem: fileSystem,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        child: Icon(
                          Icons.photo_rounded,
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                        ),
                      ),
                      errorWidget: Container(
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        child: Icon(
                          Icons.photo_rounded,
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                        ),
                      ),
                      cacheKey: photo.path,
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      );
    }

    // 没有部分结果时显示加载中心动画
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
            fromCache ? '加载缓存...' : '扫描照片中...',
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
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
  ) {
    // 获取缓存信息
    final cacheService = PhotoLibraryCacheService.instance;
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
                Icons.photo_library_rounded,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '照片库为空',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请在媒体库设置中配置照片目录并扫描',
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

  Widget _buildNotConnectedPrompt(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '未连接到 NAS',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请先在设置中配置并连接到 NAS 服务器',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          '添加连接',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoContent(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
    bool isDark,
  ) {
    return RefreshIndicator(
      onRefresh: () => ref.read(photoListProvider.notifier).forceRefresh(),
      child: CustomScrollView(
        slivers: [
          // 照片内容
          if (state.viewMode == PhotoViewMode.grid)
            _buildGridView(context, ref, state, isDark)
          else
            ..._buildTimelineView(context, ref, state, isDark),
        ],
      ),
    );
  }

  Widget _buildGridView(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
    bool isDark,
  ) {
    final photos = state.filteredPhotos;
    final crossAxisCount = context.isDesktop ? 6 : 3;

    return SliverPadding(
      padding: const EdgeInsets.all(4),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => AnimatedGridItem(
            index: index,
            delay: const Duration(milliseconds: 20),
            child: _PhotoGridItem(
              photo: photos[index],
              index: index,
              allPhotos: photos,
              isDark: isDark,
            ),
          ),
          childCount: photos.length,
        ),
      ),
    );
  }

  List<Widget> _buildTimelineView(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
    bool isDark,
  ) {
    final groups = state.groupedPhotos;
    final crossAxisCount = context.isDesktop ? 6 : 3;
    final slivers = <Widget>[];

    for (final group in groups) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.calendar_today_rounded,
                    color: AppColors.primary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  group.dateTitle,
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : null,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${group.photos.length} 张',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final photo = group.photos[index];
                final allPhotos = state.filteredPhotos;
                final globalIndex = allPhotos.indexWhere(
                  (p) => p.path == photo.path,
                );

                return AnimatedGridItem(
                  index: index,
                  delay: const Duration(milliseconds: 20),
                  child: _PhotoGridItem(
                    photo: allPhotos[globalIndex],
                    index: globalIndex,
                    allPhotos: allPhotos,
                    isDark: isDark,
                  ),
                );
              },
              childCount: group.photos.length,
            ),
          ),
        ),
      );
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 16)));
    return slivers;
  }
}

class _PhotoGridItem extends ConsumerWidget {
  const _PhotoGridItem({
    required this.photo,
    required this.index,
    required this.allPhotos,
    required this.isDark,
  });

  final PhotoFileWithSource photo;
  final int index;
  final List<PhotoFileWithSource> allPhotos;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 获取文件系统用于流式加载
    final connections = ref.watch(activeConnectionsProvider);
    final connection = connections[photo.sourceId];
    final fileSystem = connection?.adapter.fileSystem;

    return Material(
      color: isDark
          ? AppColors.darkSurfaceElevated
          : context.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () {
          debugPrint('PhotoGridItem: onTap called for ${photo.name}');
          _openPhotoViewer(context, ref);
        },
        child: StreamImage(
          url: photo.thumbnailUrl,
          path: photo.path,
          fileSystem: fileSystem,
          fit: BoxFit.cover,
          placeholder: _buildPlaceholder(),
          errorWidget: _buildPlaceholder(),
          cacheKey: photo.path,
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: 32,
        color: AppColors.fileImage.withValues(alpha: 0.5),
      ),
    );
  }

  Future<void> _openPhotoViewer(BuildContext context, WidgetRef ref) async {
    debugPrint('PhotoViewer: _openPhotoViewer called');
    debugPrint('PhotoViewer: photo.sourceId = ${photo.sourceId}');

    final connections = ref.read(activeConnectionsProvider);
    debugPrint('PhotoViewer: connections count = ${connections.length}');
    debugPrint('PhotoViewer: connections keys = ${connections.keys.toList()}');

    final connection = connections[photo.sourceId];
    if (connection == null) {
      debugPrint('PhotoViewer: connection is null for sourceId=${photo.sourceId}');
      return;
    }
    debugPrint('PhotoViewer: connection found');

    // 获取当前点击照片的原图 URL
    String currentUrl;
    try {
      currentUrl = await connection.adapter.fileSystem.getFileUrl(photo.path);
      debugPrint('PhotoViewer: got currentUrl = $currentUrl');
    } catch (e) {
      debugPrint('PhotoViewer: failed to get url: $e');
      // 如果获取失败，留空，让查看器去获取
      currentUrl = '';
    }

    // 构建照片列表
    // 当前照片使用原图 URL，其他照片 url 留空，懒加载时再获取
    final photoItems = allPhotos.map((p) {
      final isCurrentPhoto = p.path == photo.path;
      return PhotoItem(
        name: p.name,
        path: p.path,
        // 当前照片使用原图 URL，其他照片 url 为空
        url: isCurrentPhoto ? currentUrl : '',
        sourceId: p.sourceId,
        thumbnailUrl: p.thumbnailUrl,
        size: p.size,
        modifiedAt: p.modifiedTime,
      );
    }).toList();
    debugPrint('PhotoViewer: photoItems count = ${photoItems.length}');

    if (!context.mounted) {
      debugPrint('PhotoViewer: context not mounted');
      return;
    }

    // 使用 rootNavigatorKey 确保全屏显示，不受 ShellRoute 影响
    final navigator = rootNavigatorKey.currentState;
    debugPrint('PhotoViewer: rootNavigatorKey.currentState = $navigator');
    if (navigator == null) {
      debugPrint('PhotoViewer: rootNavigatorKey.currentState is null, trying Navigator.of');
      // 尝试使用 Navigator.of 作为后备方案
      if (context.mounted) {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (ctx) => PhotoViewerPage(
              photos: photoItems,
              initialIndex: index,
              getPhotoUrl: (path, sourceId) async {
                final conn = connections[sourceId];
                if (conn == null) return null;
                try {
                  return await conn.adapter.fileSystem.getFileUrl(path);
                } catch (e) {
                  debugPrint('PhotoViewer: 获取URL失败 path=$path, error=$e');
                  return null;
                }
              },
              getFileSystem: (sourceId) {
                final conn = connections[sourceId];
                return conn?.adapter.fileSystem;
              },
            ),
          ),
        );
      }
      return;
    }

    debugPrint('PhotoViewer: pushing route');
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (ctx) => PhotoViewerPage(
          photos: photoItems,
          initialIndex: index,
          getPhotoUrl: (path, sourceId) async {
            final conn = connections[sourceId];
            if (conn == null) {
              return null;
            }
            try {
              return await conn.adapter.fileSystem.getFileUrl(path);
            } catch (e) {
              debugPrint('PhotoViewer: 获取URL失败 path=$path, error=$e');
              return null;
            }
          },
          getFileSystem: (sourceId) {
            final conn = connections[sourceId];
            return conn?.adapter.fileSystem;
          },
        ),
      ),
    );
    debugPrint('PhotoViewer: route pushed successfully');
  }
}
