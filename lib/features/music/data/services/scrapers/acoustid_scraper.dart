import 'dart:async';

import 'package:dio/dio.dart';
import 'package:my_nas/features/music/data/services/fingerprint/fingerprint_service.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// AcoustID 刮削器
///
/// 使用 AcoustID API 通过音频指纹识别音乐
/// API 文档: https://acoustid.org/webservice
class AcoustIdScraper implements FingerprintScraper {
  AcoustIdScraper({
    required this.apiKey,
    FingerprintService? fingerprintService,
  }) : _fingerprintService = fingerprintService ?? FingerprintService.getInstance() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'MyNAS/1.0',
      },
    ));
  }

  static const String _baseUrl = 'https://api.acoustid.org/v2';

  final String apiKey;
  final FingerprintService? _fingerprintService;
  late final Dio _dio;

  /// 上次请求时间
  DateTime? _lastRequestTime;

  /// 最小请求间隔（AcoustID 限制每秒 3 次请求）
  static const Duration _minInterval = Duration(milliseconds: 350);

  @override
  MusicScraperType get type => MusicScraperType.acoustId;

  @override
  bool get isConfigured => apiKey.isNotEmpty;

  /// 指纹服务是否可用
  bool get isFingerprintAvailable => _fingerprintService?.isAvailable ?? false;

  @override
  Future<bool> testConnection() async {
    try {
      // 测试 API 连接（使用一个无效的指纹）
      await _rateLimitedRequest(() => _dio.get(
            '/lookup',
            queryParameters: {
              'client': apiKey,
              'fingerprint': 'test',
              'duration': 120,
              'format': 'json',
            },
          ));
      return true;
    } on DioException catch (e) {
      // 如果是 API 错误但连接成功，也算成功
      if (e.response?.statusCode != null) {
        return true;
      }
      return false;
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
    // AcoustID 不支持文本搜索，只支持指纹查询
    // 返回空结果
    return MusicScraperSearchResult.empty(type);
  }

  @override
  Future<MusicScraperDetail?> getDetail(String externalId) async {
    // AcoustID 的 externalId 是 MusicBrainz Recording ID
    // 需要通过 MusicBrainz API 获取详情
    // 这里只返回基本信息
    return null;
  }

  @override
  Future<List<CoverScraperResult>> getCoverArt(String externalId) async {
    // AcoustID 不提供封面
    return [];
  }

  @override
  Future<LyricScraperResult?> getLyrics(String externalId) async {
    // AcoustID 不提供歌词
    return null;
  }

  @override
  Future<FingerprintResult?> lookupByFingerprint(
    String fingerprint,
    int duration,
  ) async {
    try {
      final response = await _rateLimitedRequest(() => _dio.get(
            '/lookup',
            queryParameters: {
              'client': apiKey,
              'fingerprint': fingerprint,
              'duration': duration,
              'format': 'json',
              'meta': 'recordings+releasegroups+compress',
            },
          ));

      final data = response.data as Map<String, dynamic>;
      final status = data['status'] as String?;

      if (status != 'ok') {
        final error = data['error'] as Map<String, dynamic>?;
        throw MusicScraperException(
          error?['message'] as String? ?? '未知错误',
          source: type,
        );
      }

      final results = (data['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      if (results.isEmpty) {
        return FingerprintResult.empty(type);
      }

      final matches = <FingerprintMatch>[];

      for (final result in results) {
        final score = (result['score'] as num?)?.toDouble() ?? 0.0;
        final acoustId = result['id'] as String?;
        final recordings = (result['recordings'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        for (final recording in recordings) {
          final match = _parseRecording(recording, score, acoustId);
          if (match != null) {
            matches.add(match);
          }
        }
      }

      // 按分数排序
      matches.sort((a, b) => b.score.compareTo(a.score));

      return FingerprintResult(
        source: type,
        fingerprint: fingerprint,
        duration: duration,
        matches: matches,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Future<FingerprintResult?> lookupByFile(String filePath) async {
    if (_fingerprintService == null || !_fingerprintService!.isAvailable) {
      throw const FingerprintUnavailableException();
    }

    try {
      final fpData = await _fingerprintService!.generateFingerprint(filePath);
      return lookupByFingerprint(fpData.fingerprint, fpData.duration);
    } on FingerprintException {
      rethrow;
    } on Exception catch (e) {
      throw FingerprintGenerationException('生成指纹失败', cause: e);
    }
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

  /// 解析录音信息
  FingerprintMatch? _parseRecording(
    Map<String, dynamic> data,
    double score,
    String? acoustId,
  ) {
    final id = data['id'] as String?;
    if (id == null) return null;

    final title = data['title'] as String? ?? '';

    // 艺术家
    String? artist;
    final artists = data['artists'] as List?;
    if (artists != null && artists.isNotEmpty) {
      artist = artists.map((a) => a['name'] as String? ?? '').where((n) => n.isNotEmpty).join(' / ');
    }

    // 专辑（从 releasegroups 获取）
    String? album;
    int? year;
    final releaseGroups = data['releasegroups'] as List?;
    if (releaseGroups != null && releaseGroups.isNotEmpty) {
      final firstRelease = releaseGroups.first as Map<String, dynamic>;
      album = firstRelease['title'] as String?;

      // 艺术家（如果录音没有艺术家）
      if (artist == null || artist.isEmpty) {
        final releaseArtists = firstRelease['artists'] as List?;
        if (releaseArtists != null && releaseArtists.isNotEmpty) {
          artist = releaseArtists.map((a) => a['name'] as String? ?? '').where((n) => n.isNotEmpty).join(' / ');
        }
      }
    }

    // 时长
    final durationMs = data['duration'] as int?;

    return FingerprintMatch(
      externalId: id,
      acoustId: acoustId,
      mbRecordingId: id,
      title: title,
      artist: artist,
      album: album,
      year: year,
      durationMs: durationMs != null ? durationMs * 1000 : null,
      score: score,
    );
  }

  /// 处理 Dio 错误
  MusicScraperException _handleDioError(DioException e) {
    // AcoustID API 错误
    if (e.response?.data is Map) {
      final error = (e.response!.data as Map)['error'] as Map<String, dynamic>?;
      final code = error?['code'] as int?;
      final message = error?['message'] as String?;

      if (code == 4) {
        return MusicScraperAuthException(
          'API Key 无效: $message',
          source: type,
          cause: e,
        );
      }
      if (code == 5) {
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
