/// 媒体相关数据模型
library;

/// 媒体详情
class NtMediaDetail {
  const NtMediaDetail({
    required this.title,
    required this.type,
    this.tmdbId,
    this.imdbId,
    this.year,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.voteAverage,
    this.releaseDate,
    this.genres,
    this.runtime,
  });

  factory NtMediaDetail.fromJson(Map<String, dynamic> json) => NtMediaDetail(
    title: json['title'] as String? ?? json['name'] as String? ?? '',
    type: json['type'] as String? ?? json['media_type'] as String? ?? 'MOV',
    tmdbId: json['tmdb_id'] as int? ?? json['tmdbid'] as int?,
    imdbId: json['imdb_id'] as String? ?? json['imdbid'] as String?,
    year: json['year'] as int?,
    overview: json['overview'] as String? ?? json['description'] as String?,
    posterPath: json['poster_path'] as String? ?? json['poster'] as String?,
    backdropPath: json['backdrop_path'] as String? ?? json['backdrop'] as String?,
    voteAverage: (json['vote_average'] as num?)?.toDouble(),
    releaseDate: json['release_date'] as String? ?? json['first_air_date'] as String?,
    genres: (json['genres'] as List?)?.map((e) => e.toString()).toList(),
    runtime: json['runtime'] as int?,
  );

  final String title;
  final String type;
  final int? tmdbId;
  final String? imdbId;
  final int? year;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final double? voteAverage;
  final String? releaseDate;
  final List<String>? genres;
  final int? runtime;

  bool get isMovie => type.toUpperCase() == 'MOV' || type.toUpperCase() == 'MOVIE';
}

/// 媒体人物
class NtMediaPerson {
  const NtMediaPerson({
    required this.id,
    required this.name,
    this.role,
    this.profilePath,
    this.knownFor,
  });

  factory NtMediaPerson.fromJson(Map<String, dynamic> json) => NtMediaPerson(
    id: json['id'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    role: json['character'] as String? ?? json['job'] as String?,
    profilePath: json['profile_path'] as String?,
    knownFor: json['known_for_department'] as String?,
  );

  final int id;
  final String name;
  final String? role;
  final String? profilePath;
  final String? knownFor;
}

/// TV季信息
class NtTvSeason {
  const NtTvSeason({
    required this.seasonNumber,
    this.name,
    this.episodeCount,
    this.airDate,
    this.posterPath,
    this.overview,
  });

  factory NtTvSeason.fromJson(Map<String, dynamic> json) => NtTvSeason(
    seasonNumber: json['season_number'] as int? ?? 0,
    name: json['name'] as String?,
    episodeCount: json['episode_count'] as int?,
    airDate: json['air_date'] as String?,
    posterPath: json['poster_path'] as String?,
    overview: json['overview'] as String?,
  );

  final int seasonNumber;
  final String? name;
  final int? episodeCount;
  final String? airDate;
  final String? posterPath;
  final String? overview;
}

/// 二级分类
class NtMediaCategory {
  const NtMediaCategory({
    required this.name,
    this.path,
  });

  factory NtMediaCategory.fromJson(Map<String, dynamic> json) => NtMediaCategory(
    name: json['name'] as String? ?? '',
    path: json['path'] as String?,
  );

  final String name;
  final String? path;
}
