import 'dart:typed_data';

/// 音乐元数据写入服务接口
///
/// 设计说明：
/// - 统一接口，隐藏不同格式的差异
/// - 主方案使用 audiotags（基于 Rust lofty-rs）
/// - 备选方案使用 FFmpegKit（支持 DSD/WMA 等）
/// - 封面数据使用 Uint8List（JPEG/PNG）
///
/// 格式支持情况（audiotags）：
/// | 格式 | 元数据标准 | 读取 | 写入 | 封面 |
/// |------|----------|:----:|:----:|:----:|
/// | MP3  | ID3v2/v1 | ✓    | ✓    | ✓    |
/// | FLAC | Vorbis   | ✓    | ✓    | ✓    |
/// | M4A  | iTunes   | ✓    | ✓    | ✓    |
/// | OGG  | Vorbis   | ✓    | ✓    | ✓    |
/// | Opus | Vorbis   | ✓    | ✓    | ✓    |
/// | WAV  | ID3v2    | ✓    | ✓    | ✓    |
/// | AIFF | ID3v2    | ✓    | ✓    | ✓    |
/// | APE  | APEv2    | ✓    | ✓    | ✓    |
/// | MPC  | APE      | ✓    | ✓    | ✓    |
/// | WavPack| APE    | ✓    | ✓    | ✓    |
/// | Speex| Vorbis   | ✓    | ✓    | ✓    |
///
/// 需要 FFmpegKit 的格式：
/// | 格式 | 元数据标准 |
/// |------|----------|
/// | DSF  | ID3v2    |
/// | DFF  | 无标准    |
/// | WMA  | ASF      |
abstract class MusicMetadataWriter {
  /// 写入元数据到文件
  ///
  /// [filePath] 目标文件路径（本地文件）
  /// [metadata] 要写入的元数据
  ///
  /// 返回是否成功
  Future<bool> writeMetadata(String filePath, WritableMetadata metadata);

  /// 仅写入封面图片
  ///
  /// [filePath] 目标文件路径
  /// [coverData] 封面图片数据（JPEG 或 PNG）
  /// [mimeType] 图片 MIME 类型，默认 'image/jpeg'
  Future<bool> writeCover(
    String filePath,
    Uint8List coverData, {
    String mimeType = 'image/jpeg',
  });

  /// 移除所有元数据
  Future<bool> removeAllMetadata(String filePath);

  /// 检查格式是否支持写入
  bool isFormatSupported(String extension);

  /// 获取支持的格式列表
  List<String> get supportedFormats;
}

/// 可写入的元数据
class WritableMetadata {
  const WritableMetadata({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.year,
    this.trackNumber,
    this.totalTracks,
    this.discNumber,
    this.totalDiscs,
    this.genre,
    this.comment,
    this.lyrics,
    this.composer,
    this.coverData,
    this.coverMimeType = 'image/jpeg',
  });

  /// 从 Map 创建（便于 JSON 反序列化）
  factory WritableMetadata.fromMap(Map<String, dynamic> map) => WritableMetadata(
        title: map['title'] as String?,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        albumArtist: map['albumArtist'] as String?,
        year: map['year'] as int?,
        trackNumber: map['trackNumber'] as int?,
        totalTracks: map['totalTracks'] as int?,
        discNumber: map['discNumber'] as int?,
        totalDiscs: map['totalDiscs'] as int?,
        genre: map['genre'] as String?,
        comment: map['comment'] as String?,
        lyrics: map['lyrics'] as String?,
        composer: map['composer'] as String?,
        coverData: map['coverData'] as Uint8List?,
        coverMimeType: map['coverMimeType'] as String? ?? 'image/jpeg',
      );

  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist; // 专辑艺术家（合辑时与曲目艺术家不同）
  final int? year;
  final int? trackNumber;
  final int? totalTracks;
  final int? discNumber;
  final int? totalDiscs;
  final String? genre;
  final String? comment;
  final String? lyrics;
  final String? composer;
  final Uint8List? coverData;
  final String coverMimeType;

  /// 转为 Map（便于 JSON 序列化）
  Map<String, dynamic> toMap() => {
        if (title != null) 'title': title,
        if (artist != null) 'artist': artist,
        if (album != null) 'album': album,
        if (albumArtist != null) 'albumArtist': albumArtist,
        if (year != null) 'year': year,
        if (trackNumber != null) 'trackNumber': trackNumber,
        if (totalTracks != null) 'totalTracks': totalTracks,
        if (discNumber != null) 'discNumber': discNumber,
        if (totalDiscs != null) 'totalDiscs': totalDiscs,
        if (genre != null) 'genre': genre,
        if (comment != null) 'comment': comment,
        if (lyrics != null) 'lyrics': lyrics,
        if (composer != null) 'composer': composer,
        // coverData 不序列化到 JSON
        'coverMimeType': coverMimeType,
      };

  /// 是否有任何要写入的数据
  bool get hasData =>
      title != null ||
      artist != null ||
      album != null ||
      albumArtist != null ||
      year != null ||
      trackNumber != null ||
      genre != null ||
      lyrics != null ||
      coverData != null;

  /// 复制并修改部分字段
  WritableMetadata copyWith({
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    int? year,
    int? trackNumber,
    int? totalTracks,
    int? discNumber,
    int? totalDiscs,
    String? genre,
    String? comment,
    String? lyrics,
    String? composer,
    Uint8List? coverData,
    String? coverMimeType,
  }) =>
      WritableMetadata(
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        albumArtist: albumArtist ?? this.albumArtist,
        year: year ?? this.year,
        trackNumber: trackNumber ?? this.trackNumber,
        totalTracks: totalTracks ?? this.totalTracks,
        discNumber: discNumber ?? this.discNumber,
        totalDiscs: totalDiscs ?? this.totalDiscs,
        genre: genre ?? this.genre,
        comment: comment ?? this.comment,
        lyrics: lyrics ?? this.lyrics,
        composer: composer ?? this.composer,
        coverData: coverData ?? this.coverData,
        coverMimeType: coverMimeType ?? this.coverMimeType,
      );
}

/// 元数据写入结果
class MetadataWriteResult {
  const MetadataWriteResult({
    required this.success,
    this.error,
    this.fieldsWritten = const [],
    this.fieldsFailed = const [],
  });

  final bool success;
  final String? error;
  final List<String> fieldsWritten;
  final List<String> fieldsFailed;

  @override
  String toString() => success
      ? 'MetadataWriteResult(success, wrote: $fieldsWritten)'
      : 'MetadataWriteResult(failed: $error, failed fields: $fieldsFailed)';
}
