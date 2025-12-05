import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/data/services/music_library_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_metadata_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/pages/music_home_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_player_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/playlist_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/mini_player.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/animated_list_item.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/media_setup_widget.dart';

/// 音乐文件及其来源
class MusicFileWithSource {
  MusicFileWithSource({
    required this.file,
    required this.sourceId,
    // 元数据字段
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.trackNumber,
    this.year,
    this.genre,
    this.coverBase64,
    this.coverPath,
    this.metadataExtracted = false,
  });

  /// 从缓存条目创建
  factory MusicFileWithSource.fromCacheEntry(MusicLibraryCacheEntry entry) => MusicFileWithSource(
      file: FileItem(
        name: entry.fileName,
        path: entry.filePath,
        size: entry.size,
        isDirectory: false,
        modifiedTime: entry.modifiedTime,
        thumbnailUrl: entry.thumbnailUrl,
      ),
      sourceId: entry.sourceId,
      title: entry.title,
      artist: entry.artist,
      album: entry.album,
      duration: entry.duration,
      trackNumber: entry.trackNumber,
      year: entry.year,
      genre: entry.genre,
      coverBase64: entry.coverBase64,
      metadataExtracted: entry.metadataExtracted,
    );

  final FileItem file;
  final String sourceId;

  // 元数据字段
  final String? title;
  final String? artist;
  final String? album;
  final int? duration; // 毫秒
  final int? trackNumber;
  final int? year;
  final String? genre;
  final String? coverBase64; // Base64 编码的封面图片
  final String? coverPath; // 封面文件路径（磁盘缓存）
  final bool metadataExtracted; // 是否已提取过元数据

  String get name => file.name;
  String get path => file.path;
  int get size => file.size;
  DateTime? get modifiedTime => file.modifiedTime;
  String? get thumbnailUrl => file.thumbnailUrl;
  String get displaySize => file.displaySize;

  /// 显示的标题（优先使用元数据标题，否则从文件名解析）
  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    final nameWithoutExt = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    // 尝试解析 "艺术家 - 歌曲名" 格式
    final match = RegExp(r'^.+?\s*[-–—]\s*(.+)$').firstMatch(nameWithoutExt);
    return match?.group(1)?.trim() ?? nameWithoutExt;
  }

  /// 显示的艺术家
  String get displayArtist {
    if (artist != null && artist!.isNotEmpty) return artist!;
    // 尝试从文件名解析
    final nameWithoutExt = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    final match = RegExp(r'^(.+?)\s*[-–—]\s*.+$').firstMatch(nameWithoutExt);
    return match?.group(1)?.trim() ?? '未知艺术家';
  }

  /// 显示的专辑
  String get displayAlbum => album?.isNotEmpty ?? false ? album! : '未知专辑';

  /// 是否有封面
  bool get hasCover =>
      (coverBase64 != null && coverBase64!.isNotEmpty) ||
      (coverPath != null && coverPath!.isNotEmpty);

  /// 获取封面数据（从 Base64 解码，优先使用磁盘缓存会在 UI 层处理）
  List<int>? get coverData {
    if (coverBase64 == null || coverBase64!.isEmpty) return null;
    try {
      return base64Decode(coverBase64!);
    } on Exception catch (e) {
      logger.e('解码封面数据失败: $e');
      return null;
    }
  }

  /// 获取封面文件（用于 Image.file）
  /// 注意：不进行同步文件存在检查，避免阻塞 UI 线程
  /// 使用时需配合 Image.file 的 errorBuilder 处理文件不存在的情况
  File? get coverFile {
    if (coverPath == null || coverPath!.isEmpty) return null;
    return File(coverPath!);
  }

  /// 格式化时长
  String get durationText {
    if (duration == null) return '--:--';
    final totalSeconds = duration! ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 唯一标识
  String get uniqueKey => '${sourceId}_$path';

  MusicLibraryCacheEntry toCacheEntry() => MusicLibraryCacheEntry(
        sourceId: sourceId,
        filePath: path,
        fileName: name,
        thumbnailUrl: thumbnailUrl,
        size: size,
        modifiedTime: modifiedTime,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        trackNumber: trackNumber,
        year: year,
        genre: genre,
        coverBase64: coverBase64,
        metadataExtracted: metadataExtracted,
      );

  /// 复制并更新元数据
  MusicFileWithSource copyWithMetadata({
    String? title,
    String? artist,
    String? album,
    int? duration,
    int? trackNumber,
    int? year,
    String? genre,
    String? coverBase64,
    String? coverPath,
    bool? metadataExtracted,
  }) => MusicFileWithSource(
      file: file,
      sourceId: sourceId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      trackNumber: trackNumber ?? this.trackNumber,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      coverBase64: coverBase64 ?? this.coverBase64,
      coverPath: coverPath ?? this.coverPath,
      metadataExtracted: metadataExtracted ?? this.metadataExtracted,
    );
}

/// 音乐列表状态
final musicListProvider =
    StateNotifierProvider<MusicListNotifier, MusicListState>(
        MusicListNotifier.new);

sealed class MusicListState {}

class MusicListLoading extends MusicListState {
  MusicListLoading({
    this.progress = 0,
    this.currentFolder,
    this.fromCache = false,
    this.partialTracks = const [],
    this.scannedCount = 0,
    this.phase = MusicScanPhase.scanning,
    this.metadataProgress = 0,
  });
  final double progress;
  final String? currentFolder;
  final bool fromCache;
  final List<MusicFileWithSource> partialTracks;
  final int scannedCount;
  final MusicScanPhase phase;
  final double metadataProgress;
}

/// 扫描阶段
enum MusicScanPhase {
  scanning,
  metadata,
}

/// 音乐排序选项
enum MusicSortOption {
  name('名称', Icons.sort_by_alpha_rounded),
  artist('歌手', Icons.person_rounded),
  album('专辑', Icons.album_rounded),
  dateAdded('添加时间', Icons.schedule_rounded),
  duration('时长', Icons.timer_rounded);

  const MusicSortOption(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// 排序方向
enum SortDirection { ascending, descending }

/// 音乐排序状态
class MusicSortState {
  const MusicSortState({
    this.option = MusicSortOption.name,
    this.direction = SortDirection.ascending,
  });
  final MusicSortOption option;
  final SortDirection direction;

  MusicSortState copyWith({
    MusicSortOption? option,
    SortDirection? direction,
  }) => MusicSortState(
      option: option ?? this.option,
      direction: direction ?? this.direction,
    );
}

/// 音乐排序 Provider
final musicSortProvider = StateProvider<MusicSortState>(
  (ref) => const MusicSortState(),
);

class MusicListNotConnected extends MusicListState {}

/// 优化后的音乐列表状态 - 使用分类数据而非全量内存加载
class MusicListLoaded extends MusicListState {
  MusicListLoaded({
    required this.totalCount,
    this.artistCount = 0,
    this.albumCount = 0,
    this.genreCount = 0,
    this.yearCount = 0,
    this.folderCount = 0,
    this.searchQuery = '',
    this.isLoadingMetadata = false,
    this.fromCache = false,
    // 分类数据 - 从 SQLite 分页加载
    this.recentTracks = const [],
    this.allTracks = const [],
    // 搜索结果
    this.searchResults = const [],
    // 用于 O(1) 查找的 Map
    this.trackByPath = const {},
  });

  final int totalCount;
  final int artistCount;
  final int albumCount;
  final int genreCount;
  final int yearCount;
  final int folderCount;
  final String searchQuery;
  final bool isLoadingMetadata;
  final bool fromCache;

  // 分类数据 - 已从 SQLite 加载
  final List<MusicTrackEntity> recentTracks;
  final List<MusicTrackEntity> allTracks;

  // 搜索结果
  final List<MusicTrackEntity> searchResults;

  // 用于 O(1) 查找的 Map
  final Map<String, MusicTrackEntity> trackByPath;

  /// 兼容旧代码：返回当前展示的曲目列表
  List<MusicFileWithSource> get tracks => allTracks
      .map((m) => MusicFileWithSource(
            file: FileItem(
              name: m.fileName,
              path: m.filePath,
              size: m.size ?? 0,
              isDirectory: false,
              modifiedTime: m.modifiedTime,
            ),
            sourceId: m.sourceId,
            title: m.title,
            artist: m.artist,
            album: m.album,
            duration: m.duration,
            year: m.year,
            genre: m.genre,
            coverPath: m.coverPath,
            metadataExtracted: true,
          ))
      .toList();

  /// 过滤后的曲目
  List<MusicTrackEntity> get filteredMetadata {
    if (searchQuery.isNotEmpty) return searchResults;
    return allTracks;
  }

  /// 兼容旧代码
  List<MusicFileWithSource> get filteredTracks => filteredMetadata
      .map((m) => MusicFileWithSource(
            file: FileItem(
              name: m.fileName,
              path: m.filePath,
              size: m.size ?? 0,
              isDirectory: false,
              modifiedTime: m.modifiedTime,
            ),
            sourceId: m.sourceId,
            title: m.title,
            artist: m.artist,
            album: m.album,
            duration: m.duration,
            year: m.year,
            genre: m.genre,
            coverPath: m.coverPath,
            metadataExtracted: true,
          ))
      .toList();

  /// 通过路径获取曲目 - O(1) 查找
  MusicFileWithSource? getTrackByPath(String path) {
    final m = trackByPath[path];
    if (m == null) return null;
    return MusicFileWithSource(
      file: FileItem(
        name: m.fileName,
        path: m.filePath,
        size: m.size ?? 0,
        isDirectory: false,
        modifiedTime: m.modifiedTime,
      ),
      sourceId: m.sourceId,
      title: m.title,
      artist: m.artist,
      album: m.album,
      duration: m.duration,
      year: m.year,
      genre: m.genre,
      coverPath: m.coverPath,
      metadataExtracted: true,
    );
  }

  MusicListLoaded copyWith({
    int? totalCount,
    int? artistCount,
    int? albumCount,
    int? genreCount,
    int? yearCount,
    int? folderCount,
    String? searchQuery,
    bool? isLoadingMetadata,
    bool? fromCache,
    List<MusicTrackEntity>? recentTracks,
    List<MusicTrackEntity>? allTracks,
    List<MusicTrackEntity>? searchResults,
    Map<String, MusicTrackEntity>? trackByPath,
  }) =>
      MusicListLoaded(
        totalCount: totalCount ?? this.totalCount,
        artistCount: artistCount ?? this.artistCount,
        albumCount: albumCount ?? this.albumCount,
        genreCount: genreCount ?? this.genreCount,
        yearCount: yearCount ?? this.yearCount,
        folderCount: folderCount ?? this.folderCount,
        searchQuery: searchQuery ?? this.searchQuery,
        isLoadingMetadata: isLoadingMetadata ?? this.isLoadingMetadata,
        fromCache: fromCache ?? this.fromCache,
        recentTracks: recentTracks ?? this.recentTracks,
        allTracks: allTracks ?? this.allTracks,
        searchResults: searchResults ?? this.searchResults,
        trackByPath: trackByPath ?? this.trackByPath,
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
  final MusicLibraryCacheService _cacheService = MusicLibraryCacheService();
  final MusicMetadataService _metadataService = MusicMetadataService();
  final MusicDatabaseService _db = MusicDatabaseService();
  final MusicCoverCacheService _coverCache = MusicCoverCacheService();

  Future<void> _init() async {
    try {
      // 并行初始化服务
      await Future.wait([
        _cacheService.init(),
        _db.init(),
        _coverCache.init(),
      ]);

      logger.d('MusicListNotifier: 服务初始化完成');

      // 从 SQLite 加载分类数据
      await _loadCategorizedData();

      // 监听连接状态变化
      _ref.listen<Map<String, SourceConnection>>(activeConnectionsProvider, (previous, next) {
        final prevConnected = previous?.values.where((c) => c.status == SourceStatus.connected).length ?? 0;
        final nextConnected = next.values.where((c) => c.status == SourceStatus.connected).length;

        if (nextConnected > prevConnected && state is MusicListNotConnected) {
          loadMusic();
        }
      });
    } on Exception catch (e) {
      logger.e('MusicListNotifier: 初始化失败', e);
      state = MusicListLoaded(totalCount: 0);
    }
  }

  /// 从 SQLite 加载分类数据（高性能）
  Future<void> _loadCategorizedData() async {
    state = MusicListLoading(fromCache: true, currentFolder: '加载数据...');

    // 并行查询统计数据和分类数据
    final results = await Future.wait([
      _db.getStats(),
      _db.getRecentlyAdded(limit: 20),
      _db.getPage(limit: 200),
    ]);

    final stats = results[0] as Map<String, dynamic>;
    final recent = results[1] as List<MusicTrackEntity>;
    final allTracks = results[2] as List<MusicTrackEntity>;

    // 构建快速查找 Map
    final trackByPath = <String, MusicTrackEntity>{};
    for (final m in allTracks) {
      trackByPath[m.uniqueKey] = m;
    }

    final total = stats['total'] as int? ?? 0;

    if (total == 0) {
      // 数据库为空，尝试从旧缓存迁移
      await _migrateFromOldCache();
      return;
    }

    state = MusicListLoaded(
      totalCount: total,
      artistCount: stats['artists'] as int? ?? 0,
      albumCount: stats['albums'] as int? ?? 0,
      genreCount: stats['genres'] as int? ?? 0,
      yearCount: stats['years'] as int? ?? 0,
      folderCount: stats['folders'] as int? ?? 0,
      recentTracks: recent,
      allTracks: allTracks,
      trackByPath: trackByPath,
      fromCache: true,
    );

    logger.i('MusicListNotifier: 数据加载完成，总计 $total 首音乐');
  }

  /// 从旧缓存迁移数据到 SQLite
  Future<void> _migrateFromOldCache() async {
    final cache = _cacheService.getCache();
    if (cache == null || cache.tracks.isEmpty) {
      state = MusicListLoaded(totalCount: 0, fromCache: true);
      return;
    }

    logger.i('MusicListNotifier: 开始从 Hive 缓存迁移 ${cache.tracks.length} 首音乐');
    state = MusicListLoading(currentFolder: '正在迁移数据...', fromCache: true);

    final metadataList = <MusicTrackEntity>[];
    for (final entry in cache.tracks) {
      // 如果有 Base64 封面，保存到磁盘
      String? coverPath;
      if (entry.coverBase64 != null && entry.coverBase64!.isNotEmpty) {
        final uniqueKey = '${entry.sourceId}_${entry.filePath}';
        coverPath = await _coverCache.saveCoverFromBase64(uniqueKey, entry.coverBase64!);
      }

      metadataList.add(MusicTrackEntity(
        sourceId: entry.sourceId,
        filePath: entry.filePath,
        fileName: entry.fileName,
        title: entry.title,
        artist: entry.artist,
        album: entry.album,
        duration: entry.duration,
        trackNumber: entry.trackNumber,
        year: entry.year,
        genre: entry.genre,
        coverPath: coverPath,
        size: entry.size,
        modifiedTime: entry.modifiedTime,
        lastUpdated: DateTime.now(),
      ));
    }

    // 批量保存到 SQLite
    await _db.upsertBatch(metadataList);
    logger.i('MusicListNotifier: 迁移完成，已保存 ${metadataList.length} 首音乐');

    // 重新加载数据
    await _loadCategorizedData();
  }

  Future<void> loadMusic({bool forceRefresh = false, int maxDepth = 3}) async {
    final connections = _ref.read(activeConnectionsProvider);
    final configAsync = _ref.read(mediaLibraryConfigProvider);

    var config = configAsync.valueOrNull;
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
        state = MusicListLoaded(totalCount: 0);
        return;
      }
    }

    final musicPaths = config.getEnabledPathsForType(MediaType.music);
    if (musicPaths.isEmpty) {
      state = MusicListLoaded(totalCount: 0);
      return;
    }

    final connectedPaths = musicPaths.where((path) {
      final conn = connections[path.sourceId];
      return conn?.status == SourceStatus.connected;
    }).toList();

    if (connectedPaths.isEmpty) {
      final current = state;
      if (current is! MusicListLoaded || current.totalCount == 0) {
        state = MusicListNotConnected();
      }
      return;
    }

    // 如果不是强制刷新且 SQLite 有数据，直接使用
    if (!forceRefresh) {
      final count = await _db.getCount();
      if (count > 0) {
        await _loadCategorizedData();
        return;
      }
    }

    // 第一阶段：扫描文件系统
    state = MusicListLoading();
    final tracks = <MusicFileWithSource>[];
    var scannedFolders = 0;
    final totalFolders = connectedPaths.length;
    var lastUpdateCount = 0;

    for (final mediaPath in connectedPaths) {
      final connection = connections[mediaPath.sourceId];
      if (connection == null) continue;

      state = MusicListLoading(
        progress: scannedFolders / totalFolders,
        currentFolder: mediaPath.displayName,
        partialTracks: List.from(tracks),
        scannedCount: tracks.length,
      );

      try {
        await _scanForMusic(
          connection.adapter.fileSystem,
          mediaPath.path,
          tracks,
          sourceId: mediaPath.sourceId,
          depth: 0,
          maxDepth: maxDepth,
          onBatchFound: () {
            if (tracks.length - lastUpdateCount >= 20) {
              lastUpdateCount = tracks.length;
              state = MusicListLoading(
                progress: scannedFolders / totalFolders,
                currentFolder: mediaPath.displayName,
                partialTracks: List.from(tracks),
                scannedCount: tracks.length,
              );
            }
          },
        );
      } on Exception catch (e) {
        logger.w('扫描音乐文件夹失败: ${mediaPath.path} - $e');
      }

      scannedFolders++;
    }

    logger.i('音乐扫描完成，共找到 ${tracks.length} 首音乐');

    // 第二阶段：提取元数据并保存到 SQLite
    if (tracks.isNotEmpty) {
      await _extractAndSaveMetadata(tracks, connections);
    }

    // 重新加载数据
    await _loadCategorizedData();
    logger.i('音乐库加载完成');
  }

  /// 提取元数据并保存到 SQLite（优化：封面保存到磁盘）
  Future<void> _extractAndSaveMetadata(
    List<MusicFileWithSource> tracks,
    Map<String, SourceConnection> connections,
  ) async {
    await _metadataService.init();

    final totalTracks = tracks.length;
    var processedCount = 0;
    final metadataList = <MusicTrackEntity>[];

    state = MusicListLoading(
      phase: MusicScanPhase.metadata,
      currentFolder: '正在提取元数据...',
      scannedCount: totalTracks,
    );

    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final connection = connections[track.sourceId];

      if (connection == null || connection.status != SourceStatus.connected) {
        processedCount++;
        continue;
      }

      try {
        final metadata = await _metadataService.extractFromNasFile(
          connection.adapter.fileSystem,
          track.path,
          skipLyrics: true,
        );

        String? coverPath;
        if (metadata?.coverData != null && metadata!.coverData!.isNotEmpty) {
          // 保存封面到磁盘缓存
          final uniqueKey = '${track.sourceId}_${track.path}';
          coverPath = await _coverCache.saveCover(
            uniqueKey,
            Uint8List.fromList(metadata.coverData!),
          );
        }

        metadataList.add(MusicTrackEntity(
          sourceId: track.sourceId,
          filePath: track.path,
          fileName: track.name,
          title: metadata?.title,
          artist: metadata?.artist,
          album: metadata?.album,
          duration: metadata?.duration?.inMilliseconds,
          trackNumber: metadata?.trackNumber,
          year: metadata?.year,
          genre: metadata?.genre,
          coverPath: coverPath,
          size: track.size,
          modifiedTime: track.modifiedTime,
          lastUpdated: DateTime.now(),
        ));
      } on Exception catch (e) {
        logger.w('提取元数据失败 ${track.path}: $e');
        // 即使失败也保存基本信息
        metadataList.add(MusicTrackEntity(
          sourceId: track.sourceId,
          filePath: track.path,
          fileName: track.name,
          size: track.size,
          modifiedTime: track.modifiedTime,
          lastUpdated: DateTime.now(),
        ));
      }

      processedCount++;

      // 每处理 50 首保存一次，并更新进度
      if (processedCount % 50 == 0 || processedCount == totalTracks) {
        await _db.upsertBatch(metadataList);
        metadataList.clear();

        final progress = processedCount / totalTracks;
        state = MusicListLoading(
          phase: MusicScanPhase.metadata,
          currentFolder: '正在提取元数据 ($processedCount/$totalTracks)',
          metadataProgress: progress,
          scannedCount: totalTracks,
        );
      }
    }

    // 保存剩余数据
    if (metadataList.isNotEmpty) {
      await _db.upsertBatch(metadataList);
    }

    logger.i('元数据提取完成，处理了 $processedCount 首音乐');
  }

  Future<void> _scanForMusic(
    NasFileSystem fs,
    String path,
    List<MusicFileWithSource> tracks, {
    required String sourceId,
    required int depth,
    int maxDepth = 3,
    VoidCallback? onBatchFound,
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
            onBatchFound: onBatchFound,
          );
        } else if (item.type == FileType.audio) {
          tracks.add(MusicFileWithSource(file: item, sourceId: sourceId));
          onBatchFound?.call();
        }
      }
    } on Exception catch (e) {
      logger.w('扫描子文件夹失败: $path - $e');
    }
  }

  void setSearchQuery(String query) {
    final current = state;
    if (current is MusicListLoaded) {
      if (query.isEmpty) {
        state = current.copyWith(searchQuery: '', searchResults: []);
      } else {
        _performSearch(query, current);
      }
    }
  }

  /// 执行搜索（使用 SQLite LIKE 查询）
  Future<void> _performSearch(String query, MusicListLoaded current) async {
    state = current.copyWith(searchQuery: query, isLoadingMetadata: true);

    final results = await _db.search(query, limit: 100);

    final newState = state;
    if (newState is MusicListLoaded && newState.searchQuery == query) {
      state = newState.copyWith(
        searchResults: results,
        isLoadingMetadata: false,
      );
    }
  }

  /// 强制刷新
  Future<void> forceRefresh() async {
    await _db.clearAll();
    await _coverCache.clearAll();
    await loadMusic(forceRefresh: true);
  }
}

/// 音乐分类Tab枚举
/// 音乐库分类
enum MusicCategory {
  all('全部歌曲', Icons.queue_music_rounded),
  artists('艺术家', Icons.person_rounded),
  albums('专辑', Icons.album_rounded),
  folders('文件夹', Icons.folder_rounded),
  favorites('我喜欢', Icons.favorite_rounded),
  recent('最近播放', Icons.history_rounded),
  genres('流派', Icons.category_rounded),
  years('年代', Icons.date_range_rounded);

  const MusicCategory(this.label, this.icon);
  final String label;
  final IconData icon;
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
    final state = ref.watch(musicListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      body: Column(
        children: [
          _buildHeader(context, ref, isDark, state),
          Expanded(
            child: switch (state) {
              MusicListLoading(
                :final progress,
                :final currentFolder,
                :final fromCache,
                :final partialTracks,
                :final scannedCount,
              ) =>
                _buildLoadingState(
                  context,
                  progress,
                  currentFolder,
                  fromCache,
                  partialTracks,
                  scannedCount,
                  isDark,
                ),
              MusicListNotConnected() => const MediaSetupWidget(
                  mediaType: MediaType.music,
                  icon: Icons.library_music_outlined,
                ),
              MusicListError(:final message) => AppErrorWidget(
                  message: message,
                  onRetry: () => ref.read(musicListProvider.notifier).loadMusic(),
                ),
              MusicListLoaded(:final filteredTracks) when filteredTracks.isEmpty =>
                _buildEmptyState(context, ref, isDark),
              final MusicListLoaded loaded => _buildHomeContent(context, ref, loaded, isDark),
            },
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }

  /// 构建首页头部
  Widget _buildHeader(BuildContext context, WidgetRef ref, bool isDark, MusicListState state) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF2E1A1A), AppColors.darkBackground] // 深红棕色调
              : [Colors.deepOrange.withValues(alpha: 0.08), Colors.grey[50]!],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.appBarHorizontalPadding,
            AppSpacing.appBarVerticalPadding,
            AppSpacing.appBarHorizontalPadding,
            AppSpacing.lg, // 底部保持较大间距用于 header 效果
          ),
          child: _showSearch
              ? _buildSearchBar(context, ref, isDark)
              : _buildGreetingHeader(context, ref, isDark, state),
        ),
      ),
    );

  /// 问候语头部
  Widget _buildGreetingHeader(BuildContext context, WidgetRef ref, bool isDark, MusicListState state) {
    final trackCount = state is MusicListLoaded ? state.tracks.length : 0;

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
              if (trackCount > 0)
                Text(
                  '共 $trackCount 首歌曲',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => setState(() => _showSearch = true),
          icon: Icon(
            Icons.search_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          tooltip: '搜索',
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
    );
  }

  /// 搜索栏
  Widget _buildSearchBar(BuildContext context, WidgetRef ref, bool isDark) => Row(
      children: [
        IconButton(
          onPressed: () {
            setState(() => _showSearch = false);
            _searchController.clear();
            ref.read(musicListProvider.notifier).setSearchQuery('');
          },
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87),
        ),
        Expanded(
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: '搜索歌曲、艺术家、专辑...',
              hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onChanged: (value) {
              ref.read(musicListProvider.notifier).setSearchQuery(value);
            },
          ),
        ),
        if (_searchController.text.isNotEmpty)
          IconButton(
            onPressed: () {
              _searchController.clear();
              ref.read(musicListProvider.notifier).setSearchQuery('');
            },
            icon: Icon(Icons.close, color: isDark ? Colors.grey[400] : Colors.grey[600]),
          ),
      ],
    );

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

  /// 构建首页内容（现代化设计）
  Widget _buildHomeContent(BuildContext context, WidgetRef ref, MusicListLoaded state, bool isDark) {
    // 如果正在搜索，显示搜索结果
    if (state.searchQuery.isNotEmpty) {
      return _buildSearchResults(context, ref, state, isDark);
    }

    // 获取收藏和历史状态
    final favoritesState = ref.watch(musicFavoritesProvider);
    final historyState = ref.watch(musicHistoryProvider);

    // 转换收藏为 MusicFileWithSource
    final favoriteTracks = favoritesState.favorites
        .where((fav) => state.trackByPath.containsKey(fav.musicPath))
        .map((fav) {
          final m = state.trackByPath[fav.musicPath]!;
          return MusicFileWithSource(
            file: FileItem(
              name: m.fileName,
              path: m.filePath,
              size: m.size ?? 0,
              isDirectory: false,
              modifiedTime: m.modifiedTime,
            ),
            sourceId: m.sourceId,
            title: m.title,
            artist: m.artist,
            album: m.album,
            duration: m.duration,
            year: m.year,
            genre: m.genre,
            coverPath: m.coverPath,
            metadataExtracted: true,
          );
        })
        .toList();

    // 转换历史为 MusicFileWithSource
    final recentTracks = historyState.history
        .take(20)
        .where((h) => state.trackByPath.containsKey(h.musicPath))
        .map((h) {
          final m = state.trackByPath[h.musicPath]!;
          return MusicFileWithSource(
            file: FileItem(
              name: m.fileName,
              path: m.filePath,
              size: m.size ?? 0,
              isDirectory: false,
              modifiedTime: m.modifiedTime,
            ),
            sourceId: m.sourceId,
            title: m.title,
            artist: m.artist,
            album: m.album,
            duration: m.duration,
            year: m.year,
            genre: m.genre,
            coverPath: m.coverPath,
            metadataExtracted: true,
          );
        })
        .toList();

    return MusicHomeContent(
      tracks: state.tracks,
      recentTracks: recentTracks,
      favoriteTracks: favoriteTracks,
      artistCount: state.artistCount,
      albumCount: state.albumCount,
      genreCount: state.genreCount,
      yearCount: state.yearCount,
      folderCount: state.folderCount,
      onTrackTap: (track, allTracks) => _playTrack(context, ref, track, allTracks),
      onCategoryTap: (category) => _navigateToCategory(context, category, state),
    );
  }

  /// 快捷入口网格（仿 Spotify 首页）
  Widget _buildQuickAccessGrid(BuildContext context, WidgetRef ref, MusicListLoaded state, bool isDark, bool isDesktop) {
    final favoritesState = ref.watch(musicFavoritesProvider);
    final historyState = ref.watch(musicHistoryProvider);

    final cards = [
      _QuickAccessCard(
        icon: Icons.favorite_rounded,
        iconColor: Colors.pink,
        title: '我喜欢',
        subtitle: '${favoritesState.favorites.length} 首',
        isDark: isDark,
        isDesktop: isDesktop,
        onTap: () => _navigateToCategory(context, MusicCategory.favorites, state),
      ),
      _QuickAccessCard(
        icon: Icons.history_rounded,
        iconColor: Colors.blue,
        title: '最近播放',
        subtitle: '${historyState.history.length} 首',
        isDark: isDark,
        isDesktop: isDesktop,
        onTap: () => _navigateToCategory(context, MusicCategory.recent, state),
      ),
      _QuickAccessCard(
        icon: Icons.queue_music_rounded,
        iconColor: AppColors.primary,
        title: '全部歌曲',
        subtitle: '${state.tracks.length} 首',
        isDark: isDark,
        isDesktop: isDesktop,
        onTap: () => _navigateToCategory(context, MusicCategory.all, state),
      ),
      _QuickAccessCard(
        icon: Icons.shuffle_rounded,
        iconColor: Colors.green,
        title: '随机播放',
        subtitle: '发现新歌',
        isDark: isDark,
        isDesktop: isDesktop,
        onTap: () => _shufflePlay(context, ref, state),
      ),
    ];

    // 桌面模式：4列，移动端：2列
    final crossAxisCount = isDesktop ? 4 : 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: crossAxisCount,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: isDesktop ? 12 : 8,
        crossAxisSpacing: isDesktop ? 12 : 8,
        childAspectRatio: isDesktop ? 3.5 : 3.2,
        children: cards,
      ),
    );
  }

  /// 最近播放区域
  Widget _buildRecentSection(BuildContext context, WidgetRef ref, MusicListLoaded state, bool isDark, bool isDesktop) {
    final historyState = ref.watch(musicHistoryProvider);
    if (historyState.history.isEmpty) return const SizedBox.shrink();

    // 使用 O(1) 查找替代 O(n) 遍历
    final recentSongs = <MusicFileWithSource>[];
    final maxItems = isDesktop ? 20 : 10;
    for (final historyItem in historyState.history.take(maxItems)) {
      final track = state.getTrackByPath(historyItem.musicPath);
      if (track != null) recentSongs.add(track);
    }
    if (recentSongs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '最近播放',
                style: TextStyle(
                  fontSize: isDesktop ? 20 : 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              TextButton(
                onPressed: () => _navigateToCategory(context, MusicCategory.recent, state),
                child: const Text('查看全部'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 桌面模式使用网格，移动端使用横向滚动
        if (isDesktop)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.8,
              ),
              itemCount: recentSongs.length > 8 ? 8 : recentSongs.length,
              itemBuilder: (context, index) {
                final track = recentSongs[index];
                return _RecentTrackCard(
                  track: track,
                  isDark: isDark,
                  isDesktop: true,
                  onTap: () => _playTrack(context, ref, track, state.tracks),
                );
              },
            ),
          )
        else
          SizedBox(
            height: 175, // 封面120 + 间距8 + 标题16 + 间距2 + 歌手14 + 边距
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: recentSongs.length,
              itemBuilder: (context, index) {
                final track = recentSongs[index];
                return _RecentTrackCard(
                  track: track,
                  isDark: isDark,
                  onTap: () => _playTrack(context, ref, track, state.tracks),
                );
              },
            ),
          ),
      ],
    );
  }

  /// 歌单区域
  Widget _buildPlaylistSection(BuildContext context, WidgetRef ref, MusicListLoaded state, bool isDark, bool isDesktop) {
    final playlistState = ref.watch(playlistProvider);
    final playlists = playlistState.playlists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '我的歌单',
                style: TextStyle(
                  fontSize: isDesktop ? 20 : 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              IconButton(
                onPressed: () => _showCreatePlaylistDialog(context, ref),
                icon: const Icon(Icons.add_rounded),
                tooltip: '新建歌单',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _EmptyPlaylistHint(
              isDark: isDark,
              isDesktop: isDesktop,
              onCreateTap: () => _showCreatePlaylistDialog(context, ref),
            ),
          )
        else if (isDesktop)
          // 桌面模式使用网格布局
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.5,
              ),
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return _PlaylistCard(
                  playlist: playlist,
                  isDark: isDark,
                  allTracks: state.tracks,
                  isDesktop: true,
                );
              },
            ),
          )
        else
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: playlists.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return _PlaylistCard(
                  playlist: playlist,
                  isDark: isDark,
                  allTracks: state.tracks,
                );
              },
            ),
          ),
      ],
    );
  }

  /// 浏览音乐库区域
  Widget _buildBrowseSection(BuildContext context, WidgetRef ref, MusicListLoaded state, bool isDark, bool isDesktop) {
    // 使用预计算的统计数据 - O(1) 而非 O(n)
    final artistCount = state.artistCount;
    final albumCount = state.albumCount;
    final genreCount = state.genreCount;
    final yearCount = state.yearCount;
    final folderCount = state.folderCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '浏览音乐库',
            style: TextStyle(
              fontSize: isDesktop ? 20 : 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: isDesktop ? 12 : 8,
            runSpacing: isDesktop ? 12 : 8,
            children: [
              _BrowseChip(
                icon: Icons.person_rounded,
                label: '艺术家',
                count: artistCount,
                color: Colors.purple,
                isDark: isDark,
                isDesktop: isDesktop,
                onTap: () => _navigateToCategory(context, MusicCategory.artists, state),
              ),
              _BrowseChip(
                icon: Icons.album_rounded,
                label: '专辑',
                count: albumCount,
                color: Colors.orange,
                isDark: isDark,
                isDesktop: isDesktop,
                onTap: () => _navigateToCategory(context, MusicCategory.albums, state),
              ),
              _BrowseChip(
                icon: Icons.category_rounded,
                label: '流派',
                count: genreCount,
                color: Colors.pink,
                isDark: isDark,
                isDesktop: isDesktop,
                onTap: () => _navigateToCategory(context, MusicCategory.genres, state),
              ),
              _BrowseChip(
                icon: Icons.date_range_rounded,
                label: '年代',
                count: yearCount,
                color: Colors.indigo,
                isDark: isDark,
                isDesktop: isDesktop,
                onTap: () => _navigateToCategory(context, MusicCategory.years, state),
              ),
              _BrowseChip(
                icon: Icons.folder_rounded,
                label: '文件夹',
                count: folderCount,
                color: Colors.teal,
                isDark: isDark,
                isDesktop: isDesktop,
                onTap: () => _navigateToCategory(context, MusicCategory.folders, state),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 搜索结果
  Widget _buildSearchResults(BuildContext context, WidgetRef ref, MusicListLoaded state, bool isDark) {
    final results = state.filteredTracks;
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '未找到 "${state.searchQuery}" 相关歌曲',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return _buildMusicContent(context, ref, state, isDark);
  }

  void _navigateToCategory(BuildContext context, MusicCategory category, MusicListLoaded state) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => category == MusicCategory.all
            ? AllSongsPage(tracks: state.tracks)
            : _MusicCategoryPage(
                category: category,
                tracks: state.tracks,
              ),
      ),
    );
  }

  Future<void> _shufflePlay(BuildContext context, WidgetRef ref, MusicListLoaded state) async {
    if (state.tracks.isEmpty) return;

    final connections = ref.read(activeConnectionsProvider);

    // 打乱顺序
    final shuffled = List<MusicFileWithSource>.from(state.tracks)..shuffle();
    final first = shuffled.first;

    try {
      final firstConn = connections[first.sourceId];
      if (firstConn == null || firstConn.status != SourceStatus.connected) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('源未连接，请先连接到 NAS')),
          );
        }
        return;
      }

      final url = await firstConn.adapter.fileSystem.getFileUrl(first.path);
      final musicItem = MusicItem.fromFileItem(first.file, url, sourceId: first.sourceId);

      // 设置播放队列
      final queue = <MusicItem>[];
      for (final track in shuffled.take(50)) {
        final conn = connections[track.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(track.path);
        queue.add(MusicItem.fromFileItem(track.file, trackUrl, sourceId: track.sourceId));
      }

      ref.read(playQueueProvider.notifier).setQueue(queue);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    }
  }

  Future<void> _playTrack(BuildContext context, WidgetRef ref, MusicFileWithSource track, List<MusicFileWithSource> allTracks) async {
    logger.i('_playTrack: 开始播放 ${track.name}');

    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      logger.e('_playTrack: 源未连接 sourceId=${track.sourceId}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('源未连接，请先连接到 NAS')),
        );
      }
      return;
    }

    try {
      logger.d('_playTrack: 获取文件URL, path=${track.path}');
      final url = await connection.adapter.fileSystem.getFileUrl(track.path);
      logger.d('_playTrack: 文件URL => $url');
      final musicItem = MusicItem.fromFileItem(
        track.file,
        url,
        sourceId: track.sourceId,
        // 传递预提取的元数据
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationMs: track.duration,
        trackNumber: track.trackNumber,
        year: track.year,
        genre: track.genre,
        coverData: track.coverData,
      );

      // 找到当前曲目在列表中的索引
      final trackIndex = allTracks.indexWhere((t) => t.path == track.path);

      // 先播放当前曲目
      ref.read(playQueueProvider.notifier).setQueue([musicItem]);
      ref.read(musicPlayerControllerProvider.notifier).updateCurrentIndex(0);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);

      // 记录最近播放
      await ref.read(musicHistoryProvider.notifier).addToHistory(musicItem);

      // 导航到播放器页面
      if (context.mounted) {
        unawaited(MusicPlayerPage.open(context));
      }

      // 在后台构建完整播放队列
      await _buildPlayQueue(ref, connections, track, allTracks, trackIndex);
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    }
  }

  /// 在后台构建播放队列
  Future<void> _buildPlayQueue(
    WidgetRef ref,
    Map<String, SourceConnection> connections,
    MusicFileWithSource currentTrack,
    List<MusicFileWithSource> allTracks,
    int trackIndex,
  ) async {
    try {
      // 构建播放队列（最多50首，以当前曲目为中心）
      const queueSize = 50;
      int startIndex;
      int endIndex;

      if (allTracks.length <= queueSize) {
        startIndex = 0;
        endIndex = allTracks.length;
      } else {
        // 以当前曲目为中心
        final halfSize = queueSize ~/ 2;
        startIndex = (trackIndex - halfSize).clamp(0, allTracks.length - queueSize);
        endIndex = (startIndex + queueSize).clamp(0, allTracks.length);
      }

      final queueTracks = allTracks.sublist(startIndex, endIndex);
      final queue = <MusicItem>[];
      var newCurrentIndex = 0;

      for (var i = 0; i < queueTracks.length; i++) {
        final t = queueTracks[i];
        final conn = connections[t.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(t.path);
        final item = MusicItem.fromFileItem(
          t.file,
          trackUrl,
          sourceId: t.sourceId,
          // 传递预提取的元数据
          title: t.title,
          artist: t.artist,
          album: t.album,
          durationMs: t.duration,
          trackNumber: t.trackNumber,
          year: t.year,
          genre: t.genre,
          coverData: t.coverData,
        );
        queue.add(item);
        if (t.path == currentTrack.path) {
          newCurrentIndex = queue.length - 1;
        }
      }

      // 更新播放队列
      ref.read(playQueueProvider.notifier).setQueue(queue);
      ref.read(musicPlayerControllerProvider.notifier).updateCurrentIndex(newCurrentIndex);
    } on Exception catch (e) {
      logger.w('构建播放队列失败: $e');
    }
  }

  void _showCreatePlaylistDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        title: Text('新建歌单', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '输入歌单名称',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await ref.read(playlistProvider.notifier).createPlaylist(name: name);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(
    BuildContext context,
    double progress,
    String? currentFolder,
    bool fromCache,
    List<MusicFileWithSource> partialTracks,
    int scannedCount,
    bool isDark,
  ) {
    // 如果有部分结果，显示带进度条的列表
    if (partialTracks.isNotEmpty && !fromCache) {
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
                        '正在扫描... 已找到 $scannedCount 首音乐',
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
          // 部分结果列表
          Expanded(
            child: ListView.builder(
              itemCount: partialTracks.length,
              itemBuilder: (context, index) {
                final track = partialTracks[index];
                return ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.music_note_rounded,
                          color: isDark ? Colors.grey[600] : Colors.grey[400],
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  title: Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : null,
                    ),
                  ),
                  subtitle: Text(
                    '扫描中...',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
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

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
  ) {
    // 获取缓存信息
    final cacheService = MusicLibraryCacheService();
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
                Icons.library_music_rounded,
                size: 50,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '音乐库为空',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请在媒体库设置中配置音乐目录并扫描',
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

  Widget _buildMusicContent(
    BuildContext context,
    WidgetRef ref,
    MusicListLoaded state,
    bool isDark,
  ) => RefreshIndicator(
      onRefresh: () => ref.read(musicListProvider.notifier).forceRefresh(),
      child: CustomScrollView(
        slivers: [
          // 音乐列表
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => AnimatedListItem(
                  index: index,
                  child: _MusicListTile(
                    track: state.filteredTracks[index],
                    index: index,
                    isDark: isDark,
                  ),
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

// ==================== 新版首页组件 ====================

/// 快捷入口卡片
class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
    this.isDesktop = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final iconSize = isDesktop ? 48.0 : 40.0;
    final iconInnerSize = isDesktop ? 24.0 : 20.0;

    return Material(
      color: isDark ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5) : Colors.white,
      borderRadius: BorderRadius.circular(isDesktop ? 12 : 8),
      elevation: isDesktop ? 2 : 0,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isDesktop ? 12 : 8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 16 : 12,
            vertical: isDesktop ? 12 : 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isDesktop ? 12 : 8),
            border: isDark
                ? null
                : Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(isDesktop ? 12 : 8),
                ),
                child: Icon(icon, color: iconColor, size: iconInnerSize),
              ),
              SizedBox(width: isDesktop ? 16 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: isDesktop ? 15 : 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: isDesktop ? 13 : 11,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              if (isDesktop)
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 最近播放卡片
class _RecentTrackCard extends StatelessWidget {
  const _RecentTrackCard({
    required this.track,
    required this.isDark,
    required this.onTap,
    this.isDesktop = false,
  });

  final MusicFileWithSource track;
  final bool isDark;
  final VoidCallback onTap;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final coverSize = isDesktop ? 140.0 : 120.0;
    // 使用元数据（如已提取）或从文件名解析
    final title = track.displayTitle;
    final artist = track.displayArtist;
    final coverFile = track.coverFile;
    final coverData = track.coverData;
    final hasCover = coverFile != null || coverData != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isDesktop ? 12 : 8),
        child: Container(
          width: isDesktop ? null : 120,
          margin: isDesktop ? null : const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: coverSize,
                height: coverSize,
                decoration: BoxDecoration(
                  gradient: !hasCover
                      ? LinearGradient(
                          colors: [
                            AppColors.primary.withValues(alpha: 0.7),
                            AppColors.secondary.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(isDesktop ? 12 : 8),
                  boxShadow: isDesktop
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: coverFile != null
                    ? Image.file(
                        coverFile,
                        fit: BoxFit.cover,
                        width: coverSize,
                        height: coverSize,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.music_note_rounded,
                          size: isDesktop ? 56 : 48,
                          color: Colors.white,
                        ),
                      )
                    : coverData != null
                        ? Image.memory(
                            Uint8List.fromList(coverData),
                            fit: BoxFit.cover,
                            width: coverSize,
                            height: coverSize,
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.music_note_rounded,
                              size: isDesktop ? 56 : 48,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            Icons.music_note_rounded,
                            size: isDesktop ? 56 : 48,
                            color: Colors.white,
                          ),
              ),
              SizedBox(height: isDesktop ? 12 : 8),
              SizedBox(
                width: coverSize,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isDesktop ? 14 : 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: coverSize,
                child: Text(
                  artist,
                  style: TextStyle(
                    fontSize: isDesktop ? 12 : 11,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
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
  }
}

/// 歌单卡片
class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.isDark,
    required this.allTracks,
    this.isDesktop = false,
  });

  final PlaylistEntry playlist;
  final bool isDark;
  final List<MusicFileWithSource> allTracks;
  final bool isDesktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconSize = isDesktop ? 64.0 : 56.0;
    final iconInnerSize = isDesktop ? 32.0 : 28.0;

    return Material(
      color: isDark ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5) : Colors.white,
      borderRadius: BorderRadius.circular(isDesktop ? 16 : 12),
      elevation: isDesktop ? 2 : 0,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: () => _showPlaylistDetail(context, ref),
        borderRadius: BorderRadius.circular(isDesktop ? 16 : 12),
        child: Container(
          width: isDesktop ? null : 160,
          padding: EdgeInsets.all(isDesktop ? 16 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isDesktop ? 16 : 12),
            border: isDark ? null : Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(isDesktop ? 12 : 8),
                  boxShadow: isDesktop
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Icon(Icons.queue_music_rounded, color: Colors.white, size: iconInnerSize),
              ),
              SizedBox(width: isDesktop ? 16 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      playlist.name,
                      style: TextStyle(
                        fontSize: isDesktop ? 15 : 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${playlist.trackCount} 首',
                      style: TextStyle(
                        fontSize: isDesktop ? 13 : 11,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              if (isDesktop)
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPlaylistDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _PlaylistDetailSheet(
          playlist: playlist,
          allTracks: allTracks,
          isDark: isDark,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

/// 空歌单提示
class _EmptyPlaylistHint extends StatelessWidget {
  const _EmptyPlaylistHint({
    required this.isDark,
    required this.onCreateTap,
    this.isDesktop = false,
  });

  final bool isDark;
  final VoidCallback onCreateTap;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) => Container(
      padding: EdgeInsets.all(isDesktop ? 32 : 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3) : Colors.grey[100],
        borderRadius: BorderRadius.circular(isDesktop ? 16 : 12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        ),
      ),
      child: isDesktop
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.playlist_add_rounded,
                  size: 48,
                  color: isDark ? Colors.grey[500] : Colors.grey[400],
                ),
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '还没有歌单',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '创建歌单来整理你喜欢的音乐',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 32),
                FilledButton.icon(
                  onPressed: onCreateTap,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('创建歌单'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Icon(
                  Icons.playlist_add_rounded,
                  size: 40,
                  color: isDark ? Colors.grey[500] : Colors.grey[400],
                ),
                const SizedBox(height: 8),
                Text(
                  '还没有歌单',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onCreateTap,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('创建歌单'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
    );
}

/// 浏览分类标签
class _BrowseChip extends StatelessWidget {
  const _BrowseChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
    this.count,
    this.isDesktop = false,
  });

  final IconData icon;
  final String label;
  final int? count;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final borderRadius = isDesktop ? 16.0 : 12.0;

    return Material(
      color: color.withValues(alpha: isDark ? 0.15 : 0.08),
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 16 : 12,
            vertical: isDesktop ? 12 : 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.3 : 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: isDesktop ? 18 : 16, color: color),
              ),
              SizedBox(width: isDesktop ? 10 : 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: isDesktop ? 14 : 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (count != null && count! > 0)
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: isDesktop ? 11 : 10,
                        color: isDark ? Colors.grey[500] : Colors.grey[600],
                      ),
                    ),
                ],
              ),
              SizedBox(width: isDesktop ? 8 : 4),
              Icon(
                Icons.chevron_right_rounded,
                size: isDesktop ? 18 : 16,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 音乐分类页面
class _MusicCategoryPage extends ConsumerWidget {
  const _MusicCategoryPage({
    required this.category,
    required this.tracks,
  });

  final MusicCategory category;
  final List<MusicFileWithSource> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        title: Text(category.label),
        backgroundColor: isDark ? AppColors.darkSurface : null,
      ),
      body: Column(
        children: [
          Expanded(child: _buildContent(context, ref, isDark)),
          const MiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, bool isDark) => switch (category) {
      MusicCategory.all => _AllSongsContent(tracks: tracks, isDark: isDark),
      MusicCategory.artists => _ArtistsView(tracks: tracks, isDark: isDark),
      MusicCategory.albums => _AlbumsView(tracks: tracks, isDark: isDark),
      MusicCategory.folders => _FoldersView(tracks: tracks, isDark: isDark),
      MusicCategory.favorites => _FavoritesView(isDark: isDark),
      MusicCategory.recent => _RecentView(isDark: isDark),
      MusicCategory.genres => _GenresView(tracks: tracks, isDark: isDark),
      MusicCategory.years => _YearsView(tracks: tracks, isDark: isDark),
    };
}

/// 全部歌曲页面 - 独立的页面，支持更丰富的 AppBar
class AllSongsPage extends ConsumerWidget {
  const AllSongsPage({
    required this.tracks,
    super.key,
  });

  final List<MusicFileWithSource> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sortState = ref.watch(musicSortProvider);
    final sortedTracks = _applySorting(tracks, sortState);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      body: Column(
        children: [
          // 自定义顶栏
          _buildAppBar(context, ref, isDark, sortState),
          // 播放控制栏
          _buildPlayControls(context, ref, isDark, sortedTracks),
          // 歌曲列表
          Expanded(
            child: tracks.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: sortedTracks.length,
                    itemBuilder: (context, index) => _ModernMusicTile(
                      track: sortedTracks[index],
                      index: index,
                      isDark: isDark,
                      allTracks: sortedTracks,
                    ),
                  ),
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, WidgetRef ref, bool isDark, MusicSortState sortState) {
    final trackCount = tracks.length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            4,
            AppSpacing.appBarVerticalPadding,
            AppSpacing.appBarHorizontalPadding,
            12,
          ),
          child: Row(
            children: [
              // 返回按钮
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              // 标题和歌曲数量
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '所有歌曲',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      '共 $trackCount 首',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              // 排序按钮
              _SortButton(
                sortState: sortState,
                isDark: isDark,
                onTap: () => _showSortOptions(context, ref, sortState, isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayControls(BuildContext context, WidgetRef ref, bool isDark, List<MusicFileWithSource> sortedTracks) {
    if (tracks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          // 播放全部按钮
          Expanded(
            child: _SpotifyPlayButton(
              onPressed: () => _playAll(context, ref, sortedTracks),
              icon: Icons.play_arrow_rounded,
              label: '播放全部',
            ),
          ),
          const SizedBox(width: 12),
          // 随机播放按钮
          Expanded(
            child: _SpotifyPlayButton(
              onPressed: () => _shufflePlay(context, ref, sortedTracks),
              icon: Icons.shuffle_rounded,
              label: '随机播放',
              isPrimary: false,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.secondary.withValues(alpha: 0.2),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.music_off_rounded, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无歌曲',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '扫描音乐库以添加歌曲',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[600] : Colors.grey[500],
            ),
          ),
        ],
      ),
    );

  List<MusicFileWithSource> _applySorting(
    List<MusicFileWithSource> tracks,
    MusicSortState sortState,
  ) {
    final sorted = List<MusicFileWithSource>.from(tracks)
      ..sort((a, b) {
        int result;
        switch (sortState.option) {
          case MusicSortOption.name:
            result = a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
          case MusicSortOption.artist:
            result = a.displayArtist.toLowerCase().compareTo(b.displayArtist.toLowerCase());
          case MusicSortOption.album:
            result = a.displayAlbum.toLowerCase().compareTo(b.displayAlbum.toLowerCase());
          case MusicSortOption.dateAdded:
            final aTime = a.modifiedTime ?? DateTime(1970);
            final bTime = b.modifiedTime ?? DateTime(1970);
            result = aTime.compareTo(bTime);
          case MusicSortOption.duration:
            result = (a.duration ?? 0).compareTo(b.duration ?? 0);
        }
        return sortState.direction == SortDirection.ascending ? result : -result;
      });

    return sorted;
  }

  void _showSortOptions(BuildContext context, WidgetRef ref, MusicSortState currentSort, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖动指示器
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.sort_rounded,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '排序方式',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  // 排序方向切换
                  _SortDirectionButton(
                    direction: currentSort.direction,
                    isDark: isDark,
                    onTap: () {
                      final newDirection = currentSort.direction == SortDirection.ascending
                          ? SortDirection.descending
                          : SortDirection.ascending;
                      ref.read(musicSortProvider.notifier).state = currentSort.copyWith(
                        direction: newDirection,
                      );
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 排序选项列表
            ...MusicSortOption.values.map((option) => _SortOptionTile(
              option: option,
              isSelected: currentSort.option == option,
              isDark: isDark,
              onTap: () {
                ref.read(musicSortProvider.notifier).state = currentSort.copyWith(
                  option: option,
                );
                Navigator.pop(context);
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _playAll(BuildContext context, WidgetRef ref, List<MusicFileWithSource> sortedTracks) async {
    logger.i('AllSongsPage._playAll: 开始播放全部 (${sortedTracks.length} 首)');

    if (sortedTracks.isEmpty) {
      logger.w('AllSongsPage._playAll: 没有歌曲可播放');
      return;
    }

    final connections = ref.read(activeConnectionsProvider);

    try {
      final first = sortedTracks.first;
      final firstConnection = connections[first.sourceId];
      if (firstConnection == null || firstConnection.status != SourceStatus.connected) {
        logger.e('AllSongsPage._playAll: 第一首歌曲的源未连接');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('源未连接，请先连接到 NAS')),
          );
        }
        return;
      }

      logger.d('AllSongsPage._playAll: 获取第一首歌曲 URL: ${first.path}');
      final url = await firstConnection.adapter.fileSystem.getFileUrl(first.path);
      final musicItem = MusicItem.fromFileItem(first.file, url, sourceId: first.sourceId);

      final queue = <MusicItem>[];
      for (final track in sortedTracks.take(100)) {
        final conn = connections[track.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(track.path);
        queue.add(MusicItem.fromFileItem(track.file, trackUrl, sourceId: track.sourceId));
      }
      logger.d('AllSongsPage._playAll: 创建队列完成 (${queue.length} 首)');

      ref.read(playQueueProvider.notifier).setQueue(queue);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
      logger.i('AllSongsPage._playAll: 播放成功');

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e, stackTrace) {
      logger.e('AllSongsPage._playAll: 播放失败', e, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('播放失败: $e')));
      }
    }
  }

  Future<void> _shufflePlay(BuildContext context, WidgetRef ref, List<MusicFileWithSource> sortedTracks) async {
    logger.i('AllSongsPage._shufflePlay: 开始随机播放 (${sortedTracks.length} 首)');

    if (sortedTracks.isEmpty) {
      logger.w('AllSongsPage._shufflePlay: 没有歌曲可播放');
      return;
    }

    final connections = ref.read(activeConnectionsProvider);
    final shuffled = List<MusicFileWithSource>.from(sortedTracks)..shuffle();
    final first = shuffled.first;

    try {
      final firstConnection = connections[first.sourceId];
      if (firstConnection == null || firstConnection.status != SourceStatus.connected) {
        logger.e('AllSongsPage._shufflePlay: 第一首歌曲的源未连接');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('源未连接，请先连接到 NAS')),
          );
        }
        return;
      }

      logger.d('AllSongsPage._shufflePlay: 获取第一首歌曲 URL: ${first.path}');
      final url = await firstConnection.adapter.fileSystem.getFileUrl(first.path);
      final musicItem = MusicItem.fromFileItem(first.file, url, sourceId: first.sourceId);

      final queue = <MusicItem>[];
      for (final track in shuffled.take(100)) {
        final conn = connections[track.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(track.path);
        queue.add(MusicItem.fromFileItem(track.file, trackUrl, sourceId: track.sourceId));
      }
      logger.d('AllSongsPage._shufflePlay: 创建队列完成 (${queue.length} 首)');

      ref.read(playQueueProvider.notifier).setQueue(queue);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
      logger.i('AllSongsPage._shufflePlay: 播放成功');

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e, stackTrace) {
      logger.e('AllSongsPage._shufflePlay: 播放失败', e, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('播放失败: $e')));
      }
    }
  }
}

/// 排序按钮组件
class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.sortState,
    required this.isDark,
    required this.onTap,
  });

  final MusicSortState sortState;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                sortState.direction == SortDirection.ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 4),
              Text(
                sortState.option.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ],
          ),
        ),
      ),
    );
}

/// 全部歌曲内容（用于嵌入到通用分类页面中）
class _AllSongsContent extends ConsumerWidget {
  const _AllSongsContent({
    required this.tracks,
    required this.isDark,
  });

  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.2),
                    AppColors.secondary.withValues(alpha: 0.2),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.music_off_rounded, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无歌曲',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '扫描音乐库以添加歌曲',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[600] : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    // 应用排序
    final sortState = ref.watch(musicSortProvider);
    final sortedTracks = _applySorting(tracks, sortState);

    return Column(
      children: [
        // 播放控制栏
        _buildControlBar(context, ref, sortState),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: sortedTracks.length,
            itemBuilder: (context, index) => _ModernMusicTile(
              track: sortedTracks[index],
              index: index,
              isDark: isDark,
              allTracks: sortedTracks,
            ),
          ),
        ),
      ],
    );
  }

  List<MusicFileWithSource> _applySorting(
    List<MusicFileWithSource> tracks,
    MusicSortState sortState,
  ) {
    final sorted = List<MusicFileWithSource>.from(tracks)
      ..sort((a, b) {
        int result;
        switch (sortState.option) {
          case MusicSortOption.name:
            result = a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
          case MusicSortOption.artist:
            result = a.displayArtist.toLowerCase().compareTo(b.displayArtist.toLowerCase());
          case MusicSortOption.album:
            result = a.displayAlbum.toLowerCase().compareTo(b.displayAlbum.toLowerCase());
          case MusicSortOption.dateAdded:
            final aTime = a.modifiedTime ?? DateTime(1970);
            final bTime = b.modifiedTime ?? DateTime(1970);
            result = aTime.compareTo(bTime);
          case MusicSortOption.duration:
            result = (a.duration ?? 0).compareTo(b.duration ?? 0);
        }
        return sortState.direction == SortDirection.ascending ? result : -result;
      });

    return sorted;
  }

  Widget _buildControlBar(BuildContext context, WidgetRef ref, MusicSortState sortState) {
    final trackCount = tracks.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部信息行：歌曲数量 + 排序按钮
          Row(
            children: [
              // 歌曲数量
              Text(
                '共 $trackCount 首歌曲',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const Spacer(),
              // 排序按钮
              _SpotifyIconButton(
                icon: Icons.swap_vert_rounded,
                label: sortState.option.label,
                isDark: isDark,
                onTap: () => _showSortOptions(context, ref, sortState),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 播放按钮行
          Row(
            children: [
              // 播放全部按钮
              Expanded(
                child: _SpotifyPlayButton(
                  onPressed: () => _playAll(context, ref),
                  icon: Icons.play_arrow_rounded,
                  label: '播放全部',
                ),
              ),
              const SizedBox(width: 12),
              // 随机播放按钮
              Expanded(
                child: _SpotifyPlayButton(
                  onPressed: () => _shufflePlay(context, ref),
                  icon: Icons.shuffle_rounded,
                  label: '随机播放',
                  isPrimary: false,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSortOptions(BuildContext context, WidgetRef ref, MusicSortState currentSort) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖动指示器
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.sort_rounded,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '排序方式',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  // 排序方向切换
                  _SortDirectionButton(
                    direction: currentSort.direction,
                    isDark: isDark,
                    onTap: () {
                      final newDirection = currentSort.direction == SortDirection.ascending
                          ? SortDirection.descending
                          : SortDirection.ascending;
                      ref.read(musicSortProvider.notifier).state = currentSort.copyWith(
                        direction: newDirection,
                      );
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 排序选项列表
            ...MusicSortOption.values.map((option) => _SortOptionTile(
              option: option,
              isSelected: currentSort.option == option,
              isDark: isDark,
              onTap: () {
                ref.read(musicSortProvider.notifier).state = currentSort.copyWith(
                  option: option,
                );
                Navigator.pop(context);
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _playAll(BuildContext context, WidgetRef ref) async {
    logger.i('_AllSongsView._playAll: 开始播放全部 (${tracks.length} 首)');

    if (tracks.isEmpty) {
      logger.w('_AllSongsView._playAll: 没有歌曲可播放');
      return;
    }

    final connections = ref.read(activeConnectionsProvider);

    try {
      final first = tracks.first;
      final firstConnection = connections[first.sourceId];
      if (firstConnection == null || firstConnection.status != SourceStatus.connected) {
        logger.e('_AllSongsView._playAll: 第一首歌曲的源未连接');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('源未连接，请先连接到 NAS')),
          );
        }
        return;
      }

      logger.d('_AllSongsView._playAll: 获取第一首歌曲 URL: ${first.path}');
      final url = await firstConnection.adapter.fileSystem.getFileUrl(first.path);
      final musicItem = MusicItem.fromFileItem(first.file, url, sourceId: first.sourceId);

      final queue = <MusicItem>[];
      for (final track in tracks.take(100)) {
        final conn = connections[track.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(track.path);
        queue.add(MusicItem.fromFileItem(track.file, trackUrl, sourceId: track.sourceId));
      }
      logger.d('_AllSongsView._playAll: 创建队列完成 (${queue.length} 首)');

      ref.read(playQueueProvider.notifier).setQueue(queue);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
      logger.i('_AllSongsView._playAll: 播放成功');

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e, stackTrace) {
      logger.e('_AllSongsView._playAll: 播放失败', e, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('播放失败: $e')));
      }
    }
  }

  Future<void> _shufflePlay(BuildContext context, WidgetRef ref) async {
    logger.i('_AllSongsView._shufflePlay: 开始随机播放 (${tracks.length} 首)');

    if (tracks.isEmpty) {
      logger.w('_AllSongsView._shufflePlay: 没有歌曲可播放');
      return;
    }

    final connections = ref.read(activeConnectionsProvider);
    final shuffled = List<MusicFileWithSource>.from(tracks)..shuffle();
    final first = shuffled.first;

    try {
      final firstConnection = connections[first.sourceId];
      if (firstConnection == null || firstConnection.status != SourceStatus.connected) {
        logger.e('_AllSongsView._shufflePlay: 第一首歌曲的源未连接');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('源未连接，请先连接到 NAS')),
          );
        }
        return;
      }

      logger.d('_AllSongsView._shufflePlay: 获取第一首歌曲 URL: ${first.path}');
      final url = await firstConnection.adapter.fileSystem.getFileUrl(first.path);
      final musicItem = MusicItem.fromFileItem(first.file, url, sourceId: first.sourceId);

      final queue = <MusicItem>[];
      for (final track in shuffled.take(100)) {
        final conn = connections[track.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(track.path);
        queue.add(MusicItem.fromFileItem(track.file, trackUrl, sourceId: track.sourceId));
      }
      logger.d('_AllSongsView._shufflePlay: 创建队列完成 (${queue.length} 首)');

      ref.read(playQueueProvider.notifier).setQueue(queue);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
      logger.i('_AllSongsView._shufflePlay: 播放成功');

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e, stackTrace) {
      logger.e('_AllSongsView._shufflePlay: 播放失败', e, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('播放失败: $e')));
      }
    }
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

    // 使用元数据（如已提取）或从文件名解析
    final title = track.displayTitle;
    final artist = track.displayArtist;

    // 根据索引生成渐变色
    final gradientColors = _getGradientColorsForIndex(index);

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isPlaying
            ? AppColors.fileAudio.withValues(alpha: isDark ? 0.15 : 0.1)
            : (isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : context.colorScheme.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPlaying
              ? AppColors.fileAudio.withValues(alpha: 0.3)
              : (isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.15)
                  : context.colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playTrack(context, ref),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // 序号
                SizedBox(
                  width: 28,
                  child: isPlaying
                      ? Icon(
                          Icons.equalizer_rounded,
                          color: AppColors.fileAudio,
                          size: 18,
                        )
                      : Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : context.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                // 封面
                _buildCoverWidget(
                  context,
                  title: title,
                  isPlaying: isPlaying,
                  gradientColors: gradientColors,
                ),
                const SizedBox(width: 12),
                // 标题和艺术家
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: isPlaying
                              ? AppColors.fileAudio
                              : (isDark ? AppColors.darkOnSurface : null),
                          fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (track.duration != null) ...[
                            Text(
                              ' · ',
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              track.durationText,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 文件大小标签
                if (track.metadataExtracted)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isDark
                              ? AppColors.darkSurfaceElevated
                              : context.colorScheme.surfaceContainerHighest)
                          .withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      track.displaySize,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : context.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
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
                    PopupMenuItem(
                      value: 'add_to_playlist',
                      child: Row(
                        children: [
                          Icon(
                            Icons.playlist_add_rounded,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '添加到歌单',
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

  /// 构建封面组件
  Widget _buildCoverWidget(
    BuildContext context, {
    required String title,
    required bool isPlaying,
    required List<Color> gradientColors,
  }) {
    final coverFile = track.coverFile;
    final coverData = track.coverData;
    final hasCover = coverFile != null || coverData != null;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: !hasCover
            ? LinearGradient(
                colors: isPlaying
                    ? [AppColors.fileAudio, AppColors.secondary]
                    : gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        boxShadow: isPlaying
            ? [
                BoxShadow(
                  color: AppColors.fileAudio.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: coverFile != null
          ? Image.file(
              coverFile,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => _buildFallbackCover(title),
            )
          : coverData != null
              ? Image.memory(
                  Uint8List.fromList(coverData),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) => _buildFallbackCover(title),
                )
              : _buildFallbackCover(title),
    );
  }

  Widget _buildFallbackCover(String title) => Center(
      child: Text(
        title.isNotEmpty ? title[0].toUpperCase() : '♪',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

  Future<void> _playTrack(BuildContext context, WidgetRef ref) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('源未连接，请先连接到 NAS')),
        );
      }
      return;
    }

    final url = await connection.adapter.fileSystem.getFileUrl(track.path);
    final musicItem = MusicItem.fromFileItem(
      track.file,
      url,
      sourceId: track.sourceId,
      title: track.title,
      artist: track.artist,
      album: track.album,
      durationMs: track.duration,
      trackNumber: track.trackNumber,
      year: track.year,
      genre: track.genre,
      coverData: track.coverData,
    );

    if (!context.mounted) return;

    await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);

    if (!context.mounted) return;
    await MusicPlayerPage.open(context);
  }

  Future<void> _handleMenuAction(BuildContext context, WidgetRef ref, String action) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('源未连接，请先连接到 NAS')),
        );
      }
      return;
    }

    final url = await connection.adapter.fileSystem.getFileUrl(track.path);
    final musicItem = MusicItem.fromFileItem(
      track.file,
      url,
      sourceId: track.sourceId,
      title: track.title,
      artist: track.artist,
      album: track.album,
      durationMs: track.duration,
      trackNumber: track.trackNumber,
      year: track.year,
      genre: track.genre,
      coverData: track.coverData,
    );

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

      case 'add_to_playlist':
        if (context.mounted) {
          _showAddToPlaylistDialog(context, ref, track.path);
        }
    }
  }

  void _showAddToPlaylistDialog(BuildContext context, WidgetRef ref, String trackPath) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final playlistState = ref.read(playlistProvider);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '添加到歌单',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            // 新建歌单选项
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.add_rounded, color: AppColors.primary),
              ),
              title: Text(
                '新建歌单',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
                _showCreateAndAddDialog(context, ref, trackPath);
              },
            ),
            // 已有歌单列表
            if (playlistState.playlists.isNotEmpty) ...[
              const Divider(),
              ...playlistState.playlists.take(5).map((playlist) => ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.7),
                          AppColors.secondary.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.queue_music_rounded, color: Colors.white, size: 20),
                  ),
                  title: Text(
                    playlist.name,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  ),
                  subtitle: Text(
                    '${playlist.trackCount} 首歌曲',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  onTap: () async {
                    await ref.read(playlistProvider.notifier).addToPlaylist(playlist.id, trackPath);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已添加到歌单"${playlist.name}"'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                )),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showCreateAndAddDialog(BuildContext context, WidgetRef ref, String trackPath) {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        title: Text(
          '新建歌单',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '输入歌单名称',
            hintStyle: TextStyle(
              color: isDark ? Colors.grey[500] : Colors.grey[400],
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final playlist = await ref
                    .read(playlistProvider.notifier)
                    .createPlaylist(name: name, initialTracks: [trackPath]);
                if (context.mounted && playlist != null) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已添加到新歌单"$name"'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('创建并添加'),
          ),
        ],
      ),
    );
  }
}

/// 艺术家视图
class _ArtistsView extends ConsumerWidget {
  const _ArtistsView({
    required this.tracks,
    required this.isDark,
  });

  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 按艺术家分组（使用元数据或从文件名解析）
    final artistMap = <String, List<MusicFileWithSource>>{};
    for (final track in tracks) {
      final artist = track.displayArtist;
      artistMap.putIfAbsent(artist, () => []).add(track);
    }

    final artists = artistMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (artists.isEmpty) {
      return _buildEmptyView('暂无艺术家', Icons.person_off_rounded, isDark);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final entry = artists[index];
        return _ArtistTile(
          artistName: entry.key,
          tracks: entry.value,
          isDark: isDark,
        );
      },
    );
  }
}

class _ArtistTile extends ConsumerWidget {
  const _ArtistTile({
    required this.artistName,
    required this.tracks,
    required this.isDark,
  });

  final String artistName;
  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.8),
                AppColors.secondary.withValues(alpha: 0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.person_rounded, color: Colors.white, size: 24),
        ),
        title: Text(
          artistName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Text(
          '${tracks.length} 首歌曲',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        children: tracks.asMap().entries.map((entry) => _CompactMusicTile(
            track: entry.value,
            isDark: isDark,
            allTracks: tracks,
            trackIndex: entry.key,
          )).toList(),
      ),
    );
}

/// 专辑视图
class _AlbumsView extends ConsumerWidget {
  const _AlbumsView({
    required this.tracks,
    required this.isDark,
  });

  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 按文件夹作为"专辑"分组（因为没有真正的专辑元数据）
    final albumMap = <String, List<MusicFileWithSource>>{};
    for (final track in tracks) {
      final parts = track.path.split('/');
      final album = parts.length >= 2 ? parts[parts.length - 2] : '未知专辑';
      albumMap.putIfAbsent(album, () => []).add(track);
    }

    final albums = albumMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (albums.isEmpty) {
      return _buildEmptyView('暂无专辑', Icons.album_outlined, isDark);
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final entry = albums[index];
        return _AlbumCard(
          albumName: entry.key,
          tracks: entry.value,
          isDark: isDark,
        );
      },
    );
  }
}

class _AlbumCard extends ConsumerWidget {
  const _AlbumCard({
    required this.albumName,
    required this.tracks,
    required this.isDark,
  });

  final String albumName;
  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
      onTap: () => _showAlbumTracks(context, ref),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
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
                  gradient: LinearGradient(
                    colors: [
                      AppColors.fileAudio.withValues(alpha: 0.7),
                      AppColors.secondary.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: const Center(
                  child: Icon(Icons.album_rounded, size: 48, color: Colors.white),
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
                        albumName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    Text(
                      '${tracks.length} 首歌曲',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
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

  void _showAlbumTracks(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.fileAudio, AppColors.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.album_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              albumName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              '${tracks.length} 首歌曲',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      _PlayAllButton(tracks: tracks, isDark: isDark),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: tracks.length,
                itemBuilder: (context, index) => _CompactMusicTile(
                    track: tracks[index],
                    isDark: isDark,
                    allTracks: tracks,
                    trackIndex: index,
                  ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 文件夹视图
class _FoldersView extends ConsumerWidget {
  const _FoldersView({
    required this.tracks,
    required this.isDark,
  });

  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 按文件夹分组
    final folderMap = <String, List<MusicFileWithSource>>{};
    for (final track in tracks) {
      final parts = track.path.split('/');
      final folder = parts.length >= 2 ? parts[parts.length - 2] : '根目录';
      folderMap.putIfAbsent(folder, () => []).add(track);
    }

    final folders = folderMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (folders.isEmpty) {
      return _buildEmptyView('暂无文件夹', Icons.folder_off_rounded, isDark);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final entry = folders[index];
        return _FolderTile(
          folderName: entry.key,
          tracks: entry.value,
          isDark: isDark,
        );
      },
    );
  }
}

class _FolderTile extends ConsumerWidget {
  const _FolderTile({
    required this.folderName,
    required this.tracks,
    required this.isDark,
  });

  final String folderName;
  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.fileAudio.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.folder_rounded, color: AppColors.fileAudio, size: 24),
        ),
        title: Text(
          folderName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Text(
          '${tracks.length} 首歌曲',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        children: tracks.asMap().entries.map((entry) => _CompactMusicTile(
            track: entry.value,
            isDark: isDark,
            allTracks: tracks,
            trackIndex: entry.key,
          )).toList(),
      ),
    );
}

/// 流派视图
class _GenresView extends ConsumerWidget {
  const _GenresView({
    required this.tracks,
    required this.isDark,
  });

  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 按流派分组
    final genreMap = <String, List<MusicFileWithSource>>{};
    for (final track in tracks) {
      if (track.genre != null && track.genre!.isNotEmpty) {
        // 流派可能是逗号分隔的多个
        for (final g in track.genre!.split(',')) {
          final genre = g.trim();
          if (genre.isNotEmpty) {
            genreMap.putIfAbsent(genre, () => []).add(track);
          }
        }
      } else {
        genreMap.putIfAbsent('未知流派', () => []).add(track);
      }
    }

    final genres = genreMap.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length)); // 按歌曲数量排序

    if (genres.isEmpty) {
      return _buildEmptyView('暂无流派信息', Icons.category_outlined, isDark);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: genres.length,
      itemBuilder: (context, index) {
        final entry = genres[index];
        return _GenreTile(
          genreName: entry.key,
          tracks: entry.value,
          isDark: isDark,
          color: _getColorForIndex(index),
        );
      },
    );
  }

  Color _getColorForIndex(int index) {
    final colors = [
      Colors.pink,
      Colors.purple,
      Colors.indigo,
      Colors.blue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.orange,
      Colors.deepOrange,
      Colors.red,
    ];
    return colors[index % colors.length];
  }
}

class _GenreTile extends ConsumerWidget {
  const _GenreTile({
    required this.genreName,
    required this.tracks,
    required this.isDark,
    required this.color,
  });

  final String genreName;
  final List<MusicFileWithSource> tracks;
  final bool isDark;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.8), color.withValues(alpha: 0.4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.category_rounded, color: Colors.white, size: 24),
        ),
        title: Text(
          genreName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Text(
          '${tracks.length} 首歌曲',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        children: tracks.asMap().entries.map((entry) => _CompactMusicTile(
            track: entry.value,
            isDark: isDark,
            allTracks: tracks,
            trackIndex: entry.key,
          )).toList(),
      ),
    );
}

/// 年代视图
class _YearsView extends ConsumerWidget {
  const _YearsView({
    required this.tracks,
    required this.isDark,
  });

  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 按年代分组
    final yearMap = <String, List<MusicFileWithSource>>{};
    for (final track in tracks) {
      if (track.year != null && track.year! > 1900) {
        // 按年代（每10年）分组
        final decade = (track.year! ~/ 10) * 10;
        final decadeLabel = '${decade}s';
        yearMap.putIfAbsent(decadeLabel, () => []).add(track);
      } else {
        yearMap.putIfAbsent('未知年代', () => []).add(track);
      }
    }

    final years = yearMap.entries.toList()
      ..sort((a, b) {
        // 未知年代放最后
        if (a.key == '未知年代') return 1;
        if (b.key == '未知年代') return -1;
        return b.key.compareTo(a.key); // 按年代倒序
      });

    if (years.isEmpty) {
      return _buildEmptyView('暂无年代信息', Icons.date_range_rounded, isDark);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: years.length,
      itemBuilder: (context, index) {
        final entry = years[index];
        return _YearTile(
          yearLabel: entry.key,
          tracks: entry.value,
          isDark: isDark,
          color: _getColorForDecade(entry.key),
        );
      },
    );
  }

  Color _getColorForDecade(String decade) {
    switch (decade) {
      case '2020s':
        return Colors.purple;
      case '2010s':
        return Colors.blue;
      case '2000s':
        return Colors.teal;
      case '1990s':
        return Colors.green;
      case '1980s':
        return Colors.orange;
      case '1970s':
        return Colors.deepOrange;
      case '1960s':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

class _YearTile extends ConsumerWidget {
  const _YearTile({
    required this.yearLabel,
    required this.tracks,
    required this.isDark,
    required this.color,
  });

  final String yearLabel;
  final List<MusicFileWithSource> tracks;
  final bool isDark;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: ExpansionTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.8), color.withValues(alpha: 0.4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              yearLabel.replaceAll('s', ''),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        title: Text(
          yearLabel == '未知年代' ? yearLabel : '$yearLabel 年代',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Text(
          '${tracks.length} 首歌曲',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        children: tracks.asMap().entries.map((entry) => _CompactMusicTile(
            track: entry.value,
            isDark: isDark,
            allTracks: tracks,
            trackIndex: entry.key,
          )).toList(),
      ),
    );
}

/// 收藏视图
class _FavoritesView extends ConsumerWidget {
  const _FavoritesView({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesState = ref.watch(musicFavoritesProvider);
    final favorites = favoritesState.favorites;

    if (favorites.isEmpty) {
      return _buildEmptyView('暂无收藏', Icons.favorite_outline_rounded, isDark);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final item = favorites[index].toMusicItem();
        return _FavoriteTrackTile(item: item, isDark: isDark);
      },
    );
  }
}

class _FavoriteTrackTile extends ConsumerWidget {
  const _FavoriteTrackTile({
    required this.item,
    required this.isDark,
  });

  final MusicItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = currentMusic?.id == item.id;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isPlaying
            ? AppColors.fileAudio.withValues(alpha: isDark ? 0.15 : 0.1)
            : (isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPlaying
              ? AppColors.fileAudio.withValues(alpha: 0.3)
              : (isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: ListTile(
        onTap: () async {
          await ref.read(musicPlayerControllerProvider.notifier).play(item);
          if (context.mounted) {
            await MusicPlayerPage.open(context);
          }
        },
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: isPlaying
                ? const LinearGradient(
                    colors: [AppColors.fileAudio, AppColors.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isPlaying ? null : (isDark ? Colors.grey[800] : Colors.grey[200]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isPlaying ? Icons.equalizer_rounded : Icons.music_note_rounded,
            color: isPlaying ? Colors.white : (isDark ? Colors.grey[600] : Colors.grey[400]),
          ),
        ),
        title: Text(
          item.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
            color: isPlaying ? AppColors.fileAudio : (isDark ? Colors.white : Colors.black87),
          ),
        ),
        subtitle: Text(
          item.displayArtist,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.favorite_rounded, color: Colors.red[400]),
          onPressed: () async {
            await ref.read(musicFavoritesProvider.notifier).toggleFavorite(item);
          },
        ),
      ),
    );
  }
}

/// 最近播放视图
class _RecentView extends ConsumerWidget {
  const _RecentView({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentTracks = ref.watch(recentTracksProvider);

    if (recentTracks.isEmpty) {
      return _buildEmptyView('暂无播放记录', Icons.history_rounded, isDark);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: recentTracks.length,
      itemBuilder: (context, index) {
        final item = recentTracks[index];
        return _RecentTrackTile(item: item, isDark: isDark);
      },
    );
  }
}

class _RecentTrackTile extends ConsumerWidget {
  const _RecentTrackTile({
    required this.item,
    required this.isDark,
  });

  final MusicItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = currentMusic?.id == item.id;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isPlaying
            ? AppColors.fileAudio.withValues(alpha: isDark ? 0.15 : 0.1)
            : (isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPlaying
              ? AppColors.fileAudio.withValues(alpha: 0.3)
              : (isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: ListTile(
        onTap: () async {
          await ref.read(musicPlayerControllerProvider.notifier).play(item);
          if (context.mounted) {
            await MusicPlayerPage.open(context);
          }
        },
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: item.coverData == null && item.coverUrl == null
                ? LinearGradient(
                    colors: isPlaying
                        ? [AppColors.fileAudio, AppColors.secondary]
                        : [
                            AppColors.primary.withValues(alpha: 0.7),
                            AppColors.secondary.withValues(alpha: 0.7),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildCover(isPlaying),
        ),
        title: Text(
          item.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
            color: isPlaying ? AppColors.fileAudio : (isDark ? Colors.white : Colors.black87),
          ),
        ),
        subtitle: Text(
          item.displayArtist,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        trailing: Icon(
          Icons.play_arrow_rounded,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildCover(bool isPlaying) {
    // 优先使用嵌入的封面数据
    if (item.coverData != null && item.coverData!.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            Uint8List.fromList(item.coverData!),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _buildPlaceholder(isPlaying),
          ),
          if (isPlaying) _buildPlayingOverlay(),
        ],
      );
    }

    // 其次使用封面 URL
    if (item.coverUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            item.coverUrl!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _buildPlaceholder(isPlaying),
          ),
          if (isPlaying) _buildPlayingOverlay(),
        ],
      );
    }

    // 默认显示音符图标
    return _buildPlaceholder(isPlaying);
  }

  Widget _buildPlaceholder(bool isPlaying) => Center(
        child: Icon(
          isPlaying ? Icons.equalizer_rounded : Icons.music_note_rounded,
          color: Colors.white,
          size: 24,
        ),
      );

  Widget _buildPlayingOverlay() => ColoredBox(
        color: Colors.black.withValues(alpha: 0.3),
        child: const Center(
          child: Icon(
            Icons.equalizer_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      );
}

/// 歌单视图
class _PlaylistDetailSheet extends ConsumerWidget {
  const _PlaylistDetailSheet({
    required this.playlist,
    required this.allTracks,
    required this.isDark,
    required this.scrollController,
  });

  final PlaylistEntry playlist;
  final List<MusicFileWithSource> allTracks;
  final bool isDark;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 根据路径找到对应的歌曲
    final tracksInPlaylist = <MusicFileWithSource>[];
    for (final path in playlist.trackPaths) {
      final track = allTracks.where((t) => t.path == path).firstOrNull;
      if (track != null) {
        tracksInPlaylist.add(track);
      }
    }

    return Column(
      children: [
        // 标题栏
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.queue_music_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          playlist.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          '${tracksInPlaylist.length} 首歌曲',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (tracksInPlaylist.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () => _playAll(context, ref, tracksInPlaylist),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('播放'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // 歌曲列表
        Expanded(
          child: tracksInPlaylist.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.music_off_rounded,
                        size: 48,
                        color: isDark ? Colors.grey[600] : Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '歌单暂无歌曲',
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '在歌曲菜单中选择"添加到歌单"',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[500] : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  itemCount: tracksInPlaylist.length,
                  itemBuilder: (context, index) => _PlaylistTrackTile(
                      track: tracksInPlaylist[index],
                      playlistId: playlist.id,
                      isDark: isDark,
                    ),
                ),
        ),
      ],
    );
  }

  Future<void> _playAll(
    BuildContext context,
    WidgetRef ref,
    List<MusicFileWithSource> tracksInPlaylist,
  ) async {
    if (tracksInPlaylist.isEmpty) return;

    final connections = ref.read(activeConnectionsProvider);

    final musicItems = <MusicItem>[];
    for (final track in tracksInPlaylist) {
      final connection = connections[track.sourceId];
      if (connection == null || connection.status != SourceStatus.connected) {
        continue; // 跳过未连接源的歌曲
      }
      final url = await connection.adapter.fileSystem.getFileUrl(track.path);
      musicItems.add(MusicItem.fromFileItem(track.file, url, sourceId: track.sourceId));
    }

    if (musicItems.isEmpty) return;

    ref.read(playQueueProvider.notifier).setQueue(musicItems);
    await ref.read(musicPlayerControllerProvider.notifier).play(musicItems.first);

    if (context.mounted) {
      Navigator.of(context).pop();
      await MusicPlayerPage.open(context);
    }
  }
}

class _PlaylistTrackTile extends ConsumerWidget {
  const _PlaylistTrackTile({
    required this.track,
    required this.playlistId,
    required this.isDark,
  });

  final MusicFileWithSource track;
  final String playlistId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 使用元数据（如已提取）或从文件名解析
    final title = track.displayTitle;
    final artist = track.displayArtist;
    final coverFile = track.coverFile;
    final coverData = track.coverData;

    return ListTile(
      onTap: () => _playTrack(context, ref),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: coverFile != null
            ? Image.file(
                coverFile,
                fit: BoxFit.cover,
                width: 40,
                height: 40,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.music_note_rounded,
                  size: 20,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
              )
            : coverData != null
                ? Image.memory(
                    Uint8List.fromList(coverData),
                    fit: BoxFit.cover,
                    width: 40,
                    height: 40,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.music_note_rounded,
                      size: 20,
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                    ),
                  )
                : Icon(
                    Icons.music_note_rounded,
                    size: 20,
                    color: isDark ? Colors.grey[600] : Colors.grey[400],
                  ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: Text(
        '$artist${track.duration != null ? ' · ${track.durationText}' : ''}',
        style: TextStyle(
          fontSize: 11,
          color: isDark ? Colors.grey[500] : Colors.grey[600],
        ),
      ),
      trailing: IconButton(
        onPressed: () async {
          await ref.read(playlistProvider.notifier).removeFromPlaylist(playlistId, track.path);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已从歌单中移除'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        icon: Icon(
          Icons.remove_circle_outline_rounded,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
    );
  }

  Future<void> _playTrack(BuildContext context, WidgetRef ref) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('源未连接，请先连接到 NAS')),
        );
      }
      return;
    }

    final url = await connection.adapter.fileSystem.getFileUrl(track.path);
    final musicItem = MusicItem.fromFileItem(track.file, url, sourceId: track.sourceId);

    if (!context.mounted) return;

    await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);

    if (!context.mounted) return;
    Navigator.of(context).pop();
    await MusicPlayerPage.open(context);
  }
}

/// 排序方向切换按钮
class _SortDirectionButton extends StatelessWidget {
  const _SortDirectionButton({
    required this.direction,
    required this.isDark,
    required this.onTap,
  });

  final SortDirection direction;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                direction == SortDirection.ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 4),
              Text(
                direction == SortDirection.ascending ? '升序' : '降序',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
}

/// 排序选项列表项
class _SortOptionTile extends StatelessWidget {
  const _SortOptionTile({
    required this.option,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final MusicSortOption option;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : (isDark ? Colors.grey[800] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          option.icon,
          color: isSelected
              ? AppColors.primary
              : (isDark ? Colors.white70 : Colors.black54),
          size: 20,
        ),
      ),
      title: Text(
        option.label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected
              ? AppColors.primary
              : (isDark ? Colors.white : Colors.black87),
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_rounded, color: AppColors.primary, size: 22)
          : null,
      onTap: onTap,
    );
}

/// Spotify 风格播放按钮
class _SpotifyPlayButton extends StatelessWidget {
  const _SpotifyPlayButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.isPrimary = true,
    this.isDark = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool isPrimary;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            gradient: isPrimary
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.secondary],
                  )
                : null,
            color: isPrimary
                ? null
                : (isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey[200]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isPrimary
                      ? Colors.white
                      : (isDark ? Colors.white : Colors.black87),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isPrimary
                        ? Colors.white
                        : (isDark ? Colors.white : Colors.black87),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
}

/// Spotify 风格图标按钮（带文字）
class _SpotifyIconButton extends StatelessWidget {
  const _SpotifyIconButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 18,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ],
          ),
        ),
      ),
    );
}

/// 现代风格音乐列表项
class _ModernMusicTile extends ConsumerWidget {
  const _ModernMusicTile({
    required this.track,
    required this.index,
    required this.isDark,
    required this.allTracks,
  });

  final MusicFileWithSource track;
  final int index;
  final bool isDark;
  final List<MusicFileWithSource> allTracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final isPlaying = currentMusic?.path == track.path;
    final title = track.displayTitle;
    final artist = track.displayArtist;
    final coverFile = track.coverFile;
    final coverData = track.coverData;

    // 检查源是否已连接
    final connections = ref.watch(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    final isConnected = connection != null && connection.status == SourceStatus.connected;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isPlaying
            ? AppColors.primary.withValues(alpha: isDark ? 0.15 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playTrack(context, ref),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // 序号或播放指示器
                SizedBox(
                  width: 32,
                  child: isPlaying
                      ? _PlayingIndicator(isDark: isDark)
                      : Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.grey[500]
                                : Colors.grey[600],
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                // 封面
                _buildCover(coverFile, coverData, title, isPlaying, isConnected),
                const SizedBox(width: 14),
                // 标题和艺术家
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                          color: isPlaying
                              ? AppColors.primary
                              : isConnected
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : (isDark ? Colors.grey[600] : Colors.grey[500]),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (!isConnected) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '离线',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey[500] : Colors.grey[600],
                              ),
                            ),
                          ),
                          if (track.duration != null) ...[
                            Text(
                              ' · ',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey[600] : Colors.grey[500],
                              ),
                            ),
                            Text(
                              track.durationText,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey[600] : Colors.grey[500],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 更多按钮
                IconButton(
                  onPressed: () => _showMoreOptions(context, ref),
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                    size: 22,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(File? coverFile, List<int>? coverData, String title, bool isPlaying, bool isConnected) {
    final size = 52.0;
    final _ = coverFile != null || coverData != null;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isDark ? Colors.grey[800] : Colors.grey[200],
        boxShadow: isPlaying
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: coverFile != null
          ? Image.file(
              coverFile,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _buildFallbackCover(title, isConnected),
            )
          : coverData != null
              ? Image.memory(
                  Uint8List.fromList(coverData),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _buildFallbackCover(title, isConnected),
            )
          : _buildFallbackCover(title, isConnected),
    );
  }

  Widget _buildFallbackCover(String title, bool isConnected) {
    final gradientColors = _getGradientForTitle(title);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          title.isNotEmpty ? title[0].toUpperCase() : '♪',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Color> _getGradientForTitle(String title) {
    final hash = title.hashCode;
    final gradients = [
      [const Color(0xFF667eea), const Color(0xFF764ba2)],
      [const Color(0xFFf093fb), const Color(0xFFf5576c)],
      [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
      [const Color(0xFF43e97b), const Color(0xFF38f9d7)],
      [const Color(0xFFfa709a), const Color(0xFFfee140)],
      [const Color(0xFF30cfd0), const Color(0xFF330867)],
      [const Color(0xFFa8edea), const Color(0xFFfed6e3)],
      [const Color(0xFFff9a9e), const Color(0xFFfecfef)],
    ];
    return gradients[hash.abs() % gradients.length];
  }

  Future<void> _playTrack(BuildContext context, WidgetRef ref) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('源未连接，请先连接到 NAS')),
        );
      }
      return;
    }

    try {
      final url = await connection.adapter.fileSystem.getFileUrl(track.path);
      final musicItem = MusicItem.fromFileItem(
        track.file,
        url,
        sourceId: track.sourceId,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationMs: track.duration,
        trackNumber: track.trackNumber,
        year: track.year,
        genre: track.genre,
        coverData: track.coverData,
      );

      // 设置播放队列
      final queue = <MusicItem>[];
      for (final t in allTracks) {
        final conn = connections[t.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(t.path);
        queue.add(MusicItem.fromFileItem(
          t.file,
          trackUrl,
          sourceId: t.sourceId,
          title: t.title,
          artist: t.artist,
          album: t.album,
          durationMs: t.duration,
          coverData: t.coverData,
        ));
      }

      ref.read(playQueueProvider.notifier).setQueue(queue);
      ref.read(musicPlayerControllerProvider.notifier).updateCurrentIndex(index);
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);

      if (context.mounted) {
        await MusicPlayerPage.open(context);
      }
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    }
  }

  void _showMoreOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽指示器
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 歌曲信息头
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: isDark ? Colors.grey[800] : Colors.grey[200],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: track.coverFile != null
                        ? Image.file(
                            track.coverFile!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.music_note_rounded,
                              color: isDark ? Colors.grey[600] : Colors.grey[400],
                            ),
                          )
                        : track.coverData != null
                            ? Image.memory(
                                Uint8List.fromList(track.coverData!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.music_note_rounded,
                                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                                ),
                              )
                            : Icon(
                                Icons.music_note_rounded,
                                color: isDark ? Colors.grey[600] : Colors.grey[400],
                              ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          track.displayArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _BottomSheetOption(
              icon: Icons.queue_play_next_rounded,
              label: '下一首播放',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                // TODO: Add to play next
              },
            ),
            _BottomSheetOption(
              icon: Icons.playlist_add_rounded,
              label: '添加到播放队列',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                // TODO: Add to queue
              },
            ),
            _BottomSheetOption(
              icon: Icons.favorite_border_rounded,
              label: '添加到我喜欢',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                // TODO: Add to favorites
              },
            ),
            _BottomSheetOption(
              icon: Icons.playlist_add_check_rounded,
              label: '添加到歌单',
              isDark: isDark,
              onTap: () {
                Navigator.pop(context);
                // TODO: Add to playlist
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 播放中动画指示器
class _PlayingIndicator extends StatefulWidget {
  const _PlayingIndicator({required this.isDark});
  final bool isDark;

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final animValue = (_controller.value + delay) % 1.0;
            return Container(
              width: 3,
              height: 8 + (animValue * 8),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
    );
}

/// 底部弹窗选项
class _BottomSheetOption extends StatelessWidget {
  const _BottomSheetOption({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
      leading: Icon(icon, color: isDark ? Colors.white70 : Colors.black87),
      title: Text(
        label,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      ),
      onTap: onTap,
    );
}

/// 紧凑型音乐列表项
class _CompactMusicTile extends ConsumerWidget {
  const _CompactMusicTile({
    required this.track,
    required this.isDark,
    this.allTracks,
    this.trackIndex,
  });

  final MusicFileWithSource track;
  final bool isDark;
  final List<MusicFileWithSource>? allTracks;
  final int? trackIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 使用元数据（如已提取）或从文件名解析
    final title = track.displayTitle;
    final artist = track.displayArtist;
    final coverFile = track.coverFile;
    final coverData = track.coverData;

    // 检查源是否已连接
    final connections = ref.watch(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    final isConnected = connection != null && connection.status == SourceStatus.connected;

    Widget buildFallbackIcon() => Icon(
          Icons.music_note_rounded,
          size: 20,
          color: isConnected
              ? (isDark ? Colors.grey[600] : Colors.grey[400])
              : (isDark ? Colors.grey[700] : Colors.grey[350]),
        );

    return ListTile(
      onTap: () => _playTrack(context, ref),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Stack(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: coverFile != null
                ? Image.file(
                    coverFile,
                    fit: BoxFit.cover,
                    width: 40,
                    height: 40,
                    errorBuilder: (context, error, stackTrace) => buildFallbackIcon(),
                  )
                : coverData != null
                    ? Image.memory(
                        Uint8List.fromList(coverData),
                        fit: BoxFit.cover,
                        width: 40,
                        height: 40,
                        errorBuilder: (context, error, stackTrace) => buildFallbackIcon(),
                      )
                    : buildFallbackIcon(),
          ),
          if (!isConnected)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.link_off,
                  size: 8,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: isConnected
              ? (isDark ? Colors.white : Colors.black87)
              : (isDark ? Colors.grey[500] : Colors.grey[600]),
        ),
      ),
      subtitle: Text(
        isConnected
            ? '$artist${track.duration != null ? ' · ${track.durationText}' : ''}'
            : '$artist • 源未连接',
        style: TextStyle(
          fontSize: 11,
          color: isConnected
              ? (isDark ? Colors.grey[500] : Colors.grey[600])
              : Colors.orange,
        ),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) => _handleAction(context, ref, value),
        icon: Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'play_next', child: Text('下一首播放')),
          const PopupMenuItem(value: 'add_to_queue', child: Text('添加到队列')),
          const PopupMenuItem(value: 'add_to_favorites', child: Text('收藏')),
          const PopupMenuItem(value: 'add_to_playlist', child: Text('添加到歌单')),
        ],
      ),
    );
  }

  Future<void> _playTrack(BuildContext context, WidgetRef ref) async {
    logger.i('_CompactMusicTile._playTrack: 开始播放 ${track.name}');

    // 通过 sourceId 从已连接的源中获取适配器
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      logger.e('_CompactMusicTile._playTrack: 源未连接 sourceId=${track.sourceId}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('源未连接，请先连接到 NAS')),
        );
      }
      return;
    }
    final adapter = connection.adapter;

    try {
      logger.d('_CompactMusicTile._playTrack: 获取文件 URL: ${track.path}');
      final url = await adapter.fileSystem.getFileUrl(track.path);
      logger.d('_CompactMusicTile._playTrack: 获取到 URL: $url');

      final musicItem = MusicItem.fromFileItem(
        track.file,
        url,
        sourceId: track.sourceId,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationMs: track.duration,
        trackNumber: track.trackNumber,
        year: track.year,
        genre: track.genre,
        coverData: track.coverData,
      );
      logger.d('_CompactMusicTile._playTrack: 创建 MusicItem 成功');

      if (!context.mounted) {
        logger.w('_CompactMusicTile._playTrack: context 已卸载');
        return;
      }

      // 先播放当前曲目
      ref.read(playQueueProvider.notifier).setQueue([musicItem]);
      ref.read(musicPlayerControllerProvider.notifier).updateCurrentIndex(0);
      logger.d('_CompactMusicTile._playTrack: 调用播放器播放');
      await ref.read(musicPlayerControllerProvider.notifier).play(musicItem);
      logger.i('_CompactMusicTile._playTrack: 播放成功，跳转到播放页');

      // 导航到播放器页面
      if (!context.mounted) return;
      unawaited(MusicPlayerPage.open(context));

      // 在后台构建完整播放队列
      if (allTracks != null && allTracks!.isNotEmpty) {
        await _buildPlayQueue(ref, connections, trackIndex ?? 0);
      }
    } on Exception catch (e, stackTrace) {
      logger.e('_CompactMusicTile._playTrack: 播放失败', e, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    }
  }

  /// 在后台构建播放队列
  Future<void> _buildPlayQueue(
    WidgetRef ref,
    Map<String, SourceConnection> connections,
    int currentIndex,
  ) async {
    if (allTracks == null) return;

    try {
      // 构建播放队列（最多50首，以当前曲目为中心）
      const queueSize = 50;
      int startIndex;
      int endIndex;

      if (allTracks!.length <= queueSize) {
        startIndex = 0;
        endIndex = allTracks!.length;
      } else {
        // 以当前曲目为中心
        final halfSize = queueSize ~/ 2;
        startIndex = (currentIndex - halfSize).clamp(0, allTracks!.length - queueSize);
        endIndex = (startIndex + queueSize).clamp(0, allTracks!.length);
      }

      final queueTracks = allTracks!.sublist(startIndex, endIndex);
      final queue = <MusicItem>[];
      var newCurrentIndex = 0;

      for (var i = 0; i < queueTracks.length; i++) {
        final t = queueTracks[i];
        final conn = connections[t.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) continue;
        final trackUrl = await conn.adapter.fileSystem.getFileUrl(t.path);
        final item = MusicItem.fromFileItem(t.file, trackUrl, sourceId: t.sourceId);
        queue.add(item);
        if (t.path == track.path) {
          newCurrentIndex = queue.length - 1;
        }
      }

      // 更新播放队列
      ref.read(playQueueProvider.notifier).setQueue(queue);
      ref.read(musicPlayerControllerProvider.notifier).updateCurrentIndex(newCurrentIndex);
      logger.d('_CompactMusicTile._buildPlayQueue: 队列构建完成，共 ${queue.length} 首');
    } on Exception catch (e) {
      logger.w('_CompactMusicTile._buildPlayQueue: 构建播放队列失败: $e');
    }
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, String action) async {
    logger.i('_CompactMusicTile._handleAction: action=$action, track=${track.name}');

    // 通过 sourceId 从已连接的源中获取适配器
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[track.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      logger.e('_CompactMusicTile._handleAction: 源未连接 sourceId=${track.sourceId}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('源未连接，请先连接到 NAS')),
        );
      }
      return;
    }
    final adapter = connection.adapter;

    try {
      final url = await adapter.fileSystem.getFileUrl(track.path);
      final musicItem = MusicItem.fromFileItem(track.file, url, sourceId: track.sourceId);

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
      case 'add_to_playlist':
        if (context.mounted) {
          _showAddToPlaylistSheet(context, ref, track.path);
        }
      }
    } on Exception catch (e, stackTrace) {
      logger.e('_CompactMusicTile._handleAction: 操作失败', e, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  void _showAddToPlaylistSheet(BuildContext context, WidgetRef ref, String trackPath) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final playlistState = ref.read(playlistProvider);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '添加到歌单',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.add_rounded, color: AppColors.primary),
              ),
              title: Text(
                '新建歌单',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _showCreatePlaylistSheet(context, ref, trackPath);
              },
            ),
            if (playlistState.playlists.isNotEmpty) ...[
              const Divider(),
              ...playlistState.playlists.take(5).map((playlist) => ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.7),
                          AppColors.secondary.withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.queue_music_rounded, color: Colors.white, size: 20),
                  ),
                  title: Text(
                    playlist.name,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  ),
                  subtitle: Text('${playlist.trackCount} 首歌曲'),
                  onTap: () async {
                    await ref.read(playlistProvider.notifier).addToPlaylist(playlist.id, trackPath);
                    if (sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已添加到歌单"${playlist.name}"'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                )),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showCreatePlaylistSheet(BuildContext context, WidgetRef ref, String trackPath) {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        title: Text(
          '新建歌单',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '输入歌单名称',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await ref.read(playlistProvider.notifier).createPlaylist(
                      name: name,
                      initialTracks: [trackPath],
                    );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已添加到新歌单"$name"'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('创建并添加'),
          ),
        ],
      ),
    );
  }
}

/// 全部播放按钮
class _PlayAllButton extends ConsumerWidget {
  const _PlayAllButton({
    required this.tracks,
    required this.isDark,
  });

  final List<MusicFileWithSource> tracks;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ElevatedButton.icon(
      onPressed: () => _playAll(context, ref),
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: const Text('播放全部'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );

  Future<void> _playAll(BuildContext context, WidgetRef ref) async {
    if (tracks.isEmpty) return;

    final connections = ref.read(activeConnectionsProvider);

    // 转换所有曲目
    final musicItems = <MusicItem>[];
    for (final track in tracks) {
      final connection = connections[track.sourceId];
      if (connection == null || connection.status != SourceStatus.connected) {
        continue; // 跳过未连接源的歌曲
      }
      final url = await connection.adapter.fileSystem.getFileUrl(track.path);
      musicItems.add(MusicItem.fromFileItem(track.file, url, sourceId: track.sourceId));
    }

    if (musicItems.isEmpty) return;

    // 设置播放队列并播放第一首
    ref.read(playQueueProvider.notifier).setQueue(musicItems);
    await ref.read(musicPlayerControllerProvider.notifier).play(musicItems.first);

    if (context.mounted) {
      Navigator.of(context).pop();
      await MusicPlayerPage.open(context);
    }
  }
}

/// 空状态视图
Widget _buildEmptyView(String message, IconData icon, bool isDark) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 40, color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: TextStyle(
            fontSize: 16,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ],
    ),
  );

/// 根据索引获取渐变色
List<Color> _getGradientColorsForIndex(int index) {
  const colorPairs = [
    [Color(0xFF667eea), Color(0xFF764ba2)], // 紫色渐变
    [Color(0xFFf093fb), Color(0xFFf5576c)], // 粉红渐变
    [Color(0xFF4facfe), Color(0xFF00f2fe)], // 蓝色渐变
    [Color(0xFF43e97b), Color(0xFF38f9d7)], // 绿色渐变
    [Color(0xFFfa709a), Color(0xFFfee140)], // 橙粉渐变
    [Color(0xFF30cfd0), Color(0xFF330867)], // 青紫渐变
    [Color(0xFFa8edea), Color(0xFFfed6e3)], // 浅色渐变
    [Color(0xFFff9a9e), Color(0xFFfecfef)], // 粉红浅色
  ];
  return colorPairs[index % colorPairs.length];
}
