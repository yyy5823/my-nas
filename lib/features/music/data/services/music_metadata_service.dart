import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart'
    show AudioMetadata, MetadataParserException, NoMetadataParserException, readMetadata;
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/ncm_decrypt_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 音乐元数据服务
/// 用于从音频文件中提取 ID3 标签等元数据
class MusicMetadataService {
  factory MusicMetadataService() => _instance ??= MusicMetadataService._();
  MusicMetadataService._();

  static MusicMetadataService? _instance;

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

    // 清理旧的临时文件
    await _cleanupTempFiles();

    _initialized = true;
    logger.i('MusicMetadataService: 初始化完成，缓存目录: ${_cacheDir.path}');
  }

  /// 清理遗留的临时文件
  Future<void> _cleanupTempFiles() async {
    try {
      final files = _cacheDir.listSync();
      for (final entity in files) {
        if (entity is File && p.basename(entity.path).startsWith('temp_metadata_')) {
          try {
            await entity.delete();
          } on Exception catch (_) {
            // 忽略删除失败
          }
        }
      }
    } on Exception catch (e) {
      logger.d('MusicMetadataService: 清理临时文件失败: $e');
    }
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
      logger..d('MusicMetadataService: readMetadata 完成')
      ..d('MusicMetadataService: 原始元数据 - title=${metadata.title}, artist=${metadata.artist}, album=${metadata.album}')
      ..d('MusicMetadataService: 原始元数据 - pictures=${metadata.pictures.length}, lyrics=${metadata.lyrics != null}');

      final result = _convertMetadata(metadata, file.path);
      _metadataCache[cacheKey] = result;

      logger.i('MusicMetadataService: 提取完成 - hasCover=${result.hasCover}, hasLyrics=${result.hasLyrics}');
      return result;
    } on NoMetadataParserException {
      // 文件没有 ID3 标签，使用文件名作为回退
      logger.i('MusicMetadataService: 文件无元数据标签，使用文件名回退: ${file.path}');
      final fallback = _parseMetadataFromFilename(file.path);
      _metadataCache[cacheKey] = fallback;
      return fallback;
    } on Exception catch (e, stackTrace) {
      logger.e('MusicMetadataService: 提取元数据失败: ${file.path}', e, stackTrace);
      return null;
    }
  }

  /// 渐进式读取大小（从小到大尝试）
  static const List<int> _progressiveReadSizes = [
    512 * 1024,      // 512KB - 快速尝试，适用于小元数据文件
    1024 * 1024,     // 1MB
    2 * 1024 * 1024, // 2MB
    4 * 1024 * 1024, // 4MB
    -1,              // -1 表示读取整个文件
  ];

  /// 从 NAS 文件提取元数据
  /// 使用渐进式重试策略：从小到大尝试不同的读取大小，确保所有文件都能被正确解析
  /// [skipLyrics] 为 true 时跳过歌词提取，用于后台批量扫描
  Future<MusicMetadata?> extractFromNasFile(
    NasFileSystem fileSystem,
    String path, {
    bool skipLyrics = false,
  }) async {
    if (!_initialized) await init();

    final cacheKey = '${fileSystem.hashCode}_$path';
    if (_metadataCache.containsKey(cacheKey)) {
      return _metadataCache[cacheKey];
    }

    try {
      final ext = p.extension(path).toLowerCase();
      logger.d('MusicMetadataService: 提取 NAS 文件元数据: $path (ext: $ext)');

      // NCM 文件使用专门的解密服务
      if (ext == '.ncm') {
        return _extractFromNcmFile(fileSystem, path, cacheKey);
      }

      // 获取文件信息
      final fileInfo = await fileSystem.getFileInfo(path);
      final fileSize = fileInfo.size;

      // 渐进式尝试不同的读取大小
      for (final targetSize in _progressiveReadSizes) {
        final bytesToRead = targetSize == -1 ? fileSize : (fileSize < targetSize ? fileSize : targetSize);

        // 如果已经尝试过这个大小或更大，跳过
        if (targetSize != -1 && bytesToRead == fileSize && targetSize != _progressiveReadSizes.first) {
          // 已经读取了整个文件但还没成功，继续下一次尝试（最后一次是 -1）
          if (targetSize != _progressiveReadSizes[_progressiveReadSizes.length - 2]) {
            continue;
          }
        }

        final result = await _tryExtractMetadata(
          fileSystem,
          path,
          bytesToRead,
          cacheKey,
          skipLyrics: skipLyrics,
          actualFileSize: fileSize,
        );

        if (result != null) {
          return result;
        }

        // 如果已经读取了整个文件还是失败，不再重试
        if (bytesToRead >= fileSize) {
          logger.w('MusicMetadataService: 读取整个文件后仍无法解析元数据: $path');
          break;
        }

        logger.d('MusicMetadataService: 尝试更大的读取大小: $path (当前: $bytesToRead)');
      }

      // 所有尝试都失败，使用文件名作为回退
      logger.i('MusicMetadataService: 使用文件名回退解析: $path');
      final fallback = _parseMetadataFromFilename(path);
      _metadataCache[cacheKey] = fallback;
      return fallback;
    } on Exception catch (e, stackTrace) {
      logger.w('MusicMetadataService: 提取 NAS 文件元数据失败: $path', e, stackTrace);
      return null;
    }
  }

  /// 尝试使用指定大小提取元数据
  Future<MusicMetadata?> _tryExtractMetadata(
    NasFileSystem fileSystem,
    String path,
    int bytesToRead,
    String cacheKey, {
    required int actualFileSize, bool skipLyrics = false,
  }) async {
    File? tempFile;
    try {
      logger.d('MusicMetadataService: 尝试读取 $bytesToRead 字节: $path');

      // 读取文件
      final stream = await fileSystem.getFileStream(
        path,
        range: FileRange(start: 0, end: bytesToRead),
      );

      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }

      // 保存到临时文件（使用唯一文件名避免并发冲突）
      final ext = p.extension(path).toLowerCase();
      final uniqueId = '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999)}';
      tempFile = File(p.join(_cacheDir.path, 'temp_metadata_$uniqueId$ext'));
      await tempFile.writeAsBytes(Uint8List.fromList(chunks));

      final metadata = readMetadata(tempFile, getImage: true);
      // 判断是否需要跳过 duration
      // - FLAC：duration 存储在文件头的 STREAMINFO 块中，即使部分读取也是精确的
      // - 其他格式（如 MP3 CBR）：duration 基于文件大小计算，部分读取会导致不准确
      final isPartialRead = bytesToRead < actualFileSize;
      final isFlac = ext == '.flac';
      final skipDuration = isPartialRead && !isFlac;
      final result = _convertMetadata(
        metadata,
        path,
        skipLyrics: skipLyrics,
        skipDuration: skipDuration,
      );
      _metadataCache[cacheKey] = result;

      logger.d('MusicMetadataService: 成功提取元数据 (读取 $bytesToRead 字节, 跳过时长=$skipDuration, isFlac=$isFlac): $path');
      return result;
    } on MetadataParserException catch (e) {
      // 解析异常，可能需要更多数据
      if (e.toString().contains('Expected more data')) {
        logger.d('MusicMetadataService: 数据不足，需要读取更多: $path');
        return null; // 返回 null 让调用者重试更大的大小
      }
      // 其他解析异常，记录但不抛出
      logger.d('MusicMetadataService: 解析异常: $path - $e');
      return null;
    } on Exception catch (e) {
      // 其他异常
      logger.d('MusicMetadataService: 提取失败: $path - $e');
      return null;
    } finally {
      // 清理临时文件
      if (tempFile != null) {
        await _deleteTempFile(tempFile);
      }
    }
  }

  /// 从 NCM 文件提取元数据
  Future<MusicMetadata?> _extractFromNcmFile(
    NasFileSystem fileSystem,
    String path,
    String cacheKey,
  ) async {
    try {
      logger.d('MusicMetadataService: 开始解密 NCM 文件: $path');

      // 下载整个 NCM 文件（NCM 文件需要完整读取才能解密）
      final stream = await fileSystem.getFileStream(path);
      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }

      final ncmData = Uint8List.fromList(chunks);
      logger.d('MusicMetadataService: NCM 文件大小: ${ncmData.length} bytes');

      // 解密 NCM 文件
      final ncmService = NcmDecryptService();
      final result = ncmService.decrypt(ncmData);

      if (result == null) {
        logger.w('MusicMetadataService: NCM 解密失败: $path');
        return null;
      }

      // 从解密结果中提取元数据
      final ncmMeta = result.metadata;
      final metadata = MusicMetadata(
        title: ncmMeta?.musicName,
        artist: ncmMeta?.artist,
        album: ncmMeta?.album,
        duration: ncmMeta != null && ncmMeta.duration > 0
            ? Duration(milliseconds: ncmMeta.duration)
            : null,
        coverData: result.coverData?.toList(),
      );

      _metadataCache[cacheKey] = metadata;
      logger.i('MusicMetadataService: NCM 元数据提取成功 - ${metadata.title}');
      return metadata;
    } on Exception catch (e, stackTrace) {
      logger.e('MusicMetadataService: NCM 文件处理失败: $path', e, stackTrace);
      return null;
    }
  }

  /// 安全删除临时文件
  Future<void> _deleteTempFile(File tempFile) async {
    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } on Exception catch (e) {
      logger.d('MusicMetadataService: 临时文件删除失败，将稍后清理: ${tempFile.path} - $e');
      // 文件可能仍被占用，稍后重试一次
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } on Exception catch (_) {
        // 忽略删除失败，临时文件会在下次启动时被清理
        logger.d('MusicMetadataService: 临时文件删除失败，将稍后清理: ${tempFile.path}');
      }
    }
  }

  /// 将 audio_metadata_reader 的元数据转换为我们的格式
  /// [skipLyrics] 为 true 时跳过歌词提取
  /// [skipDuration] 为 true 时跳过时长提取（用于部分文件读取时，避免不准确的时长）
  MusicMetadata _convertMetadata(
    AudioMetadata metadata,
    String filePath, {
    bool skipLyrics = false,
    bool skipDuration = false,
  }) {
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
    // 只有完整读取文件时才提取时长，部分读取时 duration 不准确
    if (!skipDuration) {
      duration = metadata.duration;
    }

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
    if (genres.isNotEmpty) {
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
  /// 只更新缺失的字段，不覆盖已有的有效数据
  MusicItem applyMetadataToItem(MusicItem item, MusicMetadata metadata) => item.copyWith(
      artist: (item.artist?.isNotEmpty ?? false) ? item.artist : metadata.artist,
      album: (item.album?.isNotEmpty ?? false) ? item.album : metadata.album,
      trackNumber: item.trackNumber ?? metadata.trackNumber,
      year: item.year ?? metadata.year,
      genre: (item.genre?.isNotEmpty ?? false) ? item.genre : metadata.genre,
      lyrics: (item.lyrics?.isNotEmpty ?? false) ? item.lyrics : metadata.lyrics,
      coverData: (item.coverData?.isNotEmpty ?? false) ? item.coverData : metadata.coverData,
      duration: (item.duration != null && item.duration! > Duration.zero)
          ? item.duration
          : metadata.duration,
    );

  /// 从文件名解析元数据（用于无 ID3 标签的文件回退）
  /// 支持的格式:
  /// - "标题（艺术家）.mp3"
  /// - "标题 - 艺术家.mp3"
  /// - "艺术家 - 标题.mp3"
  /// - "标题.mp3"
  MusicMetadata _parseMetadataFromFilename(String path) {
    final filename = p.basenameWithoutExtension(path);
    String? title;
    String? artist;

    // 尝试匹配 "标题（艺术家）" 或 "标题(艺术家)" 格式
    final parenMatch = RegExp(r'^(.+?)[（(](.+?)[）)]$').firstMatch(filename);
    if (parenMatch != null) {
      title = parenMatch.group(1)?.trim();
      artist = parenMatch.group(2)?.trim();
    } else {
      // 尝试匹配 "A - B" 格式
      final dashMatch = RegExp(r'^(.+?)\s*[-–—]\s*(.+)$').firstMatch(filename);
      if (dashMatch != null) {
        final part1 = dashMatch.group(1)?.trim();
        final part2 = dashMatch.group(2)?.trim();
        // 通常是 "艺术家 - 标题" 格式，但也可能是 "标题 - 艺术家"
        // 这里我们假设第一部分是艺术家
        artist = part1;
        title = part2;
      } else {
        // 无法解析，使用整个文件名作为标题
        title = filename;
      }
    }

    logger.d('MusicMetadataService: 从文件名解析 - title=$title, artist=$artist');

    return MusicMetadata(
      title: title,
      artist: artist,
    );
  }

  /// 清除缓存
  void clearCache() {
    _metadataCache.clear();
  }

  /// 专门获取音频时长（用于播放时获取准确时长）
  /// 会尝试读取足够的数据来获取准确的时长信息
  /// 对于 MP3 等格式，可能需要读取更多数据才能获取准确时长
  Future<Duration?> getDurationFromNasFile(
    NasFileSystem fileSystem,
    String path,
  ) async {
    if (!_initialized) await init();

    try {
      logger.d('MusicMetadataService: 获取音频时长: $path');

      // 获取文件信息
      final fileInfo = await fileSystem.getFileInfo(path);
      final fileSize = fileInfo.size;
      final ext = p.extension(path).toLowerCase();

      // 对于 FLAC，只需读取文件头即可获取准确时长
      // 对于其他格式（如 MP3），需要读取更多数据
      int bytesToRead;
      if (ext == '.flac') {
        // FLAC 的 STREAMINFO 块在文件开头，512KB 足够
        bytesToRead = fileSize < 512 * 1024 ? fileSize : 512 * 1024;
      } else {
        // 对于 MP3 等 CBR/VBR 格式，读取整个文件以获取准确时长
        // 或者至少读取 4MB 以获取较准确的估算
        bytesToRead = fileSize < 4 * 1024 * 1024 ? fileSize : 4 * 1024 * 1024;
      }

      // 读取文件数据
      final stream = await fileSystem.getFileStream(
        path,
        range: FileRange(start: 0, end: bytesToRead),
      );

      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }

      // 保存到临时文件
      final uniqueId = '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999)}';
      final tempFile = File(p.join(_cacheDir.path, 'temp_duration_$uniqueId$ext'));

      try {
        await tempFile.writeAsBytes(Uint8List.fromList(chunks));

        final metadata = readMetadata(tempFile);
        final duration = metadata.duration;

        if (duration != null && duration > Duration.zero) {
          logger.i('MusicMetadataService: 获取到时长: $duration (读取了 $bytesToRead 字节)');

          // 对于部分读取的非 FLAC 文件，根据实际文件大小调整时长估算
          if (ext != '.flac' && bytesToRead < fileSize) {
            // 基于比特率估算完整文件时长
            final bytesPerSecond = bytesToRead / duration.inSeconds;
            final estimatedDuration = Duration(
              seconds: (fileSize / bytesPerSecond).round(),
            );
            logger.i('MusicMetadataService: 调整后的时长估算: $estimatedDuration');
            return estimatedDuration;
          }

          return duration;
        }

        logger.w('MusicMetadataService: 无法获取时长');
        return null;
      } finally {
        // 清理临时文件
        await _deleteTempFile(tempFile);
      }
    } on Exception catch (e, stackTrace) {
      logger.w('MusicMetadataService: 获取时长失败: $path', e, stackTrace);
      return null;
    }
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
