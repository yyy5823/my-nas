import 'dart:async';

import 'package:dio/dio.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// Last.fm 刮削器
///
/// 使用 Last.fm API 获取元数据和封面
/// API 文档: https://www.last.fm/api
class LastFmScraper implements MusicScraper {
  LastFmScraper({
    required this.apiKey,
  }) {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'MyNAS/1.0',
      },
    ));
  }

  static const String _baseUrl = 'https://ws.audioscrobbler.com/2.0/';

  final String apiKey;
  late final Dio _dio;

  /// 上次请求时间
  DateTime? _lastRequestTime;

  /// 最小请求间隔
  static const Duration _minInterval = Duration(milliseconds: 200);

  @override
  MusicScraperType get type => MusicScraperType.lastFm;

  @override
  bool get isConfigured => apiKey.isNotEmpty;

  @override
  Future<bool> testConnection() async {
    try {
      await _rateLimitedRequest(() => _dio.get(
            '',
            queryParameters: {
              'method': 'chart.gettopartists',
              'api_key': apiKey,
              'format': 'json',
              'limit': 1,
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
      // 构建搜索关键词
      var searchQuery = query;
      if (artist != null && artist.isNotEmpty) {
        searchQuery = '$artist $searchQuery';
      }

      final response = await _rateLimitedRequest(() => _dio.get(
            '',
            queryParameters: {
              'method': 'track.search',
              'track': searchQuery,
              'api_key': apiKey,
              'format': 'json',
              'page': page,
              'limit': limit,
            },
          ));

      final data = response.data as Map<String, dynamic>;
      final results = data['results'] as Map<String, dynamic>?;
      if (results == null) {
        return MusicScraperSearchResult.empty(type);
      }

      final trackMatches = results['trackmatches'] as Map<String, dynamic>?;
      final tracks = (trackMatches?['track'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      // 解析总数
      final totalResults = int.tryParse(
            results['opensearch:totalResults']?.toString() ?? '0',
          ) ??
          0;

      final items = tracks.map((t) => _parseTrack(t)).toList();

      return MusicScraperSearchResult(
        items: items,
        source: type,
        page: page,
        totalPages: (totalResults / limit).ceil(),
        totalResults: totalResults,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Future<MusicScraperDetail?> getDetail(String externalId) async {
    try {
      // externalId 格式: artist|track
      final parts = externalId.split('|');
      if (parts.length != 2) return null;

      final artistName = parts[0];
      final trackName = parts[1];

      final response = await _rateLimitedRequest(() => _dio.get(
            '',
            queryParameters: {
              'method': 'track.getInfo',
              'artist': artistName,
              'track': trackName,
              'api_key': apiKey,
              'format': 'json',
            },
          ));

      final data = response.data as Map<String, dynamic>;
      final track = data['track'] as Map<String, dynamic>?;

      if (track == null) return null;

      return _parseTrackDetail(track);
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
      // externalId 格式: artist|track
      final parts = externalId.split('|');
      if (parts.length != 2) return [];

      final artistName = parts[0];
      final trackName = parts[1];

      // 获取曲目信息以获取专辑
      final response = await _rateLimitedRequest(() => _dio.get(
            '',
            queryParameters: {
              'method': 'track.getInfo',
              'artist': artistName,
              'track': trackName,
              'api_key': apiKey,
              'format': 'json',
            },
          ));

      final data = response.data as Map<String, dynamic>;
      final track = data['track'] as Map<String, dynamic>?;

      if (track == null) return [];

      // 从专辑获取封面
      final album = track['album'] as Map<String, dynamic>?;
      if (album == null) return [];

      final images = album['image'] as List?;
      if (images == null || images.isEmpty) return [];

      // 选择最大的图片
      String? coverUrl;
      for (final image in images.reversed) {
        final url = image['#text'] as String?;
        if (url != null && url.isNotEmpty) {
          coverUrl = url;
          break;
        }
      }

      if (coverUrl == null) return [];

      return [
        CoverScraperResult(
          source: type,
          coverUrl: coverUrl,
          type: CoverType.front,
        ),
      ];
    } on Exception {
      return [];
    }
  }

  @override
  Future<LyricScraperResult?> getLyrics(String externalId) async {
    // Last.fm 不提供歌词
    return null;
  }

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

  /// 解析曲目搜索结果
  MusicScraperItem _parseTrack(Map<String, dynamic> data) {
    final name = data['name'] as String? ?? '';
    final artist = data['artist'] as String? ?? '';

    // 获取图片
    String? coverUrl;
    final images = data['image'] as List?;
    if (images != null && images.isNotEmpty) {
      for (final image in images.reversed) {
        final url = image['#text'] as String?;
        if (url != null && url.isNotEmpty) {
          coverUrl = url;
          break;
        }
      }
    }

    // 获取 listeners 作为评分参考
    final listeners = int.tryParse(data['listeners']?.toString() ?? '0') ?? 0;
    final score = listeners > 0 ? (listeners / 1000000).clamp(0.0, 1.0) : null;

    return MusicScraperItem(
      externalId: '$artist|$name',
      source: type,
      title: name,
      artist: artist.isEmpty ? null : artist,
      coverUrl: coverUrl,
      score: score,
    );
  }

  /// 解析曲目详情
  MusicScraperDetail _parseTrackDetail(Map<String, dynamic> data) {
    final name = data['name'] as String? ?? '';

    // 艺术家
    String? artist;
    final artistData = data['artist'];
    if (artistData is Map<String, dynamic>) {
      artist = artistData['name'] as String?;
    } else if (artistData is String) {
      artist = artistData;
    }

    // 专辑
    String? album;
    String? coverUrl;
    final albumData = data['album'] as Map<String, dynamic>?;
    if (albumData != null) {
      album = albumData['title'] as String?;
      final images = albumData['image'] as List?;
      if (images != null && images.isNotEmpty) {
        for (final image in images.reversed) {
          final url = image['#text'] as String?;
          if (url != null && url.isNotEmpty) {
            coverUrl = url;
            break;
          }
        }
      }
    }

    // 时长
    final durationMs = int.tryParse(data['duration']?.toString() ?? '0');

    // 标签/流派
    final tags = <String>[];
    final toptags = data['toptags'] as Map<String, dynamic>?;
    final tagList = toptags?['tag'] as List?;
    if (tagList != null) {
      for (final tag in tagList) {
        if (tag is Map<String, dynamic>) {
          final tagName = tag['name'] as String?;
          if (tagName != null && tagName.isNotEmpty) {
            tags.add(tagName);
          }
        }
      }
    }

    return MusicScraperDetail(
      externalId: '$artist|$name',
      source: type,
      title: name,
      artist: artist,
      album: album,
      durationMs: durationMs != 0 ? durationMs : null,
      coverUrl: coverUrl,
      genres: tags.isNotEmpty ? tags : null,
    );
  }

  /// 处理 Dio 错误
  MusicScraperException _handleDioError(DioException e) {
    // Last.fm API 错误
    if (e.response?.data is Map) {
      final error = (e.response!.data as Map)['error'];
      final message = (e.response!.data as Map)['message'];
      if (error == 10 || error == 26) {
        return MusicScraperAuthException(
          'API Key 无效: $message',
          source: type,
          cause: e,
        );
      }
      if (error == 29) {
        return MusicScraperRateLimitException(
          '请求过于频繁，请稍后再试',
          source: type,
          cause: e,
        );
      }
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
