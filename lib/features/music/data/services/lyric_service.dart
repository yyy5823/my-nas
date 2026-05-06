import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;

/// 单个字 / 音节（逐字歌词）
class LyricSyllable {
  const LyricSyllable({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final Duration start;
  final Duration end;

  LyricSyllable copyWith({String? text, Duration? start, Duration? end}) =>
      LyricSyllable(
        text: text ?? this.text,
        start: start ?? this.start,
        end: end ?? this.end,
      );
}

/// 行所属声部（保留给 TTML 等对唱格式使用，普通 LRC 无此信息）
enum LyricVoice { primary, secondary }

/// 歌词格式（用于 UI 决定渲染策略）
enum LyricsFormat {
  /// 无时间戳的纯文本
  plain,

  /// 行级 LRC：[mm:ss.xx]text
  lineLevel,

  /// 字级：A2 扩展 LRC（`<mm:ss.xx>word`）或 KRC（`<offset,duration,0>word`）
  wordLevel;

  bool get isSynced => this != LyricsFormat.plain;

  /// 通过扫描内容探测格式。仅看是否存在字级 / 行级时间标记。
  static LyricsFormat detect(String? content) {
    if (content == null || content.isEmpty) return LyricsFormat.plain;
    if (RegExp(r'<\d+:\d+(\.\d+)?>').hasMatch(content)) {
      return LyricsFormat.wordLevel;
    }
    if (RegExp(r'<\d+,\d+(,\d+)?>').hasMatch(content)) {
      return LyricsFormat.wordLevel;
    }
    if (RegExp(r'\[\d+:\d+(\.\d+)?\]').hasMatch(content)) {
      return LyricsFormat.lineLevel;
    }
    return LyricsFormat.plain;
  }
}

/// 歌词行
class LyricLine {
  const LyricLine({
    required this.time,
    required this.text,
    this.syllables,
    this.voice = LyricVoice.primary,
    this.endTime,
  });

  /// 时间点（行开始）
  final Duration time;

  /// 歌词文本（字级时为各 syllable 拼接）
  final String text;

  /// 字级数据；null/空 表示行级歌词
  final List<LyricSyllable>? syllables;

  /// 声部归属，默认主声部
  final LyricVoice voice;

  /// 行结束时间。字级行外部解析时填最后一字 end；行级行可由下一行 timestamp 推得
  final Duration? endTime;

  bool get isWordLevel => syllables != null && syllables!.isNotEmpty;

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
      // 获取音乐文件所在目录（NAS 路径使用 / 分隔符）
      final dir = p.posix.dirname(musicPath);
      final baseName = p.posix.basenameWithoutExtension(musicName);

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
            // NAS 路径始终使用 / 分隔符，不使用平台特定分隔符
            final lrcPath = p.posix.join(dir, fileName);
            logger.i('LyricService: 找到歌词文件 $lrcPath');

            // 直接通过文件系统读取歌词文件
            // 避免 SMB/WebDAV 等协议的 URL 无法被 HttpClient 处理
            return await _readAndParseLyrics(fileSystem, lrcPath);
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

  /// 通过文件系统直接读取并解析歌词
  /// 支持 SMB、WebDAV 等各种协议
  Future<LyricData> _readAndParseLyrics(
    NasFileSystem fileSystem,
    String lrcPath,
  ) async {
    try {
      // 通过文件系统获取文件流并读取内容
      final stream = await fileSystem.getFileStream(lrcPath);
      final bytes = await stream.fold<List<int>>(
        [],
        (previous, element) => previous..addAll(element),
      );

      if (bytes.isEmpty) {
        logger.w('LyricService: 歌词文件为空 $lrcPath');
        return LyricData.empty;
      }

      // 智能检测并解码歌词内容
      final content = await _decodeBytes(bytes);
      logger.d('LyricService: 成功读取歌词文件，共 ${bytes.length} 字节');
      return parseLrc(content);
    } on Exception catch (e) {
      logger.e('LyricService: 读取歌词文件失败 $lrcPath', e);
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
        final gbkCodec = const GbkCodec();
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
        final big5Codec = const Big5Codec();
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
  ///
  /// 同时支持：
  /// - 行级 LRC：`[mm:ss.xx]text`
  /// - A2 扩展逐字 LRC：`[mm:ss.xx]<mm:ss.xx>w<mm:ss.xx>w...`
  /// - 元数据：`[ti:][ar:][al:]`
  LyricData parseLrc(String content) {
    final lines = <LyricLine>[];
    String? title;
    String? artist;
    String? album;

    // 行首时间标签
    final headRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    // 元数据
    final metaRegex = RegExp(r'\[(ti|ar|al|by|offset):([^\]]*)\]', caseSensitive: false);

    for (final raw in content.split('\n')) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;

      // 元数据行
      final metaMatch = metaRegex.firstMatch(trimmed);
      if (metaMatch != null && headRegex.firstMatch(trimmed) == null) {
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

      // 行首可能挂多个时间戳：[00:01.23][00:45.67]text
      final heads = headRegex.allMatches(trimmed).toList();
      if (heads.isEmpty) continue;

      // 取最后一个行首时间戳之后的内容作为正文（可能含字级标记）
      final body = trimmed.substring(heads.last.end);

      for (final head in heads) {
        final lineStart = _parseTimestamp(
          head.group(1)!,
          head.group(2)!,
          head.group(3),
        );

        // 优先尝试字级解析
        final wordLevel = _parseWordLevelBody(body, lineStart);
        if (wordLevel != null) {
          lines.add(wordLevel);
          continue;
        }

        // 行级：去除内嵌的字级标记残留（虽然此分支理论上不会有）
        final plain = body
            .replaceAll(RegExp(r'<\d{1,2}:\d{2}(?:[.:]\d{1,3})?>'), '')
            .replaceAll(RegExp(r'<\d+,\d+(?:,\d+)?>'), '')
            .trim();
        if (plain.isEmpty) continue;

        lines.add(LyricLine(time: lineStart, text: plain));
      }
    }

    // 按时间排序
    lines.sort((a, b) => a.time.compareTo(b.time));

    // 行级行兜底 endTime = 下一行 time（字级行已在解析时填好）
    final filled = <LyricLine>[];
    for (var i = 0; i < lines.length; i++) {
      final cur = lines[i];
      if (cur.endTime != null || i == lines.length - 1) {
        filled.add(cur);
      } else {
        filled.add(LyricLine(
          time: cur.time,
          text: cur.text,
          syllables: cur.syllables,
          voice: cur.voice,
          endTime: lines[i + 1].time,
        ));
      }
    }

    logger.d('LyricService: 解析完成，共 ${filled.length} 行歌词');
    return LyricData(
      lines: filled,
      title: title,
      artist: artist,
      album: album,
    );
  }

  /// 把一行 body 解析为字级 LyricLine；不含字级标记时返回 null。
  ///
  /// A2 标记：`<mm:ss.xx>w<mm:ss.xx>w...`
  /// 行尾压轴时间戳（最后一个 mark 之后无文字）= 行 end，不算独立字。
  LyricLine? _parseWordLevelBody(String body, Duration lineStart) {
    final inlineRegex =
        RegExp(r'<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>');
    final marks = inlineRegex.allMatches(body).toList();
    if (marks.isEmpty) return null;

    final syllables = <LyricSyllable>[];
    for (var i = 0; i < marks.length; i++) {
      final mark = marks[i];
      final start = _parseTimestamp(
        mark.group(1)!,
        mark.group(2)!,
        mark.group(3),
      );
      final textStart = mark.end;
      final textEnd =
          (i + 1 < marks.length) ? marks[i + 1].start : body.length;
      final chunk = body.substring(textStart, textEnd);

      // 行尾压轴时间戳：把上一字的 end 推到这个时间点
      if (chunk.isEmpty) {
        if (syllables.isNotEmpty) {
          final last = syllables.last;
          if (start > last.end) {
            syllables[syllables.length - 1] =
                last.copyWith(end: start);
          }
        }
        continue;
      }
      syllables.add(LyricSyllable(text: chunk, start: start, end: start));
    }

    if (syllables.isEmpty) return null;

    // 后处理：每字 end = 下一字 start；最后一字若无压轴则 +400ms 兜底
    for (var i = 0; i < syllables.length - 1; i++) {
      final cur = syllables[i];
      final nextStart = syllables[i + 1].start;
      if (nextStart > cur.end) {
        syllables[i] = cur.copyWith(end: nextStart);
      }
    }
    final last = syllables.last;
    if (last.end <= last.start) {
      syllables[syllables.length - 1] = last.copyWith(
        end: last.start + const Duration(milliseconds: 400),
      );
    }

    final fullText = syllables.map((s) => s.text).join();
    if (fullText.trim().isEmpty) return null;

    return LyricLine(
      time: lineStart,
      text: fullText,
      syllables: syllables,
      endTime: syllables.last.end,
    );
  }

  /// 解析时间戳。`frac` 长度 == 3 时按毫秒，其它按厘秒（×10）。
  Duration _parseTimestamp(String min, String sec, String? frac) {
    final m = int.tryParse(min) ?? 0;
    final s = int.tryParse(sec) ?? 0;
    if (frac == null || frac.isEmpty) {
      return Duration(minutes: m, seconds: s);
    }
    final f = int.tryParse(frac) ?? 0;
    final ms = frac.length == 3 ? f : f * 10; // 厘秒 → 毫秒
    return Duration(minutes: m, seconds: s, milliseconds: ms);
  }
}
