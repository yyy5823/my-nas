import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/photo/domain/entities/photo_item.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_viewer_page.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/empty_widget.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';

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
  PhotoListLoading({this.progress = 0, this.currentFolder});
  final double progress;
  final String? currentFolder;
}

class PhotoListLoaded extends PhotoListState {
  PhotoListLoaded({
    required this.photos,
    this.sortType = PhotoSortType.date,
    this.viewMode = PhotoViewMode.grid,
    this.searchQuery = '',
  });

  final List<PhotoFileWithSource> photos;
  final PhotoSortType sortType;
  final PhotoViewMode viewMode;
  final String searchQuery;

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

    for (final photo in filtered) {
      final date = photo.modifiedTime ?? DateTime(1970);
      final dateKey = DateTime(date.year, date.month, date.day);

      groups.putIfAbsent(dateKey, () => []);
      groups[dateKey]!.add(PhotoItem(
        name: photo.name,
        path: photo.path,
        url: '', // URL 将在查看时获取
        thumbnailUrl: photo.thumbnailUrl,
        size: photo.size,
        modifiedAt: photo.modifiedTime,
      ));
    }

    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return sortedKeys
        .map((date) => PhotoGroup(date: date, photos: groups[date]!))
        .toList();
  }

  PhotoListLoaded copyWith({
    List<PhotoFileWithSource>? photos,
    PhotoSortType? sortType,
    PhotoViewMode? viewMode,
    String? searchQuery,
  }) =>
      PhotoListLoaded(
        photos: photos ?? this.photos,
        sortType: sortType ?? this.sortType,
        viewMode: viewMode ?? this.viewMode,
        searchQuery: searchQuery ?? this.searchQuery,
      );
}

class PhotoListError extends PhotoListState {
  PhotoListError(this.message);
  final String message;
}

class PhotoListNotConnected extends PhotoListState {}

class PhotoListNotifier extends StateNotifier<PhotoListState> {
  PhotoListNotifier(this._ref) : super(PhotoListLoading()) {
    loadPhotos();

    // 监听连接状态变化，自动刷新
    _ref.listen<Map<String, SourceConnection>>(activeConnectionsProvider, (previous, next) {
      // 检查是否有新的连接建立
      final prevConnected = previous?.values.where((c) => c.status == SourceStatus.connected).length ?? 0;
      final nextConnected = next.values.where((c) => c.status == SourceStatus.connected).length;

      // 如果连接数增加，且当前状态是未连接，则重新加载
      if (nextConnected > prevConnected && state is PhotoListNotConnected) {
        loadPhotos();
      }
    });
  }

  final Ref _ref;
  int _scannedFolders = 0;
  int _totalFolders = 0;

  Future<void> loadPhotos({int maxDepth = 3}) async {
    state = PhotoListLoading();
    _scannedFolders = 0;
    _totalFolders = 0;

    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    // 等待配置加载完成
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

    // 获取已启用的照片路径
    final photoPaths = config.getEnabledPathsForType(MediaType.photo);

    if (photoPaths.isEmpty) {
      state = PhotoListLoaded(photos: []);
      return;
    }

    // 过滤出已连接的路径
    final connectedPaths = photoPaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      state = PhotoListNotConnected();
      return;
    }

    _totalFolders = connectedPaths.length;

    try {
      final photos = <PhotoFileWithSource>[];

      for (final mediaPath in connectedPaths) {
        final connection = connections[mediaPath.sourceId];
        if (connection == null) continue;

        final fileSystem = connection.adapter.fileSystem;
        state = PhotoListLoading(
          progress: _scannedFolders / _totalFolders,
          currentFolder: mediaPath.displayName,
        );

        try {
          await _scanFolderRecursively(
            fileSystem,
            mediaPath.path,
            photos,
            sourceId: mediaPath.sourceId,
            currentDepth: 0,
            maxDepth: maxDepth,
          );
        } on Exception catch (e) {
          logger.w('扫描文件夹失败: ${mediaPath.path} - $e');
        }

        _scannedFolders++;
      }

      logger.i('照片扫描完成，共找到 ${photos.length} 张照片');
      state = PhotoListLoaded(photos: photos);
    } on Exception catch (e) {
      state = PhotoListError(e.toString());
    }
  }

  Future<void> _scanFolderRecursively(
    NasFileSystem fileSystem,
    String path,
    List<PhotoFileWithSource> photos, {
    required String sourceId,
    required int currentDepth,
    required int maxDepth,
  }) async {
    if (currentDepth > maxDepth) return;

    try {
      final files = await fileSystem.listDirectory(path);

      for (final file in files) {
        if (file.type == FileType.image) {
          // 尝试获取缩略图 URL
          String? thumbnailUrl = file.thumbnailUrl;
          if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
            try {
              thumbnailUrl = await fileSystem.getThumbnailUrl(file.path);
            } catch (e) {
              // 忽略缩略图获取失败
            }
          }

          // 如果还是没有缩略图，使用文件下载 URL 作为备用
          if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
            try {
              thumbnailUrl = await fileSystem.getFileUrl(file.path);
            } catch (e) {
              // 忽略
            }
          }

          // 创建一个新的 FileItem，包含缩略图 URL
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
        } else if (file.isDirectory && currentDepth < maxDepth) {
          // 跳过隐藏文件夹和系统文件夹
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          _buildAppBar(context, ref, isDark, state),
          Expanded(
            child: switch (state) {
              PhotoListLoading(:final progress, :final currentFolder) =>
                _buildLoadingState(progress, currentFolder),
              PhotoListNotConnected() => _buildNotConnectedPrompt(context, isDark),
              PhotoListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(photoListProvider.notifier).loadPhotos(),
                ),
              PhotoListLoaded loaded => loaded.filteredPhotos.isEmpty
                  ? const EmptyWidget(
                      icon: Icons.photo_library_outlined,
                      title: '暂无照片',
                      message: '在 NAS 中添加照片后将显示在这里',
                    )
                  : _buildPhotoContent(context, ref, loaded, isDark),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    PhotoListState state,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withOpacity(0.2)
                : context.colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (!_showSearch) ...[
                Text(
                  '照片',
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : null,
                  ),
                ),
                if (state is PhotoListLoaded)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${state.filteredPhotos.length}',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
              if (_showSearch)
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '搜索照片...',
                      hintStyle: TextStyle(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : context.colorScheme.onSurfaceVariant,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: TextStyle(
                      color: isDark ? AppColors.darkOnSurface : null,
                    ),
                    onChanged: (value) {
                      ref.read(photoListProvider.notifier).setSearchQuery(value);
                    },
                  ),
                ),
              const Spacer(),
              // 搜索按钮
              _buildIconButton(
                icon: _showSearch ? Icons.close : Icons.search_rounded,
                onTap: () {
                  setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) {
                      _searchController.clear();
                      ref.read(photoListProvider.notifier).setSearchQuery('');
                    }
                  });
                },
                isDark: isDark,
                tooltip: _showSearch ? '关闭' : '搜索',
              ),
              // 视图切换
              if (state is PhotoListLoaded)
                _buildIconButton(
                  icon: state.viewMode == PhotoViewMode.grid
                      ? Icons.view_timeline_rounded
                      : Icons.grid_view_rounded,
                  onTap: () =>
                      ref.read(photoListProvider.notifier).toggleViewMode(),
                  isDark: isDark,
                  tooltip: state.viewMode == PhotoViewMode.grid
                      ? '切换到时间线'
                      : '切换到网格',
                ),
              // 排序
              if (state is PhotoListLoaded)
                PopupMenuButton<PhotoSortType>(
                  icon: Icon(
                    Icons.sort_rounded,
                    color: isDark ? AppColors.darkOnSurfaceVariant : null,
                  ),
                  tooltip: '排序',
                  onSelected: (type) =>
                      ref.read(photoListProvider.notifier).setSortType(type),
                  itemBuilder: (context) => [
                    _buildSortMenuItem(
                      context,
                      PhotoSortType.date,
                      '按日期',
                      Icons.calendar_today_rounded,
                      state.sortType,
                      isDark,
                    ),
                    _buildSortMenuItem(
                      context,
                      PhotoSortType.name,
                      '按名称',
                      Icons.sort_by_alpha_rounded,
                      state.sortType,
                      isDark,
                    ),
                    _buildSortMenuItem(
                      context,
                      PhotoSortType.size,
                      '按大小',
                      Icons.straighten_rounded,
                      state.sortType,
                      isDark,
                    ),
                  ],
                ),
              // 刷新
              _buildIconButton(
                icon: Icons.refresh_rounded,
                onTap: () => ref.read(photoListProvider.notifier).loadPhotos(),
                isDark: isDark,
                tooltip: '刷新',
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<PhotoSortType> _buildSortMenuItem(
    BuildContext context,
    PhotoSortType type,
    String label,
    IconData icon,
    PhotoSortType current,
    bool isDark,
  ) {
    final isSelected = type == current;
    return PopupMenuItem(
      value: type,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isSelected
                ? AppColors.primary
                : (isDark ? AppColors.darkOnSurface : null),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.darkOnSurface : null),
              fontWeight: isSelected ? FontWeight.w600 : null,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            Icon(Icons.check, size: 18, color: AppColors.primary),
          ],
        ],
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
            '扫描照片中...',
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
      onRefresh: () => ref.read(photoListProvider.notifier).loadPhotos(),
      child: state.viewMode == PhotoViewMode.grid
          ? _buildGridView(context, ref, state, isDark)
          : _buildTimelineView(context, ref, state, isDark),
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

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) => _PhotoGridItem(
        photo: photos[index],
        index: index,
        allPhotos: photos,
        isDark: isDark,
      ),
    );
  }

  Widget _buildTimelineView(
    BuildContext context,
    WidgetRef ref,
    PhotoListLoaded state,
    bool isDark,
  ) {
    final groups = state.groupedPhotos;
    final crossAxisCount = context.isDesktop ? 6 : 3;

    return CustomScrollView(
      slivers: [
        for (final group in groups) ...[
          // 日期标题
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
          // 照片网格
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
                  // 找到在完整列表中的索引
                  final allPhotos = state.filteredPhotos;
                  final globalIndex = allPhotos.indexWhere(
                    (p) => p.path == photo.path,
                  );

                  return _PhotoGridItem(
                    photo: allPhotos[globalIndex],
                    index: globalIndex,
                    allPhotos: allPhotos,
                    isDark: isDark,
                  );
                },
                childCount: group.photos.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
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
    return GestureDetector(
      onTap: () => _openPhotoViewer(context, ref),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceElevated
              : context.colorScheme.surfaceContainerHighest,
        ),
        child: photo.thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: photo.thumbnailUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => _buildPlaceholder(),
                errorWidget: (context, url, error) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: 32,
        color: AppColors.fileImage.withOpacity(0.5),
      ),
    );
  }

  Future<void> _openPhotoViewer(BuildContext context, WidgetRef ref) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[photo.sourceId];
    if (connection == null) return;

    // 准备所有照片的 PhotoItem 列表
    final photoItems = <PhotoItem>[];
    for (final p in allPhotos) {
      final conn = connections[p.sourceId];
      if (conn == null) continue;

      String url;
      try {
        url = await conn.adapter.fileSystem.getFileUrl(p.path);
      } catch (e) {
        url = '';
      }

      photoItems.add(PhotoItem.fromFileItem(
        p.file,
        url,
        thumbnailUrl: p.thumbnailUrl,
      ));
    }

    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PhotoViewerPage(
          photos: photoItems,
          initialIndex: index,
        ),
      ),
    );
  }
}
