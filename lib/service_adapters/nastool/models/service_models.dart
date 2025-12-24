/// 服务相关数据模型
library;

/// 媒体识别结果
class NtMediaRecognition {
  const NtMediaRecognition({
    this.type,
    this.name,
    this.title,
    this.year,
    this.season,
    this.episode,
    this.tmdbId,
    this.imdbId,
    this.category,
  });

  factory NtMediaRecognition.fromJson(Map<String, dynamic> json) => NtMediaRecognition(
        type: json['type'] as String?,
        name: json['name'] as String?,
        title: json['title'] as String?,
        year: json['year'] as String?,
        season: json['season'] as int?,
        episode: json['episode'] as int?,
        tmdbId: json['tmdbid'] as int?,
        imdbId: json['imdbid'] as String?,
        category: json['category'] as String?,
      );

  final String? type;
  final String? name;
  final String? title;
  final String? year;
  final int? season;
  final int? episode;
  final int? tmdbId;
  final String? imdbId;
  final String? category;
}

/// 名称识别测试结果
class NtNameTestResult {
  const NtNameTestResult({
    this.title,
    this.subtitle,
    this.type,
    this.year,
    this.season,
    this.episode,
    this.part,
    this.resType,
    this.pix,
    this.team,
    this.videoCodec,
    this.audioCodec,
  });

  factory NtNameTestResult.fromJson(Map<String, dynamic> json) => NtNameTestResult(
        title: json['title'] as String?,
        subtitle: json['subtitle'] as String?,
        type: json['type'] as String?,
        year: json['year'] as String?,
        season: json['season'] as String?,
        episode: json['episode'] as String?,
        part: json['part'] as String?,
        resType: json['restype'] as String?,
        pix: json['pix'] as String?,
        team: json['team'] as String?,
        videoCodec: json['video_codec'] as String?,
        audioCodec: json['audio_codec'] as String?,
      );

  final String? title;
  final String? subtitle;
  final String? type;
  final String? year;
  final String? season;
  final String? episode;
  final String? part;
  final String? resType;
  final String? pix;
  final String? team;
  final String? videoCodec;
  final String? audioCodec;
}

/// 过滤规则测试结果
class NtRuleTestResult {
  const NtRuleTestResult({
    this.success,
    this.ruleGroup,
    this.ruleName,
    this.priority,
  });

  factory NtRuleTestResult.fromJson(Map<String, dynamic> json) => NtRuleTestResult(
        success: json['success'] as bool? ?? json['code'] == 0,
        ruleGroup: json['rule_group'] as String?,
        ruleName: json['rule_name'] as String?,
        priority: json['priority'] as String?,
      );

  final bool? success;
  final String? ruleGroup;
  final String? ruleName;
  final String? priority;
}

/// 网络测试结果
class NtNetworkTestResult {
  const NtNetworkTestResult({
    this.success,
    this.time,
    this.message,
  });

  factory NtNetworkTestResult.fromJson(Map<String, dynamic> json) => NtNetworkTestResult(
        success: json['success'] as bool? ?? json['code'] == 0,
        time: json['time'] as int?,
        message: json['message'] as String?,
      );

  final bool? success;
  final int? time;
  final String? message;
}
