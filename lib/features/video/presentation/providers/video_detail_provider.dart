import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';

/// TMDB 服务 Provider
final tmdbServiceProvider = Provider<TmdbService>((ref) => TmdbService());

/// 视频元数据服务 Provider
final videoMetadataServiceProvider = Provider<VideoMetadataService>((ref) => VideoMetadataService());

/// 电影详情 Provider（autoDispose: 离开详情页后自动清理）
final movieDetailProvider = FutureProvider.autoDispose.family<TmdbMovieDetail?, int>((ref, movieId) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return tmdbService.getMovieDetail(movieId);
});

/// 电视剧详情 Provider（autoDispose: 离开详情页后自动清理）
final tvDetailProvider = FutureProvider.autoDispose.family<TmdbTvDetail?, int>((ref, tvId) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return tmdbService.getTvDetail(tvId);
});

/// 季剧集详情 Provider（autoDispose: 离开详情页后自动清理）
/// 参数: (tvId, seasonNumber)
final seasonDetailProvider = FutureProvider.autoDispose.family<TmdbSeasonDetail?, ({int tvId, int seasonNumber})>((ref, params) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  return tmdbService.getSeasonDetail(params.tvId, params.seasonNumber);
});

/// 电影推荐 Provider（autoDispose）
final movieRecommendationsProvider = FutureProvider.autoDispose.family<List<TmdbMediaItem>, int>((ref, movieId) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  final result = await tmdbService.getMovieRecommendations(movieId);
  return result.results;
});

/// 电视剧推荐 Provider（autoDispose）
final tvRecommendationsProvider = FutureProvider.autoDispose.family<List<TmdbMediaItem>, int>((ref, tvId) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  final result = await tmdbService.getTvRecommendations(tvId);
  return result.results;
});

/// 相似电影 Provider（autoDispose）
final similarMoviesProvider = FutureProvider.autoDispose.family<List<TmdbMediaItem>, int>((ref, movieId) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  final result = await tmdbService.getSimilarMovies(movieId);
  return result.results;
});

/// 相似电视剧 Provider（autoDispose）
final similarTvShowsProvider = FutureProvider.autoDispose.family<List<TmdbMediaItem>, int>((ref, tvId) async {
  final tmdbService = ref.watch(tmdbServiceProvider);
  final result = await tmdbService.getSimilarTvShows(tvId);
  return result.results;
});

/// 本地剧集文件 Provider（autoDispose + SQLite 索引优化）
/// 根据 TMDB ID 查找本地所有匹配的剧集文件
/// 返回: `Map<seasonNumber, Map<episodeNumber, VideoMetadata>>`
final localEpisodeFilesProvider = FutureProvider.autoDispose.family<Map<int, Map<int, VideoMetadata>>, int>((ref, tmdbId) async {
  final metadataService = ref.watch(videoMetadataServiceProvider);
  await metadataService.init();
  // 使用 SQLite 索引查询，O(log N) 复杂度
  return metadataService.getEpisodesByTmdbId(tmdbId);
});

/// 同系列本地内容 Provider（autoDispose + SQLite 索引优化）
/// 根据当前视频的 TMDB ID 查找同系列的其他本地文件
final relatedLocalVideosProvider = FutureProvider.autoDispose.family<List<VideoMetadata>, int>((ref, tmdbId) async {
  final metadataService = ref.watch(videoMetadataServiceProvider);
  await metadataService.init();
  // 使用 SQLite 索引查询
  return metadataService.getByTmdbId(tmdbId);
});

/// 本地推荐内容 Provider（autoDispose + SQLite 索引优化）
/// 结合 TMDB 推荐和本地已有文件
/// 参数: (tmdbId, isMovie)
final localRecommendationsProvider = FutureProvider.autoDispose.family<List<VideoMetadata>, ({int tmdbId, bool isMovie})>((ref, params) async {
  final metadataService = ref.watch(videoMetadataServiceProvider);
  await metadataService.init();

  // 获取 TMDB 推荐
  List<TmdbMediaItem> recommendations;
  if (params.isMovie) {
    recommendations = await ref.watch(movieRecommendationsProvider(params.tmdbId).future);
  } else {
    recommendations = await ref.watch(tvRecommendationsProvider(params.tmdbId).future);
  }

  // 使用 SQLite 索引获取本地已有的 TMDB ID 集合
  final localTmdbIds = await metadataService.getAllTmdbIds();

  // 过滤出本地已有的推荐内容
  final localRecommendations = <VideoMetadata>[];
  for (final rec in recommendations) {
    if (localTmdbIds.contains(rec.id)) {
      final localVideo = await metadataService.getFirstByTmdbId(rec.id);
      if (localVideo != null) {
        localRecommendations.add(localVideo);
      }
    }
  }

  return localRecommendations;
});

/// 按类型获取本地内容 Provider（autoDispose + SQLite 分页）
/// 根据类型查找本地所有相同类型的内容
final localVideosByGenreProvider = FutureProvider.autoDispose.family<List<VideoMetadata>, String>((ref, genre) async {
  final metadataService = ref.watch(videoMetadataServiceProvider);
  await metadataService.init();
  // 使用 SQLite 分页查询
  return metadataService.getByGenre(genre);
});

/// 按年份获取本地内容 Provider（autoDispose + SQLite 分页）
final localVideosByYearProvider = FutureProvider.autoDispose.family<List<VideoMetadata>, int>((ref, year) async {
  final metadataService = ref.watch(videoMetadataServiceProvider);
  await metadataService.init();
  return metadataService.getByYear(year);
});

/// 按分类获取本地内容 Provider（autoDispose + SQLite 分页）
final localVideosByCategoryProvider = FutureProvider.autoDispose.family<List<VideoMetadata>, MediaCategory>((ref, category) async {
  final metadataService = ref.watch(videoMetadataServiceProvider);
  await metadataService.init();
  return metadataService.getByCategory(category);
});

/// 搜索本地内容 Provider（autoDispose + SQLite）
final searchLocalVideosProvider = FutureProvider.autoDispose.family<List<VideoMetadata>, String>((ref, query) async {
  final metadataService = ref.watch(videoMetadataServiceProvider);
  await metadataService.init();
  return metadataService.search(query);
});

/// 视频库统计 Provider
final videoStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final metadataService = ref.watch(videoMetadataServiceProvider);
  await metadataService.init();
  return metadataService.getStats();
});
