/// 用户相关数据模型

/// 用户信息
class NtUserInfo {
  const NtUserInfo({
    required this.username,
    this.level,
    this.pris,
  });

  factory NtUserInfo.fromJson(Map<String, dynamic> json) => NtUserInfo(
    username: json['name'] as String? ?? json['username'] as String? ?? '',
    level: json['level'] as int?,
    pris: json['pris'] as String?,
  );

  final String username;
  final int? level;
  final String? pris;
}
