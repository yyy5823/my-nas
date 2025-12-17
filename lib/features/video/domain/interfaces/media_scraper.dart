import 'package:my_nas/features/video/domain/entities/scraper_result.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';

/// 媒体刮削器接口
///
/// 所有刮削源实现都必须遵循此接口
abstract class MediaScraper {
  /// 刮削源类型
  ScraperType get type;

  /// 是否已配置（有有效的凭证/配置）
  bool get isConfigured;

  /// 测试连接是否有效
  ///
  /// 用于验证 API Key、Cookie 等凭证是否正确
  Future<bool> testConnection();

  /// 搜索电影
  ///
  /// [query] 搜索关键词
  /// [page] 页码（从 1 开始）
  /// [language] 语言代码（如 zh-CN, en）
  /// [year] 年份过滤
  Future<ScraperSearchResult> searchMovies(
    String query, {
    int page = 1,
    String? language,
    int? year,
  });

  /// 搜索电视剧
  ///
  /// [query] 搜索关键词
  /// [page] 页码（从 1 开始）
  /// [language] 语言代码（如 zh-CN, en）
  /// [year] 首播年份过滤
  Future<ScraperSearchResult> searchTvShows(
    String query, {
    int page = 1,
    String? language,
    int? year,
  });

  /// 获取电影详情
  ///
  /// [externalId] 外部 ID（如 TMDB ID 或豆瓣 ID）
  /// [language] 语言代码
  Future<ScraperMovieDetail?> getMovieDetail(
    String externalId, {
    String? language,
  });

  /// 获取电视剧详情
  ///
  /// [externalId] 外部 ID
  /// [language] 语言代码
  Future<ScraperTvDetail?> getTvDetail(
    String externalId, {
    String? language,
  });

  /// 获取剧集详情
  ///
  /// [tvId] 电视剧 ID
  /// [seasonNumber] 季号
  /// [episodeNumber] 集号
  /// [language] 语言代码
  Future<ScraperEpisodeDetail?> getEpisodeDetail(
    String tvId,
    int seasonNumber,
    int episodeNumber, {
    String? language,
  });

  /// 获取季详情（包含所有剧集）
  ///
  /// [tvId] 电视剧 ID
  /// [seasonNumber] 季号
  /// [language] 语言代码
  Future<ScraperSeasonDetail?> getSeasonDetail(
    String tvId,
    int seasonNumber, {
    String? language,
  });

  /// 释放资源
  void dispose();
}

/// 刮削器异常
class ScraperException implements Exception {
  const ScraperException(this.message, {this.source, this.cause});

  /// 错误消息
  final String message;

  /// 来源刮削器类型
  final ScraperType? source;

  /// 原始异常
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('ScraperException: $message');
    if (source != null) {
      buffer.write(' (source: ${source!.displayName})');
    }
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}

/// 认证错误（API Key 无效、Cookie 过期等）
class ScraperAuthException extends ScraperException {
  const ScraperAuthException(super.message, {super.source, super.cause});
}

/// 速率限制错误
class ScraperRateLimitException extends ScraperException {
  const ScraperRateLimitException(
    super.message, {
    super.source,
    super.cause,
    this.retryAfter,
  });

  /// 建议的重试等待时间（秒）
  final int? retryAfter;
}

/// 网络错误
class ScraperNetworkException extends ScraperException {
  const ScraperNetworkException(super.message, {super.source, super.cause});
}
