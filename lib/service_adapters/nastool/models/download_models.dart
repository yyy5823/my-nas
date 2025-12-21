/// 下载相关数据模型
library;

/// 下载任务
class NtDownloadTask {
  const NtDownloadTask({
    required this.id,
    required this.name,
    required this.state,
    required this.progress,
    this.size,
    this.speed,
    this.eta,
    this.savePath,
    this.downloader,
  });

  factory NtDownloadTask.fromJson(Map<String, dynamic> json) => NtDownloadTask(
    id: json['id']?.toString() ?? json['hash']?.toString() ?? '',
    name: json['name'] as String? ?? json['title'] as String? ?? '',
    state: json['state'] as String? ?? json['status'] as String? ?? '',
    progress: (json['progress'] as num?)?.toDouble() ??
              ((json['percent'] as num?)?.toDouble() ?? 0) / 100,
    size: json['size'] as int? ?? json['total_size'] as int?,
    speed: json['speed'] as int? ?? json['dlspeed'] as int?,
    eta: json['eta'] as int?,
    savePath: json['save_path'] as String? ?? json['path'] as String?,
    downloader: json['downloader'] as String?,
  );

  final String id;
  final String name;
  final String state;
  final double progress;
  final int? size;
  final int? speed;
  final int? eta;
  final String? savePath;
  final String? downloader;

  bool get isCompleted => progress >= 1.0;
  bool get isDownloading => state.toLowerCase().contains('download');
}

/// 下载历史
class NtDownloadHistory {
  const NtDownloadHistory({
    required this.id,
    required this.title,
    this.enclosure,
    this.site,
    this.description,
    this.date,
  });

  factory NtDownloadHistory.fromJson(Map<String, dynamic> json) => NtDownloadHistory(
    id: json['id'] as int? ?? 0,
    title: json['TITLE'] as String? ?? json['title'] as String? ?? '',
    enclosure: json['ENCLOSURE'] as String? ?? json['enclosure'] as String?,
    site: json['SITE'] as String? ?? json['site'] as String?,
    description: json['DESCRIPTION'] as String? ?? json['description'] as String?,
    date: json['DATE'] != null
        ? DateTime.tryParse(json['DATE'] as String)
        : null,
  );

  final int id;
  final String title;
  final String? enclosure;
  final String? site;
  final String? description;
  final DateTime? date;
}

/// 下载器客户端
class NtDownloadClient {
  const NtDownloadClient({
    required this.id,
    required this.name,
    required this.type,
    this.enabled,
    this.transfer,
    this.onlyNastool,
    this.rmtMode,
  });

  factory NtDownloadClient.fromJson(Map<String, dynamic> json) => NtDownloadClient(
    id: json['id']?.toString() ?? '',
    name: json['name'] as String? ?? '',
    type: json['type'] as String? ?? '',
    enabled: json['enabled'] == 1 || json['enabled'] == '1' || json['enabled'] == true,
    transfer: json['transfer'] == 1 || json['transfer'] == '1' || json['transfer'] == true,
    onlyNastool: json['only_nastool'] == 1 || json['only_nastool'] == '1',
    rmtMode: json['rmt_mode'] as String?,
  );

  final String id;
  final String name;
  final String type;
  final bool? enabled;
  final bool? transfer;
  final bool? onlyNastool;
  final String? rmtMode;
}
