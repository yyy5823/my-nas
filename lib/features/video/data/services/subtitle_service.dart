import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 支持的字幕格式
const subtitleExtensions = ['.srt', '.ass', '.ssa', '.vtt', '.sub'];

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
class SubtitleService {
  SubtitleService._();

  static SubtitleService? _instance;
  static SubtitleService get instance => _instance ??= SubtitleService._();

  /// 查找视频对应的字幕文件
  ///
  /// 在视频所在目录查找同名或相关的字幕文件
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

      // 列出目录中的文件
      final files = await fileSystem.listDirectory(videoDir);

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

        final url = await fileSystem.getFileUrl(file.path);

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
    } on Exception catch (e) {
      logger.e('SubtitleService: 查找字幕失败', e);
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
    String remaining = subtitleBaseName;

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
