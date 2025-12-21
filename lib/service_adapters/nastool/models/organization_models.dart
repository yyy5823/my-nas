/// 整理相关数据模型

/// 转移历史
class NtTransferHistory {
  const NtTransferHistory({
    required this.id,
    required this.title,
    this.type,
    this.sourcePath,
    this.destPath,
    this.transferTime,
    this.success,
    this.mode,
  });

  factory NtTransferHistory.fromJson(Map<String, dynamic> json) => NtTransferHistory(
    id: json['id'] as int? ?? 0,
    title: json['TITLE'] as String? ?? json['title'] as String? ?? '',
    type: json['TYPE'] as String? ?? json['type'] as String?,
    sourcePath: json['SOURCE_PATH'] as String? ?? json['source_path'] as String? ?? json['source'] as String?,
    destPath: json['DEST_PATH'] as String? ?? json['dest_path'] as String? ?? json['dest'] as String?,
    transferTime: json['DATE'] != null
        ? DateTime.tryParse(json['DATE'] as String)
        : (json['transfer_time'] != null
            ? DateTime.tryParse(json['transfer_time'] as String)
            : null),
    success: json['SUCCESS'] == 1 || json['success'] == true || json['state'] == 'SUCCESS',
    mode: json['MODE'] as String? ?? json['mode'] as String?,
  );

  final int id;
  final String title;
  final String? type;
  final String? sourcePath;
  final String? destPath;
  final DateTime? transferTime;
  final bool? success;
  final String? mode;
}

/// 未识别记录
class NtUnknownRecord {
  const NtUnknownRecord({
    required this.id,
    required this.path,
    this.name,
    this.addTime,
  });

  factory NtUnknownRecord.fromJson(Map<String, dynamic> json) => NtUnknownRecord(
    id: json['id'] as int? ?? 0,
    path: json['PATH'] as String? ?? json['path'] as String? ?? '',
    name: json['NAME'] as String? ?? json['name'] as String?,
    addTime: json['DATE'] != null
        ? DateTime.tryParse(json['DATE'] as String)
        : null,
  );

  final int id;
  final String path;
  final String? name;
  final DateTime? addTime;
}

/// 转移统计
class NtTransferStatistics {
  const NtTransferStatistics({
    this.movieCount,
    this.tvCount,
    this.animeCount,
  });

  factory NtTransferStatistics.fromJson(Map<String, dynamic> json) => NtTransferStatistics(
    movieCount: json['movie_count'] as int? ?? json['MovieCount'] as int?,
    tvCount: json['tv_count'] as int? ?? json['TvCount'] as int?,
    animeCount: json['anime_count'] as int? ?? json['AnimeCount'] as int?,
  );

  final int? movieCount;
  final int? tvCount;
  final int? animeCount;

  int get totalCount => (movieCount ?? 0) + (tvCount ?? 0) + (animeCount ?? 0);
}
