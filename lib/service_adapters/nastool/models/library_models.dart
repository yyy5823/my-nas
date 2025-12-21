/// 媒体库相关数据模型
library;

/// 媒体库空间
class NtLibrarySpace {
  const NtLibrarySpace({
    this.movie,
    this.tv,
    this.anime,
    this.total,
    this.used,
    this.free,
  });

  factory NtLibrarySpace.fromJson(Map<String, dynamic> json) => NtLibrarySpace(
    movie: json['movie'] as String?,
    tv: json['tv'] as String?,
    anime: json['anime'] as String?,
    total: json['total'] as int?,
    used: json['used'] as int?,
    free: json['free'] as int?,
  );

  final String? movie;
  final String? tv;
  final String? anime;
  final int? total;
  final int? used;
  final int? free;
}

/// 媒体库统计
class NtLibraryStatistics {
  const NtLibraryStatistics({
    required this.movieCount,
    required this.tvCount,
    this.animeCount,
    this.episodeCount,
  });

  factory NtLibraryStatistics.fromJson(Map<String, dynamic> json) => NtLibraryStatistics(
    movieCount: json['MovieCount'] as int? ?? json['movie_count'] as int? ?? 0,
    tvCount: json['SeriesCount'] as int? ?? json['tv_count'] as int? ?? 0,
    animeCount: json['anime_count'] as int?,
    episodeCount: json['EpisodeCount'] as int? ?? json['episode_count'] as int?,
  );

  final int movieCount;
  final int tvCount;
  final int? animeCount;
  final int? episodeCount;

  int get totalCount => movieCount + tvCount + (animeCount ?? 0);
}

/// 播放历史
class NtPlayHistory {
  const NtPlayHistory({
    required this.id,
    required this.title,
    this.type,
    this.userName,
    this.playTime,
  });

  factory NtPlayHistory.fromJson(Map<String, dynamic> json) => NtPlayHistory(
    id: json['id']?.toString() ?? '',
    title: json['title'] as String? ?? json['name'] as String? ?? '',
    type: json['type'] as String?,
    userName: json['user_name'] as String? ?? json['username'] as String?,
    playTime: json['play_time'] != null
        ? DateTime.tryParse(json['play_time'] as String)
        : null,
  );

  final String id;
  final String title;
  final String? type;
  final String? userName;
  final DateTime? playTime;
}
