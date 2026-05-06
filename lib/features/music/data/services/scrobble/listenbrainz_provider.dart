import 'package:dio/dio.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/scrobble/scrobble_provider.dart';

/// ListenBrainz scrobble provider —— token 认证，POST /1/submit-listens。
/// 文档：https://listenbrainz.readthedocs.io/en/production/dev/api/
class ListenBrainzProvider implements ScrobbleProvider {
  ListenBrainzProvider({this.userToken, this.endpoint = 'https://api.listenbrainz.org'});

  /// 用户在 listenbrainz.org → Settings → Profile 拿到的 user token
  String? userToken;
  String endpoint;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    sendTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  @override
  String get id => 'listenbrainz';

  @override
  String get displayName => 'ListenBrainz';

  @override
  bool get isConfigured => userToken != null && userToken!.isNotEmpty;

  @override
  Future<bool> nowPlaying(ScrobbleTrack track) =>
      _submit(track, type: 'playing_now');

  @override
  Future<bool> scrobble(ScrobbleTrack track, DateTime playedAt) =>
      _submit(track, type: 'single', playedAt: playedAt);

  Future<bool> _submit(
    ScrobbleTrack track, {
    required String type,
    DateTime? playedAt,
  }) async {
    if (!isConfigured) return false;
    final additional = <String, dynamic>{
      if (track.mbid != null) 'recording_mbid': track.mbid,
      if (track.trackNumber != null) 'tracknumber': track.trackNumber,
      if (track.durationMs != null)
        'duration_ms': track.durationMs,
    };
    final payload = <String, dynamic>{
      'listen_type': type,
      'payload': [
        {
          if (type == 'single' && playedAt != null)
            'listened_at': playedAt.millisecondsSinceEpoch ~/ 1000,
          'track_metadata': {
            'track_name': track.title,
            'artist_name': track.artist,
            if (track.album != null) 'release_name': track.album,
            if (additional.isNotEmpty) 'additional_info': additional,
          },
        }
      ],
    };
    try {
      final resp = await _dio.post<dynamic>(
        '$endpoint/1/submit-listens',
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'Token $userToken',
            'Content-Type': 'application/json',
          },
        ),
      );
      return resp.statusCode == 200;
    } on DioException catch (e) {
      logger.w('ListenBrainz: $type 失败 ${e.response?.statusCode} ${e.message}');
      return false;
    } on Exception catch (e) {
      logger.w('ListenBrainz: $type 失败 $e');
      return false;
    }
  }
}
