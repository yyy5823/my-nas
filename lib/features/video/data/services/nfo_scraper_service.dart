import 'dart:convert';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:xml/xml.dart';

/// NFO 刮削信息
class NfoMetadata {
  NfoMetadata({
    this.title,
    this.originalTitle,
    this.year,
    this.plot,
    this.rating,
    this.runtime,
    this.genres,
    this.director,
    this.actors,
    this.studio,
    this.tmdbId,
    this.imdbId,
    this.posterPath,
    this.fanartPath,
    this.thumbPath,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    this.aired,
  });

  final String? title;
  final String? originalTitle;
  final int? year;
  final String? plot;
  final double? rating;
  final int? runtime;
  final List<String>? genres;
  final String? director;
  final List<String>? actors;
  final String? studio;
  final int? tmdbId;
  final String? imdbId;
  final String? posterPath;   // 本地海报路径
  final String? fanartPath;   // 本地背景图路径
  final String? thumbPath;    // 本地缩略图路径
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;
  final String? aired;

  bool get hasData => title != null || tmdbId != null;

  /// 转换为 VideoMetadata
  VideoMetadata toVideoMetadata({
    required String filePath,
    required String sourceId,
    required String fileName,
    String? thumbnailUrl,
  }) {
    return VideoMetadata(
      filePath: filePath,
      sourceId: sourceId,
      fileName: fileName,
      category: seasonNumber != null || episodeNumber != null
          ? MediaCategory.tvShow
          : MediaCategory.movie,
      tmdbId: tmdbId,
      title: title,
      originalTitle: originalTitle,
      year: year,
      overview: plot,
      rating: rating,
      runtime: runtime,
      genres: genres?.join(', '),
      director: director,
      cast: actors?.take(5).join(', '),
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
      thumbnailUrl: thumbnailUrl,
      lastUpdated: DateTime.now(),
    );
  }
}

/// NFO 刮削服务
/// 用于解析视频同级目录下的 NFO 刮削文件和本地图片
class NfoScraperService {
  NfoScraperService._();

  static NfoScraperService? _instance;
  static NfoScraperService get instance => _instance ??= NfoScraperService._();

  /// 支持的 NFO 文件扩展名
  static const _nfoExtensions = ['.nfo'];

  /// 支持的图片扩展名
  static const _imageExtensions = ['.jpg', '.jpeg', '.png', '.webp'];

  /// 海报文件名模式
  static const _posterPatterns = ['poster', 'cover', 'folder'];

  /// 背景图文件名模式
  static const _fanartPatterns = ['fanart', 'backdrop', 'background', 'art'];

  /// 缩略图文件名模式
  static const _thumbPatterns = ['thumb', 'thumbnail'];

  /// 获取视频同级目录下的刮削信息
  Future<NfoMetadata?> scrapeFromDirectory({
    required NasFileSystem fileSystem,
    required String videoPath,
    required String videoFileName,
  }) async {
    try {
      // 获取视频所在目录
      final videoDir = _getParentPath(videoPath);
      final videoBaseName = _getBaseName(videoFileName);

      logger.d('NfoScraperService: 扫描目录 $videoDir 查找 $videoBaseName 的刮削信息');

      // 列出目录内容
      final files = await fileSystem.listDirectory(videoDir);

      // 查找 NFO 文件
      String? nfoContent;
      for (final file in files) {
        if (file.isDirectory) continue;

        final fileName = file.name.toLowerCase();

        // 优先查找与视频同名的 NFO 文件
        if (_isMatchingNfo(fileName, videoBaseName)) {
          try {
            nfoContent = await _readFileAsString(fileSystem, file.path);
            logger.d('NfoScraperService: 找到匹配的 NFO 文件 ${file.name}');
            break;
          } catch (e) {
            logger.w('NfoScraperService: 读取 NFO 文件失败 ${file.name}', e);
          }
        }
      }

      // 如果没找到同名 NFO，查找通用 NFO 文件
      if (nfoContent == null) {
        for (final file in files) {
          if (file.isDirectory) continue;

          final fileName = file.name.toLowerCase();
          if (fileName == 'movie.nfo' ||
              fileName == 'tvshow.nfo' ||
              fileName == 'episode.nfo') {
            try {
              nfoContent = await _readFileAsString(fileSystem, file.path);
              logger.d('NfoScraperService: 找到通用 NFO 文件 ${file.name}');
              break;
            } catch (e) {
              logger.w('NfoScraperService: 读取通用 NFO 文件失败', e);
            }
          }
        }
      }

      if (nfoContent == null) {
        logger.d('NfoScraperService: 未找到 NFO 文件');
        return null;
      }

      // 解析 NFO 内容
      final nfoMetadata = _parseNfoContent(nfoContent);

      // 查找本地图片
      final localImages = await _findLocalImages(
        files,
        videoBaseName,
        fileSystem,
        videoDir,
      );

      return NfoMetadata(
        title: nfoMetadata.title,
        originalTitle: nfoMetadata.originalTitle,
        year: nfoMetadata.year,
        plot: nfoMetadata.plot,
        rating: nfoMetadata.rating,
        runtime: nfoMetadata.runtime,
        genres: nfoMetadata.genres,
        director: nfoMetadata.director,
        actors: nfoMetadata.actors,
        studio: nfoMetadata.studio,
        tmdbId: nfoMetadata.tmdbId,
        imdbId: nfoMetadata.imdbId,
        posterPath: localImages['poster'],
        fanartPath: localImages['fanart'],
        thumbPath: localImages['thumb'],
        seasonNumber: nfoMetadata.seasonNumber,
        episodeNumber: nfoMetadata.episodeNumber,
        episodeTitle: nfoMetadata.episodeTitle,
        aired: nfoMetadata.aired,
      );
    } catch (e) {
      logger.e('NfoScraperService: 刮削失败', e);
      return null;
    }
  }

  /// 检查是否是匹配的 NFO 文件
  bool _isMatchingNfo(String fileName, String videoBaseName) {
    for (final ext in _nfoExtensions) {
      if (fileName == '${videoBaseName.toLowerCase()}$ext') {
        return true;
      }
    }
    return false;
  }

  /// 读取文件内容为字符串
  Future<String> _readFileAsString(NasFileSystem fileSystem, String path) async {
    final stream = await fileSystem.getFileStream(path);
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      // 限制文件大小，防止读取超大文件
      if (bytes.length > 1024 * 1024) { // 1MB 限制
        throw Exception('NFO 文件过大');
      }
    }
    return utf8.decode(bytes);
  }

  /// 获取父目录路径
  String _getParentPath(String path) {
    // 处理 Windows 和 Unix 路径分隔符
    final lastSeparator = path.lastIndexOf('/');
    final lastBackslash = path.lastIndexOf('\\');
    final separator = lastSeparator > lastBackslash ? lastSeparator : lastBackslash;

    if (separator > 0) {
      return path.substring(0, separator);
    }
    return path;
  }

  /// 获取文件基础名（不含扩展名）
  String _getBaseName(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex > 0) {
      return fileName.substring(0, dotIndex);
    }
    return fileName;
  }

  /// 解析 NFO 内容
  NfoMetadata _parseNfoContent(String content) {
    try {
      final document = XmlDocument.parse(content);
      final root = document.rootElement;

      // 判断是电影还是剧集
      final isEpisode = root.name.local == 'episodedetails';

      return NfoMetadata(
        title: _getElementText(root, 'title'),
        originalTitle: _getElementText(root, 'originaltitle'),
        year: _parseYear(root),
        plot: _getElementText(root, 'plot') ?? _getElementText(root, 'outline'),
        rating: _parseRating(root),
        runtime: _parseInt(_getElementText(root, 'runtime')),
        genres: _getGenres(root),
        director: _getElementText(root, 'director'),
        actors: _getActors(root),
        studio: _getElementText(root, 'studio'),
        tmdbId: _parseTmdbId(root),
        imdbId: _getElementText(root, 'imdbid') ?? _getElementText(root, 'imdb'),
        seasonNumber: isEpisode ? _parseInt(_getElementText(root, 'season')) : null,
        episodeNumber: isEpisode ? _parseInt(_getElementText(root, 'episode')) : null,
        episodeTitle: isEpisode ? _getElementText(root, 'title') : null,
        aired: _getElementText(root, 'aired') ?? _getElementText(root, 'premiered'),
      );
    } catch (e) {
      logger.e('NfoScraperService: 解析 NFO XML 失败', e);
      return NfoMetadata();
    }
  }

  /// 获取元素文本
  String? _getElementText(XmlElement root, String name) {
    try {
      final element = root.findElements(name).firstOrNull;
      if (element != null) {
        final text = element.innerText.trim();
        return text.isNotEmpty ? text : null;
      }
    } catch (_) {}
    return null;
  }

  /// 解析年份
  int? _parseYear(XmlElement root) {
    // 尝试从 year 元素获取
    var yearStr = _getElementText(root, 'year');
    if (yearStr != null) {
      return int.tryParse(yearStr);
    }

    // 尝试从 premiered 或 aired 获取
    final premiered = _getElementText(root, 'premiered') ??
        _getElementText(root, 'aired') ??
        _getElementText(root, 'releasedate');
    if (premiered != null && premiered.length >= 4) {
      return int.tryParse(premiered.substring(0, 4));
    }

    return null;
  }

  /// 解析评分
  double? _parseRating(XmlElement root) {
    // 尝试从 rating 元素获取
    var ratingStr = _getElementText(root, 'rating');
    if (ratingStr != null) {
      return double.tryParse(ratingStr);
    }

    // 尝试从 ratings/rating 获取
    try {
      final ratings = root.findElements('ratings').firstOrNull;
      if (ratings != null) {
        final rating = ratings.findElements('rating').firstOrNull;
        if (rating != null) {
          final value = rating.findElements('value').firstOrNull;
          if (value != null) {
            return double.tryParse(value.innerText.trim());
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// 获取类型列表
  List<String>? _getGenres(XmlElement root) {
    try {
      final genres = root.findElements('genre').map((e) => e.innerText.trim()).toList();
      return genres.isNotEmpty ? genres : null;
    } catch (_) {
      return null;
    }
  }

  /// 获取演员列表
  List<String>? _getActors(XmlElement root) {
    try {
      final actors = <String>[];
      for (final actor in root.findElements('actor')) {
        final name = actor.findElements('name').firstOrNull?.innerText.trim();
        if (name != null && name.isNotEmpty) {
          actors.add(name);
        }
      }
      return actors.isNotEmpty ? actors : null;
    } catch (_) {
      return null;
    }
  }

  /// 解析 TMDB ID
  int? _parseTmdbId(XmlElement root) {
    // 从 tmdbid 元素获取
    var tmdbStr = _getElementText(root, 'tmdbid');
    if (tmdbStr != null) {
      return int.tryParse(tmdbStr);
    }

    // 从 uniqueid 获取
    try {
      for (final uniqueid in root.findElements('uniqueid')) {
        final type = uniqueid.getAttribute('type')?.toLowerCase();
        if (type == 'tmdb') {
          return int.tryParse(uniqueid.innerText.trim());
        }
      }
    } catch (_) {}

    return null;
  }

  int? _parseInt(String? value) {
    if (value == null) return null;
    return int.tryParse(value);
  }

  /// 查找本地图片
  Future<Map<String, String?>> _findLocalImages(
    List<FileItem> files,
    String videoBaseName,
    NasFileSystem fileSystem,
    String videoDir,
  ) async {
    String? posterPath;
    String? fanartPath;
    String? thumbPath;

    for (final file in files) {
      if (file.isDirectory) continue;

      final fileName = file.name.toLowerCase();
      final baseName = _getBaseName(fileName);

      // 检查是否是图片文件
      bool isImage = false;
      for (final ext in _imageExtensions) {
        if (fileName.endsWith(ext)) {
          isImage = true;
          break;
        }
      }
      if (!isImage) continue;

      // 检查是否是与视频同名的图片
      if (baseName == videoBaseName.toLowerCase()) {
        posterPath ??= file.path;
        continue;
      }

      // 检查海报模式
      if (posterPath == null) {
        for (final pattern in _posterPatterns) {
          if (baseName.contains(pattern) || baseName == pattern) {
            posterPath = file.path;
            break;
          }
        }
      }

      // 检查背景图模式
      if (fanartPath == null) {
        for (final pattern in _fanartPatterns) {
          if (baseName.contains(pattern) || baseName == pattern) {
            fanartPath = file.path;
            break;
          }
        }
      }

      // 检查缩略图模式
      if (thumbPath == null) {
        for (final pattern in _thumbPatterns) {
          if (baseName.contains(pattern) || baseName == pattern) {
            thumbPath = file.path;
            break;
          }
        }
      }
    }

    return {
      'poster': posterPath,
      'fanart': fanartPath,
      'thumb': thumbPath,
    };
  }

  /// 获取图片 URL（通过 NAS 适配器）
  Future<String?> getImageUrl({
    required NasFileSystem fileSystem,
    required String imagePath,
  }) async {
    try {
      // 尝试获取图片的下载 URL 或缩略图 URL
      return await fileSystem.getFileUrl(imagePath);
    } catch (e) {
      logger.w('NfoScraperService: 获取图片 URL 失败', e);
      return null;
    }
  }
}
