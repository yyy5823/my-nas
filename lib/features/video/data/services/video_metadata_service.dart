import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/nfo_scraper_service.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/data/services/video_thumbnail_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 视频元数据服务
class VideoMetadataService {
  VideoMetadataService._();

  static VideoMetadataService? _instance;
  static VideoMetadataService get instance => _instance ??= VideoMetadataService._();

  static const String _boxName = 'video_metadata';

  Box<dynamic>? _box;
  final TmdbService _tmdbService = TmdbService.instance;
  final NfoScraperService _nfoService = NfoScraperService.instance;
  final VideoThumbnailService _thumbnailService = VideoThumbnailService.instance;

  /// 初始化
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    try {
      _box = await Hive.openBox(_boxName);
      await _thumbnailService.init();
      logger.i('VideoMetadataService: 初始化完成，缓存条目: ${_box!.length}');
    } catch (e) {
      logger.e('VideoMetadataService: 打开缓存失败，尝试删除并重建', e);
      // 删除损坏的 box 并重新创建
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName);
      logger.i('VideoMetadataService: 重建缓存完成');
    }
  }

  /// 获取缓存的元数据
  VideoMetadata? getCached(String sourceId, String filePath) {
    final key = '${sourceId}_$filePath';
    final data = _box?.get(key);
    if (data == null) return null;
    try {
      return VideoMetadata.fromMap(data as Map<dynamic, dynamic>);
    } catch (e) {
      logger.e('VideoMetadataService: 解析缓存数据失败', e);
      return null;
    }
  }

  /// 保存元数据
  Future<void> save(VideoMetadata metadata) async {
    await _box?.put(metadata.uniqueKey, metadata.toMap());
  }

  /// 删除元数据
  Future<void> delete(String sourceId, String filePath) async {
    final key = '${sourceId}_$filePath';
    await _box?.delete(key);
  }

  /// 清除所有缓存
  Future<void> clearAll() async {
    await _box?.clear();
  }

  /// 获取所有缓存的元数据
  List<VideoMetadata> getAll() {
    if (_box == null) return [];
    final results = <VideoMetadata>[];
    for (final key in _box!.keys) {
      final data = _box!.get(key);
      if (data != null) {
        try {
          results.add(VideoMetadata.fromMap(data as Map<dynamic, dynamic>));
        } catch (e) {
          logger.w('VideoMetadataService: 跳过无效缓存数据 $key');
        }
      }
    }
    return results;
  }

  /// 获取或刷新元数据
  /// [fileSystem] 可选的文件系统接口，用于读取 NFO 文件
  Future<VideoMetadata> getOrFetch({
    required String sourceId,
    required String filePath,
    required String fileName,
    NasFileSystem? fileSystem,
    bool forceRefresh = false,
  }) async {
    // 检查缓存
    var metadata = getCached(sourceId, filePath);

    if (metadata != null && !forceRefresh) {
      // 检查是否需要更新（超过7天）
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

    // 保存到缓存
    await save(metadata);

    return metadata;
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
        // 更新元数据
        metadata.category = nfoData.seasonNumber != null || nfoData.episodeNumber != null
            ? MediaCategory.tvShow
            : MediaCategory.movie;
        metadata.tmdbId = nfoData.tmdbId;
        metadata.title = nfoData.title;
        metadata.originalTitle = nfoData.originalTitle;
        metadata.year = nfoData.year;
        metadata.overview = nfoData.plot;
        metadata.rating = nfoData.rating;
        metadata.runtime = nfoData.runtime;
        metadata.genres = nfoData.genres?.join(', ');
        metadata.director = nfoData.director;
        metadata.cast = nfoData.actors?.take(5).join(', ');
        metadata.seasonNumber = nfoData.seasonNumber;
        metadata.episodeNumber = nfoData.episodeNumber;
        metadata.episodeTitle = nfoData.episodeTitle;
        metadata.lastUpdated = DateTime.now();

        // 如果有本地海报，获取 URL
        if (nfoData.posterPath != null) {
          try {
            metadata.posterUrl = await fileSystem.getFileUrl(nfoData.posterPath!);
          } catch (e) {
            logger.w('VideoMetadataService: 获取本地海报 URL 失败', e);
          }
        }

        // 如果有本地背景图，获取 URL
        if (nfoData.fanartPath != null) {
          try {
            metadata.backdropUrl = await fileSystem.getFileUrl(nfoData.fanartPath!);
          } catch (e) {
            logger.w('VideoMetadataService: 获取本地背景图 URL 失败', e);
          }
        }

        logger.i('VideoMetadataService: 从 NFO 获取到元数据 "${nfoData.title}"');
        return true;
      }
    } catch (e) {
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

    // 解析文件名
    final info = VideoFileNameParser.parse(metadata.fileName);
    logger.d('VideoMetadataService: 解析文件名 "${metadata.fileName}" -> '
        'title: "${info.cleanTitle}", year: ${info.year}, '
        'S${info.season}E${info.episode}');

    if (info.cleanTitle.isEmpty) {
      return;
    }

    try {
      if (info.isTvShow) {
        // 搜索电视剧
        final results = await _tmdbService.searchTvShows(
          info.cleanTitle,
          year: info.year,
        );

        if (results.isNotEmpty) {
          final tvItem = results.results.first;
          final tvDetail = await _tmdbService.getTvDetail(tvItem.id);

          if (tvDetail != null) {
            // 获取剧集标题
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
        // 搜索电影
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
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
    } catch (e) {
      logger.e('VideoMetadataService: 手动匹配电视剧失败', e);
    }
  }

  /// 批量获取元数据
  /// [fileSystem] 可选的文件系统接口，用于读取 NFO 文件
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

      // 添加延迟以避免 API 限制
      if (i < videos.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }

    return results;
  }

  /// 为没有封面的视频生成缩略图
  ///
  /// 类似于 Emby/Jellyfin 的 Screen Grabber 功能
  /// 在视频的 15% 位置提取帧作为缩略图
  Future<String?> generateThumbnailForVideo({
    required String videoUrl,
    required String videoPath,
  }) async {
    try {
      final thumbnailPath = await _thumbnailService.generateThumbnail(
        videoUrl: videoUrl,
        videoPath: videoPath,
        timeMs: 5000, // 5秒位置，通常能避开片头黑屏
      );

      if (thumbnailPath != null) {
        // 返回 file:// URL
        return _thumbnailService.getCachedThumbnailUrl(videoPath);
      }
    } catch (e) {
      logger.w('VideoMetadataService: 生成视频缩略图失败', e);
    }
    return null;
  }

  /// 获取视频的显示封面 URL
  ///
  /// 优先级：TMDB 海报 > NFO 本地海报 > NAS 内置缩略图 > 生成的缩略图
  Future<String?> getDisplayPosterUrl({
    required VideoMetadata metadata,
    String? videoUrl,
  }) async {
    // 1. 优先使用 TMDB 海报或 NFO 本地海报
    if (metadata.posterUrl != null && metadata.posterUrl!.isNotEmpty) {
      return metadata.posterUrl;
    }

    // 2. 使用 NAS 内置缩略图
    if (metadata.thumbnailUrl != null && metadata.thumbnailUrl!.isNotEmpty) {
      return metadata.thumbnailUrl;
    }

    // 3. 检查是否有缓存的生成缩略图
    final cachedUrl = _thumbnailService.getCachedThumbnailUrl(metadata.filePath);
    if (cachedUrl != null) {
      return cachedUrl;
    }

    // 4. 如果提供了视频 URL，尝试生成缩略图
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
  Future<int> getThumbnailCacheSize() async {
    return _thumbnailService.getCacheSize();
  }
}
