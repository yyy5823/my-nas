import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:my_nas/core/utils/logger.dart';

/// TMDB API 服务
class TmdbService {
  TmdbService._();

  static TmdbService? _instance;
  static TmdbService get instance => _instance ??= TmdbService._();

  // TMDB API Key - 可以在设置中配置
  static const String _defaultApiKey = ''; // 用户需要自己申请
  String _apiKey = _defaultApiKey;

  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _imageBaseUrl = 'https://image.tmdb.org/t/p';

  /// 设置 API Key
  void setApiKey(String key) {
    _apiKey = key;
  }

  /// 检查是否配置了 API Key
  bool get hasApiKey => _apiKey.isNotEmpty;

  /// 获取图片完整 URL
  static String getImageUrl(String? path, {ImageSize size = ImageSize.w500}) {
    if (path == null || path.isEmpty) return '';
    return '$_imageBaseUrl/${size.value}$path';
  }

  /// 搜索电影
  Future<TmdbSearchResult> searchMovies(
    String query, {
    int page = 1,
    String language = 'zh-CN',
    int? year,
  }) async {
    if (!hasApiKey) {
      return TmdbSearchResult.empty();
    }

    try {
      final params = {
        'api_key': _apiKey,
        'query': query,
        'page': page.toString(),
        'language': language,
        'include_adult': 'false',
      };
      if (year != null) {
        params['year'] = year.toString();
      }

      final uri = Uri.parse('$_baseUrl/search/movie').replace(queryParameters: params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSearchResult.fromJson(data, isMovie: true);
      } else {
        logger.e('TMDB搜索电影失败: ${response.statusCode}');
        return TmdbSearchResult.empty();
      }
    } catch (e) {
      logger.e('TMDB搜索电影异常', e);
      return TmdbSearchResult.empty();
    }
  }

  /// 搜索电视剧
  Future<TmdbSearchResult> searchTvShows(
    String query, {
    int page = 1,
    String language = 'zh-CN',
    int? year,
  }) async {
    if (!hasApiKey) {
      return TmdbSearchResult.empty();
    }

    try {
      final params = {
        'api_key': _apiKey,
        'query': query,
        'page': page.toString(),
        'language': language,
      };
      if (year != null) {
        params['first_air_date_year'] = year.toString();
      }

      final uri = Uri.parse('$_baseUrl/search/tv').replace(queryParameters: params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSearchResult.fromJson(data, isMovie: false);
      } else {
        logger.e('TMDB搜索电视剧失败: ${response.statusCode}');
        return TmdbSearchResult.empty();
      }
    } catch (e) {
      logger.e('TMDB搜索电视剧异常', e);
      return TmdbSearchResult.empty();
    }
  }

  /// 获取电影详情
  Future<TmdbMovieDetail?> getMovieDetail(
    int movieId, {
    String language = 'zh-CN',
  }) async {
    if (!hasApiKey) return null;

    try {
      final params = {
        'api_key': _apiKey,
        'language': language,
        'append_to_response': 'credits,videos,images',
      };

      final uri = Uri.parse('$_baseUrl/movie/$movieId').replace(queryParameters: params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbMovieDetail.fromJson(data);
      } else {
        logger.e('TMDB获取电影详情失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      logger.e('TMDB获取电影详情异常', e);
      return null;
    }
  }

  /// 获取电视剧详情
  Future<TmdbTvDetail?> getTvDetail(
    int tvId, {
    String language = 'zh-CN',
  }) async {
    if (!hasApiKey) return null;

    try {
      final params = {
        'api_key': _apiKey,
        'language': language,
        'append_to_response': 'credits,videos,images',
      };

      final uri = Uri.parse('$_baseUrl/tv/$tvId').replace(queryParameters: params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbTvDetail.fromJson(data);
      } else {
        logger.e('TMDB获取电视剧详情失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      logger.e('TMDB获取电视剧详情异常', e);
      return null;
    }
  }

  /// 获取电视剧季详情
  Future<TmdbSeasonDetail?> getSeasonDetail(
    int tvId,
    int seasonNumber, {
    String language = 'zh-CN',
  }) async {
    if (!hasApiKey) return null;

    try {
      final params = {
        'api_key': _apiKey,
        'language': language,
      };

      final uri = Uri.parse('$_baseUrl/tv/$tvId/season/$seasonNumber')
          .replace(queryParameters: params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSeasonDetail.fromJson(data);
      } else {
        logger.e('TMDB获取季详情失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      logger.e('TMDB获取季详情异常', e);
      return null;
    }
  }

  /// 获取电影推荐
  Future<TmdbSearchResult> getMovieRecommendations(
    int movieId, {
    int page = 1,
    String language = 'zh-CN',
  }) async {
    if (!hasApiKey) return TmdbSearchResult.empty();

    try {
      final params = {
        'api_key': _apiKey,
        'page': page.toString(),
        'language': language,
      };

      final uri = Uri.parse('$_baseUrl/movie/$movieId/recommendations')
          .replace(queryParameters: params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSearchResult.fromJson(data, isMovie: true);
      } else {
        logger.e('TMDB获取电影推荐失败: ${response.statusCode}');
        return TmdbSearchResult.empty();
      }
    } catch (e) {
      logger.e('TMDB获取电影推荐异常', e);
      return TmdbSearchResult.empty();
    }
  }

  /// 获取电视剧推荐
  Future<TmdbSearchResult> getTvRecommendations(
    int tvId, {
    int page = 1,
    String language = 'zh-CN',
  }) async {
    if (!hasApiKey) return TmdbSearchResult.empty();

    try {
      final params = {
        'api_key': _apiKey,
        'page': page.toString(),
        'language': language,
      };

      final uri = Uri.parse('$_baseUrl/tv/$tvId/recommendations')
          .replace(queryParameters: params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSearchResult.fromJson(data, isMovie: false);
      } else {
        logger.e('TMDB获取电视剧推荐失败: ${response.statusCode}');
        return TmdbSearchResult.empty();
      }
    } catch (e) {
      logger.e('TMDB获取电视剧推荐异常', e);
      return TmdbSearchResult.empty();
    }
  }

  /// 获取相似电影
  Future<TmdbSearchResult> getSimilarMovies(
    int movieId, {
    int page = 1,
    String language = 'zh-CN',
  }) async {
    if (!hasApiKey) return TmdbSearchResult.empty();

    try {
      final params = {
        'api_key': _apiKey,
        'page': page.toString(),
        'language': language,
      };

      final uri = Uri.parse('$_baseUrl/movie/$movieId/similar')
          .replace(queryParameters: params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSearchResult.fromJson(data, isMovie: true);
      } else {
        logger.e('TMDB获取相似电影失败: ${response.statusCode}');
        return TmdbSearchResult.empty();
      }
    } catch (e) {
      logger.e('TMDB获取相似电影异常', e);
      return TmdbSearchResult.empty();
    }
  }

  /// 获取相似电视剧
  Future<TmdbSearchResult> getSimilarTvShows(
    int tvId, {
    int page = 1,
    String language = 'zh-CN',
  }) async {
    if (!hasApiKey) return TmdbSearchResult.empty();

    try {
      final params = {
        'api_key': _apiKey,
        'page': page.toString(),
        'language': language,
      };

      final uri = Uri.parse('$_baseUrl/tv/$tvId/similar')
          .replace(queryParameters: params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSearchResult.fromJson(data, isMovie: false);
      } else {
        logger.e('TMDB获取相似电视剧失败: ${response.statusCode}');
        return TmdbSearchResult.empty();
      }
    } catch (e) {
      logger.e('TMDB获取相似电视剧异常', e);
      return TmdbSearchResult.empty();
    }
  }
}

/// 图片尺寸
enum ImageSize {
  w92('w92'),
  w154('w154'),
  w185('w185'),
  w342('w342'),
  w500('w500'),
  w780('w780'),
  original('original');

  const ImageSize(this.value);
  final String value;
}

/// 搜索结果
class TmdbSearchResult {
  TmdbSearchResult({
    required this.page,
    required this.totalPages,
    required this.totalResults,
    required this.results,
  });

  factory TmdbSearchResult.empty() => TmdbSearchResult(
        page: 0,
        totalPages: 0,
        totalResults: 0,
        results: [],
      );

  factory TmdbSearchResult.fromJson(Map<String, dynamic> json, {required bool isMovie}) {
    final results = (json['results'] as List?)
            ?.map((e) => TmdbMediaItem.fromJson(e as Map<String, dynamic>, isMovie: isMovie))
            .toList() ??
        [];

    return TmdbSearchResult(
      page: json['page'] as int? ?? 0,
      totalPages: json['total_pages'] as int? ?? 0,
      totalResults: json['total_results'] as int? ?? 0,
      results: results,
    );
  }

  final int page;
  final int totalPages;
  final int totalResults;
  final List<TmdbMediaItem> results;

  bool get isEmpty => results.isEmpty;
  bool get isNotEmpty => results.isNotEmpty;
}

/// 媒体项
class TmdbMediaItem {
  TmdbMediaItem({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.releaseDate,
    required this.voteAverage,
    required this.voteCount,
    required this.popularity,
    required this.isMovie,
    required this.genreIds,
  });

  factory TmdbMediaItem.fromJson(Map<String, dynamic> json, {required bool isMovie}) {
    return TmdbMediaItem(
      id: json['id'] as int,
      title: (isMovie ? json['title'] : json['name']) as String? ?? '',
      originalTitle:
          (isMovie ? json['original_title'] : json['original_name']) as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate:
          (isMovie ? json['release_date'] : json['first_air_date']) as String? ?? '',
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['vote_count'] as int? ?? 0,
      popularity: (json['popularity'] as num?)?.toDouble() ?? 0.0,
      isMovie: isMovie,
      genreIds:
          (json['genre_ids'] as List?)?.map((e) => e as int).toList() ?? [],
    );
  }

  final int id;
  final String title;
  final String originalTitle;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String releaseDate;
  final double voteAverage;
  final int voteCount;
  final double popularity;
  final bool isMovie;
  final List<int> genreIds;

  String get posterUrl => TmdbService.getImageUrl(posterPath);
  String get backdropUrl => TmdbService.getImageUrl(backdropPath, size: ImageSize.w780);

  int? get year {
    if (releaseDate.isEmpty) return null;
    return int.tryParse(releaseDate.split('-').first);
  }

  String get ratingText => voteAverage.toStringAsFixed(1);
}

/// 电影详情
class TmdbMovieDetail {
  TmdbMovieDetail({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.releaseDate,
    required this.runtime,
    required this.voteAverage,
    required this.voteCount,
    required this.genres,
    required this.productionCompanies,
    required this.cast,
    required this.crew,
    required this.tagline,
    required this.status,
    required this.budget,
    required this.revenue,
  });

  factory TmdbMovieDetail.fromJson(Map<String, dynamic> json) {
    final credits = json['credits'] as Map<String, dynamic>?;

    return TmdbMovieDetail(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      originalTitle: json['original_title'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate: json['release_date'] as String? ?? '',
      runtime: json['runtime'] as int? ?? 0,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['vote_count'] as int? ?? 0,
      genres: (json['genres'] as List?)
              ?.map((e) => TmdbGenre.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      productionCompanies: (json['production_companies'] as List?)
              ?.map((e) => TmdbCompany.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      cast: (credits?['cast'] as List?)
              ?.take(20)
              .map((e) => TmdbCast.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      crew: (credits?['crew'] as List?)
              ?.map((e) => TmdbCrew.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tagline: json['tagline'] as String? ?? '',
      status: json['status'] as String? ?? '',
      budget: json['budget'] as int? ?? 0,
      revenue: json['revenue'] as int? ?? 0,
    );
  }

  final int id;
  final String title;
  final String originalTitle;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String releaseDate;
  final int runtime;
  final double voteAverage;
  final int voteCount;
  final List<TmdbGenre> genres;
  final List<TmdbCompany> productionCompanies;
  final List<TmdbCast> cast;
  final List<TmdbCrew> crew;
  final String tagline;
  final String status;
  final int budget;
  final int revenue;

  String get posterUrl => TmdbService.getImageUrl(posterPath);
  String get backdropUrl => TmdbService.getImageUrl(backdropPath, size: ImageSize.original);

  int? get year {
    if (releaseDate.isEmpty) return null;
    return int.tryParse(releaseDate.split('-').first);
  }

  String get runtimeText {
    if (runtime == 0) return '';
    final hours = runtime ~/ 60;
    final minutes = runtime % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String get genresText => genres.map((g) => g.name).join(' / ');

  TmdbCrew? get director => crew.where((c) => c.job == 'Director').firstOrNull;
}

/// 电视剧详情
class TmdbTvDetail {
  TmdbTvDetail({
    required this.id,
    required this.name,
    required this.originalName,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.firstAirDate,
    required this.lastAirDate,
    required this.voteAverage,
    required this.voteCount,
    required this.genres,
    required this.seasons,
    required this.numberOfSeasons,
    required this.numberOfEpisodes,
    required this.episodeRunTime,
    required this.cast,
    required this.crew,
    required this.status,
    required this.tagline,
    required this.networks,
  });

  factory TmdbTvDetail.fromJson(Map<String, dynamic> json) {
    final credits = json['credits'] as Map<String, dynamic>?;

    return TmdbTvDetail(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      originalName: json['original_name'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      firstAirDate: json['first_air_date'] as String? ?? '',
      lastAirDate: json['last_air_date'] as String? ?? '',
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['vote_count'] as int? ?? 0,
      genres: (json['genres'] as List?)
              ?.map((e) => TmdbGenre.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      seasons: (json['seasons'] as List?)
              ?.map((e) => TmdbSeason.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      numberOfSeasons: json['number_of_seasons'] as int? ?? 0,
      numberOfEpisodes: json['number_of_episodes'] as int? ?? 0,
      episodeRunTime: (json['episode_run_time'] as List?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      cast: (credits?['cast'] as List?)
              ?.take(20)
              .map((e) => TmdbCast.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      crew: (credits?['crew'] as List?)
              ?.map((e) => TmdbCrew.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      status: json['status'] as String? ?? '',
      tagline: json['tagline'] as String? ?? '',
      networks: (json['networks'] as List?)
              ?.map((e) => TmdbNetwork.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  final int id;
  final String name;
  final String originalName;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String firstAirDate;
  final String lastAirDate;
  final double voteAverage;
  final int voteCount;
  final List<TmdbGenre> genres;
  final List<TmdbSeason> seasons;
  final int numberOfSeasons;
  final int numberOfEpisodes;
  final List<int> episodeRunTime;
  final List<TmdbCast> cast;
  final List<TmdbCrew> crew;
  final String status;
  final String tagline;
  final List<TmdbNetwork> networks;

  String get posterUrl => TmdbService.getImageUrl(posterPath);
  String get backdropUrl => TmdbService.getImageUrl(backdropPath, size: ImageSize.original);

  int? get year {
    if (firstAirDate.isEmpty) return null;
    return int.tryParse(firstAirDate.split('-').first);
  }

  String get genresText => genres.map((g) => g.name).join(' / ');
}

/// 季详情
class TmdbSeasonDetail {
  TmdbSeasonDetail({
    required this.id,
    required this.name,
    required this.overview,
    required this.posterPath,
    required this.seasonNumber,
    required this.airDate,
    required this.episodes,
  });

  factory TmdbSeasonDetail.fromJson(Map<String, dynamic> json) {
    return TmdbSeasonDetail(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      seasonNumber: json['season_number'] as int? ?? 0,
      airDate: json['air_date'] as String? ?? '',
      episodes: (json['episodes'] as List?)
              ?.map((e) => TmdbEpisode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  final int id;
  final String name;
  final String overview;
  final String? posterPath;
  final int seasonNumber;
  final String airDate;
  final List<TmdbEpisode> episodes;

  String get posterUrl => TmdbService.getImageUrl(posterPath);
}

/// 季信息
class TmdbSeason {
  TmdbSeason({
    required this.id,
    required this.name,
    required this.overview,
    required this.posterPath,
    required this.seasonNumber,
    required this.episodeCount,
    required this.airDate,
  });

  factory TmdbSeason.fromJson(Map<String, dynamic> json) {
    return TmdbSeason(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      seasonNumber: json['season_number'] as int? ?? 0,
      episodeCount: json['episode_count'] as int? ?? 0,
      airDate: json['air_date'] as String? ?? '',
    );
  }

  final int id;
  final String name;
  final String overview;
  final String? posterPath;
  final int seasonNumber;
  final int episodeCount;
  final String airDate;

  String get posterUrl => TmdbService.getImageUrl(posterPath);
}

/// 剧集信息
class TmdbEpisode {
  TmdbEpisode({
    required this.id,
    required this.name,
    required this.overview,
    required this.stillPath,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.airDate,
    required this.runtime,
    required this.voteAverage,
  });

  factory TmdbEpisode.fromJson(Map<String, dynamic> json) {
    return TmdbEpisode(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      stillPath: json['still_path'] as String?,
      episodeNumber: json['episode_number'] as int? ?? 0,
      seasonNumber: json['season_number'] as int? ?? 0,
      airDate: json['air_date'] as String? ?? '',
      runtime: json['runtime'] as int? ?? 0,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
    );
  }

  final int id;
  final String name;
  final String overview;
  final String? stillPath;
  final int episodeNumber;
  final int seasonNumber;
  final String airDate;
  final int runtime;
  final double voteAverage;

  String get stillUrl => TmdbService.getImageUrl(stillPath, size: ImageSize.w500);
}

/// 类型
class TmdbGenre {
  TmdbGenre({required this.id, required this.name});

  factory TmdbGenre.fromJson(Map<String, dynamic> json) {
    return TmdbGenre(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
    );
  }

  final int id;
  final String name;
}

/// 演员
class TmdbCast {
  TmdbCast({
    required this.id,
    required this.name,
    required this.character,
    required this.profilePath,
    required this.order,
  });

  factory TmdbCast.fromJson(Map<String, dynamic> json) {
    return TmdbCast(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      character: json['character'] as String? ?? '',
      profilePath: json['profile_path'] as String?,
      order: json['order'] as int? ?? 0,
    );
  }

  final int id;
  final String name;
  final String character;
  final String? profilePath;
  final int order;

  String get profileUrl => TmdbService.getImageUrl(profilePath, size: ImageSize.w185);
}

/// 剧组人员
class TmdbCrew {
  TmdbCrew({
    required this.id,
    required this.name,
    required this.job,
    required this.department,
    required this.profilePath,
  });

  factory TmdbCrew.fromJson(Map<String, dynamic> json) {
    return TmdbCrew(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      job: json['job'] as String? ?? '',
      department: json['department'] as String? ?? '',
      profilePath: json['profile_path'] as String?,
    );
  }

  final int id;
  final String name;
  final String job;
  final String department;
  final String? profilePath;

  String get profileUrl => TmdbService.getImageUrl(profilePath, size: ImageSize.w185);
}

/// 制作公司
class TmdbCompany {
  TmdbCompany({
    required this.id,
    required this.name,
    required this.logoPath,
    required this.originCountry,
  });

  factory TmdbCompany.fromJson(Map<String, dynamic> json) {
    return TmdbCompany(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      logoPath: json['logo_path'] as String?,
      originCountry: json['origin_country'] as String? ?? '',
    );
  }

  final int id;
  final String name;
  final String? logoPath;
  final String originCountry;

  String get logoUrl => TmdbService.getImageUrl(logoPath, size: ImageSize.w185);
}

/// 电视网络
class TmdbNetwork {
  TmdbNetwork({
    required this.id,
    required this.name,
    required this.logoPath,
    required this.originCountry,
  });

  factory TmdbNetwork.fromJson(Map<String, dynamic> json) {
    return TmdbNetwork(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      logoPath: json['logo_path'] as String?,
      originCountry: json['origin_country'] as String? ?? '',
    );
  }

  final int id;
  final String name;
  final String? logoPath;
  final String originCountry;

  String get logoUrl => TmdbService.getImageUrl(logoPath, size: ImageSize.w185);
}
