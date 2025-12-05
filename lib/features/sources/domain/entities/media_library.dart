import 'package:uuid/uuid.dart';

/// 媒体类型
enum MediaType {
  video('视频', 'video'),
  music('音乐', 'music'),
  photo('照片', 'photo'),
  comic('漫画', 'comic'),
  book('书籍', 'book'),
  note('笔记', 'note');

  const MediaType(this.displayName, this.id);
  final String displayName;
  final String id;
}

/// 媒体库目录
class MediaLibraryPath {
  MediaLibraryPath({
    required this.sourceId, required this.path, String? id,
    this.name,
    this.isEnabled = true,
  }) : id = id ?? const Uuid().v4();

  factory MediaLibraryPath.fromJson(Map<String, dynamic> json) =>
      MediaLibraryPath(
        id: json['id'] as String,
        sourceId: json['sourceId'] as String,
        path: json['path'] as String,
        name: json['name'] as String?,
        isEnabled: json['isEnabled'] as bool? ?? true,
      );

  final String id;

  /// 关联的源ID
  final String sourceId;

  /// 目录路径
  final String path;

  /// 自定义名称（可选）
  final String? name;

  /// 是否启用
  final bool isEnabled;

  String get displayName => name ?? path.split('/').last;

  MediaLibraryPath copyWith({
    String? id,
    String? sourceId,
    String? path,
    String? name,
    bool? isEnabled,
  }) =>
      MediaLibraryPath(
        id: id ?? this.id,
        sourceId: sourceId ?? this.sourceId,
        path: path ?? this.path,
        name: name ?? this.name,
        isEnabled: isEnabled ?? this.isEnabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'path': path,
        'name': name,
        'isEnabled': isEnabled,
      };
}

/// 媒体库配置
class MediaLibraryConfig {
  const MediaLibraryConfig({
    this.videoPaths = const [],
    this.musicPaths = const [],
    this.photoPaths = const [],
    this.comicPaths = const [],
    this.bookPaths = const [],
    this.notePaths = const [],
  });

  factory MediaLibraryConfig.fromJson(Map<String, dynamic> json) {
    List<MediaLibraryPath> parsePaths(dynamic data) {
      if (data == null) return [];
      return (data as List<dynamic>)
          .map((e) => MediaLibraryPath.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    return MediaLibraryConfig(
      videoPaths: parsePaths(json['videoPaths']),
      musicPaths: parsePaths(json['musicPaths']),
      photoPaths: parsePaths(json['photoPaths']),
      comicPaths: parsePaths(json['comicPaths']),
      bookPaths: parsePaths(json['bookPaths']),
      notePaths: parsePaths(json['notePaths']),
    );
  }

  final List<MediaLibraryPath> videoPaths;
  final List<MediaLibraryPath> musicPaths;
  final List<MediaLibraryPath> photoPaths;
  final List<MediaLibraryPath> comicPaths;
  final List<MediaLibraryPath> bookPaths;
  final List<MediaLibraryPath> notePaths;

  /// 获取指定类型的路径列表
  List<MediaLibraryPath> getPathsForType(MediaType type) => switch (type) {
      MediaType.video => videoPaths,
      MediaType.music => musicPaths,
      MediaType.photo => photoPaths,
      MediaType.comic => comicPaths,
      MediaType.book => bookPaths,
      MediaType.note => notePaths,
    };

  /// 获取指定类型的启用路径列表
  List<MediaLibraryPath> getEnabledPathsForType(MediaType type) => getPathsForType(type).where((p) => p.isEnabled).toList();

  MediaLibraryConfig copyWith({
    List<MediaLibraryPath>? videoPaths,
    List<MediaLibraryPath>? musicPaths,
    List<MediaLibraryPath>? photoPaths,
    List<MediaLibraryPath>? comicPaths,
    List<MediaLibraryPath>? bookPaths,
    List<MediaLibraryPath>? notePaths,
  }) =>
      MediaLibraryConfig(
        videoPaths: videoPaths ?? this.videoPaths,
        musicPaths: musicPaths ?? this.musicPaths,
        photoPaths: photoPaths ?? this.photoPaths,
        comicPaths: comicPaths ?? this.comicPaths,
        bookPaths: bookPaths ?? this.bookPaths,
        notePaths: notePaths ?? this.notePaths,
      );

  /// 添加路径
  MediaLibraryConfig addPath(MediaType type, MediaLibraryPath path) {
    final paths = List<MediaLibraryPath>.from(getPathsForType(type))..add(path);
    return switch (type) {
      MediaType.video => copyWith(videoPaths: paths),
      MediaType.music => copyWith(musicPaths: paths),
      MediaType.photo => copyWith(photoPaths: paths),
      MediaType.comic => copyWith(comicPaths: paths),
      MediaType.book => copyWith(bookPaths: paths),
      MediaType.note => copyWith(notePaths: paths),
    };
  }

  /// 移除路径
  MediaLibraryConfig removePath(MediaType type, String pathId) {
    final paths = getPathsForType(type).where((p) => p.id != pathId).toList();
    return switch (type) {
      MediaType.video => copyWith(videoPaths: paths),
      MediaType.music => copyWith(musicPaths: paths),
      MediaType.photo => copyWith(photoPaths: paths),
      MediaType.comic => copyWith(comicPaths: paths),
      MediaType.book => copyWith(bookPaths: paths),
      MediaType.note => copyWith(notePaths: paths),
    };
  }

  /// 移除指定源的所有路径
  MediaLibraryConfig removePathsForSource(String sourceId) => MediaLibraryConfig(
      videoPaths: videoPaths.where((p) => p.sourceId != sourceId).toList(),
      musicPaths: musicPaths.where((p) => p.sourceId != sourceId).toList(),
      photoPaths: photoPaths.where((p) => p.sourceId != sourceId).toList(),
      comicPaths: comicPaths.where((p) => p.sourceId != sourceId).toList(),
      bookPaths: bookPaths.where((p) => p.sourceId != sourceId).toList(),
      notePaths: notePaths.where((p) => p.sourceId != sourceId).toList(),
    );

  Map<String, dynamic> toJson() => {
        'videoPaths': videoPaths.map((p) => p.toJson()).toList(),
        'musicPaths': musicPaths.map((p) => p.toJson()).toList(),
        'photoPaths': photoPaths.map((p) => p.toJson()).toList(),
        'comicPaths': comicPaths.map((p) => p.toJson()).toList(),
        'bookPaths': bookPaths.map((p) => p.toJson()).toList(),
        'notePaths': notePaths.map((p) => p.toJson()).toList(),
      };
}
