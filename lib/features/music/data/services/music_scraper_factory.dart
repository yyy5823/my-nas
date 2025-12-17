import 'package:my_nas/features/music/data/services/scrapers/coverart_archive_scraper.dart';
import 'package:my_nas/features/music/data/services/scrapers/genius_scraper.dart';
import 'package:my_nas/features/music/data/services/scrapers/lastfm_scraper.dart';
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
        MusicScraperType.acoustId => _createAcoustIdScraper(source),
        MusicScraperType.coverArtArchive => CoverArtArchiveScraper(),
        MusicScraperType.lastFm => LastFmScraper(apiKey: source.apiKey ?? ''),
        MusicScraperType.neteaseMusic => NeteaseScraper(cookie: source.cookie),
        MusicScraperType.qqMusic => QQMusicScraper(cookie: source.cookie),
        MusicScraperType.genius => GeniusScraper(accessToken: source.apiKey ?? ''),
      };

  /// 创建 AcoustID 刮削器
  static MusicScraper _createAcoustIdScraper(MusicScraperSourceEntity source) {
    // TODO: 实现 AcoustID 刮削器 (需要 Chromaprint FFI)
    throw UnimplementedError('AcoustID scraper not implemented yet');
  }

  /// 检查刮削源类型是否已实现
  static bool isImplemented(MusicScraperType type) => [
        MusicScraperType.musicBrainz,
        MusicScraperType.coverArtArchive,
        MusicScraperType.lastFm,
        MusicScraperType.neteaseMusic,
        MusicScraperType.qqMusic,
        MusicScraperType.genius,
      ].contains(type);

  /// 获取所有已实现的刮削源类型
  static List<MusicScraperType> get implementedTypes => [
        MusicScraperType.musicBrainz,
        MusicScraperType.coverArtArchive,
        MusicScraperType.lastFm,
        MusicScraperType.neteaseMusic,
        MusicScraperType.qqMusic,
        MusicScraperType.genius,
      ];
}
