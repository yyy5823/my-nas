import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';

/// 视频元数据服务
class VideoMetadataService {
  VideoMetadataService._();

  static VideoMetadataService? _instance;
  static VideoMetadataService get instance => _instance ??= VideoMetadataService._();

  static const String _boxName = 'video_metadata';

  Box<dynamic>? _box;
  final TmdbService _tmdbService = TmdbService.instance;

  /// 初始化
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    try {
      _box = await Hive.openBox(_boxName);
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
  Future<VideoMetadata> getOrFetch({
    required String sourceId,
    required String filePath,
    required String fileName,
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

    // 尝试从 TMDB 获取信息
    await _fetchMetadata(metadata);

    // 保存到缓存
    await save(metadata);

    return metadata;
  }

  /// 从 TMDB 获取元数据
  Future<void> _fetchMetadata(VideoMetadata metadata) async {
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
  Future<List<VideoMetadata>> batchFetch(
    List<({String sourceId, String filePath, String fileName})> videos, {
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
      );
      results.add(metadata);

      // 添加延迟以避免 API 限制
      if (i < videos.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }

    return results;
  }
}
