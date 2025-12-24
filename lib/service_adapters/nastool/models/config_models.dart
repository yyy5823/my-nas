/// 配置相关数据模型
library;

/// 系统配置信息
class NtConfigInfo {
  const NtConfigInfo({
    this.app,
    this.laboratory,
    this.security,
    this.speedLimit,
    this.message,
    this.douban,
  });

  factory NtConfigInfo.fromJson(Map<String, dynamic> json) => NtConfigInfo(
        app: json['app'] as Map<String, dynamic>?,
        laboratory: json['laboratory'] as Map<String, dynamic>?,
        security: json['security'] as Map<String, dynamic>?,
        speedLimit: json['speedlimit'] as Map<String, dynamic>?,
        message: json['message'] as Map<String, dynamic>?,
        douban: json['douban'] as Map<String, dynamic>?,
      );

  final Map<String, dynamic>? app;
  final Map<String, dynamic>? laboratory;
  final Map<String, dynamic>? security;
  final Map<String, dynamic>? speedLimit;
  final Map<String, dynamic>? message;
  final Map<String, dynamic>? douban;
}

/// 目录配置
class NtDirectoryConfig {
  const NtDirectoryConfig({
    this.moviePaths,
    this.tvPaths,
    this.animePaths,
    this.unknownPath,
  });

  factory NtDirectoryConfig.fromJson(Map<String, dynamic> json) => NtDirectoryConfig(
        moviePaths: (json['movie_path'] as List?)?.cast<String>(),
        tvPaths: (json['tv_path'] as List?)?.cast<String>(),
        animePaths: (json['anime_path'] as List?)?.cast<String>(),
        unknownPath: json['unknown_path'] as String?,
      );

  final List<String>? moviePaths;
  final List<String>? tvPaths;
  final List<String>? animePaths;
  final String? unknownPath;
}
