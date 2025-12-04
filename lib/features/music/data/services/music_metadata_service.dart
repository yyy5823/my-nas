import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 音乐元数据服务
/// 用于从音频文件中提取 ID3 标签等元数据
class MusicMetadataService {
  MusicMetadataService._();
  static final MusicMetadataService instance = MusicMetadataService._();

  late Directory _cacheDir;
  bool _initialized = false;

  /// 已缓存的元数据（按路径索引）
  final Map<String, MusicMetadata> _metadataCache = {};

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;

    final appDir = await getApplicationSupportDirectory();
    _cacheDir = Directory(p.join(appDir.path, 'music_metadata_cache'));
    if (!await _cacheDir.exists()) {
      await _cacheDir.create(recursive: true);
    }

    _initialized = true;
    logger.i('MusicMetadataService: 初始化完成，缓存目录: ${_cacheDir.path}');
  }

  /// 从本地文件提取元数据
  Future<MusicMetadata?> extractFromLocalFile(File file) async {
    if (!_initialized) await init();

    final cacheKey = file.path;
    if (_metadataCache.containsKey(cacheKey)) {
      logger.d('MusicMetadataService: 使用缓存的元数据: ${file.path}');
      return _metadataCache[cacheKey];
    }

    try {
      logger.i('MusicMetadataService: 开始提取本地文件元数据: ${file.path}');
      final fileSize = await file.length();
      logger.d('MusicMetadataService: 文件大小 = $fileSize bytes');

      final metadata = readMetadata(file, getImage: true);
      logger.d('MusicMetadataService: readMetadata 完成');
      logger.d('MusicMetadataService: 原始元数据 - title=${metadata.title}, artist=${metadata.artist}, album=${metadata.album}');
      logger.d('MusicMetadataService: 原始元数据 - pictures=${metadata.pictures.length}, lyrics=${metadata.lyrics != null}');

      final result = _convertMetadata(metadata, file.path);
      _metadataCache[cacheKey] = result;

      logger.i('MusicMetadataService: 提取完成 - hasCover=${result.hasCover}, hasLyrics=${result.hasLyrics}');
      return result;
    } catch (e, stackTrace) {
      logger.e('MusicMetadataService: 提取元数据失败: ${file.path}', e, stackTrace);
      return null;
    }
  }

  /// 从 NAS 文件提取元数据
  /// 需要先下载文件头部到本地临时文件
  /// [skipLyrics] 为 true 时跳过歌词提取，用于后台批量扫描
  Future<MusicMetadata?> extractFromNasFile(
    NasFileSystem fileSystem,
    String path, {
    int maxBytes = 512 * 1024, // 默认读取前 512KB，足够读取大多数 ID3 标签
    bool skipLyrics = false,
  }) async {
    if (!_initialized) await init();

    final cacheKey = '${fileSystem.hashCode}_$path';
    if (_metadataCache.containsKey(cacheKey)) {
      return _metadataCache[cacheKey];
    }

    try {
      logger.d('MusicMetadataService: 提取 NAS 文件元数据: $path');

      // 获取文件信息
      final fileInfo = await fileSystem.getFileInfo(path);
      final bytesToRead = fileInfo.size < maxBytes ? fileInfo.size : maxBytes;

      // 读取文件头部
      final stream = await fileSystem.getFileStream(
        path,
        range: FileRange(start: 0, end: bytesToRead),
      );

      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }

      // 保存到临时文件
      final ext = p.extension(path).toLowerCase();
      final tempFile = File(p.join(_cacheDir.path, 'temp_metadata$ext'));
      await tempFile.writeAsBytes(Uint8List.fromList(chunks));

      try {
        final metadata = readMetadata(tempFile, getImage: true);
        final result = _convertMetadata(metadata, path, skipLyrics: skipLyrics);
        _metadataCache[cacheKey] = result;
        return result;
      } finally {
        // 清理临时文件
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } catch (e, stackTrace) {
      logger.w('MusicMetadataService: 提取 NAS 文件元数据失败: $path', e, stackTrace);
      return null;
    }
  }

  /// 将 audio_metadata_reader 的元数据转换为我们的格式
  /// [skipLyrics] 为 true 时跳过歌词提取
  MusicMetadata _convertMetadata(AudioMetadata metadata, String filePath, {bool skipLyrics = false}) {
    String? artist;
    String? album;
    String? title;
    int? trackNumber;
    int? year;
    String? genre;
    String? lyrics;
    List<int>? coverData;
    Duration? duration;

    // 提取通用字段
    title = metadata.title;
    album = metadata.album;
    duration = metadata.duration;

    // 提取艺术家（可能有多个）
    if (metadata.artist != null) {
      artist = metadata.artist;
    }

    // 提取曲目号
    trackNumber = metadata.trackNumber;

    // 提取年份
    year = metadata.year?.year;

    // 提取流派
    final genres = metadata.genres;
    if (genres != null && genres.isNotEmpty) {
      genre = genres.join(', ');
    }

    // 提取歌词（后台扫描时跳过，播放时按需提取）
    if (!skipLyrics) {
      lyrics = metadata.lyrics;
    }

    // 提取封面图片
    if (metadata.pictures.isNotEmpty) {
      final cover = metadata.pictures.first;
      coverData = cover.bytes.toList();
    }

    logger.d('MusicMetadataService: 提取成功 - title=$title, artist=$artist, album=$album');

    return MusicMetadata(
      title: title,
      artist: artist,
      album: album,
      trackNumber: trackNumber,
      year: year,
      genre: genre,
      lyrics: lyrics,
      coverData: coverData,
      duration: duration,
    );
  }

  /// 将元数据应用到 MusicItem
  MusicItem applyMetadataToItem(MusicItem item, MusicMetadata metadata) {
    return item.copyWith(
      artist: metadata.artist ?? item.artist,
      album: metadata.album ?? item.album,
      trackNumber: metadata.trackNumber,
      year: metadata.year,
      genre: metadata.genre,
      lyrics: metadata.lyrics,
      coverData: metadata.coverData,
      duration: metadata.duration ?? item.duration,
    );
  }

  /// 清除缓存
  void clearCache() {
    _metadataCache.clear();
  }
}

/// 音乐元数据
class MusicMetadata {
  const MusicMetadata({
    this.title,
    this.artist,
    this.album,
    this.trackNumber,
    this.year,
    this.genre,
    this.lyrics,
    this.coverData,
    this.duration,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final int? year;
  final String? genre;
  final String? lyrics;
  final List<int>? coverData;
  final Duration? duration;

  bool get hasCover => coverData != null && coverData!.isNotEmpty;
  bool get hasLyrics => lyrics != null && lyrics!.isNotEmpty;
}
