import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/ncm_decrypt_service.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 音乐标签写入结果
class MusicTagWriteResult {
  const MusicTagWriteResult({
    required this.success,
    this.error,
    this.updatedFields = const [],
  });

  factory MusicTagWriteResult.success(List<String> fields) => MusicTagWriteResult(
        success: true,
        updatedFields: fields,
      );

  factory MusicTagWriteResult.failure(String error) => MusicTagWriteResult(
        success: false,
        error: error,
      );

  final bool success;
  final String? error;
  final List<String> updatedFields;
}

/// 要写入的元数据
class MusicTagData {
  const MusicTagData({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.genre,
    this.lyrics,
    this.coverData,
    this.coverMimeType,
  });

  /// 从刮削结果创建
  factory MusicTagData.fromScrapeResult(
    MusicScrapeResult result, {
    Uint8List? downloadedCover,
    String? coverMimeType,
  }) {
    final detail = result.detail;
    final lyrics = result.lyrics;

    return MusicTagData(
      title: detail?.title,
      artist: detail?.artist,
      album: detail?.album,
      albumArtist: detail?.albumArtist,
      year: detail?.year,
      trackNumber: detail?.trackNumber,
      discNumber: detail?.discNumber,
      genre: detail?.genres?.join(', '),
      lyrics: lyrics?.lrcContent ?? lyrics?.plainText,
      coverData: downloadedCover,
      coverMimeType: coverMimeType ?? 'image/jpeg',
    );
  }

  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final int? year;
  final int? trackNumber;
  final int? discNumber;
  final String? genre;
  final String? lyrics;
  final Uint8List? coverData;
  final String? coverMimeType;

  bool get isEmpty =>
      title == null &&
      artist == null &&
      album == null &&
      albumArtist == null &&
      year == null &&
      trackNumber == null &&
      discNumber == null &&
      genre == null &&
      lyrics == null &&
      coverData == null;
}

/// 支持写入的音频格式
enum SupportedAudioFormat {
  mp3('MP3', ['.mp3'], 'ID3v2'),
  flac('FLAC', ['.flac'], 'Vorbis Comment'),
  mp4('MP4/M4A', ['.mp4', '.m4a', '.aac'], 'iTunes ilst'),
  wav('WAV', ['.wav'], 'RIFF INFO'),
  ncm('NCM', ['.ncm'], '解密后写入');

  const SupportedAudioFormat(this.displayName, this.extensions, this.tagType);

  final String displayName;
  final List<String> extensions;
  final String tagType;

  /// 是否需要转换（如 NCM 需要解密）
  bool get requiresConversion => this == ncm;

  static SupportedAudioFormat? fromExtension(String ext) {
    final lowerExt = ext.toLowerCase();
    for (final format in values) {
      if (format.extensions.contains(lowerExt)) {
        return format;
      }
    }
    return null;
  }
}

/// 音乐标签写入服务
/// 支持将元数据写入音频文件的 ID3/Vorbis Comment/iTunes 标签
class MusicTagWriterService {
  factory MusicTagWriterService() => _instance ??= MusicTagWriterService._();
  MusicTagWriterService._();

  static MusicTagWriterService? _instance;

  late Directory _tempDir;
  bool _initialized = false;

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;

    final appDir = await getApplicationSupportDirectory();
    _tempDir = Directory(p.join(appDir.path, 'music_tag_temp'));
    if (!await _tempDir.exists()) {
      await _tempDir.create(recursive: true);
    }

    _initialized = true;
    logger.i('MusicTagWriterService: 初始化完成');
  }

  /// 检查文件格式是否支持写入
  bool isFormatSupported(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return SupportedAudioFormat.fromExtension(ext) != null;
  }

  /// 获取支持的格式信息
  SupportedAudioFormat? getFormat(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return SupportedAudioFormat.fromExtension(ext);
  }

  /// 写入标签到本地文件
  Future<MusicTagWriteResult> writeToLocalFile(
    File file,
    MusicTagData tagData,
  ) async {
    if (!_initialized) await init();

    final format = getFormat(file.path);
    if (format == null) {
      return MusicTagWriteResult.failure('不支持的文件格式: ${p.extension(file.path)}');
    }

    if (tagData.isEmpty) {
      return MusicTagWriteResult.failure('没有要写入的数据');
    }

    try {
      logger.i('MusicTagWriterService: 开始写入标签到 ${file.path}');
      logger.d('MusicTagWriterService: 格式=${format.displayName}, 标签类型=${format.tagType}');

      final updatedFields = <String>[];

      // 使用 audio_metadata_reader 的 updateMetadata 函数
      // 扩展方法会自动处理不同格式（MP3/FLAC/MP4/WAV）的差异
      updateMetadata(file, (metadata) {
        // metadata 可能是 Mp3Metadata, VorbisMetadata, Mp4Metadata, RiffMetadata 等
        // 使用扩展方法统一设置属性
        if (tagData.title != null && tagData.title!.isNotEmpty) {
          metadata.setTitle(tagData.title!);
          updatedFields.add('标题');
        }
        if (tagData.artist != null && tagData.artist!.isNotEmpty) {
          metadata.setArtist(tagData.artist!);
          updatedFields.add('艺术家');
        }
        if (tagData.album != null && tagData.album!.isNotEmpty) {
          metadata.setAlbum(tagData.album!);
          updatedFields.add('专辑');
        }
        if (tagData.trackNumber != null) {
          metadata.setTrackNumber(tagData.trackNumber!);
          updatedFields.add('曲目号');
        }
        if (tagData.year != null) {
          metadata.setYear(DateTime(tagData.year!));
          updatedFields.add('年份');
        }
        if (tagData.genre != null && tagData.genre!.isNotEmpty) {
          final genres = tagData.genre!.split(',').map((g) => g.trim()).toList();
          metadata.setGenres(genres);
          updatedFields.add('流派');
        }
        if (tagData.lyrics != null && tagData.lyrics!.isNotEmpty) {
          metadata.setLyrics(tagData.lyrics!);
          updatedFields.add('歌词');
        }
        if (tagData.coverData != null && tagData.coverData!.isNotEmpty) {
          final mimeType = tagData.coverMimeType ?? 'image/jpeg';
          metadata.setPictures([
            Picture(tagData.coverData!, mimeType, PictureType.coverFront),
          ]);
          updatedFields.add('封面');
        }
      });

      logger.i('MusicTagWriterService: 写入成功, 更新字段: $updatedFields');
      return MusicTagWriteResult.success(updatedFields);
    } on Exception catch (e, st) {
      logger.e('MusicTagWriterService: 写入失败', e, st);
      return MusicTagWriteResult.failure('写入失败: $e');
    }
  }

  /// 写入标签到 NAS 文件
  /// 注意：这需要下载文件、修改、再上传
  /// 对于 NCM 文件，会解密并保存为新的 MP3/FLAC 文件
  /// [convertedPath] 用于返回 NCM 转换后的新文件路径
  Future<MusicTagWriteResult> writeToNasFile(
    NasFileSystem fileSystem,
    String remotePath,
    MusicTagData tagData, {
    void Function(String newPath)? onConverted,
  }) async {
    if (!_initialized) await init();

    final format = getFormat(remotePath);
    if (format == null) {
      return MusicTagWriteResult.failure('不支持的文件格式: ${p.extension(remotePath)}');
    }

    if (tagData.isEmpty) {
      return MusicTagWriteResult.failure('没有要写入的数据');
    }

    // NCM 文件需要特殊处理
    if (format == SupportedAudioFormat.ncm) {
      return _writeToNcmFile(fileSystem, remotePath, tagData, onConverted);
    }

    File? tempFile;
    try {
      logger.i('MusicTagWriterService: 开始写入标签到 NAS 文件 $remotePath');

      // 1. 下载整个文件到本地临时目录
      final ext = p.extension(remotePath).toLowerCase();
      final uniqueId = '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999)}';
      tempFile = File(p.join(_tempDir.path, 'tag_edit_$uniqueId$ext'));

      logger.d('MusicTagWriterService: 下载文件到临时目录...');
      final stream = await fileSystem.getFileStream(remotePath);
      final sink = tempFile.openWrite();
      await for (final chunk in stream) {
        sink.add(chunk);
      }
      await sink.close();

      logger.d('MusicTagWriterService: 文件下载完成, 大小=${await tempFile.length()} bytes');

      // 2. 写入标签
      final result = await writeToLocalFile(tempFile, tagData);
      if (!result.success) {
        return result;
      }

      // 3. 上传回 NAS
      logger.d('MusicTagWriterService: 上传修改后的文件...');
      final modifiedData = await tempFile.readAsBytes();
      await fileSystem.writeFile(remotePath, modifiedData);

      logger.i('MusicTagWriterService: NAS 文件标签写入成功');
      return result;
    } on Exception catch (e, st) {
      logger.e('MusicTagWriterService: NAS 文件标签写入失败', e, st);
      return MusicTagWriteResult.failure('写入失败: $e');
    } finally {
      // 清理临时文件
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } on Exception catch (_) {
          // 忽略删除失败
        }
      }
    }
  }

  /// 处理 NCM 文件的标签写入
  /// NCM 文件需要解密后写入标签，无法重新加密，因此保存为 MP3/FLAC
  Future<MusicTagWriteResult> _writeToNcmFile(
    NasFileSystem fileSystem,
    String remotePath,
    MusicTagData tagData,
    void Function(String newPath)? onConverted,
  ) async {
    File? tempNcmFile;
    File? tempAudioFile;

    try {
      logger.i('MusicTagWriterService: 开始处理 NCM 文件 $remotePath');

      // 1. 下载 NCM 文件
      final uniqueId = '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999)}';
      tempNcmFile = File(p.join(_tempDir.path, 'ncm_$uniqueId.ncm'));

      logger.d('MusicTagWriterService: 下载 NCM 文件...');
      final stream = await fileSystem.getFileStream(remotePath);
      final sink = tempNcmFile.openWrite();
      await for (final chunk in stream) {
        sink.add(chunk);
      }
      await sink.close();

      // 2. 解密 NCM 文件
      logger.d('MusicTagWriterService: 解密 NCM 文件...');
      final ncmData = await tempNcmFile.readAsBytes();
      final ncmService = NcmDecryptService();
      final decryptResult = ncmService.decrypt(ncmData);

      if (decryptResult == null) {
        return MusicTagWriteResult.failure('NCM 文件解密失败');
      }

      // 确定输出格式
      final outputFormat = decryptResult.metadata?.format ?? 'mp3';
      final outputExt = outputFormat == 'flac' ? '.flac' : '.mp3';

      logger.d('MusicTagWriterService: 解密成功，格式=$outputFormat');

      // 3. 保存解密后的音频到临时文件
      tempAudioFile = File(p.join(_tempDir.path, 'audio_$uniqueId$outputExt'));
      await tempAudioFile.writeAsBytes(decryptResult.audioData);

      // 4. 合并 NCM 内置元数据和刮削数据
      final mergedTagData = _mergeNcmMetadata(tagData, decryptResult);

      // 5. 写入标签
      final writeResult = await writeToLocalFile(tempAudioFile, mergedTagData);
      if (!writeResult.success) {
        return writeResult;
      }

      // 6. 上传新文件到 NAS（与原文件同目录，但扩展名不同）
      final baseName = p.basenameWithoutExtension(remotePath);
      final dirPath = p.dirname(remotePath);
      final newPath = p.join(dirPath, '$baseName$outputExt');

      logger.d('MusicTagWriterService: 上传转换后的文件到 $newPath');
      final modifiedData = await tempAudioFile.readAsBytes();
      await fileSystem.writeFile(newPath, modifiedData);

      // 通知调用者新文件路径
      onConverted?.call(newPath);

      logger.i('MusicTagWriterService: NCM 转换并写入标签成功 -> $newPath');

      final updatedFields = List<String>.from(writeResult.updatedFields);
      if (!updatedFields.contains('转换')) {
        updatedFields.insert(0, '转换为 ${outputFormat.toUpperCase()}');
      }

      return MusicTagWriteResult.success(updatedFields);
    } on Exception catch (e, st) {
      logger.e('MusicTagWriterService: NCM 文件处理失败', e, st);
      return MusicTagWriteResult.failure('NCM 处理失败: $e');
    } finally {
      // 清理临时文件
      for (final file in [tempNcmFile, tempAudioFile]) {
        if (file != null) {
          try {
            if (await file.exists()) {
              await file.delete();
            }
          } on Exception catch (_) {
            // 忽略
          }
        }
      }
    }
  }

  /// 合并 NCM 内置元数据和刮削数据
  /// 刮削数据优先，NCM 内置数据作为补充
  MusicTagData _mergeNcmMetadata(MusicTagData tagData, NcmDecryptResult ncmResult) {
    final ncmMeta = ncmResult.metadata;

    return MusicTagData(
      title: tagData.title ?? ncmMeta?.musicName,
      artist: tagData.artist ?? ncmMeta?.artist,
      album: tagData.album ?? ncmMeta?.album,
      albumArtist: tagData.albumArtist,
      year: tagData.year,
      trackNumber: tagData.trackNumber,
      discNumber: tagData.discNumber,
      genre: tagData.genre,
      lyrics: tagData.lyrics,
      // 封面优先使用刮削的，其次使用 NCM 内置的
      coverData: tagData.coverData ?? ncmResult.coverData,
      coverMimeType: tagData.coverMimeType ?? (ncmResult.coverData != null ? 'image/jpeg' : null),
    );
  }

  /// 批量写入标签
  Future<Map<String, MusicTagWriteResult>> writeBatch(
    NasFileSystem fileSystem,
    Map<String, MusicTagData> files,
  ) async {
    final results = <String, MusicTagWriteResult>{};

    for (final entry in files.entries) {
      final path = entry.key;
      final tagData = entry.value;

      logger.d('MusicTagWriterService: 批量写入 ${files.keys.toList().indexOf(path) + 1}/${files.length}: $path');

      results[path] = await writeToNasFile(fileSystem, path, tagData);

      // 添加小延迟避免过快
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    final successCount = results.values.where((r) => r.success).length;
    logger.i('MusicTagWriterService: 批量写入完成, 成功 $successCount/${files.length}');

    return results;
  }

  /// 清理临时文件
  Future<void> cleanup() async {
    if (!_initialized) return;

    try {
      final files = _tempDir.listSync();
      for (final entity in files) {
        if (entity is File) {
          try {
            await entity.delete();
          } on Exception catch (_) {
            // 忽略
          }
        }
      }
    } on Exception catch (e) {
      logger.d('MusicTagWriterService: 清理临时文件失败: $e');
    }
  }
}
