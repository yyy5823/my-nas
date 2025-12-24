/// 自定义 RSS 订阅相关数据模型
library;

/// 自定义 RSS 任务
class NtRssTask {
  const NtRssTask({
    required this.id,
    required this.name,
    this.address,
    this.parser,
    this.interval,
    this.uses,
    this.state,
    this.include,
    this.exclude,
    this.filterRule,
    this.note,
  });

  factory NtRssTask.fromJson(Map<String, dynamic> json) => NtRssTask(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        address: json['address'] as String?,
        parser: json['parser'] as int?,
        interval: json['interval'] as int?,
        uses: json['uses'] as String?,
        state: json['state'] as String?,
        include: json['include'] as String?,
        exclude: json['exclude'] as String?,
        filterRule: json['filterrule'] as int?,
        note: json['note'] as String?,
      );

  final int id;
  final String name;
  final String? address;
  final int? parser;
  final int? interval;
  final String? uses;
  final String? state;
  final String? include;
  final String? exclude;
  final int? filterRule;
  final String? note;

  /// 是否启用
  bool get isEnabled => state == 'Y';
}

/// RSS 解析器
class NtRssParser {
  const NtRssParser({
    required this.id,
    required this.name,
    this.type,
    this.format,
    this.params,
  });

  factory NtRssParser.fromJson(Map<String, dynamic> json) => NtRssParser(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        type: json['type'] as String?,
        format: json['format'] as String?,
        params: json['params'] as String?,
      );

  final int id;
  final String name;
  final String? type;
  final String? format;
  final String? params;
}

/// RSS 条目
class NtRssArticle {
  const NtRssArticle({
    this.title,
    this.enclosure,
    this.description,
    this.link,
    this.size,
    this.pubDate,
    this.finished,
  });

  factory NtRssArticle.fromJson(Map<String, dynamic> json) => NtRssArticle(
        title: json['title'] as String?,
        enclosure: json['enclosure'] as String?,
        description: json['description'] as String?,
        link: json['link'] as String?,
        size: json['size'] as int?,
        pubDate: json['pubdate'] as String?,
        finished: json['finished'] as bool? ?? false,
      );

  final String? title;
  final String? enclosure;
  final String? description;
  final String? link;
  final int? size;
  final String? pubDate;
  final bool? finished;
}

/// RSS 任务处理历史
class NtRssHistory {
  const NtRssHistory({
    this.title,
    this.enclosure,
    this.downloader,
    this.date,
  });

  factory NtRssHistory.fromJson(Map<String, dynamic> json) => NtRssHistory(
        title: json['title'] as String?,
        enclosure: json['enclosure'] as String?,
        downloader: json['downloader'] as String?,
        date: json['date'] as String?,
      );

  final String? title;
  final String? enclosure;
  final String? downloader;
  final String? date;
}
