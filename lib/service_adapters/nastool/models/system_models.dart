/// 系统相关数据模型

/// 系统版本信息
class NtSystemVersion {
  const NtSystemVersion({
    required this.version,
    this.latestVersion,
    this.hasUpdate,
  });

  factory NtSystemVersion.fromJson(Map<String, dynamic> json) => NtSystemVersion(
    version: json['version'] as String? ?? 
             json['data']?['version'] as String? ?? '',
    latestVersion: json['latest_version'] as String?,
    hasUpdate: json['has_update'] as bool? ?? false,
  );

  final String version;
  final String? latestVersion;
  final bool? hasUpdate;
}

/// 系统进度信息
class NtSystemProgress {
  const NtSystemProgress({
    required this.type,
    required this.value,
    this.text,
  });

  factory NtSystemProgress.fromJson(Map<String, dynamic> json) => NtSystemProgress(
    type: json['type'] as String? ?? '',
    value: (json['value'] as num?)?.toDouble() ?? 0,
    text: json['text'] as String?,
  );

  final String type;
  final double value;
  final String? text;
}

/// 路径信息
class NtPathInfo {
  const NtPathInfo({
    required this.path,
    required this.name,
    required this.isDir,
    this.size,
  });

  factory NtPathInfo.fromJson(Map<String, dynamic> json) => NtPathInfo(
    path: json['path'] as String? ?? json['value'] as String? ?? '',
    name: json['name'] as String? ?? '',
    isDir: json['type'] == 'dir' || json['is_dir'] == true,
    size: json['size'] as int?,
  );

  final String path;
  final String name;
  final bool isDir;
  final int? size;
}
