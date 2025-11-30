import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_detail_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_page.dart';
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/poster_wall.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/empty_widget.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/loading_widget.dart';

/// 视频文件及其来源
class VideoFileWithSource {
  VideoFileWithSource({
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
  String get displaySize => file.displaySize;
}

/// 视频列表状态
final videoListProvider =
    StateNotifierProvider<VideoListNotifier, VideoListState>((ref) {
  return VideoListNotifier(ref);
});

/// 视频排序方式
enum VideoSortType { name, date, size, rating }

/// 视频视图模式
enum VideoViewMode { poster, grid, list }

sealed class VideoListState {}

class VideoListLoading extends VideoListState {
  VideoListLoading({this.progress = 0, this.currentFolder});
  final double progress;
  final String? currentFolder;
}

class VideoListLoaded extends VideoListState {
  VideoListLoaded({
    required this.videos,
    this.sortType = VideoSortType.name,
    this.viewMode = VideoViewMode.poster,
    this.searchQuery = '',
    this.metadataMap = const {},
    this.isLoadingMetadata = false,
    this.metadataProgress = 0,
  });

  final List<VideoFileWithSource> videos;
  final VideoSortType sortType;
  final VideoViewMode viewMode;
  final String searchQuery;
  final Map<String, VideoMetadata> metadataMap;
  final bool isLoadingMetadata;
  final double metadataProgress;

  List<VideoFileWithSource> get filteredVideos {
    var result = List<VideoFileWithSource>.from(videos);

    // 搜索过滤
    if (searchQuery.isNotEmpty) {
      result = result
          .where((v) {
            final metadata = metadataMap['${v.sourceId}_${v.path}'];
            final title = metadata?.title ?? v.name;
            return title.toLowerCase().contains(searchQuery.toLowerCase());
          })
          .toList();
    }

    // 排序
    switch (sortType) {
      case VideoSortType.name:
        result.sort((a, b) {
          final metaA = metadataMap['${a.sourceId}_${a.path}'];
          final metaB = metadataMap['${b.sourceId}_${b.path}'];
          final titleA = metaA?.title ?? a.name;
          final titleB = metaB?.title ?? b.name;
          return titleA.compareTo(titleB);
        });
      case VideoSortType.date:
        result.sort((a, b) => (b.modifiedTime ?? DateTime(1970))
            .compareTo(a.modifiedTime ?? DateTime(1970)));
      case VideoSortType.size:
        result.sort((a, b) => b.size.compareTo(a.size));
      case VideoSortType.rating:
        result.sort((a, b) {
          final metaA = metadataMap['${a.sourceId}_${a.path}'];
          final metaB = metadataMap['${b.sourceId}_${b.path}'];
          final ratingA = metaA?.rating ?? 0;
          final ratingB = metaB?.rating ?? 0;
          return ratingB.compareTo(ratingA);
        });
    }

    return result;
  }

  /// 获取过滤后的元数据列表
  List<VideoMetadata> get filteredMetadata {
    return filteredVideos
        .map((v) => metadataMap['${v.sourceId}_${v.path}'])
        .whereType<VideoMetadata>()
        .toList();
  }

  VideoListLoaded copyWith({
    List<VideoFileWithSource>? videos,
    VideoSortType? sortType,
    VideoViewMode? viewMode,
    String? searchQuery,
    Map<String, VideoMetadata>? metadataMap,
    bool? isLoadingMetadata,
    double? metadataProgress,
  }) =>
      VideoListLoaded(
        videos: videos ?? this.videos,
        sortType: sortType ?? this.sortType,
        viewMode: viewMode ?? this.viewMode,
        searchQuery: searchQuery ?? this.searchQuery,
        metadataMap: metadataMap ?? this.metadataMap,
        isLoadingMetadata: isLoadingMetadata ?? this.isLoadingMetadata,
        metadataProgress: metadataProgress ?? this.metadataProgress,
      );
}

class VideoListError extends VideoListState {
  VideoListError(this.message);
  final String message;
}

class VideoListNotifier extends StateNotifier<VideoListState> {
  VideoListNotifier(this._ref) : super(VideoListLoading()) {
    _initMetadataService();
    loadVideos();
  }

  final Ref _ref;
  int _scannedFolders = 0;
  int _totalFolders = 0;
  final VideoMetadataService _metadataService = VideoMetadataService.instance;

  Future<void> _initMetadataService() async {
    await _metadataService.init();
  }

  Future<void> loadVideos({int maxDepth = 3}) async {
    state = VideoListLoading();
    _scannedFolders = 0;
    _totalFolders = 0;

    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    // 等待配置加载
    final config = configAsync.valueOrNull;
    if (config == null) {
      state = VideoListError('媒体库配置加载中...');
      return;
    }

    // 获取已启用的视频路径
    final videoPaths = config.getEnabledPathsForType(MediaType.video);

    if (videoPaths.isEmpty) {
      // 如果没有配置视频目录，提示用户配置
      state = VideoListLoaded(videos: []);
      return;
    }

    // 过滤出已连接的路径
    final connectedPaths = videoPaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      state = VideoListError('没有已连接的源');
      return;
    }

    _totalFolders = connectedPaths.length;

    try {
      final videos = <VideoFileWithSource>[];

      for (final mediaPath in connectedPaths) {
        final connection = connections[mediaPath.sourceId];
        if (connection == null) continue;

        final fileSystem = connection.adapter.fileSystem;
        state = VideoListLoading(
          progress: _scannedFolders / _totalFolders,
          currentFolder: mediaPath.displayName,
        );

        try {
          await _scanFolderRecursively(
            fileSystem,
            mediaPath.path,
            videos,
            sourceId: mediaPath.sourceId,
            currentDepth: 0,
            maxDepth: maxDepth,
          );
        } on Exception catch (e) {
          logger.w('扫描文件夹失败: ${mediaPath.path} - $e');
        }

        _scannedFolders++;
      }

      logger.i('视频扫描完成，共找到 ${videos.length} 个视频');

      // 加载缓存的元数据
      final metadataMap = <String, VideoMetadata>{};
      for (final video in videos) {
        final cached = _metadataService.getCached(video.sourceId, video.path);
        if (cached != null) {
          metadataMap[cached.uniqueKey] = cached;
        }
      }

      state = VideoListLoaded(videos: videos, metadataMap: metadataMap);

      // 后台加载未缓存的元数据
      _loadMissingMetadata(videos);
    } on Exception catch (e) {
      state = VideoListError(e.toString());
    }
  }

  /// 后台加载缺失的元数据
  Future<void> _loadMissingMetadata(List<VideoFileWithSource> videos) async {
    final current = state;
    if (current is! VideoListLoaded) return;

    // 找出没有元数据的视频
    final missingVideos = videos.where((v) {
      final key = '${v.sourceId}_${v.path}';
      return !current.metadataMap.containsKey(key);
    }).toList();

    if (missingVideos.isEmpty) return;

    state = current.copyWith(isLoadingMetadata: true, metadataProgress: 0);

    final updatedMap = Map<String, VideoMetadata>.from(current.metadataMap);
    final total = missingVideos.length;

    for (var i = 0; i < missingVideos.length; i++) {
      final video = missingVideos[i];

      try {
        final metadata = await _metadataService.getOrFetch(
          sourceId: video.sourceId,
          filePath: video.path,
          fileName: video.name,
        );
        updatedMap[metadata.uniqueKey] = metadata;

        // 每处理5个或最后一个时更新状态
        if ((i + 1) % 5 == 0 || i == missingVideos.length - 1) {
          final currentState = state;
          if (currentState is VideoListLoaded) {
            state = currentState.copyWith(
              metadataMap: Map.from(updatedMap),
              metadataProgress: (i + 1) / total,
            );
          }
        }
      } on Exception catch (e) {
        logger.w('获取元数据失败: ${video.name} - $e');
      }

      // 添加延迟避免 API 限制
      if (i < missingVideos.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    final finalState = state;
    if (finalState is VideoListLoaded) {
      state = finalState.copyWith(isLoadingMetadata: false);
    }
  }

  /// 刷新元数据
  Future<void> refreshMetadata() async {
    final current = state;
    if (current is! VideoListLoaded) return;

    state = current.copyWith(isLoadingMetadata: true, metadataProgress: 0);

    final videos = current.videos;
    final updatedMap = <String, VideoMetadata>{};
    final total = videos.length;

    for (var i = 0; i < videos.length; i++) {
      final video = videos[i];

      try {
        final metadata = await _metadataService.getOrFetch(
          sourceId: video.sourceId,
          filePath: video.path,
          fileName: video.name,
          forceRefresh: true,
        );
        updatedMap[metadata.uniqueKey] = metadata;

        if ((i + 1) % 5 == 0 || i == videos.length - 1) {
          final currentState = state;
          if (currentState is VideoListLoaded) {
            state = currentState.copyWith(
              metadataMap: Map.from(updatedMap),
              metadataProgress: (i + 1) / total,
            );
          }
        }
      } on Exception catch (e) {
        logger.w('刷新元数据失败: ${video.name} - $e');
      }

      if (i < videos.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    final finalState = state;
    if (finalState is VideoListLoaded) {
      state = finalState.copyWith(isLoadingMetadata: false);
    }
  }

  Future<void> _scanFolderRecursively(
    NasFileSystem fileSystem,
    String path,
    List<VideoFileWithSource> videos, {
    required String sourceId,
    required int currentDepth,
    required int maxDepth,
  }) async {
    if (currentDepth > maxDepth) return;

    try {
      final files = await fileSystem.listDirectory(path);

      for (final file in files) {
        if (file.type == FileType.video) {
          videos.add(VideoFileWithSource(file: file, sourceId: sourceId));
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
            videos,
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
    if (current is VideoListLoaded) {
      state = current.copyWith(searchQuery: query);
    }
  }

  void setSortType(VideoSortType sortType) {
    final current = state;
    if (current is VideoListLoaded) {
      state = current.copyWith(sortType: sortType);
    }
  }

  void toggleViewMode() {
    final current = state;
    if (current is VideoListLoaded) {
      final nextMode = switch (current.viewMode) {
        VideoViewMode.poster => VideoViewMode.grid,
        VideoViewMode.grid => VideoViewMode.list,
        VideoViewMode.list => VideoViewMode.poster,
      };
      state = current.copyWith(viewMode: nextMode);
    }
  }

  void setViewMode(VideoViewMode mode) {
    final current = state;
    if (current is VideoListLoaded) {
      state = current.copyWith(viewMode: mode);
    }
  }
}

class VideoListPage extends ConsumerStatefulWidget {
  const VideoListPage({super.key});

  @override
  ConsumerState<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends ConsumerState<VideoListPage> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          _buildAppBar(context, ref, isDark, state),
          Expanded(
            child: switch (state) {
              VideoListLoading(:final progress, :final currentFolder) =>
                _buildLoadingState(progress, currentFolder),
              VideoListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(videoListProvider.notifier).loadVideos(),
                ),
              VideoListLoaded loaded =>
                loaded.filteredVideos.isEmpty
                    ? const EmptyWidget(
                        icon: Icons.video_library_outlined,
                        title: '暂无视频',
                        message: '在 NAS 中添加视频后将显示在这里',
                      )
                    : _buildVideoContent(context, ref, loaded.filteredVideos, loaded.viewMode, isDark, loaded),
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
    VideoListState state,
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  if (!_showSearch) ...[
                    Text(
                      '视频',
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : null,
                      ),
                    ),
                    if (state is VideoListLoaded)
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
                          '${state.filteredVideos.length}',
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
                          hintText: '搜索视频...',
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
                          ref.read(videoListProvider.notifier).setSearchQuery(value);
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
                          ref.read(videoListProvider.notifier).setSearchQuery('');
                        }
                      });
                    },
                    isDark: isDark,
                    tooltip: _showSearch ? '关闭' : '搜索',
                  ),
                  // 视图切换
                  if (state is VideoListLoaded)
                    _buildIconButton(
                      icon: switch (state.viewMode) {
                        VideoViewMode.poster => Icons.grid_view_rounded,
                        VideoViewMode.grid => Icons.view_list_rounded,
                        VideoViewMode.list => Icons.photo_library_rounded,
                      },
                      onTap: () =>
                          ref.read(videoListProvider.notifier).toggleViewMode(),
                      isDark: isDark,
                      tooltip: switch (state.viewMode) {
                        VideoViewMode.poster => '切换到网格视图',
                        VideoViewMode.grid => '切换到列表视图',
                        VideoViewMode.list => '切换到海报墙',
                      },
                    ),
                  // 排序
                  if (state is VideoListLoaded)
                    PopupMenuButton<VideoSortType>(
                      icon: Icon(
                        Icons.sort_rounded,
                        color: isDark ? AppColors.darkOnSurfaceVariant : null,
                      ),
                      tooltip: '排序',
                      onSelected: (type) =>
                          ref.read(videoListProvider.notifier).setSortType(type),
                      itemBuilder: (context) => [
                        _buildSortMenuItem(
                          context,
                          VideoSortType.name,
                          '按名称',
                          Icons.sort_by_alpha_rounded,
                          state.sortType,
                          isDark,
                        ),
                        _buildSortMenuItem(
                          context,
                          VideoSortType.date,
                          '按日期',
                          Icons.calendar_today_rounded,
                          state.sortType,
                          isDark,
                        ),
                        _buildSortMenuItem(
                          context,
                          VideoSortType.size,
                          '按大小',
                          Icons.straighten_rounded,
                          state.sortType,
                          isDark,
                        ),
                        _buildSortMenuItem(
                          context,
                          VideoSortType.rating,
                          '按评分',
                          Icons.star_rounded,
                          state.sortType,
                          isDark,
                        ),
                      ],
                    ),
                  // 刷新
                  _buildIconButton(
                    icon: Icons.refresh_rounded,
                    onTap: () => ref.read(videoListProvider.notifier).loadVideos(),
                    isDark: isDark,
                    tooltip: '刷新',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<VideoSortType> _buildSortMenuItem(
    BuildContext context,
    VideoSortType type,
    String label,
    IconData icon,
    VideoSortType current,
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
          Text(
            '扫描视频中...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (currentFolder != null) ...[
            const SizedBox(height: 8),
            Text(
              currentFolder,
              style: TextStyle(
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

  Widget _buildVideoContent(
    BuildContext context,
    WidgetRef ref,
    List<VideoFileWithSource> videos,
    VideoViewMode viewMode,
    bool isDark,
    VideoListLoaded state,
  ) {
    return RefreshIndicator(
      onRefresh: () => ref.read(videoListProvider.notifier).loadVideos(),
      child: CustomScrollView(
        slivers: [
          // 继续观看区域
          _ContinueWatchingSection(isDark: isDark),

          // 元数据加载进度
          if (state.isLoadingMetadata)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: state.metadataProgress > 0 ? state.metadataProgress : null,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '正在获取影片信息... ${(state.metadataProgress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 视频列表
          if (viewMode == VideoViewMode.poster)
            _buildPosterWall(context, ref, videos, state, isDark)
          else if (viewMode == VideoViewMode.grid)
            SliverPadding(
              padding: AppSpacing.paddingMd,
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: context.isDesktop ? 300 : 200,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 16 / 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _VideoCard(
                    video: videos[index],
                    isDark: isDark,
                  ),
                  childCount: videos.length,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _VideoListTile(
                    video: videos[index],
                    isDark: isDark,
                  ),
                  childCount: videos.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPosterWall(
    BuildContext context,
    WidgetRef ref,
    List<VideoFileWithSource> videos,
    VideoListLoaded state,
    bool isDark,
  ) {
    // 为每个视频创建或获取元数据
    final metadataList = videos.map((video) {
      final key = '${video.sourceId}_${video.path}';
      return state.metadataMap[key] ??
          VideoMetadata(
            filePath: video.path,
            sourceId: video.sourceId,
            fileName: video.name,
          );
    }).toList();

    return SliverPosterWall(
      items: metadataList,
      onItemTap: (metadata) => _openVideoDetail(context, ref, metadata),
      onItemLongPress: (metadata) => _playVideoDirectly(context, ref, metadata),
    );
  }

  Future<void> _openVideoDetail(
    BuildContext context,
    WidgetRef ref,
    VideoMetadata metadata,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoDetailPage(
          metadata: metadata,
          sourceId: metadata.sourceId,
        ),
      ),
    );
    ref.invalidate(continueWatchingProvider);
  }

  Future<void> _playVideoDirectly(
    BuildContext context,
    WidgetRef ref,
    VideoMetadata metadata,
  ) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[metadata.sourceId];
    if (connection == null) return;

    final url = await connection.adapter.fileSystem.getFileUrl(metadata.filePath);

    if (!context.mounted) return;

    final videoItem = VideoItem(
      name: metadata.displayTitle,
      path: metadata.filePath,
      url: url,
      size: 0,
    );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoPlayerPage(video: videoItem),
      ),
    );

    ref.invalidate(continueWatchingProvider);
  }
}

/// 继续观看区域
class _ContinueWatchingSection extends ConsumerWidget {
  const _ContinueWatchingSection({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final continueWatchingAsync = ref.watch(continueWatchingProvider);

    return continueWatchingAsync.when(
      data: (items) {
        if (items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

        return SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.history_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '继续观看',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : null,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        // TODO: 查看全部历史
                      },
                      child: Text(
                        '查看全部',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 160,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _ContinueWatchingCard(
                    item: items[index],
                    isDark: isDark,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: isDark
                    ? AppColors.darkOutline.withOpacity(0.2)
                    : Colors.grey.withOpacity(0.2),
              ),
            ],
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

/// 继续观看卡片
class _ContinueWatchingCard extends ConsumerWidget {
  const _ContinueWatchingCard({
    required this.item,
    required this.isDark,
  });

  final VideoHistoryItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playVideo(context, ref),
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 缩略图
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceElevated
                        : context.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkOutline.withOpacity(0.2)
                          : context.colorScheme.outlineVariant.withOpacity(0.5),
                    ),
                  ),
                  child: Stack(
                    children: [
                      // 缩略图或占位符
                      Center(
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppColors.fileVideo.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_circle_rounded,
                            size: 28,
                            color: AppColors.fileVideo,
                          ),
                        ),
                      ),
                      // 进度条
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 4,
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: item.progressPercent.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 标题
              Text(
                item.videoName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.darkOnSurface : null,
                ),
              ),
              // 进度信息
              if (item.lastPosition != null && item.duration != null)
                Text(
                  '${_formatDuration(item.lastPosition!)} / ${_formatDuration(item.duration!)}',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _playVideo(BuildContext context, WidgetRef ref) async {
    // 直接使用历史记录中保存的 URL 播放视频
    final videoItem = VideoItem(
      name: item.videoName,
      path: item.videoPath,
      url: item.videoUrl,
      size: item.size,
      thumbnailUrl: item.thumbnailUrl,
      lastPosition: item.lastPosition,
    );

    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoPlayerPage(video: videoItem),
      ),
    );

    // 刷新继续观看列表
    ref.invalidate(continueWatchingProvider);
  }
}

class _VideoCard extends ConsumerWidget {
  const _VideoCard({
    required this.video,
    required this.isDark,
  });

  final VideoFileWithSource video;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceVariant.withOpacity(0.3)
              : context.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? AppColors.darkOutline.withOpacity(0.2)
                : context.colorScheme.outlineVariant.withOpacity(0.5),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _playVideo(context, ref),
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 缩略图
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: Container(
                      color: isDark
                          ? AppColors.darkSurfaceElevated
                          : context.colorScheme.surfaceContainerHighest,
                      child: video.thumbnailUrl != null
                          ? Image.network(
                              video.thumbnailUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildPlaceholder(),
                            )
                          : _buildPlaceholder(),
                    ),
                  ),
                ),
                // 标题和信息
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppColors.darkOnSurface : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.fileVideo.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              video.displaySize,
                              style: context.textTheme.labelSmall?.copyWith(
                                color: AppColors.fileVideo,
                                fontWeight: FontWeight.w500,
                              ),
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

  Widget _buildPlaceholder() => Center(
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: AppColors.fileVideo.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.play_circle_rounded,
            size: 32,
            color: AppColors.fileVideo,
          ),
        ),
      );

  Future<void> _playVideo(BuildContext context, WidgetRef ref) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[video.sourceId];
    if (connection == null) return;

    final url = await connection.adapter.fileSystem.getFileUrl(video.path);

    if (!context.mounted) return;

    final videoItem = VideoItem.fromFileItem(video.file, url);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoPlayerPage(video: videoItem),
      ),
    );

    // 刷新继续观看列表
    ref.invalidate(continueWatchingProvider);
  }
}

class _VideoListTile extends ConsumerWidget {
  const _VideoListTile({
    required this.video,
    required this.isDark,
  });

  final VideoFileWithSource video;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withOpacity(0.3)
            : context.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutline.withOpacity(0.2)
              : context.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playVideo(context, ref),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // 缩略图
                Container(
                  width: 80,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceElevated
                        : context.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.play_circle_rounded,
                      size: 28,
                      color: AppColors.fileVideo,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // 视频信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppColors.darkOnSurface : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.fileVideo.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              video.displaySize,
                              style: context.textTheme.labelSmall?.copyWith(
                                color: AppColors.fileVideo,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              video.path.split('/').reversed.skip(1).firstOrNull ?? '',
                              style: context.textTheme.labelSmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 播放按钮
                Icon(
                  Icons.play_arrow_rounded,
                  color: isDark ? AppColors.darkOnSurfaceVariant : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playVideo(BuildContext context, WidgetRef ref) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[video.sourceId];
    if (connection == null) return;

    final url = await connection.adapter.fileSystem.getFileUrl(video.path);

    if (!context.mounted) return;

    final videoItem = VideoItem.fromFileItem(video.file, url);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoPlayerPage(video: videoItem),
      ),
    );

    // 刷新继续观看列表
    ref.invalidate(continueWatchingProvider);
  }
}
