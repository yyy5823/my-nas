import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';

/// TMDB 服务 Provider
final tmdbServiceProvider = Provider<TmdbService>((ref) => TmdbService.instance);

/// 视频元数据服务 Provider
final videoMetadataServiceProvider = Provider<VideoMetadataService>((ref) => VideoMetadataService.instance);

/// 电影详情 Provider
final movieDetailProvider = FutureProvider.family<TmdbMovieDetail?, int>((ref, movieId) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return tmdbService.getMovieDetail(movieId);
});

/// 电视剧详情 Provider
final tvDetailProvider = FutureProvider.family<TmdbTvDetail?, int>((ref, tvId) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return tmdbService.getTvDetail(tvId);
});

/// 季剧集详情 Provider
/// 参数: (tvId, seasonNumber)
final seasonDetailProvider = FutureProvider.family<TmdbSeasonDetail?, ({int tvId, int seasonNumber})>((ref, params) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return tmdbService.getSeasonDetail(params.tvId, params.seasonNumber);
});

/// 电影推荐 Provider
final movieRecommendationsProvider = FutureProvider.family<List<TmdbMediaItem>, int>((ref, movieId) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  final result = await tmdbService.getMovieRecommendations(movieId);
  return result.results;
});

/// 电视剧推荐 Provider
final tvRecommendationsProvider = FutureProvider.family<List<TmdbMediaItem>, int>((ref, tvId) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  final result = await tmdbService.getTvRecommendations(tvId);
  return result.results;
});

/// 相似电影 Provider
final similarMoviesProvider = FutureProvider.family<List<TmdbMediaItem>, int>((ref, movieId) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  final result = await tmdbService.getSimilarMovies(movieId);
  return result.results;
});

/// 相似电视剧 Provider
final similarTvShowsProvider = FutureProvider.family<List<TmdbMediaItem>, int>((ref, tvId) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  final result = await tmdbService.getSimilarTvShows(tvId);
  return result.results;
});

/// 本地剧集文件 Provider
/// 根据 TMDB ID 查找本地所有匹配的剧集文件
/// 返回: Map<seasonNumber, Map<episodeNumber, VideoMetadata>>
final localEpisodeFilesProvider = FutureProvider.family<Map<int, Map<int, VideoMetadata>>, int>((ref, tmdbId) async {
  final metadataService = ref.watch(videoMetadataServiceProvider);
  await metadataService.init();

  final allMetadata = metadataService.getAll();
  final episodeMap = <int, Map<int, VideoMetadata>>{};

  for (final metadata in allMetadata) {
    if (metadata.tmdbId == tmdbId &&
        metadata.seasonNumber != null &&
        metadata.episodeNumber != null) {
      final season = metadata.seasonNumber!;
      final episode = metadata.episodeNumber!;

      episodeMap[season] ??= {};
      episodeMap[season]![episode] = metadata;
    }
  }

  return episodeMap;
});

/// 同系列本地内容 Provider
/// 根据当前视频的 TMDB ID 查找同系列的其他本地文件
final relatedLocalVideosProvider = FutureProvider.family<List<VideoMetadata>, int>((ref, tmdbId) async {
  final metadataService = ref.watch(videoMetadataServiceProvider);
  await metadataService.init();

  final allMetadata = metadataService.getAll();
  return allMetadata.where((m) => m.tmdbId == tmdbId).toList();
});

/// 本地推荐内容 Provider
/// 结合 TMDB 推荐和本地已有文件
/// 参数: (tmdbId, isMovie)
final localRecommendationsProvider = FutureProvider.family<List<VideoMetadata>, ({int tmdbId, bool isMovie})>((ref, params) async {
  final metadataService = ref.watch(videoMetadataServiceProvider);
  await metadataService.init();

  // 获取 TMDB 推荐
  List<TmdbMediaItem> recommendations;
  if (params.isMovie) {
    recommendations = await ref.watch(movieRecommendationsProvider(params.tmdbId).future);
  } else {
    recommendations = await ref.watch(tvRecommendationsProvider(params.tmdbId).future);
  }

  // 获取所有本地元数据
  final allMetadata = metadataService.getAll();
  final localTmdbIds = allMetadata.where((m) => m.tmdbId != null).map((m) => m.tmdbId!).toSet();

  // 过滤出本地已有的推荐内容
  final localRecommendations = <VideoMetadata>[];
  for (final rec in recommendations) {
    if (localTmdbIds.contains(rec.id)) {
      final localVideo = allMetadata.firstWhere((m) => m.tmdbId == rec.id);
      localRecommendations.add(localVideo);
    }
  }

  return localRecommendations;
});

/// 按类型获取本地内容 Provider
/// 根据类型查找本地所有相同类型的内容
final localVideosByGenreProvider = FutureProvider.family<List<VideoMetadata>, String>((ref, genre) async {
  final metadataService = ref.watch(videoMetadataServiceProvider);
  await metadataService.init();

  final allMetadata = metadataService.getAll();
  return allMetadata.where((m) {
    final genres = m.genres?.toLowerCase() ?? '';
    return genres.contains(genre.toLowerCase());
  }).toList();
});
