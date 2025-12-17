import 'dart:async';

import 'package:dio/dio.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// Genius 刮削器
///
/// 使用 Genius API 获取元数据和歌词
/// API 文档: https://docs.genius.com/
class GeniusScraper implements MusicScraper {
  GeniusScraper({
    required this.accessToken,
  }) {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'MyNAS/1.0',
        'Authorization': 'Bearer $accessToken',
      },
    ));

    _webDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    ));
  }

  static const String _baseUrl = 'https://api.genius.com';

  final String accessToken;
  late final Dio _dio;
  late final Dio _webDio;

  /// 上次请求时间
  DateTime? _lastRequestTime;

  /// 最小请求间隔
  static const Duration _minInterval = Duration(milliseconds: 200);

  @override
  MusicScraperType get type => MusicScraperType.genius;

  @override
  bool get isConfigured => accessToken.isNotEmpty;

  @override
  Future<bool> testConnection() async {
    try {
      await _rateLimitedRequest(() => _dio.get('/account'));
      return true;
    } on DioException catch (e) {
      // 401 表示 token 无效，其他错误可能是网络问题
      return e.response?.statusCode != 401;
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
            '/search',
            queryParameters: {
              'q': searchQuery,
              'per_page': limit,
              'page': page,
            },
          ));

      final data = response.data as Map<String, dynamic>;
      final responseData = data['response'] as Map<String, dynamic>?;
      if (responseData == null) {
        return MusicScraperSearchResult.empty(type);
      }

      final hits = (responseData['hits'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      final items = hits
          .where((h) => h['type'] == 'song')
          .map((h) => _parseSong(h['result'] as Map<String, dynamic>))
          .toList();

      // Genius API 不返回总数，估算
      return MusicScraperSearchResult(
        items: items,
        source: type,
        page: page,
        totalPages: items.length < limit ? page : page + 1,
        totalResults: items.length,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Future<MusicScraperDetail?> getDetail(String externalId) async {
    try {
      final response = await _rateLimitedRequest(() => _dio.get(
            '/songs/$externalId',
          ));

      final data = response.data as Map<String, dynamic>;
      final responseData = data['response'] as Map<String, dynamic>?;
      final song = responseData?['song'] as Map<String, dynamic>?;

      if (song == null) return null;

      return _parseSongDetail(song);
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
      final detail = await getDetail(externalId);
      if (detail?.coverUrl == null) {
        return [];
      }

      return [
        CoverScraperResult(
          source: type,
          coverUrl: detail!.coverUrl!,
          type: CoverType.front,
        ),
      ];
    } on Exception {
      return [];
    }
  }

  @override
  Future<LyricScraperResult?> getLyrics(String externalId) async {
    try {
      // 首先获取歌曲详情以获取歌词页面 URL
      final response = await _rateLimitedRequest(() => _dio.get(
            '/songs/$externalId',
          ));

      final data = response.data as Map<String, dynamic>;
      final responseData = data['response'] as Map<String, dynamic>?;
      final song = responseData?['song'] as Map<String, dynamic>?;

      if (song == null) return null;

      final lyricsUrl = song['url'] as String?;
      if (lyricsUrl == null) return null;

      // 从网页抓取歌词
      final lyrics = await _fetchLyricsFromPage(lyricsUrl);
      if (lyrics == null || lyrics.isEmpty) return null;

      return LyricScraperResult(
        source: type,
        plainText: lyrics,
        sourceUrl: lyricsUrl,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// 从 Genius 网页抓取歌词
  Future<String?> _fetchLyricsFromPage(String url) async {
    try {
      final response = await _webDio.get(url);
      final html = response.data.toString();

      // 尝试多种方式提取歌词
      // 方式1: 从 data-lyrics-container 属性提取
      var lyricsMatch = RegExp(r'<div[^>]*data-lyrics-container="true"[^>]*>(.*?)</div>')
          .allMatches(html);

      if (lyricsMatch.isEmpty) {
        // 方式2: 从 Lyrics__Container 类提取
        lyricsMatch = RegExp(r'<div[^>]*class="[^"]*Lyrics__Container[^"]*"[^>]*>(.*?)</div>')
            .allMatches(html);
      }

      if (lyricsMatch.isEmpty) return null;

      // 合并所有歌词片段
      final lyricsHtml = lyricsMatch.map((m) => m.group(1) ?? '').join('\n');

      // 清理 HTML 标签，保留换行
      var lyrics = lyricsHtml
          .replaceAll(RegExp(r'<br\s*/?>'), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#x27;', "'")
          .replaceAll('&nbsp;', ' ')
          .trim();

      // 清理多余的空行
      lyrics = lyrics.split('\n').map((l) => l.trim()).join('\n');
      lyrics = lyrics.replaceAll(RegExp(r'\n{3,}'), '\n\n');

      return lyrics.isEmpty ? null : lyrics;
    } on Exception {
      return null;
    }
  }

  @override
  void dispose() {
    _dio.close();
    _webDio.close();
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

  /// 解析歌曲搜索结果
  MusicScraperItem _parseSong(Map<String, dynamic> data) {
    final id = data['id'].toString();
    final title = data['title'] as String? ?? '';

    // 艺术家
    final primaryArtist = data['primary_artist'] as Map<String, dynamic>?;
    final artist = primaryArtist?['name'] as String?;

    // 封面
    final coverUrl = data['song_art_image_url'] as String? ??
        data['song_art_image_thumbnail_url'] as String? ??
        data['header_image_url'] as String?;

    return MusicScraperItem(
      externalId: id,
      source: type,
      title: title,
      artist: artist,
      coverUrl: coverUrl,
    );
  }

  /// 解析歌曲详情
  MusicScraperDetail _parseSongDetail(Map<String, dynamic> data) {
    final id = data['id'].toString();
    final title = data['title'] as String? ?? '';

    // 艺术家
    final primaryArtist = data['primary_artist'] as Map<String, dynamic>?;
    final artist = primaryArtist?['name'] as String?;

    // 专辑
    final albumData = data['album'] as Map<String, dynamic>?;
    final album = albumData?['name'] as String?;
    String? albumArtist;
    final albumArtistData = albumData?['artist'] as Map<String, dynamic>?;
    if (albumArtistData != null) {
      albumArtist = albumArtistData['name'] as String?;
    }

    // 封面
    final coverUrl = data['song_art_image_url'] as String? ??
        albumData?['cover_art_url'] as String? ??
        data['header_image_url'] as String?;

    // 发行日期
    final releaseDate = data['release_date'] as String?;
    int? year;
    if (releaseDate != null && releaseDate.length >= 4) {
      year = int.tryParse(releaseDate.substring(0, 4));
    }

    return MusicScraperDetail(
      externalId: id,
      source: type,
      title: title,
      artist: artist,
      albumArtist: albumArtist,
      album: album,
      year: year,
      coverUrl: coverUrl,
      releaseDate: releaseDate,
    );
  }

  /// 处理 Dio 错误
  MusicScraperException _handleDioError(DioException e) {
    if (e.response?.statusCode == 401) {
      return MusicScraperAuthException(
        'Access Token 无效或已过期',
        source: type,
        cause: e,
      );
    }
    if (e.response?.statusCode == 403) {
      return MusicScraperAuthException(
        'Access Token 权限不足',
        source: type,
        cause: e,
      );
    }
    if (e.response?.statusCode == 429) {
      return MusicScraperRateLimitException(
        '请求过于频繁，请稍后再试',
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
