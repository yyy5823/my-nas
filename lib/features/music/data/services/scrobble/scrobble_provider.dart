/// Scrobble 上报对象
class ScrobbleTrack {
  const ScrobbleTrack({
    required this.title,
    required this.artist,
    this.album,
    this.albumArtist,
    this.durationMs,
    this.trackNumber,
    this.mbid,
  });

  final String title;
  final String artist;
  final String? album;
  final String? albumArtist;
  final int? durationMs;
  final int? trackNumber;

  /// MusicBrainz Track ID（如果元数据里有）
  final String? mbid;

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        if (album != null) 'album': album,
        if (albumArtist != null) 'albumArtist': albumArtist,
        if (durationMs != null) 'durationMs': durationMs,
        if (trackNumber != null) 'trackNumber': trackNumber,
        if (mbid != null) 'mbid': mbid,
      };

  static ScrobbleTrack fromJson(Map<dynamic, dynamic> m) => ScrobbleTrack(
        title: (m['title'] as String?) ?? '',
        artist: (m['artist'] as String?) ?? '',
        album: m['album'] as String?,
        albumArtist: m['albumArtist'] as String?,
        durationMs: (m['durationMs'] as num?)?.toInt(),
        trackNumber: (m['trackNumber'] as num?)?.toInt(),
        mbid: m['mbid'] as String?,
      );
}

/// Scrobble provider 抽象。每家服务（ListenBrainz / Last.fm）实现这个接口。
abstract class ScrobbleProvider {
  String get id;
  String get displayName;

  /// 上报「正在播放」（不计入累计听歌时长，仅显示当前曲目）
  Future<bool> nowPlaying(ScrobbleTrack track);

  /// 上报「已听完」。[playedAt] = 用户开始听这首的 wall-clock 时间。
  Future<bool> scrobble(ScrobbleTrack track, DateTime playedAt);

  /// 是否已完成必要凭证配置
  bool get isConfigured;
}
