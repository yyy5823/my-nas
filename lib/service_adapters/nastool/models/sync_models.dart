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
    this.syncModeName,
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
        syncModeName: json['syncmod_name'] as String?,
        // 支持布尔值和字符串类型
        compatibility: _toBoolString(json['compatibility']),
        rename: _toBoolString(json['rename']),
        enabled: _toBoolString(json['enabled']),
      );

  // 将各种类型转换为统一的布尔字符串
  static String? _toBoolString(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value ? 'Y' : 'N';
    if (value is String) return value;
    return value.toString();
  }

  final int id;
  final String? from;
  final String? to;
  final String? unknown;
  final String? syncMode;
  final String? syncModeName;
  final String? compatibility;
  final String? rename;
  final String? enabled;

  /// 是否启用
  bool get isEnabled => enabled == 'Y' || enabled == '1' || enabled == 'true';

  /// 是否重命名
  bool get isRename => rename == 'Y' || rename == '1' || rename == 'true';
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
        mode: json['syncmod'] as String? ?? json['syncmod_name'] as String? ?? json['mode'] as String?,
        // enabled 字段可能是 bool 或 String
        state: NtSyncDirectory._toBoolString(json['enabled']) ?? json['state'] as String?,
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

  bool get isEnabled => state == 'Y' || state == '1' || state == 'true';
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
