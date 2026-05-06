import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:path/path.dart' as p;

/// 一组重复歌曲（同 title + artist + duration±2s 桶）
class DuplicateGroup {
  const DuplicateGroup({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationMs,
    required this.tracks,
  });

  final String id;
  final String title;
  final String artist;
  final int durationMs;

  /// 按质量评分降序：第一项 = 推荐保留
  final List<MusicTrackEntity> tracks;

  MusicTrackEntity get best => tracks.first;

  List<MusicTrackEntity> get redundant =>
      tracks.length > 1 ? tracks.sublist(1) : const [];

  int get count => tracks.length;
}

/// 检测 library 内同首歌的多个版本（NAS 上同时存放 mp3 + flac，或不同目录里的相同文件）。
/// 按 (normalize(title), normalize(artist), duration±2s 桶) 分组，每组超过 1 首即视为重复。
class DuplicateDetector {
  DuplicateDetector._();

  /// duration ±2s 容差：同一首歌不同 encoder 转出来 duration 可能差几百毫秒
  static const int _durationBucketSec = 2;

  /// 在指定 tracks 列表里检测重复分组。
  static List<DuplicateGroup> detect(List<MusicTrackEntity> tracks) {
    final groups = <String, List<MusicTrackEntity>>{};
    for (final t in tracks) {
      final title = _normalize(t.displayTitle);
      final artist = _normalize(t.displayArtist);
      if (title.isEmpty) continue;
      final durSec = (t.duration ?? 0) ~/ 1000;
      final bucket = durSec ~/ _durationBucketSec;
      final key = '$title|$artist|$bucket';
      groups.putIfAbsent(key, () => []).add(t);
    }

    return groups.entries
        .where((e) => e.value.length > 1)
        .map((e) {
          final sorted = [...e.value]
            ..sort((a, b) => qualityScore(b).compareTo(qualityScore(a)));
          final disp = sorted.first;
          return DuplicateGroup(
            id: e.key,
            title: disp.displayTitle,
            artist: disp.displayArtist,
            durationMs: disp.duration ?? 0,
            tracks: sorted,
          );
        })
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  /// 质量评分：高 = 推荐保留。
  ///
  /// MusicTrackEntity 没有 bitDepth/sampleRate/bitRate 元数据，所以维度简化为：
  /// 1. lossless > lossy（无损 +10000）
  /// 2. fileSize（MB）作为 tiebreaker
  static int qualityScore(MusicTrackEntity track) {
    var score = 0;
    if (_isLossless(track.fileName)) score += 10000;
    final sizeMB = (track.size ?? 0) ~/ (1024 * 1024);
    score += sizeMB;
    return score;
  }

  static bool _isLossless(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    const lossless = {
      '.flac',
      '.alac',
      '.wav',
      '.aiff',
      '.aif',
      '.ape',
      '.wv',
      '.dsf',
      '.dff',
    };
    return lossless.contains(ext);
  }

  /// 标题 / 艺术家 normalize：trim + 大小写不敏感。保留内部空白和标点
  /// （太激进会把「Hello (Live)」与「Hello」误归到同组）。
  static String _normalize(String s) =>
      s.trim().toLowerCase();
}
