import 'dart:async';

import 'package:dio/dio.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// Cover Art Archive 刮削器
///
/// 使用 Cover Art Archive API 获取专辑封面
/// 需要先通过 MusicBrainz 获取 release ID 或 release group ID
/// API 文档: https://musicbrainz.org/doc/Cover_Art_Archive/API
class CoverArtArchiveScraper implements MusicScraper {
  CoverArtArchiveScraper() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'MyNAS/1.0 (https://github.com/my-nas)',
      },
    ));

    _musicBrainzDio = Dio(BaseOptions(
      baseUrl: _musicBrainzBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'MyNAS/1.0 (https://github.com/my-nas)',
      },
    ));
  }

  static const String _baseUrl = 'https://coverartarchive.org';
  static const String _musicBrainzBaseUrl = 'https://musicbrainz.org/ws/2';

  late final Dio _dio;
  late final Dio _musicBrainzDio;

  /// 上次请求时间
  DateTime? _lastRequestTime;

  /// 最小请求间隔 (MusicBrainz 要求 1 秒)
  static const Duration _minInterval = Duration(seconds: 1);

  @override
  MusicScraperType get type => MusicScraperType.coverArtArchive;

  @override
  bool get isConfigured => true; // 无需认证

  @override
  Future<bool> testConnection() async {
    try {
      // 测试 Cover Art Archive API
      await _dio.head<dynamic>('/release/76df3287-6cda-33eb-8e9a-044b5e15ffdd');
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
    // Cover Art Archive 不支持直接搜索
    // 需要先通过 MusicBrainz 搜索获取 release ID
    try {
      final queryParts = <String>[];
      if (album != null && album.isNotEmpty) {
        queryParts.add('release:"$album"');
      } else {
        queryParts.add(query);
      }
      if (artist != null && artist.isNotEmpty) {
        queryParts.add('artist:"$artist"');
      }

      final luceneQuery = queryParts.join(' AND ');
      final offset = (page - 1) * limit;

      final response = await _rateLimitedRequest(() => _musicBrainzDio.get<dynamic>(
            '/release',
            queryParameters: {
              'query': luceneQuery,
              'limit': limit,
              'offset': offset,
              'fmt': 'json',
            },
          ));

      final data = response.data as Map<String, dynamic>;
      final releases = (data['releases'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final count = data['count'] as int? ?? 0;

      final items = releases.map(_parseRelease).toList();

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
    // Cover Art Archive 主要用于封面，不提供详细元数据
    // 返回基本信息
    try {
      final response = await _rateLimitedRequest(() => _musicBrainzDio.get<dynamic>(
            '/release/$externalId',
            queryParameters: {
              'inc': 'artists+recordings',
              'fmt': 'json',
            },
          ));

      final data = response.data as Map<String, dynamic>;
      return _parseReleaseDetail(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw _handleDioError(e);
    }
  }

  @override
  Future<List<CoverScraperResult>> getCoverArt(String externalId) async {
    try {
      final response = await _dio.get<dynamic>('/release/$externalId');

      final data = response.data as Map<String, dynamic>;
      final images = (data['images'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      if (images.isEmpty) return [];

      final results = <CoverScraperResult>[];
      for (final image in images) {
        final imageUrl = image['image'] as String?;
        final thumbnails = image['thumbnails'] as Map<String, dynamic>?;
        final thumbnailUrl = thumbnails?['500'] as String? ??
            thumbnails?['250'] as String? ??
            thumbnails?['small'] as String?;

        // 确定封面类型
        final types = (image['types'] as List?)?.cast<String>() ?? [];
        var coverType = CoverType.other;
        if (types.contains('Front')) {
          coverType = CoverType.front;
        } else if (types.contains('Back')) {
          coverType = CoverType.back;
        } else if (types.contains('Booklet')) {
          coverType = CoverType.booklet;
        } else if (types.contains('Medium')) {
          coverType = CoverType.medium;
        }

        if (imageUrl != null) {
          results.add(CoverScraperResult(
            source: type,
            coverUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            type: coverType,
          ));
        }
      }

      return results;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return [];
      }
      throw _handleDioError(e);
    }
  }

  /// Cover Art Archive 不提供歌词
  @override
  Future<LyricScraperResult?> getLyrics(String externalId) async => null;

  @override
  void dispose() {
    _dio.close();
    _musicBrainzDio.close();
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

  /// 解析 Release 搜索结果
  MusicScraperItem _parseRelease(Map<String, dynamic> data) {
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

    // 年份
    int? year;
    final date = data['date'] as String?;
    if (date != null && date.length >= 4) {
      year = int.tryParse(date.substring(0, 4));
    }

    // 匹配分数
    final score = data['score'] as int?;

    return MusicScraperItem(
      externalId: id,
      source: type,
      title: title,
      artist: artist,
      album: title, // Release title 通常是专辑名
      year: year,
      score: score != null ? score / 100 : null,
    );
  }

  /// 解析 Release 详情
  MusicScraperDetail _parseReleaseDetail(Map<String, dynamic> data) {
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

    // 年份
    int? year;
    final date = data['date'] as String?;
    if (date != null && date.length >= 4) {
      year = int.tryParse(date.substring(0, 4));
    }

    return MusicScraperDetail(
      externalId: id,
      source: type,
      title: title,
      artist: artist,
      album: title,
      year: year,
      releaseDate: date,
    );
  }

  /// 处理 Dio 错误
  MusicScraperException _handleDioError(DioException e) {
    if (e.response?.statusCode == 503) {
      return MusicScraperRateLimitException(
        '服务暂时不可用，请稍后再试',
        source: type,
        cause: e,
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
