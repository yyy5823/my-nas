import 'package:my_nas/features/video/data/services/tmdb_service.dart';

/// 媒体类型
enum MediaCategory {
  movie,
  tvShow,
  unknown,
}

/// 刮削状态
enum ScrapeStatus {
  /// 未刮削（新扫描到的文件）
  pending,

  /// 刮削中
  scraping,

  /// 已刮削成功（成功获取TMDB数据）
  completed,

  /// 刮削失败（无匹配或API错误）
  failed,

  /// 已跳过（用户手动标记或不需要刮削）
  skipped,
}

/// 视频元数据
class VideoMetadata {
  VideoMetadata({
    required this.filePath,
    required this.sourceId,
    required this.fileName,
    this.category = MediaCategory.unknown,
    this.scrapeStatus = ScrapeStatus.pending,
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
    this.localPosterUrl,
    this.fileSize,
    this.fileModifiedTime,
    this.collectionId,
    this.collectionName,
    this.showDirectory,
    this.movieDirectory,
    this.resolution,
  });

  /// 从 Map 创建
  factory VideoMetadata.fromMap(Map<dynamic, dynamic> map) => VideoMetadata(
      filePath: map['filePath'] as String,
      sourceId: map['sourceId'] as String,
      fileName: map['fileName'] as String,
      category: MediaCategory.values[map['category'] as int? ?? 2],
      scrapeStatus: ScrapeStatus.values[map['scrapeStatus'] as int? ?? 0],
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
      localPosterUrl: map['localPosterUrl'] as String?,
      fileSize: map['fileSize'] as int?,
      fileModifiedTime: map['fileModifiedTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['fileModifiedTime'] as int)
          : null,
      collectionId: map['collectionId'] as int?,
      collectionName: map['collectionName'] as String?,
      showDirectory: map['showDirectory'] as String?,
      movieDirectory: map['movieDirectory'] as String?,
      resolution: map['resolution'] as String?,
    );

  final String filePath;
  final String sourceId;
  final String fileName;
  MediaCategory category;
  ScrapeStatus scrapeStatus;
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
  String? localPosterUrl; // 本地缓存的海报 URL（本地 file://，离线可用）
  int? fileSize; // 文件大小（字节）
  DateTime? fileModifiedTime; // 文件修改时间
  int? collectionId; // TMDB 电影系列 ID
  String? collectionName; // TMDB 电影系列名称
  String? showDirectory; // 所属剧目录（TV 剧集专用，用于分组）
  String? movieDirectory; // 电影所在目录（用于目录系列识别）
  String? resolution; // 视频分辨率（4K, 1080p, 720p 等）

  /// 海报显示优先级：
  /// 1. 本地缓存的海报（离线可用）
  /// 2. TMDB 海报（需网络，但会被 CachedNetworkImage 缓存）
  /// 3. NAS 内置缩略图（需 NAS 连接）
  /// 4. 生成的视频缩略图（离线可用）
  String? get displayPosterUrl => localPosterUrl ?? posterUrl ?? thumbnailUrl ?? generatedThumbnailUrl;

  /// 是否有元数据（已成功刮削TMDB数据）
  bool get hasMetadata => tmdbId != null;

  /// 是否已完成刮削（成功或失败都算完成）
  bool get isScrapeDone =>
      scrapeStatus == ScrapeStatus.completed ||
      scrapeStatus == ScrapeStatus.failed ||
      scrapeStatus == ScrapeStatus.skipped;

  /// 是否正在刮削
  bool get isScraping => scrapeStatus == ScrapeStatus.scraping;

  /// 是否待刮削
  bool get isPendingScrape => scrapeStatus == ScrapeStatus.pending;

  /// 文件大小显示文本
  String get fileSizeText {
    if (fileSize == null || fileSize == 0) return '';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (fileSize! >= gb) {
      return '${(fileSize! / gb).toStringAsFixed(2)} GB';
    } else if (fileSize! >= mb) {
      return '${(fileSize! / mb).toStringAsFixed(1)} MB';
    } else if (fileSize! >= kb) {
      return '${(fileSize! / kb).toStringAsFixed(0)} KB';
    }
    return '$fileSize B';
  }

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
    // 保存电影系列信息
    collectionId = movie.belongsToCollection?.id;
    collectionName = movie.belongsToCollection?.name;
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
      'scrapeStatus': scrapeStatus.index,
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
      'localPosterUrl': localPosterUrl,
      'fileSize': fileSize,
      'fileModifiedTime': fileModifiedTime?.millisecondsSinceEpoch,
      'collectionId': collectionId,
      'collectionName': collectionName,
      'showDirectory': showDirectory,
      'movieDirectory': movieDirectory,
      'resolution': resolution,
    };

  /// 复制
  VideoMetadata copyWith({
    String? filePath,
    String? sourceId,
    String? fileName,
    MediaCategory? category,
    ScrapeStatus? scrapeStatus,
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
    String? localPosterUrl,
    int? fileSize,
    DateTime? fileModifiedTime,
    int? collectionId,
    String? collectionName,
    String? showDirectory,
    String? movieDirectory,
    String? resolution,
  }) => VideoMetadata(
      filePath: filePath ?? this.filePath,
      sourceId: sourceId ?? this.sourceId,
      fileName: fileName ?? this.fileName,
      category: category ?? this.category,
      scrapeStatus: scrapeStatus ?? this.scrapeStatus,
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
      localPosterUrl: localPosterUrl ?? this.localPosterUrl,
      fileSize: fileSize ?? this.fileSize,
      fileModifiedTime: fileModifiedTime ?? this.fileModifiedTime,
      collectionId: collectionId ?? this.collectionId,
      collectionName: collectionName ?? this.collectionName,
      showDirectory: showDirectory ?? this.showDirectory,
      movieDirectory: movieDirectory ?? this.movieDirectory,
      resolution: resolution ?? this.resolution,
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
    '(4K|2160[pP]|1080[pP]|720[pP]|480[pP])',
    caseSensitive: false,
  );
  static final _sourcePattern = RegExp(
    '(BluRay|BDRip|WEB-?DL|WEBRip|HDRip|DVDRip|HDTV)',
    caseSensitive: false,
  );
  static final _codecPattern = RegExp(
    r'(x264|x265|HEVC|H\.?264|H\.?265|AVC)',
    caseSensitive: false,
  );
  static final _cleanupPattern = RegExp(
    r'[\[\]\(\)\{\}]|\.(?=\S)|_|-(?=\s)|'
    '(?:BluRay|BDRip|WEB-?DL|WEBRip|HDRip|DVDRip|HDTV|'
    r'x264|x265|HEVC|H\.?264|H\.?265|AVC|AAC|AC3|DTS|'
    '4K|2160p|1080p|720p|480p|'
    r'PROPER|REPACK|EXTENDED|UNRATED|DIRECTORS\.CUT|'
    '中英字幕|中文字幕|双语字幕|简体|繁体|'
    'RARBG|YTS|YIFY|FGT|EVO|SPARKS)',
    caseSensitive: false,
  );

  /// 解析视频文件名
  static VideoFileNameInfo parse(String fileName) {
    // 移除扩展名
    final name = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

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
