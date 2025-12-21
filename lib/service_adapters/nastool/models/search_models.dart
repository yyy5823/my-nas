/// 搜索相关数据模型

/// 搜索结果
class NtSearchResult {
  const NtSearchResult({
    required this.title,
    required this.size,
    this.seeders,
    this.leechers,
    this.enclosure,
    this.site,
    this.pageUrl,
    this.description,
    this.resolution,
    this.uploadFactor,
    this.downloadFactor,
  });

  factory NtSearchResult.fromJson(Map<String, dynamic> json) => NtSearchResult(
    title: json['title'] as String? ?? json['torrent_name'] as String? ?? '',
    size: json['size'] as int? ?? 0,
    seeders: json['seeders'] as int?,
    leechers: json['leechers'] as int? ?? json['peers'] as int?,
    enclosure: json['enclosure'] as String? ?? json['url'] as String?,
    site: json['site'] as String?,
    pageUrl: json['page_url'] as String?,
    description: json['description'] as String?,
    resolution: json['res'] as String? ?? json['resolution'] as String?,
    uploadFactor: (json['uploadvolumefactor'] as num?)?.toDouble(),
    downloadFactor: (json['downloadvolumefactor'] as num?)?.toDouble(),
  );

  final String title;
  final int size;
  final int? seeders;
  final int? leechers;
  final String? enclosure;
  final String? site;
  final String? pageUrl;
  final String? description;
  final String? resolution;
  final double? uploadFactor;
  final double? downloadFactor;

  /// 是否免费
  bool get isFree => downloadFactor == 0;
  
  /// 是否2x上传
  bool get is2xUpload => uploadFactor == 2;

  /// 格式化大小
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}
