import 'dart:io';
import 'dart:typed_data';

import 'package:audiotags/audiotags.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_metadata_writer.dart';
import 'package:path/path.dart' as p;

// iOS/macOS 上 audiotags 有链接问题，暂时禁用
// 参见: https://github.com/erikas-taroza/audiotags/issues/21
// macOS: libaudiotags.a 与 macOS 26.1 SDK 不兼容，链接失败
bool get _disableAudiotags => Platform.isIOS || Platform.isMacOS;

/// 基于 audiotags (lofty-rs) 的元数据写入实现
///
/// 支持格式：
/// - MP3 (ID3v2, ID3v1, APE)
/// - FLAC (Vorbis Comments)
/// - M4A/MP4 (iTunes ilst)
/// - OGG Vorbis (Vorbis Comments)
/// - Opus (Vorbis Comments)
/// - WAV (ID3v2, RIFF INFO)
/// - AIFF (ID3v2, Text Chunks)
/// - APE (APEv2)
/// - MPC (APE)
/// - WavPack (APE)
/// - Speex (Vorbis Comments)
///
/// 不支持的格式（需要使用 FFmpegKit）：
/// - DSF/DFF (DSD)
/// - WMA
/// - AAC (纯 ADTS，非 M4A 容器)
class AudiotagsMetadataWriter implements MusicMetadataWriter {
  factory AudiotagsMetadataWriter() => _instance;
  AudiotagsMetadataWriter._();

  static final AudiotagsMetadataWriter _instance = AudiotagsMetadataWriter._();

  /// audiotags 支持的格式
  static const _supportedExtensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.mp4',
    '.m4b',
    '.m4p',
    '.m4r',
    '.m4v',
    '.3gp',
    '.ogg',
    '.oga',
    '.opus',
    '.wav',
    '.aiff',
    '.aif',
    '.ape',
    '.mpc',
    '.wv', // WavPack
    '.spx', // Speex
  };

  /// 需要使用备选方案的格式
  static const _unsupportedExtensions = {
    '.dsf',
    '.dff',
    '.dsd',
    '.wma',
    '.asf',
    '.aac', // 纯 ADTS
  };

  @override
  List<String> get supportedFormats => _supportedExtensions.toList();

  @override
  bool isFormatSupported(String extension) {
    final ext = extension.toLowerCase();
    final normalized = ext.startsWith('.') ? ext : '.$ext';
    return _supportedExtensions.contains(normalized);
  }

  /// 检查是否需要使用备选方案
  bool needsFallback(String extension) {
    final ext = extension.toLowerCase();
    final normalized = ext.startsWith('.') ? ext : '.$ext';
    return _unsupportedExtensions.contains(normalized);
  }

  @override
  Future<bool> writeMetadata(String filePath, WritableMetadata metadata) async {
    // iOS 上暂时禁用 audiotags，使用 FFmpeg 后备
    if (_disableAudiotags) {
      return false;
    }

    final ext = p.extension(filePath).toLowerCase();

    if (!isFormatSupported(ext)) {
      logger.w('AudiotagsMetadataWriter: 不支持的格式: $ext');
      return false;
    }

    if (!metadata.hasData) {
      logger.d('AudiotagsMetadataWriter: 没有要写入的数据');
      return true;
    }

    try {
      // 检查文件是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        logger.e('AudiotagsMetadataWriter: 文件不存在: $filePath');
        return false;
      }

      // 构建 Tag 对象
      final pictures = <Picture>[];
      if (metadata.coverData != null && metadata.coverData!.isNotEmpty) {
        pictures.add(Picture(
          bytes: metadata.coverData!,
          mimeType: _getMimeType(metadata.coverMimeType),
          pictureType: PictureType.coverFront,
        ));
      }

      final tag = Tag(
        title: metadata.title,
        trackArtist: metadata.artist,
        album: metadata.album,
        albumArtist: metadata.albumArtist,
        year: metadata.year,
        trackNumber: metadata.trackNumber,
        trackTotal: metadata.totalTracks,
        discNumber: metadata.discNumber,
        discTotal: metadata.totalDiscs,
        genre: metadata.genre,
        pictures: pictures,
      );

      // 写入元数据
      await AudioTags.write(filePath, tag);

      logger.i('AudiotagsMetadataWriter: 成功写入元数据: $filePath');
      return true;
    } catch (e, st) {
      logger.e('AudiotagsMetadataWriter: 写入失败: $filePath', e, st);
      return false;
    }
  }

  @override
  Future<bool> writeCover(
    String filePath,
    Uint8List coverData, {
    String mimeType = 'image/jpeg',
  }) async {
    // iOS 上暂时禁用 audiotags
    if (_disableAudiotags) {
      return false;
    }

    final ext = p.extension(filePath).toLowerCase();

    if (!isFormatSupported(ext)) {
      logger.w('AudiotagsMetadataWriter: 不支持的格式: $ext');
      return false;
    }

    try {
      // 先读取现有标签
      final existingTag = await AudioTags.read(filePath);

      // 构建新的 pictures 列表
      final pictures = <Picture>[
        Picture(
          bytes: coverData,
          mimeType: _getMimeType(mimeType),
          pictureType: PictureType.coverFront,
        ),
      ];

      // 保留其他类型的图片
      if (existingTag != null) {
        for (final pic in existingTag.pictures) {
          if (pic.pictureType != PictureType.coverFront) {
            pictures.add(pic);
          }
        }
      }

      // 使用现有标签信息，只更新图片
      final tag = Tag(
        title: existingTag?.title,
        trackArtist: existingTag?.trackArtist,
        album: existingTag?.album,
        albumArtist: existingTag?.albumArtist,
        year: existingTag?.year,
        trackNumber: existingTag?.trackNumber,
        trackTotal: existingTag?.trackTotal,
        discNumber: existingTag?.discNumber,
        discTotal: existingTag?.discTotal,
        genre: existingTag?.genre,
        pictures: pictures,
      );

      await AudioTags.write(filePath, tag);

      logger.i('AudiotagsMetadataWriter: 成功写入封面: $filePath');
      return true;
    } catch (e, st) {
      logger.e('AudiotagsMetadataWriter: 写入封面失败: $filePath', e, st);
      return false;
    }
  }

  @override
  Future<bool> removeAllMetadata(String filePath) async {
    // iOS 上暂时禁用 audiotags
    if (_disableAudiotags) {
      return false;
    }

    final ext = p.extension(filePath).toLowerCase();

    if (!isFormatSupported(ext)) {
      logger.w('AudiotagsMetadataWriter: 不支持的格式: $ext');
      return false;
    }

    try {
      // 写入空标签
      final emptyTag = Tag(pictures: []);
      await AudioTags.write(filePath, emptyTag);

      logger.i('AudiotagsMetadataWriter: 成功清除元数据: $filePath');
      return true;
    } catch (e, st) {
      logger.e('AudiotagsMetadataWriter: 清除元数据失败: $filePath', e, st);
      return false;
    }
  }

  /// 读取现有元数据
  Future<WritableMetadata?> readMetadata(String filePath) async {
    // iOS 上暂时禁用 audiotags
    if (_disableAudiotags) {
      return null;
    }

    final ext = p.extension(filePath).toLowerCase();

    if (!isFormatSupported(ext)) {
      return null;
    }

    try {
      final tag = await AudioTags.read(filePath);
      if (tag == null) return null;

      Uint8List? coverData;
      var coverMimeType = 'image/jpeg';

      if (tag.pictures.isNotEmpty) {
        // 优先获取封面图片
        final coverPic = tag.pictures.firstWhere(
          (p) => p.pictureType == PictureType.coverFront,
          orElse: () => tag.pictures.first,
        );
        coverData = Uint8List.fromList(coverPic.bytes);
        coverMimeType = _mimeTypeToString(coverPic.mimeType);
      }

      return WritableMetadata(
        title: tag.title,
        artist: tag.trackArtist,
        album: tag.album,
        albumArtist: tag.albumArtist,
        year: tag.year,
        trackNumber: tag.trackNumber,
        totalTracks: tag.trackTotal,
        discNumber: tag.discNumber,
        totalDiscs: tag.discTotal,
        genre: tag.genre,
        coverData: coverData,
        coverMimeType: coverMimeType,
      );
    } catch (e, st) {
      logger.e('AudiotagsMetadataWriter: 读取元数据失败: $filePath', e, st);
      return null;
    }
  }

  /// 转换 MIME 类型字符串到枚举
  MimeType _getMimeType(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'image/png':
        return MimeType.png;
      case 'image/gif':
        return MimeType.gif;
      case 'image/bmp':
        return MimeType.bmp;
      case 'image/tiff':
        return MimeType.tiff;
      case 'image/jpeg':
      case 'image/jpg':
      default:
        return MimeType.jpeg;
    }
  }

  /// 转换 MIME 枚举到字符串
  String _mimeTypeToString(MimeType? mimeType) => switch (mimeType) {
        MimeType.png => 'image/png',
        MimeType.gif => 'image/gif',
        MimeType.bmp => 'image/bmp',
        MimeType.tiff => 'image/tiff',
        MimeType.jpeg || null => 'image/jpeg',
      };
}
