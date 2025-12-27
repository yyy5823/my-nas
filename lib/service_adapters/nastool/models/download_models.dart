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
    this.type,
    this.year,
    this.imageUrl,
    this.tmdbId,
  });

  factory NtDownloadHistory.fromJson(Map<String, dynamic> json) => NtDownloadHistory(
    // ID 可能是 int 或 String
    id: json['id'] is int ? json['id'] as int : (int.tryParse(json['id']?.toString() ?? '0') ?? 0),
    // title 字段支持多种大小写格式
    title: json['title'] as String? ?? json['TITLE'] as String? ?? json['name'] as String? ?? '',
    enclosure: json['enclosure'] as String? ?? json['ENCLOSURE'] as String?,
    site: json['site'] as String? ?? json['SITE'] as String?,
    description: json['description'] as String? ?? json['DESCRIPTION'] as String? ?? json['overview'] as String?,
    date: _parseDate(json['date'] ?? json['DATE']),
    type: json['type'] as String? ?? json['media_type'] as String?,
    year: json['year']?.toString(),
    imageUrl: json['image'] as String?,
    tmdbId: json['tmdbid']?.toString() ?? json['orgid']?.toString(),
  );

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  final int id;
  final String title;
  final String? enclosure;
  final String? site;
  final String? description;
  final DateTime? date;
  final String? type;
  final String? year;
  final String? imageUrl;
  final String? tmdbId;
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
