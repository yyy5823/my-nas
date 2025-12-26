/// 同步目录相关数据模型
library;

/// 同步目录
class NtSyncDirectory {
  const NtSyncDirectory({
    required this.id,
    this.from,
    this.to,
    this.unknown,
    this.syncMode,
    this.compatibility,
    this.rename,
    this.enabled,
  });

  factory NtSyncDirectory.fromJson(Map<String, dynamic> json) => NtSyncDirectory(
        id: json['id'] as int? ?? json['sid'] as int? ?? 0,
        from: json['from'] as String?,
        to: json['to'] as String?,
        unknown: json['unknown'] as String?,
        syncMode: json['syncmod'] as String?,
        compatibility: json['compatibility'] as String?,
        rename: json['rename'] as String?,
        enabled: json['enabled'] as String?,
      );

  final int id;
  final String? from;
  final String? to;
  final String? unknown;
  final String? syncMode;
  final String? compatibility;
  final String? rename;
  final String? enabled;

  /// 是否启用
  bool get isEnabled => enabled == 'Y' || enabled == '1';

  /// 是否重命名
  bool get isRename => rename == 'Y' || rename == '1';
}

/// 同步目录（用于 UI 展示）
class NtSyncDir {
  const NtSyncDir({
    this.id,
    this.name,
    this.from,
    this.to,
    this.mode,
    this.state,
    this.include,
    this.exclude,
  });

  factory NtSyncDir.fromJson(Map<String, dynamic> json) => NtSyncDir(
        id: json['id'] as int? ?? json['sid'] as int?,
        name: json['name'] as String? ?? json['from'] as String?,
        from: json['from'] as String?,
        to: json['to'] as String?,
        mode: json['syncmod'] as String? ?? json['mode'] as String?,
        state: json['enabled'] as String? ?? json['state'] as String?,
        include: json['include'] as String?,
        exclude: json['exclude'] as String?,
      );

  final int? id;
  final String? name;
  final String? from;
  final String? to;
  final String? mode;
  final String? state;
  final String? include;
  final String? exclude;

  bool get isEnabled => state == 'Y' || state == '1';
}

/// 同步历史记录
class NtSyncHistory {
  const NtSyncHistory({
    this.id,
    this.sourcePath,
    this.sourceFilename,
    this.destPath,
    this.mode,
    this.date,
    this.success,
  });

  factory NtSyncHistory.fromJson(Map<String, dynamic> json) => NtSyncHistory(
        id: json['id'] as int?,
        sourcePath: json['source_path'] as String? ?? json['src'] as String?,
        sourceFilename: json['source_filename'] as String? ?? json['source_name'] as String?,
        destPath: json['dest_path'] as String? ?? json['dest'] as String?,
        mode: json['mode'] as String? ?? json['syncmod'] as String?,
        date: json['date'] as String? ?? json['time'] as String?,
        success: json['success'] as bool? ?? json['state'] == 'success',
      );

  final int? id;
  final String? sourcePath;
  final String? sourceFilename;
  final String? destPath;
  final String? mode;
  final String? date;
  final bool? success;
}
