/// 站点相关数据模型
library;

/// 站点信息
class NtSite {
  const NtSite({
    required this.id,
    required this.name,
    this.signUrl,
    this.rssUrl,
    this.cookie,
    this.note,
    this.include,
    this.pri,
  });

  factory NtSite.fromJson(Map<String, dynamic> json) => NtSite(
    id: json['id'] as int? ?? 0,
    name: json['name'] as String? ?? json['site_name'] as String? ?? '',
    signUrl: json['signurl'] as String? ?? json['site_signurl'] as String?,
    rssUrl: json['rssurl'] as String? ?? json['site_rssurl'] as String?,
    cookie: json['cookie'] as String? ?? json['site_cookie'] as String?,
    note: json['note'] as String? ?? json['site_note'] as String?,
    include: json['include'] as String? ?? json['site_include'] as String?,
    pri: json['pri'] as String? ?? json['site_pri'] as String?,
  );

  final int id;
  final String name;
  final String? signUrl;
  final String? rssUrl;
  final String? cookie;
  final String? note;
  final String? include;
  final String? pri;
}

/// 站点统计
class NtSiteStatistics {
  const NtSiteStatistics({
    required this.siteName,
    this.upload,
    this.download,
    this.ratio,
    this.seedingCount,
    this.bonus,
    this.userLevel,
  });

  factory NtSiteStatistics.fromJson(Map<String, dynamic> json) => NtSiteStatistics(
    siteName: json['site'] as String? ?? json['name'] as String? ?? '',
    upload: json['upload'] as int?,
    download: json['download'] as int?,
    ratio: (json['ratio'] as num?)?.toDouble(),
    seedingCount: json['seeding'] as int? ?? json['seeding_count'] as int?,
    bonus: (json['bonus'] as num?)?.toDouble(),
    userLevel: json['user_level'] as String?,
  );

  final String siteName;
  final int? upload;
  final int? download;
  final double? ratio;
  final int? seedingCount;
  final double? bonus;
  final String? userLevel;
}

/// 站点索引器
class NtSiteIndexer {
  const NtSiteIndexer({
    required this.id,
    required this.name,
    this.domain,
    this.public,
  });

  factory NtSiteIndexer.fromJson(Map<String, dynamic> json) => NtSiteIndexer(
    id: json['id']?.toString() ?? '',
    name: json['name'] as String? ?? '',
    domain: json['domain'] as String?,
    public: json['public'] as bool? ?? false,
  );

  final String id;
  final String name;
  final String? domain;
  final bool? public;
}
