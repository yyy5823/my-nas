import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 视频项目
class VideoItem {
  const VideoItem({
    required this.name,
    required this.path,
    required this.url,
    this.sourceId,
    this.size = 0,
    this.duration,
    this.thumbnailUrl,
    this.lastPosition,
    this.subtitles = const [],
  });

  factory VideoItem.fromFileItem(FileItem file, String url, {String? sourceId}) => VideoItem(
        name: file.name,
        path: file.path,
        url: url,
        sourceId: sourceId,
        size: file.size,
        thumbnailUrl: file.thumbnailUrl,
      );

  final String name;
  final String path;
  final String url;
  final String? sourceId;
  final int size;
  final Duration? duration;
  final String? thumbnailUrl;
  final Duration? lastPosition;
  final List<VideoSubtitle> subtitles;

  /// 检查是否需要代理（SMB 等不支持直接 URL 访问的协议）
  bool get needsProxy => url.startsWith('smb://');

  VideoItem copyWith({
    String? name,
    String? path,
    String? url,
    String? sourceId,
    int? size,
    Duration? duration,
    String? thumbnailUrl,
    Duration? lastPosition,
    List<VideoSubtitle>? subtitles,
  }) =>
      VideoItem(
        name: name ?? this.name,
        path: path ?? this.path,
        url: url ?? this.url,
        sourceId: sourceId ?? this.sourceId,
        size: size ?? this.size,
        duration: duration ?? this.duration,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        lastPosition: lastPosition ?? this.lastPosition,
        subtitles: subtitles ?? this.subtitles,
      );
}

/// 字幕轨道
class VideoSubtitle {
  const VideoSubtitle({
    required this.id,
    required this.title,
    required this.url,
    this.language,
    this.isExternal = true,
  });

  final String id;
  final String title;
  final String url;
  final String? language;
  final bool isExternal;
}

/// 音频轨道
class VideoAudioTrack {
  const VideoAudioTrack({
    required this.id,
    required this.title,
    this.language,
  });

  final String id;
  final String title;
  final String? language;
}
