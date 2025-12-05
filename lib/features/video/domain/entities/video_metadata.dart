import 'package:my_nas/features/video/data/services/tmdb_service.dart';

/// 媒体类型
enum MediaCategory {
  movie,
  tvShow,
  unknown,
}

/// 视频元数据
class VideoMetadata {
  VideoMetadata({
    required this.filePath,
    required this.sourceId,
    required this.fileName,
    this.category = MediaCategory.unknown,
    this.tmdbId,
    this.title,
    this.originalTitle,
    this.year,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.rating,
    this.runtime,
    this.genres,
    this.director,
    this.cast,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    this.lastUpdated,
    this.thumbnailUrl,
    this.generatedThumbnailUrl,
  });

  final String filePath;
  final String sourceId;
  final String fileName;
  MediaCategory category;
  int? tmdbId;
  String? title;
  String? originalTitle;
  int? year;
  String? overview;
  String? posterUrl;
  String? backdropUrl;
  double? rating;
  int? runtime;
  String? genres;
  String? director;
  String? cast;
  int? seasonNumber;
  int? episodeNumber;
  String? episodeTitle;
  DateTime? lastUpdated;
  String? thumbnailUrl; // 内置缩略图 URL（来自 NAS）
  String? generatedThumbnailUrl; // 生成的缩略图 URL（本地 file://）

  /// 优先使用 TMDB 海报，其次使用内置缩略图，最后使用生成的缩略图
  String? get displayPosterUrl => posterUrl ?? thumbnailUrl ?? generatedThumbnailUrl;

  /// 是否有元数据
  bool get hasMetadata => tmdbId != null;

  /// 显示标题
  String get displayTitle => title ?? fileName;

  /// 评分文本
  String get ratingText => rating != null ? rating!.toStringAsFixed(1) : '';

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

  /// 类型列表
  List<String> get genreList => genres?.split(',').map((e) => e.trim()).toList() ?? [];

  /// 演员列表
  List<String> get castList => cast?.split(',').map((e) => e.trim()).toList() ?? [];

  /// 从 TMDB 电影详情更新
  void updateFromMovie(TmdbMovieDetail movie) {
    category = MediaCategory.movie;
    tmdbId = movie.id;
    title = movie.title;
    originalTitle = movie.originalTitle;
    year = movie.year;
    overview = movie.overview;
    posterUrl = movie.posterUrl;
    backdropUrl = movie.backdropUrl;
    rating = movie.voteAverage;
    runtime = movie.runtime;
    genres = movie.genresText;
    director = movie.director?.name;
    cast = movie.cast.take(5).map((c) => c.name).join(', ');
    lastUpdated = DateTime.now();
  }

  /// 从 TMDB 电视剧详情更新
  void updateFromTvShow(TmdbTvDetail tv, {int? season, int? episode, String? epTitle}) {
    category = MediaCategory.tvShow;
    tmdbId = tv.id;
    title = tv.name;
    originalTitle = tv.originalName;
    year = tv.year;
    overview = tv.overview;
    posterUrl = tv.posterUrl;
    backdropUrl = tv.backdropUrl;
    rating = tv.voteAverage;
    runtime = tv.episodeRunTime.isNotEmpty ? tv.episodeRunTime.first : null;
    genres = tv.genresText;
    cast = tv.cast.take(5).map((c) => c.name).join(', ');
    seasonNumber = season;
    episodeNumber = episode;
    episodeTitle = epTitle;
    lastUpdated = DateTime.now();
  }

  /// 从 TMDB 搜索结果更新
  void updateFromSearchResult(TmdbMediaItem item) {
    category = item.isMovie ? MediaCategory.movie : MediaCategory.tvShow;
    tmdbId = item.id;
    title = item.title;
    originalTitle = item.originalTitle;
    year = item.year;
    overview = item.overview;
    posterUrl = item.posterUrl;
    backdropUrl = item.backdropUrl;
    rating = item.voteAverage;
    lastUpdated = DateTime.now();
  }

  /// 唯一标识
  String get uniqueKey => '${sourceId}_$filePath';

  /// 转为 Map
  Map<String, dynamic> toMap() => {
      'filePath': filePath,
      'sourceId': sourceId,
      'fileName': fileName,
      'category': category.index,
      'tmdbId': tmdbId,
      'title': title,
      'originalTitle': originalTitle,
      'year': year,
      'overview': overview,
      'posterUrl': posterUrl,
      'backdropUrl': backdropUrl,
      'rating': rating,
      'runtime': runtime,
      'genres': genres,
      'director': director,
      'cast': cast,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      'episodeTitle': episodeTitle,
      'lastUpdated': lastUpdated?.millisecondsSinceEpoch,
      'thumbnailUrl': thumbnailUrl,
      'generatedThumbnailUrl': generatedThumbnailUrl,
    };

  /// 从 Map 创建
  factory VideoMetadata.fromMap(Map<dynamic, dynamic> map) => VideoMetadata(
      filePath: map['filePath'] as String,
      sourceId: map['sourceId'] as String,
      fileName: map['fileName'] as String,
      category: MediaCategory.values[map['category'] as int? ?? 2],
      tmdbId: map['tmdbId'] as int?,
      title: map['title'] as String?,
      originalTitle: map['originalTitle'] as String?,
      year: map['year'] as int?,
      overview: map['overview'] as String?,
      posterUrl: map['posterUrl'] as String?,
      backdropUrl: map['backdropUrl'] as String?,
      rating: (map['rating'] as num?)?.toDouble(),
      runtime: map['runtime'] as int?,
      genres: map['genres'] as String?,
      director: map['director'] as String?,
      cast: map['cast'] as String?,
      seasonNumber: map['seasonNumber'] as int?,
      episodeNumber: map['episodeNumber'] as int?,
      episodeTitle: map['episodeTitle'] as String?,
      lastUpdated: map['lastUpdated'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastUpdated'] as int)
          : null,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      generatedThumbnailUrl: map['generatedThumbnailUrl'] as String?,
    );

  /// 复制
  VideoMetadata copyWith({
    String? filePath,
    String? sourceId,
    String? fileName,
    MediaCategory? category,
    int? tmdbId,
    String? title,
    String? originalTitle,
    int? year,
    String? overview,
    String? posterUrl,
    String? backdropUrl,
    double? rating,
    int? runtime,
    String? genres,
    String? director,
    String? cast,
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
    DateTime? lastUpdated,
    String? thumbnailUrl,
    String? generatedThumbnailUrl,
  }) => VideoMetadata(
      filePath: filePath ?? this.filePath,
      sourceId: sourceId ?? this.sourceId,
      fileName: fileName ?? this.fileName,
      category: category ?? this.category,
      tmdbId: tmdbId ?? this.tmdbId,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      year: year ?? this.year,
      overview: overview ?? this.overview,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      rating: rating ?? this.rating,
      runtime: runtime ?? this.runtime,
      genres: genres ?? this.genres,
      director: director ?? this.director,
      cast: cast ?? this.cast,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      generatedThumbnailUrl: generatedThumbnailUrl ?? this.generatedThumbnailUrl,
    );
}

/// 视频文件名解析结果
class VideoFileNameInfo {
  VideoFileNameInfo({
    required this.cleanTitle,
    this.year,
    this.season,
    this.episode,
    this.resolution,
    this.source,
    this.codec,
  });

  final String cleanTitle;
  final int? year;
  final int? season;
  final int? episode;
  final String? resolution;
  final String? source;
  final String? codec;

  bool get isTvShow => season != null || episode != null;
  bool get isMovie => !isTvShow;
}

/// 视频文件名解析器
class VideoFileNameParser {
  static final _yearPattern = RegExp(r'[\[\(]?((?:19|20)\d{2})[\]\)]?');
  static final _tvShowPattern = RegExp(
    r'[Ss](\d{1,2})[Ee](\d{1,2})|(\d{1,2})x(\d{1,2})|第(\d+)季.*?第(\d+)集|第(\d+)集',
    caseSensitive: false,
  );
  static final _resolutionPattern = RegExp(
    r'(4K|2160[pP]|1080[pP]|720[pP]|480[pP])',
    caseSensitive: false,
  );
  static final _sourcePattern = RegExp(
    r'(BluRay|BDRip|WEB-?DL|WEBRip|HDRip|DVDRip|HDTV)',
    caseSensitive: false,
  );
  static final _codecPattern = RegExp(
    r'(x264|x265|HEVC|H\.?264|H\.?265|AVC)',
    caseSensitive: false,
  );
  static final _cleanupPattern = RegExp(
    r'[\[\]\(\)\{\}]|\.(?=\S)|_|-(?=\s)|'
    r'(?:BluRay|BDRip|WEB-?DL|WEBRip|HDRip|DVDRip|HDTV|'
    r'x264|x265|HEVC|H\.?264|H\.?265|AVC|AAC|AC3|DTS|'
    r'4K|2160p|1080p|720p|480p|'
    r'PROPER|REPACK|EXTENDED|UNRATED|DIRECTORS\.CUT|'
    r'中英字幕|中文字幕|双语字幕|简体|繁体|'
    r'RARBG|YTS|YIFY|FGT|EVO|SPARKS)',
    caseSensitive: false,
  );

  /// 解析视频文件名
  static VideoFileNameInfo parse(String fileName) {
    // 移除扩展名
    var name = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

    // 提取年份
    int? year;
    final yearMatch = _yearPattern.firstMatch(name);
    if (yearMatch != null) {
      year = int.tryParse(yearMatch.group(1) ?? '');
    }

    // 提取剧集信息
    int? season;
    int? episode;
    final tvMatch = _tvShowPattern.firstMatch(name);
    if (tvMatch != null) {
      if (tvMatch.group(1) != null && tvMatch.group(2) != null) {
        // S01E01 格式
        season = int.tryParse(tvMatch.group(1) ?? '');
        episode = int.tryParse(tvMatch.group(2) ?? '');
      } else if (tvMatch.group(3) != null && tvMatch.group(4) != null) {
        // 1x01 格式
        season = int.tryParse(tvMatch.group(3) ?? '');
        episode = int.tryParse(tvMatch.group(4) ?? '');
      } else if (tvMatch.group(5) != null && tvMatch.group(6) != null) {
        // 第X季第X集格式
        season = int.tryParse(tvMatch.group(5) ?? '');
        episode = int.tryParse(tvMatch.group(6) ?? '');
      } else if (tvMatch.group(7) != null) {
        // 只有第X集
        episode = int.tryParse(tvMatch.group(7) ?? '');
        season = 1;
      }
    }

    // 提取分辨率
    final resolutionMatch = _resolutionPattern.firstMatch(name);
    final resolution = resolutionMatch?.group(1);

    // 提取来源
    final sourceMatch = _sourcePattern.firstMatch(name);
    final source = sourceMatch?.group(1);

    // 提取编码
    final codecMatch = _codecPattern.firstMatch(name);
    final codec = codecMatch?.group(1);

    // 清理标题
    var cleanTitle = name;

    // 移除年份后的所有内容（对于电影）
    if (year != null && season == null) {
      final yearIndex = name.indexOf(yearMatch!.group(0)!);
      if (yearIndex > 0) {
        cleanTitle = name.substring(0, yearIndex);
      }
    }

    // 移除剧集信息后的内容
    if (tvMatch != null) {
      final matchIndex = name.indexOf(tvMatch.group(0)!);
      if (matchIndex > 0) {
        cleanTitle = name.substring(0, matchIndex);
      }
    }

    // 清理特殊字符和关键词
    cleanTitle = cleanTitle
        .replaceAll(_cleanupPattern, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return VideoFileNameInfo(
      cleanTitle: cleanTitle,
      year: year,
      season: season,
      episode: episode,
      resolution: resolution,
      source: source,
      codec: codec,
    );
  }
}
