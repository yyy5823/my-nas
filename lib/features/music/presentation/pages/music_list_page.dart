import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/connection/presentation/providers/connection_provider.dart';
import 'package:my_nas/features/music/data/services/music_library_cache_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/pages/music_player_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/mini_player.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/empty_widget.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/media_setup_widget.dart';

/// 音乐文件及其来源
class MusicFileWithSource {
  MusicFileWithSource({
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

  MusicLibraryCacheEntry toCacheEntry() => MusicLibraryCacheEntry(
        sourceId: sourceId,
        filePath: path,
        fileName: name,
        thumbnailUrl: thumbnailUrl,
        size: size,
        modifiedTime: modifiedTime,
      );
}

/// 音乐列表状态
final musicListProvider =
    StateNotifierProvider<MusicListNotifier, MusicListState>(
        (ref) => MusicListNotifier(ref));

sealed class MusicListState {}

class MusicListLoading extends MusicListState {
  MusicListLoading({this.progress = 0, this.currentFolder, this.fromCache = false});
  final double progress;
  final String? currentFolder;
  final bool fromCache;
}

class MusicListNotConnected extends MusicListState {}

class MusicListLoaded extends MusicListState {
  MusicListLoaded({
    required this.tracks,
    this.fromCache = false,
    this.searchQuery = '',
  });
  final List<MusicFileWithSource> tracks;
  final bool fromCache;
  final String searchQuery;

  List<MusicFileWithSource> get filteredTracks {
    if (searchQuery.isEmpty) return tracks;
    return tracks
        .where((t) => t.name.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();
  }

  MusicListLoaded copyWith({
    List<MusicFileWithSource>? tracks,
    bool? fromCache,
    String? searchQuery,
  }) =>
      MusicListLoaded(
        tracks: tracks ?? this.tracks,
        fromCache: fromCache ?? this.fromCache,
        searchQuery: searchQuery ?? this.searchQuery,
      );
}

class MusicListError extends MusicListState {
  MusicListError(this.message);
  final String message;
}

class MusicListNotifier extends StateNotifier<MusicListState> {
  MusicListNotifier(this._ref) : super(MusicListLoading()) {
    _init();
  }

  final Ref _ref;
  final MusicLibraryCacheService _cacheService = MusicLibraryCacheService.instance;

  Future<void> _init() async {
    try {
      await _cacheService.init();
      await _loadFromCacheImmediately();

      // 监听连接状态变化
      _ref.listen<Map<String, SourceConnection>>(activeConnectionsProvider, (previous, next) {
        final prevConnected = previous?.values.where((c) => c.status == SourceStatus.connected).length ?? 0;
        final nextConnected = next.values.where((c) => c.status == SourceStatus.connected).length;

        if (nextConnected > prevConnected && state is MusicListNotConnected) {
          loadMusic();
        }
      });
    } catch (e) {
      logger.e('MusicListNotifier: 初始化失败', e);
      state = MusicListLoaded(tracks: [], fromCache: false);
    }
  }

  /// 立即从缓存加载
  Future<void> _loadFromCacheImmediately() async {
    final cache = _cacheService.getCache();
    if (cache != null && cache.tracks.isNotEmpty) {
      state = MusicListLoading(fromCache: true, currentFolder: '加载缓存...');

      final tracks = cache.tracks.map((entry) {
        return MusicFileWithSource(
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

      state = MusicListLoaded(tracks: tracks, fromCache: true);
      logger.i('从缓存加载了 ${tracks.length} 首音乐');
    } else {
      state = MusicListLoaded(tracks: [], fromCache: true);
    }
  }

  Future<void> loadMusic({bool forceRefresh = false, int maxDepth = 3}) async {
    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    MediaLibraryConfig? config = configAsync.valueOrNull;
    if (config == null) {
      state = MusicListLoading(currentFolder: '正在加载配置...');
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final updated = _ref.read(mediaLibraryConfigProvider);
        config = updated.valueOrNull;
        if (config != null) break;
        if (updated.hasError) {
          state = MusicListError('加载媒体库配置失败');
          return;
        }
      }
      if (config == null) {
        state = MusicListLoaded(tracks: []);
        return;
      }
    }

    final musicPaths = config.getEnabledPathsForType(MediaType.music);
    if (musicPaths.isEmpty) {
      state = MusicListLoaded(tracks: []);
      return;
    }

    final connectedPaths = musicPaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      if (state is! MusicListLoaded || (state as MusicListLoaded).tracks.isEmpty) {
        state = MusicListNotConnected();
      }
      return;
    }

    final sourceIds = connectedPaths.map((p) => p.sourceId).toList();

    // 尝试使用缓存
    if (!forceRefresh && _cacheService.isCacheValid(sourceIds)) {
      final cache = _cacheService.getCache();
      if (cache != null) {
        state = MusicListLoading(fromCache: true, currentFolder: '加载缓存...');

        final tracks = cache.tracks.map((entry) {
          return MusicFileWithSource(
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

        state = MusicListLoaded(tracks: tracks, fromCache: true);
        logger.i('从缓存加载了 ${tracks.length} 首音乐');
        return;
      }
    }

    // 扫描文件系统
    state = MusicListLoading();
    final tracks = <MusicFileWithSource>[];
    var scannedFolders = 0;
    final totalFolders = connectedPaths.length;

    for (final mediaPath in connectedPaths) {
      final connection = connections[mediaPath.sourceId];
      if (connection == null) continue;

      state = MusicListLoading(
        progress: scannedFolders / totalFolders,
        currentFolder: mediaPath.displayName,
      );

      try {
        await _scanForMusic(
          connection.adapter.fileSystem,
          mediaPath.path,
          tracks,
          sourceId: mediaPath.sourceId,
          depth: 0,
          maxDepth: maxDepth,
        );
      } on Exception catch (e) {
        logger.w('扫描音乐文件夹失败: ${mediaPath.path} - $e');
      }

      scannedFolders++;
    }

    logger.i('音乐扫描完成，共找到 ${tracks.length} 首音乐');

    // 保存到缓存
    final cacheEntries = tracks.map((t) => t.toCacheEntry()).toList();
    await _cacheService.saveCache(MusicLibraryCache(
      tracks: cacheEntries,
      lastUpdated: DateTime.now(),
      sourceIds: sourceIds,
    ));

    state = MusicListLoaded(tracks: tracks);
  }

  Future<void> _scanForMusic(
    NasFileSystem fs,
    String path,
    List<MusicFileWithSource> tracks, {
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
          await _scanForMusic(
            fs,
            item.path,
            tracks,
            sourceId: sourceId,
            depth: depth + 1,
            maxDepth: maxDepth,
          );
        } else if (item.type == FileType.audio) {
          tracks.add(MusicFileWithSource(file: item, sourceId: sourceId));
        }
      }
    } on Exception catch (e) {
      logger.w('扫描子文件夹失败: $path - $e');
    }
  }

  void setSearchQuery(String query) {
    final current = state;
    if (current is MusicListLoaded) {
      state = current.copyWith(searchQuery: query);
    }
  }

  /// 强制刷新
  Future<void> forceRefresh() async {
    await _cacheService.clearCache();
    await loadMusic(forceRefresh: true);
  }
}

class MusicListPage extends ConsumerStatefulWidget {
  const MusicListPage({super.key});

  @override
  ConsumerState<MusicListPage> createState() => _MusicListPageState();
}

class _MusicListPageState extends ConsumerState<MusicListPage> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(musicListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          _buildAppBar(context, ref, isDark, state),
          Expanded(
            child: switch (state) {
              MusicListLoading(:final progress, :final currentFolder, :final fromCache) =>
                _buildLoadingState(progress, currentFolder, fromCache, isDark),
              MusicListNotConnected() => const MediaSetupWidget(
                  mediaType: MediaType.music,
                  icon: Icons.library_music_outlined,
                ),
              MusicListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(musicListProvider.notifier).loadMusic(),
                ),
              MusicListLoaded(:final filteredTracks) when filteredTracks.isEmpty =>
                const EmptyWidget(
                  icon: Icons.library_music_outlined,
                  title: '暂无音乐',
                  message: '在配置的目录中添加音乐后将显示在这里',
                ),
              MusicListLoaded loaded => _buildMusicContent(context, ref, loaded, isDark),
            },
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    MusicListState state,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (!_showSearch) ...[
                Text(
                  '音乐',
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : null,
                  ),
                ),
                if (state is MusicListLoaded && state.fromCache)
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
              if (_showSearch)
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '搜索音乐...',
                      hintStyle: TextStyle(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : context.colorScheme.onSurfaceVariant,
                      ),
                      border: InputBorder.none,
                    ),
                    style: TextStyle(
                      color: isDark ? AppColors.darkOnSurface : null,
                    ),
                    onChanged: (v) =>
                        ref.read(musicListProvider.notifier).setSearchQuery(v),
                  ),
                ),
              const Spacer(),
              _buildIconButton(
                icon: _showSearch ? Icons.close : Icons.search_rounded,
                onTap: () {
                  setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) {
                      _searchController.clear();
                      ref.read(musicListProvider.notifier).setSearchQuery('');
                    }
                  });
                },
                isDark: isDark,
                tooltip: _showSearch ? '关闭' : '搜索',
              ),
              _buildIconButton(
                icon: Icons.refresh_rounded,
                onTap: () => ref.read(musicListProvider.notifier).forceRefresh(),
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
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
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
            fromCache ? '加载缓存...' : '扫描音乐中...',
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

  Widget _buildMusicContent(
    BuildContext context,
    WidgetRef ref,
    MusicListLoaded state,
    bool isDark,
  ) {
    return RefreshIndicator(
      onRefresh: () => ref.read(musicListProvider.notifier).forceRefresh(),
      child: CustomScrollView(
        slivers: [
          // 缓存信息条
          _MusicCacheInfoBar(state: state, isDark: isDark),
          // 音乐列表
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _MusicListTile(
                  track: state.filteredTracks[index],
                  index: index,
                  isDark: isDark,
                ),
                childCount: state.filteredTracks.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

/// 缓存信息条
class _MusicCacheInfoBar extends ConsumerWidget {
  const _MusicCacheInfoBar({
    required this.state,
    required this.isDark,
  });

  final MusicListLoaded state;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheService = MusicLibraryCacheService.instance;
    final cache = cacheService.getCache();

    if (cache == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final trackCount = state.tracks.length;
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
              Icons.library_music_rounded,
              size: 14,
              color: AppColors.fileAudio,
            ),
            const SizedBox(width: 4),
            Text(
              '$trackCount',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              '首音乐',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
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
                onTap: () => ref.read(musicListProvider.notifier).forceRefresh(),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.fileAudio.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: AppColors.fileAudio,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MusicListTile extends ConsumerWidget {
  const _MusicListTile({
    required this.track,
    required this.index,
    required this.isDark,
  });

  final MusicFileWithSource track;
  final int index;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = currentMusic?.path == track.path;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isPlaying
            ? AppColors.fileAudio.withOpacity(isDark ? 0.15 : 0.1)
            : (isDark
                ? AppColors.darkSurfaceVariant.withOpacity(0.3)
                : context.colorScheme.surface),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPlaying
              ? AppColors.fileAudio.withOpacity(0.3)
              : (isDark
                  ? AppColors.darkOutline.withOpacity(0.2)
                  : context.colorScheme.outlineVariant.withOpacity(0.5)),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playTrack(context, ref),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: isPlaying
                        ? const LinearGradient(
                            colors: [AppColors.fileAudio, AppColors.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isPlaying
                        ? null
                        : (isDark
                            ? AppColors.darkSurfaceElevated
                            : context.colorScheme.surfaceContainerHighest),
                  ),
                  child: Icon(
                    isPlaying ? Icons.equalizer_rounded : Icons.music_note_rounded,
                    color: isPlaying
                        ? Colors.white
                        : (isDark
                            ? AppColors.darkOnSurfaceVariant
                            : context.colorScheme.onSurfaceVariant),
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyLarge?.copyWith(
                          color: isPlaying
                              ? AppColors.fileAudio
                              : (isDark ? AppColors.darkOnSurface : null),
                          fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
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
                              color: (isDark
                                      ? AppColors.darkSurfaceElevated
                                      : context.colorScheme.surfaceContainerHighest)
                                  .withOpacity(isDark ? 1 : 0.8),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              track.displaySize,
                              style: context.textTheme.labelSmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => _handleMenuAction(context, ref, value),
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: isDark ? AppColors.darkOnSurfaceVariant : null,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: isDark ? AppColors.darkSurface : null,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'play_next',
                      child: Row(
                        children: [
                          Icon(
                            Icons.queue_play_next_rounded,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '下一首播放',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'add_to_queue',
                      child: Row(
                        children: [
                          Icon(
                            Icons.playlist_add_rounded,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '添加到播放列表',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'add_to_favorites',
                      child: Row(
                        children: [
                          Icon(
                            Icons.favorite_border_rounded,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '收藏',
                            style: TextStyle(
                              color: isDark ? AppColors.darkOnSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playTrack(BuildContext context, WidgetRef ref) async {
    final adapter = ref.read(activeAdapterProvider);
    if (adapter == null) return;

    final url = await adapter.fileSystem.getFileUrl(track.path);
    final musicItem = MusicItem.fromFileItem(track.file, url);

    if (!context.mounted) return;

    await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const MusicPlayerPage(),
      ),
    );
  }

  Future<void> _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    final adapter = ref.read(activeAdapterProvider);
    if (adapter == null) return;

    final url = await adapter.fileSystem.getFileUrl(track.path);
    final musicItem = MusicItem.fromFileItem(track.file, url);

    switch (action) {
      case 'play_next':
        final queue = ref.read(playQueueProvider);
        final playerState = ref.read(musicPlayerControllerProvider);

        if (queue.isEmpty) {
          await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
        } else {
          final insertIndex = playerState.currentIndex + 1;
          final newQueue = [...queue];
          newQueue.insert(insertIndex.clamp(0, newQueue.length), musicItem);
          ref.read(playQueueProvider.notifier).setQueue(newQueue);

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已添加到下一首播放')),
            );
          }
        }

      case 'add_to_queue':
        ref.read(playQueueProvider.notifier).addToQueue(musicItem);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已添加到播放队列')),
          );
        }

      case 'add_to_favorites':
        final isFav = await ref.read(musicFavoritesProvider.notifier).toggleFavorite(musicItem);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(isFav ? '已添加到收藏' : '已取消收藏')),
          );
        }
    }
  }
}
