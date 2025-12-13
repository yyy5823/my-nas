import 'dart:async';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 支持的字幕格式
const subtitleExtensions = ['.srt', '.ass', '.ssa', '.vtt', '.sub'];

/// 字幕搜索超时时间
const _subtitleSearchTimeout = Duration(seconds: 15);

/// 字幕项
class SubtitleItem {
  const SubtitleItem({
    required this.name,
    required this.path,
    required this.url,
    required this.format,
    this.language,
  });

  /// 字幕名称
  final String name;

  /// 字幕路径
  final String path;

  /// 字幕URL
  final String url;

  /// 字幕格式 (srt, ass, vtt 等)
  final String format;

  /// 语言 (从文件名解析)
  final String? language;

  @override
  String toString() => 'SubtitleItem($name, $format, $language)';
}

/// 字幕服务 - 用于查找和管理视频字幕
///
/// 支持两种方式获取字幕：
/// 1. 从本地 SQLite 缓存获取（毫秒级响应，推荐）
/// 2. 实时扫描文件系统（耗时，作为后备方案）
class SubtitleService {
  factory SubtitleService() => _instance ??= SubtitleService._();
  SubtitleService._();

  static SubtitleService? _instance;

  final VideoDatabaseService _dbService = VideoDatabaseService();

  /// 查找视频对应的字幕文件
  ///
  /// 在视频所在目录查找同名或相关的字幕文件
  /// 添加超时保护和错误处理，避免大目录或网络问题导致崩溃
  Future<List<SubtitleItem>> findSubtitles({
    required String videoPath,
    required String videoName,
    required NasFileSystem fileSystem,
  }) async {
    final subtitles = <SubtitleItem>[];

    try {
      // 获取视频所在目录
      final videoDir = _getDirectory(videoPath);
      final videoBaseName = _getBaseName(videoName);

      logger.d('SubtitleService: 在 $videoDir 中查找字幕，视频: $videoBaseName');

      // 列出目录中的文件（带超时保护）
      List<FileItem> files;
      try {
        files = await fileSystem.listDirectory(videoDir).timeout(
              _subtitleSearchTimeout,
              onTimeout: () {
                logger.w('SubtitleService: 目录列表超时，跳过字幕搜索: $videoDir');
                return <FileItem>[];
              },
            );
        // ignore: avoid_catches_without_on_clauses
      } catch (e, st) {
        // 捕获所有错误（包括 Error），防止目录列表失败导致闪退
        AppError.ignore(e, st, '目录列表失败，字幕搜索跳过: $videoDir');
        return subtitles;
      }

      // 限制处理的文件数量，避免超大目录导致性能问题
      const maxFilesToProcess = 500;
      if (files.length > maxFilesToProcess) {
        logger.w('SubtitleService: 目录文件数过多 (${files.length})，仅处理前 $maxFilesToProcess 个');
        files = files.take(maxFilesToProcess).toList();
      }

      for (final file in files) {
        if (file.isDirectory) continue;

        final fileName = file.name.toLowerCase();
        final ext = _getExtension(fileName);

        // 检查是否是字幕文件
        if (!subtitleExtensions.contains(ext)) continue;

        // 检查是否与视频相关
        final subtitleBaseName = _getBaseName(file.name);
        if (!_isRelatedSubtitle(videoBaseName, subtitleBaseName)) continue;

        // 解析语言
        final language = _parseLanguage(file.name, videoBaseName);

        // 获取文件 URL（带超时保护）
        String url;
        try {
          url = await fileSystem.getFileUrl(file.path).timeout(
                const Duration(seconds: 5),
                onTimeout: () {
                  logger.w('SubtitleService: 获取字幕URL超时: ${file.path}');
                  return '';
                },
              );
          // ignore: avoid_catches_without_on_clauses
        } catch (e) {
          logger.w('SubtitleService: 获取字幕URL失败: ${file.path}', e);
          continue;
        }

        if (url.isEmpty) continue;

        subtitles.add(SubtitleItem(
          name: file.name,
          path: file.path,
          url: url,
          format: ext.substring(1), // 去掉点号
          language: language,
        ));

        logger.d('SubtitleService: 找到字幕 ${file.name} (语言: $language)');
      }

      // 按语言排序（中文优先，然后英文）
      subtitles.sort((a, b) {
        final aScore = _getLanguageScore(a.language);
        final bScore = _getLanguageScore(b.language);
        return aScore.compareTo(bScore);
      });

      logger.i('SubtitleService: 共找到 ${subtitles.length} 个字幕');
      // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      // 使用 catch 而非 on Exception catch 捕获所有错误
      // 字幕搜索失败不应影响视频播放
      AppError.ignore(e, st, '字幕搜索失败，不影响播放');
    }

    return subtitles;
  }

  /// 从本地缓存获取字幕（毫秒级响应）
  ///
  /// 优先使用此方法获取字幕，速度快且不依赖网络。
  /// 返回的字幕列表已按语言排序（中文优先）。
  ///
  /// [sourceId] 源ID
  /// [videoPath] 视频文件路径
  /// [fileSystem] 文件系统，用于获取字幕文件URL
  ///
  /// 如果缓存中没有字幕，会自动回退到实时扫描。
  Future<List<SubtitleItem>> getSubtitles({
    required String sourceId,
    required String videoPath,
    required String videoName,
    required NasFileSystem fileSystem,
  }) async {
    // 1. 先从数据库缓存获取（毫秒级）
    final cachedSubtitles = await _getSubtitlesFromCache(
      sourceId: sourceId,
      videoPath: videoPath,
      fileSystem: fileSystem,
    );

    if (cachedSubtitles.isNotEmpty) {
      logger.i('SubtitleService: 从缓存获取到 ${cachedSubtitles.length} 个字幕');
      return cachedSubtitles;
    }

    // 2. 缓存中没有，回退到实时扫描（可能较慢）
    logger.d('SubtitleService: 缓存中无字幕，回退到实时扫描');
    return findSubtitles(
      videoPath: videoPath,
      videoName: videoName,
      fileSystem: fileSystem,
    );
  }

  /// 仅从数据库缓存获取字幕（不回退到实时扫描）
  ///
  /// 适用于只想要快速获取缓存数据的场景
  Future<List<SubtitleItem>> _getSubtitlesFromCache({
    required String sourceId,
    required String videoPath,
    required NasFileSystem fileSystem,
  }) async {
    final subtitles = <SubtitleItem>[];

    try {
      // 从数据库查询
      final indexes = await _dbService.getSubtitlesForVideo(sourceId, videoPath);

      if (indexes.isEmpty) {
        return subtitles;
      }

      // 并行获取所有字幕的 URL
      final futures = indexes.map((index) async {
        try {
          final url = await fileSystem.getFileUrl(index.subtitlePath).timeout(
                const Duration(seconds: 5),
                onTimeout: () {
                  logger.w('SubtitleService: 获取字幕URL超时: ${index.subtitlePath}');
                  return '';
                },
              );

          if (url.isNotEmpty) {
            return SubtitleItem(
              name: index.fileName,
              path: index.subtitlePath,
              url: url,
              format: index.format,
              language: index.language,
            );
          }
          // ignore: avoid_catches_without_on_clauses
        } catch (e) {
          logger.w('SubtitleService: 获取字幕URL失败: ${index.subtitlePath}', e);
        }
        return null;
      });

      final results = await Future.wait(futures);
      subtitles.addAll(results.whereType<SubtitleItem>());

      // 按语言排序（中文优先）
      subtitles.sort((a, b) {
        final aScore = _getLanguageScore(a.language);
        final bScore = _getLanguageScore(b.language);
        return aScore.compareTo(bScore);
      });
      // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      AppError.ignore(e, st, '从缓存获取字幕失败，不影响播放');
    }

    return subtitles;
  }

  /// 获取目录路径
  String _getDirectory(String path) {
    final lastSlash = path.lastIndexOf('/');
    if (lastSlash == -1) return '/';
    return path.substring(0, lastSlash);
  }

  /// 获取文件扩展名（小写）
  String _getExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1) return '';
    return fileName.substring(lastDot).toLowerCase();
  }

  /// 获取文件基础名（不含扩展名）
  String _getBaseName(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1) return fileName.toLowerCase();
    return fileName.substring(0, lastDot).toLowerCase();
  }

  /// 检查字幕是否与视频相关
  bool _isRelatedSubtitle(String videoBaseName, String subtitleBaseName) {
    // 完全匹配
    if (subtitleBaseName == videoBaseName) return true;

    // 字幕以视频名开头
    if (subtitleBaseName.startsWith(videoBaseName)) return true;

    // 视频以字幕名开头（处理带语言后缀的情况）
    if (videoBaseName.startsWith(subtitleBaseName)) return true;

    return false;
  }

  /// 从文件名解析语言
  String? _parseLanguage(String subtitleName, String videoBaseName) {
    // 常见的语言标记
    const languagePatterns = {
      // 中文
      'chs': '简体中文',
      'cht': '繁体中文',
      'sc': '简体中文',
      'tc': '繁体中文',
      'zh': '中文',
      'zh-cn': '简体中文',
      'zh-tw': '繁体中文',
      'zh-hans': '简体中文',
      'zh-hant': '繁体中文',
      'chinese': '中文',
      '简体': '简体中文',
      '繁体': '繁体中文',
      '中文': '中文',
      '简中': '简体中文',
      '繁中': '繁体中文',
      // 英文
      'en': 'English',
      'eng': 'English',
      'english': 'English',
      // 日文
      'ja': '日本語',
      'jp': '日本語',
      'jpn': '日本語',
      'japanese': '日本語',
      '日语': '日本語',
      // 韩文
      'ko': '한국어',
      'kor': '한국어',
      'korean': '한국어',
      '韩语': '한국어',
      // 其他
      'default': '默认',
    };

    // 移除视频基础名后剩余的部分
    final subtitleBaseName = _getBaseName(subtitleName);
    var remaining = subtitleBaseName;

    if (subtitleBaseName.startsWith(videoBaseName)) {
      remaining = subtitleBaseName.substring(videoBaseName.length);
    }

    // 移除常见分隔符
    remaining = remaining.replaceAll(RegExp(r'^[._\-\s]+'), '');
    remaining = remaining.toLowerCase();

    // 尝试匹配语言标记
    for (final entry in languagePatterns.entries) {
      if (remaining.contains(entry.key)) {
        return entry.value;
      }
    }

    // 如果没有匹配，返回剩余部分（如果有的话）
    if (remaining.isNotEmpty) {
      return remaining;
    }

    return null;
  }

  /// 获取语言排序分数（越小越优先）
  int _getLanguageScore(String? language) {
    if (language == null) return 100;

    final lang = language.toLowerCase();

    // 中文最优先
    if (lang.contains('中') || lang.contains('chs') || lang.contains('cht')) {
      return 0;
    }

    // 英文次之
    if (lang.contains('english') || lang.contains('eng') || lang == 'en') {
      return 10;
    }

    // 日文
    if (lang.contains('日') || lang.contains('jp')) {
      return 20;
    }

    return 50;
  }
}
