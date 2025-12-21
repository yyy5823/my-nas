/// 订阅相关数据模型

/// 订阅信息
class NtSubscribe {
  const NtSubscribe({
    required this.id,
    required this.name,
    required this.type,
    this.tmdbId,
    this.year,
    this.season,
    this.state,
    this.posterPath,
    this.keyword,
    this.sites,
    this.filterRule,
    this.totalEp,
    this.currentEp,
  });

  factory NtSubscribe.fromJson(Map<String, dynamic> json, [String? defaultType]) => NtSubscribe(
    id: json['id'] as int? ?? json['rssid'] as int? ?? 0,
    name: json['name'] as String? ?? json['title'] as String? ?? '',
    type: json['type'] as String? ?? defaultType ?? 'MOV',
    tmdbId: json['tmdbid']?.toString() ?? json['mediaid']?.toString(),
    year: json['year']?.toString(),
    season: json['season'] as int?,
    state: json['state'] as String?,
    posterPath: json['poster'] as String? ?? json['image'] as String?,
    keyword: json['keyword'] as String?,
    sites: json['rss_sites'] as String? ?? json['search_sites'] as String?,
    filterRule: json['filter_rule'] as int? ?? json['filterrule'] as int?,
    totalEp: json['total_ep'] as int? ?? json['total'] as int?,
    currentEp: json['current_ep'] as int? ?? json['current'] as int?,
  );

  final int id;
  final String name;
  final String type;
  final String? tmdbId;
  final String? year;
  final int? season;
  final String? state;
  final String? posterPath;
  final String? keyword;
  final String? sites;
  final int? filterRule;
  final int? totalEp;
  final int? currentEp;

  bool get isMovie => type.toUpperCase() == 'MOV';
  bool get isTv => type.toUpperCase() == 'TV';
}

/// 订阅历史
class NtSubscribeHistory {
  const NtSubscribeHistory({
    required this.id,
    required this.name,
    required this.type,
    this.tmdbId,
    this.year,
    this.season,
    this.posterPath,
    this.addTime,
  });

  factory NtSubscribeHistory.fromJson(Map<String, dynamic> json) => NtSubscribeHistory(
    id: json['id'] as int? ?? json['rssid'] as int? ?? 0,
    name: json['name'] as String? ?? json['title'] as String? ?? '',
    type: json['type'] as String? ?? 'MOV',
    tmdbId: json['tmdbid']?.toString(),
    year: json['year']?.toString(),
    season: json['season'] as int?,
    posterPath: json['poster'] as String? ?? json['image'] as String?,
    addTime: json['add_time'] != null 
        ? DateTime.tryParse(json['add_time'] as String)
        : null,
  );

  final int id;
  final String name;
  final String type;
  final String? tmdbId;
  final String? year;
  final int? season;
  final String? posterPath;
  final DateTime? addTime;
}
