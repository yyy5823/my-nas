import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 音乐项实体
class MusicItem {
  const MusicItem({
    required this.id,
    required this.name,
    required this.path,
    required this.url,
    this.artist,
    this.album,
    this.duration,
    this.coverUrl,
    this.size,
    this.lastPosition = Duration.zero,
  });

  final String id;
  final String name;
  final String path;
  final String url;
  final String? artist;
  final String? album;
  final Duration? duration;
  final String? coverUrl;
  final int? size;
  final Duration lastPosition;

  /// 从文件项创建音乐项
  factory MusicItem.fromFileItem(FileItem file, String url) => MusicItem(
        id: file.path,
        name: file.name,
        path: file.path,
        url: url,
        size: file.size,
      );

  /// 显示的艺术家名称
  String get displayArtist => artist ?? '未知艺术家';

  /// 显示的专辑名称
  String get displayAlbum => album ?? '未知专辑';

  /// 格式化时长
  String get durationText {
    if (duration == null) return '--:--';
    final minutes = duration!.inMinutes;
    final seconds = duration!.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  MusicItem copyWith({
    String? id,
    String? name,
    String? path,
    String? url,
    String? artist,
    String? album,
    Duration? duration,
    String? coverUrl,
    int? size,
    Duration? lastPosition,
  }) =>
      MusicItem(
        id: id ?? this.id,
        name: name ?? this.name,
        path: path ?? this.path,
        url: url ?? this.url,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        duration: duration ?? this.duration,
        coverUrl: coverUrl ?? this.coverUrl,
        size: size ?? this.size,
        lastPosition: lastPosition ?? this.lastPosition,
      );
}

/// 播放列表
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.tracks,
    this.coverUrl,
  });

  final String id;
  final String name;
  final List<MusicItem> tracks;
  final String? coverUrl;

  int get trackCount => tracks.length;

  Duration get totalDuration => tracks.fold(
        Duration.zero,
        (total, track) => total + (track.duration ?? Duration.zero),
      );
}
