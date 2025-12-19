import 'package:my_nas/features/video/data/services/scrapers/douban_api_scraper.dart';
import 'package:my_nas/features/video/data/services/scrapers/douban_web_scraper.dart';
import 'package:my_nas/features/video/data/services/scrapers/tmdb_scraper.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/domain/interfaces/media_scraper.dart';

/// 刮削器工厂
///
/// 根据刮削源配置创建对应的刮削器实例
class ScraperFactory {
  const ScraperFactory._();

  /// 根据刮削源实体创建刮削器
  static MediaScraper create(ScraperSourceEntity source) => switch (source.type) {
        ScraperType.tmdb => TmdbScraper(
            apiKey: source.apiKey ?? '',
            apiUrl: source.apiUrl,
            imageProxy: source.extraConfig?['imageProxy'] as String?,
          ),
        ScraperType.doubanApi => DoubanApiScraper(
            apiUrl: source.apiUrl ?? '',
            apiKey: source.apiKey,
          ),
        ScraperType.doubanWeb => DoubanWebScraper(
            cookie: source.cookie ?? '',
            requestInterval: source.requestInterval,
          ),
      };

  /// 根据刮削源类型和凭证创建刮削器
  static MediaScraper createFromCredential(
    ScraperType type,
    ScraperCredential credential, {
    String? apiUrl,
    String? imageProxy,
    int requestInterval = 0,
  }) => switch (type) {
        ScraperType.tmdb => TmdbScraper(
            apiKey: credential.apiKey ?? '',
            apiUrl: apiUrl,
            imageProxy: imageProxy,
          ),
        ScraperType.doubanApi => DoubanApiScraper(
            apiUrl: apiUrl ?? '',
            apiKey: credential.apiKey,
          ),
        ScraperType.doubanWeb => DoubanWebScraper(
            cookie: credential.cookie ?? '',
            requestInterval: requestInterval,
          ),
      };
}
