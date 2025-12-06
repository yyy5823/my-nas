import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;

/// 歌词行
class LyricLine {
  const LyricLine({
    required this.time,
    required this.text,
  });

  /// 时间点
  final Duration time;

  /// 歌词文本
  final String text;

  @override
  String toString() => '[${time.inMilliseconds}] $text';
}

/// 歌词数据
class LyricData {
  const LyricData({
    required this.lines,
    this.title,
    this.artist,
    this.album,
  });

  /// 空歌词
  static const empty = LyricData(lines: []);

  /// 歌词行列表（按时间排序）
  final List<LyricLine> lines;

  /// 歌曲标题
  final String? title;

  /// 艺术家
  final String? artist;

  /// 专辑
  final String? album;

  /// 是否为空
  bool get isEmpty => lines.isEmpty;

  /// 是否有内容
  bool get isNotEmpty => lines.isNotEmpty;

  /// 根据当前播放位置获取当前行索引
  int getCurrentLineIndex(Duration position) {
    if (lines.isEmpty) return -1;

    for (var i = lines.length - 1; i >= 0; i--) {
      if (position >= lines[i].time) {
        return i;
      }
    }
    return -1;
  }

  /// 根据当前播放位置获取当前行
  LyricLine? getCurrentLine(Duration position) {
    final index = getCurrentLineIndex(position);
    return index >= 0 ? lines[index] : null;
  }
}

/// 歌词服务
class LyricService {
  factory LyricService() => _instance ??= LyricService._();
  LyricService._();

  static LyricService? _instance;

  /// 从文件系统查找并加载歌词
  Future<LyricData> loadLyrics({
    required String musicPath,
    required String musicName,
    required NasFileSystem fileSystem,
  }) async {
    try {
      // 获取音乐文件所在目录
      final dir = p.dirname(musicPath);
      final baseName = p.basenameWithoutExtension(musicName);

      // 尝试不同的歌词文件名格式
      final possibleNames = [
        '$baseName.lrc',
        '$baseName.LRC',
      ];

      logger.d('LyricService: 在目录 $dir 中查找歌词文件 (baseName: $baseName)');

      // 列出目录下的文件
      final files = await fileSystem.listDirectory(dir);

      for (final file in files) {
        final fileName = file.name;
        for (final possibleName in possibleNames) {
          if (fileName.toLowerCase() == possibleName.toLowerCase()) {
            final lrcPath = p.join(dir, fileName);
            logger.i('LyricService: 找到歌词文件 $lrcPath');

            // 下载并解析歌词
            final url = await fileSystem.getFileUrl(lrcPath);
            return await _downloadAndParseLyrics(url);
          }
        }
      }

      logger.d('LyricService: 未找到歌词文件');
      return LyricData.empty;
    } on Exception catch (e) {
      logger.e('LyricService: 加载歌词失败', e);
      return LyricData.empty;
    }
  }

  /// 下载并解析歌词
  Future<LyricData> _downloadAndParseLyrics(String url) async {
    try {
      final client = HttpClient()
      // 允许自签名证书
      ..badCertificateCallback = (_, _, _) => true;

      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode == 200) {
        final bytes = await response.fold<List<int>>(
          [],
          (previous, element) => previous..addAll(element),
        );

        // 智能检测并解码歌词内容
        final content = await _decodeBytes(bytes);

        client.close();
        return parseLrc(content);
      }

      client.close();
      return LyricData.empty;
    } on Exception catch (e) {
      logger.e('LyricService: 下载歌词失败', e);
      return LyricData.empty;
    }
  }

  /// 智能检测字节编码并解码为字符串
  /// 支持 UTF-8、UTF-16、GBK/GB2312、Latin-1 等编码
  Future<String> _decodeBytes(List<int> bytes) async {
    if (bytes.isEmpty) return '';

    // 1. 检查 BOM (Byte Order Mark)
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      // UTF-8 with BOM
      logger.d('LyricService: 检测到 UTF-8 BOM');
      return utf8.decode(bytes.sublist(3));
    }
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        // UTF-16 LE BOM
        logger.d('LyricService: 检测到 UTF-16 LE BOM');
        return _decodeUtf16Le(bytes.sublist(2));
      }
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        // UTF-16 BE BOM
        logger.d('LyricService: 检测到 UTF-16 BE BOM');
        return _decodeUtf16Be(bytes.sublist(2));
      }
    }

    // 2. 尝试 UTF-8 解码
    try {
      final decoded = utf8.decode(bytes, allowMalformed: false);
      // 检查解码结果是否包含有效的中文字符或看起来正常
      if (_looksValidUtf8(decoded)) {
        logger.d('LyricService: 成功使用 UTF-8 解码');
        return decoded;
      }
    } on FormatException catch (_) {
      // UTF-8 解码失败，继续尝试其他编码
    }

    // 3. 尝试 GBK/GB2312 解码（中文 Windows 常用）
    final uint8Bytes = Uint8List.fromList(bytes);

    // 根据平台选择不同的解码方式
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    if (isDesktop) {
      // 桌面平台使用 enough_convert（纯 Dart 实现）
      try {
        final gbkCodec = const GbkCodec(allowInvalid: false);
        final decoded = gbkCodec.decode(bytes);
        if (decoded.isNotEmpty && _looksValidGbk(decoded)) {
          logger.d('LyricService: 成功使用 GBK 解码 (enough_convert)');
          return decoded;
        }
      } on Exception catch (e) {
        logger.d('LyricService: GBK 解码失败 (enough_convert): $e');
      }

      // 尝试 Big5 解码（繁体中文）
      try {
        final big5Codec = const Big5Codec(allowInvalid: false);
        final decoded = big5Codec.decode(bytes);
        if (decoded.isNotEmpty && _containsChinese(decoded)) {
          logger.d('LyricService: 成功使用 Big5 解码 (enough_convert)');
          return decoded;
        }
      } on Exception catch (e) {
        logger.d('LyricService: Big5 解码失败 (enough_convert): $e');
      }
    } else {
      // 移动平台使用 charset_converter（原生实现）
      try {
        final decoded = await CharsetConverter.decode('GBK', uint8Bytes);
        if (decoded.isNotEmpty && _looksValidGbk(decoded)) {
          logger.d('LyricService: 成功使用 GBK 解码');
          return decoded;
        }
      } on Exception catch (e) {
        logger.d('LyricService: GBK 解码失败: $e');
      }

      // 4. 尝试 GB18030 解码（GBK 的超集）
      try {
        final decoded = await CharsetConverter.decode('GB18030', uint8Bytes);
        if (decoded.isNotEmpty) {
          logger.d('LyricService: 成功使用 GB18030 解码');
          return decoded;
        }
      } on Exception catch (e) {
        logger.d('LyricService: GB18030 解码失败: $e');
      }

      // 5. 尝试 Big5 解码（繁体中文）
      try {
        final decoded = await CharsetConverter.decode('Big5', uint8Bytes);
        if (decoded.isNotEmpty && _containsChinese(decoded)) {
          logger.d('LyricService: 成功使用 Big5 解码');
          return decoded;
        }
      } on Exception catch (e) {
        logger.d('LyricService: Big5 解码失败: $e');
      }
    }

    // 6. 最后尝试 UTF-8 with allowMalformed
    logger.d('LyricService: 使用 UTF-8 (allowMalformed) 解码');
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 检查 UTF-8 解码结果是否看起来正确
  bool _looksValidUtf8(String text) {
    // 如果包含替换字符，说明有解码错误
    if (text.contains('\uFFFD')) return false;
    // 如果包含常见的 GBK 乱码特征，说明可能不是 UTF-8
    // GBK 编码的中文在 UTF-8 下会产生特定的乱码模式
    if (text.contains('鏈') || text.contains('鐜') || text.contains('闈')) {
      return false;
    }
    return true;
  }

  /// 检查 GBK 解码结果是否看起来正确
  bool _looksValidGbk(String text) {
    // 检查是否包含中文字符
    if (_containsChinese(text)) return true;
    // 检查是否全是 ASCII 字符（也是有效的）
    if (text.codeUnits.every((c) => c < 128)) return true;
    return false;
  }

  /// 检查字符串是否包含中文字符
  bool _containsChinese(String text) {
    // 中文 Unicode 范围：\u4e00-\u9fff
    final chineseRegex = RegExp(r'[\u4e00-\u9fff]');
    return chineseRegex.hasMatch(text);
  }

  /// UTF-16 LE 解码
  String _decodeUtf16Le(List<int> bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length - 1; i += 2) {
      final codeUnit = bytes[i] | (bytes[i + 1] << 8);
      buffer.writeCharCode(codeUnit);
    }
    return buffer.toString();
  }

  /// UTF-16 BE 解码
  String _decodeUtf16Be(List<int> bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length - 1; i += 2) {
      final codeUnit = (bytes[i] << 8) | bytes[i + 1];
      buffer.writeCharCode(codeUnit);
    }
    return buffer.toString();
  }

  /// 解析歌词（自动检测格式：LRC 或纯文本）
  LyricData parseLyrics(String content) {
    // 检测是否为 LRC 格式（包含时间标签）
    final timeRegex = RegExp(r'\[\d{1,2}:\d{2}');
    if (timeRegex.hasMatch(content)) {
      return parseLrc(content);
    }

    // 纯文本歌词（没有时间标签）
    final lines = <LyricLine>[];
    final textLines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();

    // 为纯文本歌词生成等间距时间点（假设每行 4 秒）
    const secondsPerLine = 4;
    for (var i = 0; i < textLines.length; i++) {
      lines.add(LyricLine(
        time: Duration(seconds: i * secondsPerLine),
        text: textLines[i].trim(),
      ));
    }

    logger.d('LyricService: 解析纯文本歌词，共 ${lines.length} 行');
    return LyricData(lines: lines);
  }

  /// 解析 LRC 格式歌词
  LyricData parseLrc(String content) {
    final lines = <LyricLine>[];
    String? title;
    String? artist;
    String? album;

    // LRC 时间格式: [mm:ss.xx] 或 [mm:ss:xx] 或 [mm:ss]
    final timeRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    // 元数据格式: [ti:标题] [ar:艺术家] [al:专辑]
    final metaRegex = RegExp(r'\[(ti|ar|al|by|offset):([^\]]*)\]', caseSensitive: false);

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 检查元数据
      final metaMatch = metaRegex.firstMatch(trimmed);
      if (metaMatch != null) {
        final key = metaMatch.group(1)!.toLowerCase();
        final value = metaMatch.group(2)!.trim();
        switch (key) {
          case 'ti':
            title = value;
          case 'ar':
            artist = value;
          case 'al':
            album = value;
        }
        continue;
      }

      // 解析时间标签和歌词
      final timeMatches = timeRegex.allMatches(trimmed).toList();
      if (timeMatches.isEmpty) continue;

      // 获取歌词文本（去除所有时间标签）
      var text = trimmed;
      for (final match in timeMatches.reversed) {
        text = text.replaceRange(match.start, match.end, '');
      }
      text = text.trim();

      // 跳过空歌词行
      if (text.isEmpty) continue;

      // 为每个时间标签创建歌词行
      for (final match in timeMatches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final millisStr = match.group(3);
        var millis = 0;
        if (millisStr != null) {
          // 补齐到3位
          final padded = millisStr.padRight(3, '0');
          millis = int.parse(padded.substring(0, 3));
        }

        final time = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: millis,
        );

        lines.add(LyricLine(time: time, text: text));
      }
    }

    // 按时间排序
    lines.sort((a, b) => a.time.compareTo(b.time));

    logger.d('LyricService: 解析完成，共 ${lines.length} 行歌词');
    return LyricData(
      lines: lines,
      title: title,
      artist: artist,
      album: album,
    );
  }
}
