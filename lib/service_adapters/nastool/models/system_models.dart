/// 系统相关数据模型
library;

/// 系统版本信息
class NtSystemVersion {
  const NtSystemVersion({
    required this.version,
    this.latestVersion,
    this.hasUpdate,
  });

  factory NtSystemVersion.fromJson(Map<String, dynamic> json) => NtSystemVersion(
    version: json['version'] as String? ??
             (json['data'] as Map<String, dynamic>?)?['version'] as String? ?? '',
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

/// 系统信息（综合）
class NtSystemInfo {
  const NtSystemInfo({
    this.version,
    this.latestVersion,
    this.totalSpace,
    this.freeSpace,
    this.cpuUsage,
    this.memoryUsage,
    this.updateChannel,
  });

  factory NtSystemInfo.fromJson(Map<String, dynamic> json) => NtSystemInfo(
    version: json['version'] as String?,
    latestVersion: json['latest_version'] as String?,
    totalSpace: json['total_space'] as int?,
    freeSpace: json['free_space'] as int?,
    cpuUsage: (json['cpu_usage'] as num?)?.toDouble(),
    memoryUsage: (json['memory_usage'] as num?)?.toDouble(),
    updateChannel: json['update_channel'] as String? ?? json['channel'] as String?,
  );

  final String? version;
  final String? latestVersion;
  final int? totalSpace;
  final int? freeSpace;
  final double? cpuUsage;
  final double? memoryUsage;
  final String? updateChannel;

  /// 是否有更新
  bool get hasUpdate => latestVersion != null && latestVersion != version;

  /// 已用空间
  int? get usedSpace => (totalSpace != null && freeSpace != null)
      ? totalSpace! - freeSpace!
      : null;

  /// CPU 使用百分比 (0-100)
  double? get cpuUsedPercent => cpuUsage != null ? cpuUsage! * 100 : null;

  /// 内存使用百分比 (0-100)
  double? get memoryUsedPercent => memoryUsage != null ? memoryUsage! * 100 : null;
}

/// 服务信息
class NtService {
  const NtService({
    required this.id,
    required this.name,
    this.state,
    this.description,
  });

  factory NtService.fromJson(Map<String, dynamic> json) => NtService(
    id: json['id'] as String? ?? json['name'] as String? ?? '',
    name: json['name'] as String? ?? '',
    state: json['state'] as String? ?? json['status'] as String?,
    description: json['description'] as String?,
  );

  final String id;
  final String name;
  final String? state;
  final String? description;

  /// 服务状态（别名）
  String? get status => state;

  bool get isRunning => state == 'running' || state == 'active';
}

/// 进程信息
class NtProcess {
  const NtProcess({
    required this.pid,
    required this.name,
    this.cpuPercent,
    this.memoryPercent,
    this.status,
  });

  factory NtProcess.fromJson(Map<String, dynamic> json) => NtProcess(
    pid: json['pid'] as int? ?? 0,
    name: json['name'] as String? ?? '',
    cpuPercent: (json['cpu_percent'] as num?)?.toDouble() ?? (json['cpu'] as num?)?.toDouble(),
    memoryPercent: (json['memory_percent'] as num?)?.toDouble() ?? (json['memory'] as num?)?.toDouble(),
    status: json['status'] as String?,
  );

  final int pid;
  final String name;
  final double? cpuPercent;
  final double? memoryPercent;
  final String? status;

  /// CPU 使用率（别名）
  double? get cpu => cpuPercent;

  /// 内存使用率（别名）
  double? get memory => memoryPercent;

  bool get isRunning => status == 'running';
}

/// 日志条目
class NtLogEntry {
  const NtLogEntry({
    required this.time,
    required this.level,
    required this.message,
    this.module,
  });

  factory NtLogEntry.fromJson(Map<String, dynamic> json) => NtLogEntry(
    time: json['time'] as String? ?? json['timestamp'] as String? ?? '',
    level: json['level'] as String? ?? 'INFO',
    message: json['message'] as String? ?? json['msg'] as String? ?? '',
    module: json['module'] as String?,
  );

  final String time;
  final String level;
  final String message;
  final String? module;

  bool get isError => level == 'ERROR' || level == 'CRITICAL';
  bool get isWarning => level == 'WARNING' || level == 'WARN';
}
