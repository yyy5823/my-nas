import 'package:my_nas/features/video/domain/entities/video_metadata.dart';

/// 剧集分组模型
/// 将同一部剧的所有集按季组织在一起
class TvShowGroup {
  TvShowGroup({
    required this.groupKey,
    required this.title,
    this.tmdbId,
    this.posterUrl,
    this.backdropUrl,
    this.rating,
    this.overview,
    this.year,
    this.genres,
    required this.seasonEpisodes,
  });

  /// 分组键（优先使用 tmdbId，否则使用标准化的标题）
  final String groupKey;

  /// 剧集标题
  final String title;

  /// TMDB ID（如果有）
  final int? tmdbId;

  /// 海报 URL
  final String? posterUrl;

  /// 背景图 URL
  final String? backdropUrl;

  /// 评分
  final double? rating;

  /// 简介
  final String? overview;

  /// 首播年份
  final int? year;

  /// 类型标签（逗号分隔的字符串）
  final String? genres;

  /// 获取类型列表
  List<String> get genreList => genres?.split(',').map((e) => e.trim()).toList() ?? [];

  /// 按季分组的剧集 `Map<seasonNumber, List<VideoMetadata>>`
  final Map<int, List<VideoMetadata>> seasonEpisodes;

  /// 季数
  int get seasonCount => seasonEpisodes.keys.where((s) => s > 0).length;

  /// 总集数
  int get episodeCount =>
      seasonEpisodes.values.fold(0, (sum, list) => sum + list.length);

  /// 获取所有季号（已排序）
  List<int> get seasons => seasonEpisodes.keys.toList()..sort();

  /// 获取代表性的元数据（用于列表显示）
  /// 优先返回第一季第一集，如果没有则返回任意一集
  VideoMetadata get representative {
    // 优先找第一季
    for (final season in seasons) {
      if (season > 0 && seasonEpisodes[season]!.isNotEmpty) {
        return seasonEpisodes[season]!.first;
      }
    }
    // 没有正片季则返回任意一集
    return seasonEpisodes.values.first.first;
  }

  /// 获取显示用的海报 URL
  String? get displayPosterUrl =>
      posterUrl ?? representative.posterUrl ?? representative.generatedThumbnailUrl;

  /// 获取显示用的标题
  String get displayTitle => title;

  /// 获取所有剧集的平铺列表（按季集排序）
  List<VideoMetadata> get allEpisodes {
    final result = <VideoMetadata>[];
    for (final season in seasons) {
      result.addAll(seasonEpisodes[season]!);
    }
    return result;
  }

  /// 从剧集列表构建分组
  /// 优先使用 tmdbId 分组，如果没有则使用标准化标题
  static Map<String, TvShowGroup> fromMetadataList(List<VideoMetadata> tvShows) {
    final groups = <String, _TvShowGroupBuilder>{};

    for (final metadata in tvShows) {
      // 确定分组键：优先使用 tmdbId
      final groupKey = _getGroupKey(metadata);

      // 获取或创建分组构建器，并添加剧集
      groups
          .putIfAbsent(
            groupKey,
            () => _TvShowGroupBuilder(groupKey: groupKey),
          )
          .addEpisode(metadata);
    }

    // 构建最终结果
    return groups.map((key, builder) => MapEntry(key, builder.build()));
  }

  /// 获取分组键
  static String _getGroupKey(VideoMetadata metadata) {
    // 优先使用 tmdbId（最准确）
    if (metadata.tmdbId != null) {
      return 'tmdb_${metadata.tmdbId}';
    }

    // 否则使用标准化的标题
    return _normalizeTitle(metadata.title ?? metadata.fileName);
  }

  /// 标准化标题（移除季集信息、年份等，便于同剧归组）
  static String _normalizeTitle(String title) {
    var normalized = title.toLowerCase().trim();

    // 移除常见的季集标记
    // 第X季、Season X、S01、第一季 等
    normalized = normalized.replaceAll(
      RegExp(r'[第\s]*(\d+|[一二三四五六七八九十]+)[季部期]'),
      '',
    );
    normalized = normalized.replaceAll(
      RegExp(r'season\s*\d+', caseSensitive: false),
      '',
    );
    normalized = normalized.replaceAll(RegExp(r's\d+', caseSensitive: false), '');

    // 移除年份标记 (2020) [2020]
    normalized = normalized.replaceAll(RegExp(r'[\(\[\s]\d{4}[\)\]\s]?'), '');

    // 移除多余空格
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

    return 'title_$normalized';
  }
}

/// 内部使用的分组构建器
class _TvShowGroupBuilder {
  _TvShowGroupBuilder({required this.groupKey});

  final String groupKey;
  final Map<int, List<VideoMetadata>> seasonEpisodes = {};

  // 存储最佳元数据（用于获取海报、简介等）
  VideoMetadata? _bestMetadata;

  void addEpisode(VideoMetadata metadata) {
    final season = metadata.seasonNumber ?? 0;
    seasonEpisodes.putIfAbsent(season, () => []).add(metadata);

    // 更新最佳元数据（优先选择有完整信息的）
    if (_bestMetadata == null || _isBetterMetadata(metadata, _bestMetadata!)) {
      _bestMetadata = metadata;
    }
  }

  bool _isBetterMetadata(VideoMetadata a, VideoMetadata b) {
    // 有 TMDB 信息的优先
    if (a.tmdbId != null && b.tmdbId == null) return true;
    if (a.tmdbId == null && b.tmdbId != null) return false;

    // 有海报的优先
    if (a.posterUrl != null && b.posterUrl == null) return true;
    if (a.posterUrl == null && b.posterUrl != null) return false;

    // 有评分的优先
    if (a.rating != null && b.rating == null) return true;

    return false;
  }

  TvShowGroup build() {
    // 每季内按集号排序
    for (final episodes in seasonEpisodes.values) {
      episodes.sort((a, b) {
        final episodeA = a.episodeNumber ?? 0;
        final episodeB = b.episodeNumber ?? 0;
        return episodeA.compareTo(episodeB);
      });
    }

    final best = _bestMetadata!;

    return TvShowGroup(
      groupKey: groupKey,
      title: best.title ?? best.fileName,
      tmdbId: best.tmdbId,
      posterUrl: best.posterUrl,
      backdropUrl: best.backdropUrl,
      rating: best.rating,
      overview: best.overview,
      year: best.year,
      genres: best.genres,
      seasonEpisodes: seasonEpisodes,
    );
  }
}
