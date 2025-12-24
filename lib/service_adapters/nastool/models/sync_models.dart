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
