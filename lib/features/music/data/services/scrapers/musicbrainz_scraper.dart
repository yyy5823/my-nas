import 'dart:async';

import 'package:dio/dio.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// MusicBrainz 刮削器
///
/// 使用 MusicBrainz JSON Web Service 2 API
/// 文档: https://musicbrainz.org/doc/MusicBrainz_API
class MusicBrainzScraper implements MusicScraper {
  MusicBrainzScraper({
    String? userAgent,
  }) : _userAgent = userAgent ?? 'MyNAS/1.0 (https://github.com/my-nas)' {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'User-Agent': _userAgent,
      },
    ));
  }

  static const String _baseUrl = 'https://musicbrainz.org/ws/2';

  final String _userAgent;
  late final Dio _dio;

  /// 上次请求时间（用于速率限制）
  DateTime? _lastRequestTime;

  /// 最小请求间隔（1秒）
  static const Duration _minInterval = Duration(seconds: 1);

  @override
  MusicScraperType get type => MusicScraperType.musicBrainz;

  @override
  bool get isConfigured => true; // MusicBrainz 无需认证

  @override
  Future<bool> testConnection() async {
    try {
      await _rateLimitedRequest(() => _dio.get<dynamic>(
            '/recording',
            queryParameters: {
              'query': 'test',
              'limit': 1,
              'fmt': 'json',
            },
          ));
      return true;
    } on Exception {
      return false;
    }
  }

  @override
  Future<MusicScraperSearchResult> search(
    String query, {
    String? artist,
    String? album,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      // 构建 Lucene 查询
      final queryParts = <String>[query];
      if (artist != null && artist.isNotEmpty) {
        queryParts.add('artist:"$artist"');
      }
      if (album != null && album.isNotEmpty) {
        queryParts.add('release:"$album"');
      }

      final luceneQuery = queryParts.join(' AND ');
      final offset = (page - 1) * limit;

      final response = await _rateLimitedRequest(() => _dio.get<dynamic>(
            '/recording',
            queryParameters: {
              'query': luceneQuery,
              'limit': limit,
              'offset': offset,
              'fmt': 'json',
            },
          ));

      final data = response.data as Map<String, dynamic>;
      final recordings = (data['recordings'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final count = data['count'] as int? ?? 0;

      final items = recordings.map(_parseRecording).toList();

      return MusicScraperSearchResult(
        items: items,
        source: type,
        page: page,
        totalPages: (count / limit).ceil(),
        totalResults: count,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Future<MusicScraperDetail?> getDetail(String externalId) async {
    try {
      final response = await _rateLimitedRequest(() => _dio.get<dynamic>(
            '/recording/$externalId',
            queryParameters: {
              'inc': 'artists+releases+genres+isrcs+artist-credits',
              'fmt': 'json',
            },
          ));

      final data = response.data as Map<String, dynamic>;
      return _parseRecordingDetail(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw _handleDioError(e);
    }
  }
  /// MusicBrainz 本身不提供封面，需要通过 Cover Art Archive
  /// 这里返回空列表，由 CoverArtArchiveScraper 处理
  @override
  Future<List<CoverScraperResult>> getCoverArt(String externalId) async => [];

  /// MusicBrainz 不提供歌词
  @override
  Future<LyricScraperResult?> getLyrics(String externalId) async => null;

  @override
  void dispose() {
    _dio.close();
  }

  /// 速率限制请求
  Future<Response<T>> _rateLimitedRequest<T>(
    Future<Response<T>> Function() request,
  ) async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed < _minInterval) {
        await Future<void>.delayed(_minInterval - elapsed);
      }
    }
    _lastRequestTime = DateTime.now();
    return request();
  }

  /// 解析 Recording 搜索结果
  MusicScraperItem _parseRecording(Map<String, dynamic> data) {
    final id = data['id'] as String;
    final title = data['title'] as String? ?? '';

    // 艺术家
    String? artist;
    final artistCredit = (data['artist-credit'] as List?)?.cast<Map<String, dynamic>>();
    if (artistCredit != null && artistCredit.isNotEmpty) {
      artist = artistCredit.map((ac) {
        final artistData = ac['artist'] as Map<String, dynamic>?;
        final name = ac['name'] as String? ?? artistData?['name'] as String? ?? '';
        final joinPhrase = ac['joinphrase'] as String? ?? '';
        return '$name$joinPhrase';
      }).join();
    }

    // 专辑（第一个 release）
    String? album;
    int? year;
    final releases = (data['releases'] as List?)?.cast<Map<String, dynamic>>();
    if (releases != null && releases.isNotEmpty) {
      final firstRelease = releases.first;
      album = firstRelease['title'] as String?;
      final date = firstRelease['date'] as String?;
      if (date != null && date.length >= 4) {
        year = int.tryParse(date.substring(0, 4));
      }
    }

    // 时长
    final lengthMs = data['length'] as int?;

    // 匹配分数
    final score = data['score'] as int?;

    return MusicScraperItem(
      externalId: id,
      source: type,
      title: title,
      artist: artist,
      album: album,
      year: year,
      durationMs: lengthMs,
      score: score != null ? score / 100 : null,
    );
  }

  /// 解析 Recording 详情
  MusicScraperDetail _parseRecordingDetail(Map<String, dynamic> data) {
    final id = data['id'] as String;
    final title = data['title'] as String? ?? '';

    // 艺术家
    String? artist;
    final artistCredit = (data['artist-credit'] as List?)?.cast<Map<String, dynamic>>();
    if (artistCredit != null && artistCredit.isNotEmpty) {
      artist = artistCredit.map((ac) {
        final artistData = ac['artist'] as Map<String, dynamic>?;
        final name = ac['name'] as String? ?? artistData?['name'] as String? ?? '';
        final joinPhrase = ac['joinphrase'] as String? ?? '';
        return '$name$joinPhrase';
      }).join();
    }

    // 专辑信息
    String? album;
    String? albumArtist;
    int? year;
    int? trackNumber;
    int? discNumber;
    String? releaseDate;
    String? label;

    final releases = (data['releases'] as List?)?.cast<Map<String, dynamic>>();
    if (releases != null && releases.isNotEmpty) {
      final firstRelease = releases.first;
      album = firstRelease['title'] as String?;

      final date = firstRelease['date'] as String?;
      releaseDate = date;
      if (date != null && date.length >= 4) {
        year = int.tryParse(date.substring(0, 4));
      }

      // 唱片公司
      final labelInfo = (firstRelease['label-info'] as List?)?.cast<Map<String, dynamic>>();
      if (labelInfo != null && labelInfo.isNotEmpty) {
        final labelData = labelInfo.first['label'] as Map<String, dynamic>?;
        label = labelData?['name'] as String?;
      }

      // 音轨信息
      final media = (firstRelease['media'] as List?)?.cast<Map<String, dynamic>>();
      if (media != null && media.isNotEmpty) {
        for (var i = 0; i < media.length; i++) {
          final disc = media[i];
          final tracks = (disc['tracks'] as List?)?.cast<Map<String, dynamic>>();
          if (tracks != null) {
            for (final track in tracks) {
              final recording = track['recording'] as Map<String, dynamic>?;
              if (recording?['id'] == id) {
                trackNumber = track['position'] as int?;
                discNumber = i + 1;
                break;
              }
            }
          }
        }
      }

      // 专辑艺术家
      final releaseArtistCredit = (firstRelease['artist-credit'] as List?)?.cast<Map<String, dynamic>>();
      if (releaseArtistCredit != null && releaseArtistCredit.isNotEmpty) {
        albumArtist = releaseArtistCredit.map((ac) {
          final artistData = ac['artist'] as Map<String, dynamic>?;
          final name = ac['name'] as String? ?? artistData?['name'] as String? ?? '';
          final joinPhrase = ac['joinphrase'] as String? ?? '';
          return '$name$joinPhrase';
        }).join();
      }
    }

    // 时长
    final lengthMs = data['length'] as int?;

    // 流派
    final genres = (data['genres'] as List?)?.cast<Map<String, dynamic>>()
        .map((g) => g['name'] as String)
        .toList();

    // ISRC
    String? isrc;
    final isrcs = data['isrcs'] as List?;
    if (isrcs != null && isrcs.isNotEmpty) {
      isrc = isrcs.first as String?;
    }

    return MusicScraperDetail(
      externalId: id,
      source: type,
      title: title,
      artist: artist,
      albumArtist: albumArtist,
      album: album,
      year: year,
      trackNumber: trackNumber,
      discNumber: discNumber,
      durationMs: lengthMs,
      genres: genres,
      mbid: id,
      isrc: isrc,
      releaseDate: releaseDate,
      label: label,
    );
  }

  /// 处理 Dio 错误
  MusicScraperException _handleDioError(DioException e) {
    if (e.response?.statusCode == 401) {
      return MusicScraperAuthException(
        '认证失败',
        source: type,
        cause: e,
      );
    }
    if (e.response?.statusCode == 429) {
      final retryAfter = int.tryParse(
        e.response?.headers.value('retry-after') ?? '',
      );
      return MusicScraperRateLimitException(
        '请求过于频繁，请稍后再试',
        source: type,
        cause: e,
        retryAfter: retryAfter,
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return MusicScraperNetworkException(
        '网络连接失败',
        source: type,
        cause: e,
      );
    }
    return MusicScraperException(
      e.message ?? '未知错误',
      source: type,
      cause: e,
    );
  }
}
