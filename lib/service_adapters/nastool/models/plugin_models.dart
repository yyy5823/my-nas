/// 插件相关数据模型
library;

/// 已安装插件
class NtPlugin {
  const NtPlugin({
    required this.id,
    required this.name,
    this.version,
    this.description,
    this.author,
    this.enabled,
    this.hasPage,
    this.icon,
  });

  factory NtPlugin.fromJson(Map<String, dynamic> json) => NtPlugin(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        version: json['version'] as String?,
        description: json['desc'] as String? ?? json['description'] as String?,
        author: json['author'] as String?,
        enabled: json['enabled'] as bool? ?? json['status'] == 1,
        hasPage: json['has_page'] as bool? ?? false,
        icon: json['icon'] as String?,
      );

  final int id;
  final String name;
  final String? version;
  final String? description;
  final String? author;
  final bool? enabled;
  final bool? hasPage;
  final String? icon;
}

/// 插件市场应用
class NtPluginApp {
  const NtPluginApp({
    required this.id,
    required this.name,
    this.version,
    this.description,
    this.author,
    this.repo,
    this.icon,
    this.installed,
  });

  factory NtPluginApp.fromJson(Map<String, dynamic> json) => NtPluginApp(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        version: json['version'] as String?,
        description: json['desc'] as String? ?? json['description'] as String?,
        author: json['author'] as String?,
        repo: json['repo'] as String?,
        icon: json['icon'] as String?,
        installed: json['installed'] as bool? ?? false,
      );

  final int id;
  final String name;
  final String? version;
  final String? description;
  final String? author;
  final String? repo;
  final String? icon;
  final bool? installed;
}

/// 插件运行状态
class NtPluginStatus {
  const NtPluginStatus({
    required this.id,
    this.status,
    this.message,
  });

  factory NtPluginStatus.fromJson(Map<String, dynamic> json) => NtPluginStatus(
        id: json['id'] as int? ?? 0,
        status: json['status'] as String?,
        message: json['message'] as String?,
      );

  final int id;
  final String? status;
  final String? message;
}
