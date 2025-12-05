import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/nfo_scraper_service.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/data/services/video_thumbnail_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 视频元数据服务 - 使用 SQLite 后端，支持大规模数据
class VideoMetadataService {
  VideoMetadataService._();

  static VideoMetadataService? _instance;
  static VideoMetadataService get instance =>
      _instance ??= VideoMetadataService._();

  final VideoDatabaseService _db = VideoDatabaseService.instance;
  final TmdbService _tmdbService = TmdbService.instance;
  final NfoScraperService _nfoService = NfoScraperService.instance;
  final VideoThumbnailService _thumbnailService = VideoThumbnailService.instance;
  final VideoHistoryService _historyService = VideoHistoryService.instance;

  bool _initialized = false;

  /// 初始化
  Future<void> init() async {
    if (_initialized) return;

    try {
      // 并行初始化 SQLite 和 ThumbnailService
      await Future.wait([
        _db.init(),
        _thumbnailService.init(),
      ]);

      _initialized = true;

      final stats = await _db.getStats();
      logger.i('VideoMetadataService: 初始化完成，SQLite 条目: ${stats['total']}');
    } catch (e) {
      logger.e('VideoMetadataService: 初始化失败', e);
      rethrow;
    }
  }

  /// 获取缓存的元数据（异步，使用 SQLite）
  Future<VideoMetadata?> getCachedAsync(String sourceId, String filePath) async {
    if (!_initialized) await init();
    return _db.get(sourceId, filePath);
  }

  /// 批量获取缓存的元数据（异步）
  Future<Map<String, VideoMetadata>> getCachedBatch(
      List<({String sourceId, String filePath})> keys) async {
    if (!_initialized) await init();
    return _db.getBatch(keys);
  }

  /// 保存元数据
  Future<void> save(VideoMetadata metadata) async {
    if (!_initialized) await init();
    await _db.upsert(metadata);
  }

  /// 批量保存元数据
  Future<void> saveBatch(List<VideoMetadata> metadataList) async {
    if (!_initialized) await init();
    await _db.upsertBatch(metadataList);
  }

  /// 删除元数据
  Future<void> delete(String sourceId, String filePath) async {
    if (!_initialized) await init();
    await _db.delete(sourceId, filePath);
  }

  /// 清除所有缓存
  Future<void> clearAll() async {
    if (!_initialized) await init();
    await _db.clearAll();
  }

  // ============ 索引查询方法（使用 SQLite 索引）============

  /// 根据 TMDB ID 获取所有匹配的元数据
  Future<List<VideoMetadata>> getByTmdbId(int tmdbId) async {
    if (!_initialized) await init();
    return _db.getByTmdbId(tmdbId);
  }

  /// 根据 TMDB ID 获取剧集映射
  Future<Map<int, Map<int, VideoMetadata>>> getEpisodesByTmdbId(int tmdbId) async {
    if (!_initialized) await init();
    return _db.getEpisodesByTmdbId(tmdbId);
  }

  /// 获取所有 TMDB ID 集合
  Future<Set<int>> getAllTmdbIds() async {
    if (!_initialized) await init();
    return _db.getAllTmdbIds();
  }

  /// 根据 TMDB ID 获取第一个匹配的元数据
  Future<VideoMetadata?> getFirstByTmdbId(int tmdbId) async {
    if (!_initialized) await init();
    return _db.getFirstByTmdbId(tmdbId);
  }

  /// 根据分类获取元数据（分页）
  Future<List<VideoMetadata>> getByCategory(
    MediaCategory category, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();
    return _db.getByCategory(category, limit: limit, offset: offset);
  }

  /// 根据年份获取元数据（分页）
  Future<List<VideoMetadata>> getByYear(int year, {int limit = 50, int offset = 0}) async {
    if (!_initialized) await init();
    return _db.getByYear(year, limit: limit, offset: offset);
  }

  /// 根据类型获取元数据（分页）
  Future<List<VideoMetadata>> getByGenre(String genre, {int limit = 50, int offset = 0}) async {
    if (!_initialized) await init();
    return _db.getByGenre(genre, limit: limit, offset: offset);
  }

  /// 获取高评分内容（分页）
  Future<List<VideoMetadata>> getTopRated({
    double minRating = 7.0,
    MediaCategory? category,
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();
    return _db.getTopRated(
      minRating: minRating,
      category: category,
      limit: limit,
      offset: offset,
    );
  }

  /// 分页获取元数据
  Future<List<VideoMetadata>> getPage({
    int limit = 50,
    int offset = 0,
    MediaCategory? category,
  }) async {
    if (!_initialized) await init();
    return _db.getPage(limit: limit, offset: offset, category: category);
  }

  /// 搜索元数据
  Future<List<VideoMetadata>> search(String query, {int limit = 50, int offset = 0}) async {
    if (!_initialized) await init();
    return _db.search(query, limit: limit, offset: offset);
  }

  /// 获取统计信息
  Future<Map<String, dynamic>> getStats() async {
    if (!_initialized) await init();
    return _db.getStats();
  }

  /// 获取总数量
  Future<int> getCount({MediaCategory? category}) async {
    if (!_initialized) await init();
    return _db.getCount(category: category);
  }

  // ============ 元数据获取方法 ============

  /// 当播放进度更新时，刷新缩略图
  Future<void> refreshThumbnailOnProgressUpdate({
    required String sourceId,
    required String filePath,
    required String videoUrl,
    NasFileSystem? fileSystem,
  }) async {
    try {
      final metadata = await getCachedAsync(sourceId, filePath);
      if (metadata == null) return;

      if (metadata.posterUrl != null || metadata.thumbnailUrl != null) {
        logger.d('VideoMetadataService: 视频有刮削封面，跳过缩略图更新');
        return;
      }

      await _thumbnailService.deleteCached(filePath);
      await _tryGenerateThumbnail(metadata, videoUrl, fileSystem);
      await save(metadata);

      logger.i('VideoMetadataService: 已更新缩略图为当前播放位置 "${metadata.fileName}"');
    } catch (e) {
      logger.w('VideoMetadataService: 更新缩略图失败', e);
    }
  }

  /// 获取或刷新元数据
  Future<VideoMetadata> getOrFetch({
    required String sourceId,
    required String filePath,
    required String fileName,
    NasFileSystem? fileSystem,
    String? videoUrl,
    bool forceRefresh = false,
  }) async {
    if (!_initialized) await init();

    // 检查缓存
    var metadata = await getCachedAsync(sourceId, filePath);

    if (metadata != null && !forceRefresh) {
      final needsUpdate = metadata.lastUpdated == null ||
          DateTime.now().difference(metadata.lastUpdated!).inDays > 7;

      if (!needsUpdate && metadata.hasMetadata) {
        return metadata;
      }
    }

    // 创建新的元数据
    metadata ??= VideoMetadata(
      filePath: filePath,
      sourceId: sourceId,
      fileName: fileName,
    );

    // 优先尝试从 NFO 文件获取信息
    bool hasNfoData = false;
    if (fileSystem != null) {
      hasNfoData = await _fetchFromNfo(metadata, fileSystem);
    }

    // 如果 NFO 没有数据或缺少关键信息，尝试从 TMDB 获取
    if (!hasNfoData || !metadata.hasMetadata) {
      await _fetchFromTmdb(metadata);
    }

    // 如果没有封面图，尝试生成缩略图
    if (metadata.displayPosterUrl == null && videoUrl != null) {
      await _tryGenerateThumbnail(metadata, videoUrl, fileSystem);
    }

    // 保存到缓存
    await save(metadata);

    return metadata;
  }

  /// 尝试为视频生成缩略图
  Future<void> _tryGenerateThumbnail(
    VideoMetadata metadata,
    String videoUrl,
    NasFileSystem? fileSystem,
  ) async {
    try {
      final cachedUrl = _thumbnailService.getCachedThumbnailUrl(metadata.filePath);
      if (cachedUrl != null) {
        metadata.generatedThumbnailUrl = cachedUrl;
        return;
      }

      int timeMs = 5000;
      final progress = await _historyService.getProgress(metadata.filePath);
      if (progress != null && progress.position.inMilliseconds > 0) {
        timeMs = progress.position.inMilliseconds;
        logger.d('VideoMetadataService: 使用播放历史位置生成缩略图 "${metadata.fileName}" @ ${progress.position.inSeconds}s');
      } else {
        logger.d('VideoMetadataService: 尝试为 "${metadata.fileName}" 生成缩略图 @ 5s');
      }

      final thumbnailPath = await _thumbnailService.generateThumbnail(
        videoUrl: videoUrl,
        videoPath: metadata.filePath,
        timeMs: timeMs,
        fileSystem: fileSystem,
      );

      if (thumbnailPath != null) {
        metadata.generatedThumbnailUrl = _thumbnailService.getCachedThumbnailUrl(metadata.filePath);
        logger.i('VideoMetadataService: 缩略图生成成功 "${metadata.fileName}"');
      }
    } on Exception catch (e) {
      logger.w('VideoMetadataService: 生成缩略图失败 "${metadata.fileName}"', e);
    }
  }

  /// 从 NFO 文件获取元数据
  Future<bool> _fetchFromNfo(VideoMetadata metadata, NasFileSystem fileSystem) async {
    try {
      final nfoData = await _nfoService.scrapeFromDirectory(
        fileSystem: fileSystem,
        videoPath: metadata.filePath,
        videoFileName: metadata.fileName,
      );

      if (nfoData != null && nfoData.hasData) {
        metadata..category = nfoData.seasonNumber != null || nfoData.episodeNumber != null
            ? MediaCategory.tvShow
            : MediaCategory.movie
        ..tmdbId = nfoData.tmdbId
        ..title = nfoData.title
        ..originalTitle = nfoData.originalTitle
        ..year = nfoData.year
        ..overview = nfoData.plot
        ..rating = nfoData.rating
        ..runtime = nfoData.runtime
        ..genres = nfoData.genres?.join(', ')
        ..director = nfoData.director
        ..cast = nfoData.actors?.take(5).join(', ')
        ..seasonNumber = nfoData.seasonNumber
        ..episodeNumber = nfoData.episodeNumber
        ..episodeTitle = nfoData.episodeTitle
        ..lastUpdated = DateTime.now();

        if (nfoData.posterPath != null) {
          try {
            final posterUrl = await fileSystem.getFileUrl(nfoData.posterPath!);
            if (posterUrl.startsWith('http') || posterUrl.startsWith('file')) {
              metadata.posterUrl = posterUrl;
            }
          } on Exception catch (e) {
            logger.w('VideoMetadataService: 获取本地海报 URL 失败', e);
          }
        }

        if (nfoData.fanartPath != null) {
          try {
            final backdropUrl = await fileSystem.getFileUrl(nfoData.fanartPath!);
            if (backdropUrl.startsWith('http') || backdropUrl.startsWith('file')) {
              metadata.backdropUrl = backdropUrl;
            }
          } on Exception catch (e) {
            logger.w('VideoMetadataService: 获取本地背景图 URL 失败', e);
          }
        }

        logger.i('VideoMetadataService: 从 NFO 获取到元数据 "${nfoData.title}"');
        return true;
      }
    } on Exception catch (e) {
      logger.w('VideoMetadataService: 从 NFO 获取元数据失败', e);
    }
    return false;
  }

  /// 从 TMDB 获取元数据
  Future<void> _fetchFromTmdb(VideoMetadata metadata) async {
    if (!_tmdbService.hasApiKey) {
      logger.w('VideoMetadataService: 未配置 TMDB API Key');
      return;
    }

    final info = VideoFileNameParser.parse(metadata.fileName);
    logger.d('VideoMetadataService: 解析文件名 "${metadata.fileName}" -> '
        'title: "${info.cleanTitle}", year: ${info.year}, '
        'S${info.season}E${info.episode}');

    if (info.cleanTitle.isEmpty) {
      return;
    }

    try {
      if (info.isTvShow) {
        final results = await _tmdbService.searchTvShows(
          info.cleanTitle,
          year: info.year,
        );

        if (results.isNotEmpty) {
          final tvItem = results.results.first;
          final tvDetail = await _tmdbService.getTvDetail(tvItem.id);

          if (tvDetail != null) {
            String? episodeTitle;
            if (info.season != null && info.episode != null) {
              final seasonDetail = await _tmdbService.getSeasonDetail(
                tvItem.id,
                info.season!,
              );
              if (seasonDetail != null) {
                final episode = seasonDetail.episodes
                    .where((e) => e.episodeNumber == info.episode)
                    .firstOrNull;
                episodeTitle = episode?.name;
              }
            }

            metadata.updateFromTvShow(
              tvDetail,
              season: info.season,
              episode: info.episode,
              epTitle: episodeTitle,
            );
            logger.i('VideoMetadataService: 匹配到电视剧 "${tvDetail.name}"');
          }
        }
      } else {
        final results = await _tmdbService.searchMovies(
          info.cleanTitle,
          year: info.year,
        );

        if (results.isNotEmpty) {
          final movieItem = results.results.first;
          final movieDetail = await _tmdbService.getMovieDetail(movieItem.id);

          if (movieDetail != null) {
            metadata.updateFromMovie(movieDetail);
            logger.i('VideoMetadataService: 匹配到电影 "${movieDetail.title}"');
          }
        }
      }
    } on Exception catch (e) {
      logger.e('VideoMetadataService: 获取元数据失败', e);
    }
  }

  /// 手动搜索并匹配
  Future<List<TmdbMediaItem>> searchMedia(String query, {bool isMovie = true}) async {
    if (!_tmdbService.hasApiKey) {
      return [];
    }

    try {
      if (isMovie) {
        final results = await _tmdbService.searchMovies(query);
        return results.results;
      } else {
        final results = await _tmdbService.searchTvShows(query);
        return results.results;
      }
    } on Exception catch (e) {
      logger.e('VideoMetadataService: 搜索失败', e);
      return [];
    }
  }

  /// 手动匹配电影
  Future<void> matchMovie(VideoMetadata metadata, int movieId) async {
    try {
      final movieDetail = await _tmdbService.getMovieDetail(movieId);
      if (movieDetail != null) {
        metadata.updateFromMovie(movieDetail);
        await save(metadata);
        logger.i('VideoMetadataService: 手动匹配电影 "${movieDetail.title}"');
      }
    } on Exception catch (e) {
      logger.e('VideoMetadataService: 手动匹配电影失败', e);
    }
  }

  /// 手动匹配电视剧
  Future<void> matchTvShow(
    VideoMetadata metadata,
    int tvId, {
    int? season,
    int? episode,
  }) async {
    try {
      final tvDetail = await _tmdbService.getTvDetail(tvId);
      if (tvDetail != null) {
        String? episodeTitle;
        if (season != null && episode != null) {
          final seasonDetail = await _tmdbService.getSeasonDetail(tvId, season);
          if (seasonDetail != null) {
            final ep = seasonDetail.episodes
                .where((e) => e.episodeNumber == episode)
                .firstOrNull;
            episodeTitle = ep?.name;
          }
        }

        metadata.updateFromTvShow(
          tvDetail,
          season: season,
          episode: episode,
          epTitle: episodeTitle,
        );
        await save(metadata);
        logger.i('VideoMetadataService: 手动匹配电视剧 "${tvDetail.name}"');
      }
    } on Exception catch (e) {
      logger.e('VideoMetadataService: 手动匹配电视剧失败', e);
    }
  }

  /// 批量获取元数据
  Future<List<VideoMetadata>> batchFetch(
    List<({String sourceId, String filePath, String fileName})> videos, {
    NasFileSystem? fileSystem,
    void Function(int current, int total)? onProgress,
  }) async {
    final results = <VideoMetadata>[];
    final total = videos.length;

    for (var i = 0; i < videos.length; i++) {
      final video = videos[i];
      onProgress?.call(i + 1, total);

      final metadata = await getOrFetch(
        sourceId: video.sourceId,
        filePath: video.filePath,
        fileName: video.fileName,
        fileSystem: fileSystem,
      );
      results.add(metadata);

      if (i < videos.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }

    return results;
  }

  /// 为没有封面的视频生成缩略图
  Future<String?> generateThumbnailForVideo({
    required String videoUrl,
    required String videoPath,
  }) async {
    try {
      final thumbnailPath = await _thumbnailService.generateThumbnail(
        videoUrl: videoUrl,
        videoPath: videoPath,
        timeMs: 5000,
      );

      if (thumbnailPath != null) {
        return _thumbnailService.getCachedThumbnailUrl(videoPath);
      }
    } on Exception catch (e) {
      logger.w('VideoMetadataService: 生成视频缩略图失败', e);
    }
    return null;
  }

  /// 获取视频的显示封面 URL
  Future<String?> getDisplayPosterUrl({
    required VideoMetadata metadata,
    String? videoUrl,
  }) async {
    if (metadata.posterUrl != null && metadata.posterUrl!.isNotEmpty) {
      return metadata.posterUrl;
    }

    if (metadata.thumbnailUrl != null && metadata.thumbnailUrl!.isNotEmpty) {
      return metadata.thumbnailUrl;
    }

    final cachedUrl = _thumbnailService.getCachedThumbnailUrl(metadata.filePath);
    if (cachedUrl != null) {
      return cachedUrl;
    }

    if (videoUrl != null && videoUrl.isNotEmpty) {
      return generateThumbnailForVideo(
        videoUrl: videoUrl,
        videoPath: metadata.filePath,
      );
    }

    return null;
  }

  /// 清除缩略图缓存
  Future<void> clearThumbnailCache() async {
    await _thumbnailService.clearAllCache();
  }

  /// 获取缩略图缓存大小
  Future<int> getThumbnailCacheSize() async => _thumbnailService.getCacheSize();
}
