/// 消息通知相关数据模型
library;

/// 消息渠道
class NtMessageClient {
  const NtMessageClient({
    required this.id,
    required this.name,
    required this.type,
    this.config,
    this.switches,
    this.interactive,
    this.enabled,
  });

  factory NtMessageClient.fromJson(Map<String, dynamic> json) => NtMessageClient(
        id: json['id'] as int? ?? json['cid'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? '',
        config: json['config'] as String?,
        switches: json['switchs'] as String?,
        interactive: json['interactive'] as int? ?? 0,
        enabled: json['enabled'] as int? ?? 0,
      );

  final int id;
  final String name;
  final String type;
  final String? config;
  final String? switches;
  final int? interactive;
  final int? enabled;

  /// 是否启用
  bool get isEnabled => enabled == 1;

  /// 是否开启交互
  bool get isInteractive => interactive == 1;
}
