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
    this.musicCount,
    this.userCount,
  });

  factory NtLibraryStatistics.fromJson(Map<String, dynamic> json) => NtLibraryStatistics(
    // NASTool API 返回格式: {"Movie": "950", "Series": "301", "Episodes": "7,706", ...}
    // 数字可能是字符串且带逗号分隔符
    movieCount: _parseCount(json['Movie']) ??
                _parseCount(json['MovieCount']) ??
                _parseCount(json['movie_count']) ?? 0,
    tvCount: _parseCount(json['Series']) ??
             _parseCount(json['SeriesCount']) ??
             _parseCount(json['tv_count']) ?? 0,
    animeCount: _parseCount(json['anime_count']),
    episodeCount: _parseCount(json['Episodes']) ??
                  _parseCount(json['EpisodeCount']) ??
                  _parseCount(json['episode_count']),
    musicCount: _parseCount(json['Music']),
    userCount: _parseCount(json['User']),
  );

  /// 解析数字，支持整数、带逗号的字符串（如 "7,706"）
  static int? _parseCount(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) {
      // 移除逗号分隔符后解析
      final cleaned = value.replaceAll(',', '');
      return int.tryParse(cleaned);
    }
    return null;
  }

  final int movieCount;
  final int tvCount;
  final int? animeCount;
  final int? episodeCount;
  final int? musicCount;
  final int? userCount;

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
