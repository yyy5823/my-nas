import 'package:my_nas/features/music/data/services/fingerprint/fingerprint_service.dart';
import 'package:my_nas/features/music/data/services/scrapers/acoustid_scraper.dart';
import 'package:my_nas/features/music/data/services/scrapers/coverart_archive_scraper.dart';
import 'package:my_nas/features/music/data/services/scrapers/genius_scraper.dart';
import 'package:my_nas/features/music/data/services/scrapers/lastfm_scraper.dart';
import 'package:my_nas/features/music/data/services/scrapers/music_tag_web_scraper.dart';
import 'package:my_nas/features/music/data/services/scrapers/musicbrainz_scraper.dart';
import 'package:my_nas/features/music/data/services/scrapers/netease_scraper.dart';
import 'package:my_nas/features/music/data/services/scrapers/qq_music_scraper.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// 音乐刮削器工厂
class MusicScraperFactory {
  MusicScraperFactory._();

  /// 根据刮削源配置创建刮削器实例
  static MusicScraper create(MusicScraperSourceEntity source) => switch (source.type) {
        MusicScraperType.musicBrainz => MusicBrainzScraper(),
        MusicScraperType.acoustId => AcoustIdScraper(
            apiKey: source.apiKey ?? '',
            fingerprintService: FingerprintService.getInstance(),
          ),
        MusicScraperType.coverArtArchive => CoverArtArchiveScraper(),
        MusicScraperType.lastFm => LastFmScraper(apiKey: source.apiKey ?? ''),
        MusicScraperType.neteaseMusic => NeteaseScraper(cookie: source.cookie),
        MusicScraperType.qqMusic => QQMusicScraper(cookie: source.cookie),
        MusicScraperType.genius => GeniusScraper(accessToken: source.apiKey ?? ''),
        MusicScraperType.musicTagWeb => MusicTagWebScraper(
            serverUrl: source.serverUrl ?? '',
            username: source.extraConfig?['username'] as String?,
            password: source.extraConfig?['password'] as String?,
            preferredSource: MusicTagWebSource.fromId(
              source.extraConfig?['preferredSource'] as String? ?? 'netease',
            ),
          ),
      };

  /// 检查刮削源类型是否已实现
  static bool isImplemented(MusicScraperType type) => [
        MusicScraperType.musicBrainz,
        MusicScraperType.acoustId,
        MusicScraperType.coverArtArchive,
        MusicScraperType.lastFm,
        MusicScraperType.neteaseMusic,
        MusicScraperType.qqMusic,
        MusicScraperType.genius,
        MusicScraperType.musicTagWeb,
      ].contains(type);

  /// 获取所有已实现的刮削源类型
  static List<MusicScraperType> get implementedTypes => [
        MusicScraperType.musicBrainz,
        MusicScraperType.acoustId,
        MusicScraperType.coverArtArchive,
        MusicScraperType.lastFm,
        MusicScraperType.neteaseMusic,
        MusicScraperType.qqMusic,
        MusicScraperType.genius,
        MusicScraperType.musicTagWeb,
      ];

  /// 检查指纹服务是否可用
  static bool get isFingerprintAvailable {
    final service = FingerprintService.getInstance();
    return service?.isAvailable ?? false;
  }
}
