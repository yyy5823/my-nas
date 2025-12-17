import 'dart:async';
import 'dart:convert';
import 'dart:math';

// ignore: unused_import
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// 网易云音乐刮削器
///
/// 使用网易云音乐 API 获取元数据、封面和歌词
class NeteaseScraper implements MusicScraper {
  NeteaseScraper({
    this.cookie,
  }) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://music.163.com/',
        'Origin': 'https://music.163.com',
        if (cookie != null && cookie!.isNotEmpty) 'Cookie': cookie,
      },
      contentType: 'application/x-www-form-urlencoded',
    ));
  }

  static const String _baseUrl = 'https://music.163.com';

  final String? cookie;
  late final Dio _dio;

  /// 上次请求时间
  DateTime? _lastRequestTime;

  /// 最小请求间隔
  static const Duration _minInterval = Duration(milliseconds: 500);

  @override
  MusicScraperType get type => MusicScraperType.neteaseMusic;

  @override
  bool get isConfigured => true; // Cookie 可选

  @override
  Future<bool> testConnection() async {
    try {
      final _ = await search('test', limit: 1);
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
        searchQuery += ' $artist';
      }
      if (album != null && album.isNotEmpty) {
        searchQuery += ' $album';
      }

      final offset = (page - 1) * limit;

      final params = {
        's': searchQuery,
        'type': 1, // 1: 单曲
        'limit': limit,
        'offset': offset,
      };

      final response = await _rateLimitedRequest(() => _dio.post(
            '$_baseUrl/weapi/cloudsearch/get/web',
            data: _encryptParams(params),
          ));

      final data = response.data as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>?;
      if (result == null) {
        return MusicScraperSearchResult.empty(type);
      }

      final songs = (result['songs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final songCount = result['songCount'] as int? ?? 0;

      final items = songs.map((s) => _parseSong(s)).toList();

      return MusicScraperSearchResult(
        items: items,
        source: type,
        page: page,
        totalPages: (songCount / limit).ceil(),
        totalResults: songCount,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Future<MusicScraperDetail?> getDetail(String externalId) async {
    try {
      final params = {
        'c': '[{"id":$externalId}]',
      };

      final response = await _rateLimitedRequest(() => _dio.post(
            '$_baseUrl/weapi/v3/song/detail',
            data: _encryptParams(params),
          ));

      final data = response.data as Map<String, dynamic>;
      final songs = (data['songs'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      if (songs.isEmpty) {
        return null;
      }

      return _parseSongDetail(songs.first);
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
          thumbnailUrl: '${detail.coverUrl}?param=300y300',
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
      final params = {
        'id': externalId,
        'lv': -1,
        'tv': -1,
        'kv': -1,
      };

      final response = await _rateLimitedRequest(() => _dio.post(
            '$_baseUrl/weapi/song/lyric',
            data: _encryptParams(params),
          ));

      final data = response.data as Map<String, dynamic>;

      // 原文歌词
      final lrc = data['lrc'] as Map<String, dynamic>?;
      final lrcContent = lrc?['lyric'] as String?;

      // 翻译歌词
      final tlyric = data['tlyric'] as Map<String, dynamic>?;
      final translation = tlyric?['lyric'] as String?;

      if (lrcContent == null || lrcContent.isEmpty) {
        return null;
      }

      return LyricScraperResult(
        source: type,
        lrcContent: lrcContent,
        translation: translation,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
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

  /// 解析歌曲搜索结果
  MusicScraperItem _parseSong(Map<String, dynamic> data) {
    final id = data['id'].toString();
    final name = data['name'] as String? ?? '';

    // 艺术家
    final artists = data['ar'] as List? ?? data['artists'] as List? ?? [];
    final artist = artists
        .map((a) => a['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(' / ');

    // 专辑
    final album = data['al'] as Map<String, dynamic>? ??
        data['album'] as Map<String, dynamic>?;
    final albumName = album?['name'] as String?;
    final coverUrl = album?['picUrl'] as String?;

    // 时长
    final duration = data['dt'] as int? ?? data['duration'] as int?;

    return MusicScraperItem(
      externalId: id,
      source: type,
      title: name,
      artist: artist.isEmpty ? null : artist,
      album: albumName,
      durationMs: duration,
      coverUrl: coverUrl,
    );
  }

  /// 解析歌曲详情
  MusicScraperDetail _parseSongDetail(Map<String, dynamic> data) {
    final id = data['id'].toString();
    final name = data['name'] as String? ?? '';

    // 艺术家
    final artists = data['ar'] as List? ?? data['artists'] as List? ?? [];
    final artist = artists
        .map((a) => a['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(' / ');

    // 专辑信息
    final album = data['al'] as Map<String, dynamic>? ??
        data['album'] as Map<String, dynamic>?;
    final albumName = album?['name'] as String?;
    final coverUrl = album?['picUrl'] as String?;

    // 时长
    final duration = data['dt'] as int? ?? data['duration'] as int?;

    // 音轨号
    final trackNumber = data['no'] as int?;

    // 碟号
    final discNumber = data['cd'] != null ? int.tryParse(data['cd'].toString()) : null;

    return MusicScraperDetail(
      externalId: id,
      source: type,
      title: name,
      artist: artist.isEmpty ? null : artist,
      album: albumName,
      durationMs: duration,
      coverUrl: coverUrl,
      trackNumber: trackNumber,
      discNumber: discNumber,
    );
  }

  /// 处理 Dio 错误
  MusicScraperException _handleDioError(DioException e) {
    if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
      return MusicScraperAuthException(
        'Cookie 无效或已过期',
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

  // ===== 网易云 API 加密 =====

  static const String _secretKey = '0CoJUm6Qyw8W8jud';
  static const String _iv = '0102030405060708';
  static const String _pubKey =
      '010001';
  static const String _modulus =
      '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';

  /// 加密请求参数
  String _encryptParams(Map<String, dynamic> params) {
    final text = json.encode(params);

    // 生成随机 16 位字符串
    final secKey = _createSecretKey(16);

    // 两次 AES 加密
    final encText = _aesEncrypt(_aesEncrypt(text, _secretKey), secKey);

    // RSA 加密 secKey
    final encSecKey = _rsaEncrypt(secKey.split('').reversed.join(), _pubKey, _modulus);

    return 'params=${Uri.encodeComponent(encText)}&encSecKey=$encSecKey';
  }

  /// AES 加密
  String _aesEncrypt(String text, String secKey) {
    final key = encrypt.Key.fromUtf8(secKey);
    final iv = encrypt.IV.fromUtf8(_iv);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    return encrypter.encrypt(text, iv: iv).base64;
  }

  /// RSA 加密（简化实现）
  String _rsaEncrypt(String text, String pubKey, String modulus) {
    final textBytes = utf8.encode(text);
    final textHex = textBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // 使用 BigInt 进行模幂运算
    final base = BigInt.parse(textHex, radix: 16);
    final exp = BigInt.parse(pubKey, radix: 16);
    final mod = BigInt.parse(modulus, radix: 16);

    final result = base.modPow(exp, mod);
    return result.toRadixString(16).padLeft(256, '0');
  }

  /// 生成随机字符串
  String _createSecretKey(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
