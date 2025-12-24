import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';

/// 统一的刮削搜索结果
class ScraperSearchResult {
  const ScraperSearchResult({
    required this.items,
    required this.source,
    this.page = 1,
    this.totalPages = 1,
    this.totalResults = 0,
  });

  factory ScraperSearchResult.empty([ScraperType? source]) => ScraperSearchResult(
        items: const [],
        source: source ?? ScraperType.tmdb,
      );

  /// 搜索结果列表
  final List<ScraperMediaItem> items;

  /// 来源类型
  final ScraperType source;

  /// 当前页码
  final int page;

  /// 总页数
  final int totalPages;

  /// 总结果数
  final int totalResults;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  bool get hasMore => page < totalPages;
}

/// 统一的媒体项（搜索结果中的单个项目）
class ScraperMediaItem {
  const ScraperMediaItem({
    required this.externalId,
    required this.source,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.year,
    this.rating,
    this.isMovie = true,
    this.genres,
    this.voteCount,
  });

  /// 外部 ID（TMDB ID 或豆瓣 ID）
  final String externalId;

  /// 来源类型
  final ScraperType source;

  /// 标题
  final String title;

  /// 原始标题
  final String? originalTitle;

  /// 简介
  final String? overview;

  /// 海报 URL
  final String? posterUrl;

  /// 背景图 URL
  final String? backdropUrl;

  /// 年份
  final int? year;

  /// 评分
  final double? rating;

  /// 是否为电影
  final bool isMovie;

  /// 类型列表
  final List<String>? genres;

  /// 评分人数
  final int? voteCount;

  /// 评分文本（保留一位小数）
  String get ratingText => rating?.toStringAsFixed(1) ?? '';

  /// 类型文本（以 / 分隔）
  String get genresText => genres?.join(' / ') ?? '';
}

/// 统一的电影详情
class ScraperMovieDetail {
  const ScraperMovieDetail({
    required this.externalId,
    required this.source,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.year,
    this.rating,
    this.voteCount,
    this.runtime,
    this.genres,
    this.countries,
    this.director,
    this.cast,
    this.tagline,
    this.status,
    this.collectionId,
    this.collectionName,
    this.collectionPosterUrl,
    this.collectionBackdropUrl,
    this.imdbId,
    this.localizedTitles,
    this.localizedOverviews,
  });

  /// 外部 ID
  final String externalId;

  /// 来源类型
  final ScraperType source;

  /// 标题
  final String title;

  /// 原始标题
  final String? originalTitle;

  /// 简介
  final String? overview;

  /// 海报 URL
  final String? posterUrl;

  /// 背景图 URL
  final String? backdropUrl;

  /// 年份
  final int? year;

  /// 评分
  final double? rating;

  /// 评分人数
  final int? voteCount;

  /// 时长（分钟）
  final int? runtime;

  /// 类型列表
  final List<String>? genres;

  /// 制片国家/地区列表
  final List<String>? countries;

  /// 导演
  final String? director;

  /// 演员列表
  final List<String>? cast;

  /// 宣传语
  final String? tagline;

  /// 状态
  final String? status;

  /// 电影系列 ID
  final String? collectionId;

  /// 电影系列名称
  final String? collectionName;

  /// 电影系列海报 URL（TMDB 系列专属海报）
  final String? collectionPosterUrl;

  /// 电影系列背景图 URL
  final String? collectionBackdropUrl;

  /// IMDB ID
  final String? imdbId;

  /// 多语言标题
  final Map<String, String>? localizedTitles;

  /// 多语言简介
  final Map<String, String>? localizedOverviews;

  /// 类型文本（以 / 分隔）
  String get genresText => genres?.join(' / ') ?? '';

  /// 国家/地区文本（以 , 分隔）
  String get countriesText => countries?.join(', ') ?? '';

  /// 演员文本（以 , 分隔）
  String get castText => cast?.join(', ') ?? '';

  /// 时长文本
  String get runtimeText {
    if (runtime == null || runtime == 0) return '';
    final hours = runtime! ~/ 60;
    final minutes = runtime! % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  /// 将详情应用到 VideoMetadata
  void applyTo(VideoMetadata metadata) {
    metadata
      ..category = MediaCategory.movie
      ..title = title
      ..originalTitle = originalTitle
      ..overview = overview
      ..posterUrl = posterUrl
      ..backdropUrl = backdropUrl
      ..year = year
      ..rating = rating
      ..runtime = runtime
      ..genres = genresText
      ..countries = countriesText
      ..director = director
      ..cast = castText
      ..localizedTitles = localizedTitles
      ..localizedOverviews = localizedOverviews
      ..lastUpdated = DateTime.now();

    // 根据来源设置对应的 ID
    switch (source) {
      case ScraperType.tmdb:
        metadata.tmdbId = int.tryParse(externalId);
        if (collectionId != null) {
          metadata
            ..collectionId = int.tryParse(collectionId!)
            ..collectionName = collectionName
            ..collectionPosterUrl = collectionPosterUrl
            ..collectionBackdropUrl = collectionBackdropUrl;
        }
      case ScraperType.doubanApi:
      case ScraperType.doubanWeb:
        metadata.doubanId = externalId;
    }
  }
}

/// 统一的电视剧详情
class ScraperTvDetail {
  const ScraperTvDetail({
    required this.externalId,
    required this.source,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.year,
    this.rating,
    this.voteCount,
    this.episodeRuntime,
    this.genres,
    this.countries,
    this.cast,
    this.status,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.seasons,
    this.imdbId,
    this.localizedTitles,
    this.localizedOverviews,
  });

  /// 外部 ID
  final String externalId;

  /// 来源类型
  final ScraperType source;

  /// 标题
  final String title;

  /// 原始标题
  final String? originalTitle;

  /// 简介
  final String? overview;

  /// 海报 URL
  final String? posterUrl;

  /// 背景图 URL
  final String? backdropUrl;

  /// 首播年份
  final int? year;

  /// 评分
  final double? rating;

  /// 评分人数
  final int? voteCount;

  /// 单集时长（分钟）
  final int? episodeRuntime;

  /// 类型列表
  final List<String>? genres;

  /// 制片国家/地区列表
  final List<String>? countries;

  /// 演员列表
  final List<String>? cast;

  /// 状态
  final String? status;

  /// 季数
  final int? numberOfSeasons;

  /// 集数
  final int? numberOfEpisodes;

  /// 季列表
  final List<ScraperSeasonInfo>? seasons;

  /// IMDB ID
  final String? imdbId;

  /// 多语言标题
  final Map<String, String>? localizedTitles;

  /// 多语言简介
  final Map<String, String>? localizedOverviews;

  /// 类型文本
  String get genresText => genres?.join(' / ') ?? '';

  /// 国家/地区文本（以 , 分隔）
  String get countriesText => countries?.join(', ') ?? '';

  /// 演员文本
  String get castText => cast?.join(', ') ?? '';

  /// 将详情应用到 VideoMetadata
  void applyTo(
    VideoMetadata metadata, {
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
  }) {
    metadata
      ..category = MediaCategory.tvShow
      ..title = title
      ..originalTitle = originalTitle
      ..overview = overview
      ..posterUrl = posterUrl
      ..backdropUrl = backdropUrl
      ..year = year
      ..rating = rating
      ..runtime = episodeRuntime
      ..genres = genresText
      ..countries = countriesText
      ..cast = castText
      ..seasonNumber = seasonNumber
      ..episodeNumber = episodeNumber
      ..episodeTitle = episodeTitle
      ..localizedTitles = localizedTitles
      ..localizedOverviews = localizedOverviews
      ..lastUpdated = DateTime.now();

    // 根据来源设置对应的 ID
    switch (source) {
      case ScraperType.tmdb:
        metadata.tmdbId = int.tryParse(externalId);
      case ScraperType.doubanApi:
      case ScraperType.doubanWeb:
        metadata.doubanId = externalId;
    }
  }
}

/// 季信息
class ScraperSeasonInfo {
  const ScraperSeasonInfo({
    required this.seasonNumber,
    this.name,
    this.overview,
    this.posterUrl,
    this.airDate,
    this.episodeCount,
  });

  final int seasonNumber;
  final String? name;
  final String? overview;
  final String? posterUrl;
  final String? airDate;
  final int? episodeCount;
}

/// 剧集详情
class ScraperEpisodeDetail {
  const ScraperEpisodeDetail({
    required this.externalId,
    required this.source,
    required this.seasonNumber,
    required this.episodeNumber,
    this.name,
    this.overview,
    this.stillUrl,
    this.airDate,
    this.runtime,
    this.rating,
  });

  /// 外部 ID（电视剧 ID）
  final String externalId;

  /// 来源类型
  final ScraperType source;

  /// 季号
  final int seasonNumber;

  /// 集号
  final int episodeNumber;

  /// 剧集名称
  final String? name;

  /// 剧集简介
  final String? overview;

  /// 剧照 URL
  final String? stillUrl;

  /// 播出日期
  final String? airDate;

  /// 时长（分钟）
  final int? runtime;

  /// 评分
  final double? rating;
}

/// 季详情（包含所有剧集）
class ScraperSeasonDetail {
  const ScraperSeasonDetail({
    required this.externalId,
    required this.source,
    required this.seasonNumber,
    this.name,
    this.overview,
    this.posterUrl,
    this.airDate,
    required this.episodes,
  });

  /// 外部 ID（电视剧 ID）
  final String externalId;

  /// 来源类型
  final ScraperType source;

  /// 季号
  final int seasonNumber;

  /// 季名称
  final String? name;

  /// 季简介
  final String? overview;

  /// 海报 URL
  final String? posterUrl;

  /// 首播日期
  final String? airDate;

  /// 剧集列表
  final List<ScraperEpisodeDetail> episodes;

  /// 获取指定集的详情
  ScraperEpisodeDetail? getEpisode(int episodeNumber) => episodes
      .where((e) => e.episodeNumber == episodeNumber)
      .firstOrNull;
}
