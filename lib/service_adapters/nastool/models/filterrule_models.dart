/// 过滤规则相关数据模型
library;

/// 过滤规则组
class NtFilterRuleGroup {
  const NtFilterRuleGroup({
    required this.id,
    required this.name,
    this.isDefault,
    this.rules,
  });

  factory NtFilterRuleGroup.fromJson(Map<String, dynamic> json) => NtFilterRuleGroup(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        isDefault: json['default'] == 'Y' || json['is_default'] == true,
        rules: (json['rules'] as List?)
            ?.map((e) => NtFilterRule.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final int id;
  final String name;
  final bool? isDefault;
  final List<NtFilterRule>? rules;
}

/// 过滤规则
class NtFilterRule {
  const NtFilterRule({
    required this.id,
    required this.groupId,
    required this.name,
    this.priority,
    this.include,
    this.exclude,
    this.sizeLimit,
    this.free,
  });

  factory NtFilterRule.fromJson(Map<String, dynamic> json) => NtFilterRule(
        id: json['id'] as int? ?? json['rule_id'] as int? ?? 0,
        groupId: json['group_id'] as int? ?? 0,
        name: json['name'] as String? ?? json['rule_name'] as String? ?? '',
        priority: json['pri'] as String? ?? json['rule_pri'] as String?,
        include: json['include'] as String? ?? json['rule_include'] as String?,
        exclude: json['exclude'] as String? ?? json['rule_exclude'] as String?,
        sizeLimit: json['sizelimit'] as String? ?? json['rule_sizelimit'] as String?,
        free: json['free'] as String? ?? json['rule_free'] as String?,
      );

  final int id;
  final int groupId;
  final String name;
  final String? priority;
  final String? include;
  final String? exclude;
  final String? sizeLimit;
  final String? free;
}
