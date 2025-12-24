/// 刷流任务相关数据模型
library;

/// 刷流任务
class NtBrushTask {
  const NtBrushTask({
    required this.id,
    required this.name,
    this.site,
    this.interval,
    this.downloader,
    this.totalSize,
    this.savePath,
    this.label,
    this.rssUrl,
    this.state,
    this.transfer,
    this.sendMessage,
    this.free,
    this.hr,
    this.torrentSize,
    this.include,
    this.exclude,
    this.dlCount,
    this.peerCount,
    this.seedTime,
    this.hrSeedTime,
    this.seedRatio,
    this.seedSize,
    this.dlTime,
    this.avgUpSpeed,
    this.iaTime,
    this.pubDate,
    this.upSpeed,
    this.downSpeed,
  });

  factory NtBrushTask.fromJson(Map<String, dynamic> json) => NtBrushTask(
        id: json['id']?.toString() ?? '',
        name: json['name'] as String? ?? json['brushtask_name'] as String? ?? '',
        site: json['site'] as int? ?? json['brushtask_site'] as int?,
        interval: json['interval'] as int? ?? json['brushtask_interval'] as int?,
        downloader: json['downloader'] as int? ?? json['brushtask_downloader'] as int?,
        totalSize: json['totalsize'] as int? ?? json['brushtask_totalsize'] as int?,
        savePath: json['savepath'] as String? ?? json['brushtask_savepath'] as String?,
        label: json['label'] as String? ?? json['brushtask_label'] as String?,
        rssUrl: json['rssurl'] as String? ?? json['brushtask_rssurl'] as String?,
        state: json['state'] as String? ?? json['brushtask_state'] as String?,
        transfer: json['transfer'] as String? ?? json['brushtask_transfer'] as String?,
        sendMessage: json['sendmessage'] as String? ?? json['brushtask_sendmessage'] as String?,
        free: json['free'] as String? ?? json['brushtask_free'] as String?,
        hr: json['hr'] as String? ?? json['brushtask_hr'] as String?,
        torrentSize: json['torrent_size'] as int? ?? json['brushtask_torrent_size'] as int?,
        include: json['include'] as String? ?? json['brushtask_include'] as String?,
        exclude: json['exclude'] as String? ?? json['brushtask_exclude'] as String?,
        dlCount: json['dlcount'] as int? ?? json['brushtask_dlcount'] as int?,
        peerCount: json['peercount'] as int? ?? json['brushtask_peercount'] as int?,
        seedTime: (json['seedtime'] as num?)?.toDouble() ?? (json['brushtask_seedtime'] as num?)?.toDouble(),
        hrSeedTime: (json['hr_seedtime'] as num?)?.toDouble() ?? (json['brushtask_hr_seedtime'] as num?)?.toDouble(),
        seedRatio: (json['seedratio'] as num?)?.toDouble() ?? (json['brushtask_seedratio'] as num?)?.toDouble(),
        seedSize: json['seedsize'] as int? ?? json['brushtask_seedsize'] as int?,
        dlTime: (json['dltime'] as num?)?.toDouble() ?? (json['brushtask_dltime'] as num?)?.toDouble(),
        avgUpSpeed: json['avg_upspeed'] as int? ?? json['brushtask_avg_upspeed'] as int?,
        iaTime: (json['iatime'] as num?)?.toDouble() ?? (json['brushtask_iatime'] as num?)?.toDouble(),
        pubDate: json['pubdate'] as int? ?? json['brushtask_pubdate'] as int?,
        upSpeed: json['upspeed'] as int? ?? json['brushtask_upspeed'] as int?,
        downSpeed: json['downspeed'] as int? ?? json['brushtask_downspeed'] as int?,
      );

  final String id;
  final String name;
  final int? site;
  final int? interval;
  final int? downloader;
  final int? totalSize;
  final String? savePath;
  final String? label;
  final String? rssUrl;
  final String? state;
  final String? transfer;
  final String? sendMessage;
  final String? free;
  final String? hr;
  final int? torrentSize;
  final String? include;
  final String? exclude;
  final int? dlCount;
  final int? peerCount;
  final double? seedTime;
  final double? hrSeedTime;
  final double? seedRatio;
  final int? seedSize;
  final double? dlTime;
  final int? avgUpSpeed;
  final double? iaTime;
  final int? pubDate;
  final int? upSpeed;
  final int? downSpeed;

  /// 是否启用
  bool get isEnabled => state == 'Y';
}

/// 刷流任务种子
class NtBrushTorrent {
  const NtBrushTorrent({
    required this.id,
    this.title,
    this.size,
    this.uploadSpeed,
    this.downloadSpeed,
    this.uploaded,
    this.downloaded,
    this.ratio,
    this.seedingTime,
    this.addTime,
  });

  factory NtBrushTorrent.fromJson(Map<String, dynamic> json) => NtBrushTorrent(
        id: json['id']?.toString() ?? '',
        title: json['title'] as String?,
        size: json['size'] as int?,
        uploadSpeed: json['upload_speed'] as int? ?? json['upspeed'] as int?,
        downloadSpeed: json['download_speed'] as int? ?? json['dlspeed'] as int?,
        uploaded: json['uploaded'] as int?,
        downloaded: json['downloaded'] as int?,
        ratio: (json['ratio'] as num?)?.toDouble(),
        seedingTime: json['seeding_time'] as int?,
        addTime: json['add_time'] as String?,
      );

  final String id;
  final String? title;
  final int? size;
  final int? uploadSpeed;
  final int? downloadSpeed;
  final int? uploaded;
  final int? downloaded;
  final double? ratio;
  final int? seedingTime;
  final String? addTime;
}
