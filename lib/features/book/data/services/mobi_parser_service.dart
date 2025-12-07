import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:my_nas/core/utils/logger.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// MOBI 解析结果
class MobiParseResult {
  const MobiParseResult({
    required this.success,
    this.title,
    this.author,
    this.content,
    this.error,
  });

  factory MobiParseResult.failure(String error) => MobiParseResult(
        success: false,
        error: error,
      );

  factory MobiParseResult.fromContent({
    required String content,
    String? title,
    String? author,
  }) =>
      MobiParseResult(
        success: true,
        content: content,
        title: title,
        author: author,
      );

  final bool success;
  final String? title;
  final String? author;
  final String? content;
  final String? error;
}

/// MOBI/AZW3 解析服务
///
/// 支持的格式：
/// - MOBI (PalmDOC 压缩)
/// - AZW3 (KF8 格式)
///
/// 桌面平台优先使用 Calibre 的 ebook-convert 工具
/// 如果没有安装 Calibre，则使用内置解析器（仅支持简单格式）
class MobiParserService {
  factory MobiParserService() => _instance ??= MobiParserService._();
  MobiParserService._();

  static MobiParserService? _instance;

  /// 解析 MOBI/AZW3 文件
  Future<MobiParseResult> parse(Uint8List bytes, String fileName) async {
    // 桌面平台优先使用 Calibre
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final calibreResult = await _parseWithCalibre(bytes, fileName);
      if (calibreResult.success) {
        return calibreResult;
      }
      // Calibre 不可用，尝试内置解析器
      logger.i('Calibre 不可用，尝试内置解析器');
    }

    // 使用内置解析器
    return _parseWithBuiltIn(bytes);
  }

  /// 使用 Calibre 解析
  Future<MobiParseResult> _parseWithCalibre(
    Uint8List bytes,
    String fileName,
  ) async {
    // 检查 ebook-convert 是否可用
    final convertCmd = await _findCalibreConvert();
    if (convertCmd == null) {
      return MobiParseResult.failure('Calibre 未安装');
    }

    // 创建临时目录
    final tempDir = await getTemporaryDirectory();
    final workDir = Directory(
      path.join(
        tempDir.path,
        'mobi_parse_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    await workDir.create(recursive: true);

    try {
      // 写入临时文件
      final inputFile = File(path.join(workDir.path, fileName));
      await inputFile.writeAsBytes(bytes);

      // 转换为 TXT
      final outputFile = File(
        path.join(workDir.path, '${path.basenameWithoutExtension(fileName)}.txt'),
      );

      final result = await Process.run(
        convertCmd,
        [inputFile.path, outputFile.path],
      );

      if (result.exitCode != 0) {
        logger.e('Calibre 转换失败: ${result.stderr}');
        return MobiParseResult.failure('转换失败: ${result.stderr}');
      }

      // 读取转换后的内容
      if (await outputFile.exists()) {
        final content = await outputFile.readAsString();
        return MobiParseResult.fromContent(content: content);
      }

      return MobiParseResult.failure('转换后的文件不存在');
    } finally {
      // 清理临时目录
      try {
        await workDir.delete(recursive: true);
      } on Exception catch (e) {
        logger.w('清理临时目录失败', e);
      }
    }
  }

  /// 查找 Calibre 的 ebook-convert 命令
  Future<String?> _findCalibreConvert() async {
    final commands = <String>[];

    if (Platform.isMacOS) {
      commands.addAll([
        '/Applications/calibre.app/Contents/MacOS/ebook-convert',
        'ebook-convert',
      ]);
    } else if (Platform.isWindows) {
      commands.addAll([
        r'C:\Program Files\Calibre2\ebook-convert.exe',
        r'C:\Program Files (x86)\Calibre2\ebook-convert.exe',
        'ebook-convert',
      ]);
    } else {
      commands.add('ebook-convert');
    }

    for (final cmd in commands) {
      if (await _isCommandAvailable(cmd)) {
        return cmd;
      }
    }

    return null;
  }

  /// 检查命令是否可用
  Future<bool> _isCommandAvailable(String command) async {
    try {
      // 如果是完整路径，检查文件是否存在
      if (command.contains('/') || command.contains(r'\')) {
        return File(command).existsSync();
      }

      final whichCmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(whichCmd, [command]);
      return result.exitCode == 0;
    } on Exception catch (_) {
      return false;
    }
  }

  /// 使用内置解析器解析 MOBI
  Future<MobiParseResult> _parseWithBuiltIn(Uint8List bytes) async {
    try {
      // 验证 Palm Database 格式
      if (bytes.length < 78) {
        return MobiParseResult.failure('文件太小，不是有效的 MOBI 文件');
      }

      // 读取数据库名称（标题）
      final nameBytes = bytes.sublist(0, 32);
      final nullIndex = nameBytes.indexOf(0);
      final title = utf8.decode(
        nameBytes.sublist(0, nullIndex > 0 ? nullIndex : 32),
        allowMalformed: true,
      );

      // 检查类型和创建者 ID
      final type = String.fromCharCodes(bytes.sublist(60, 64));
      final creator = String.fromCharCodes(bytes.sublist(64, 68));

      if (type != 'BOOK' || creator != 'MOBI') {
        return MobiParseResult.failure('不是有效的 MOBI 文件');
      }

      // 读取记录数量
      final numRecords = _readUint16(bytes, 76);
      if (numRecords == 0) {
        return MobiParseResult.failure('MOBI 文件没有记录');
      }

      // 读取记录偏移表
      final recordOffsets = <int>[];
      for (var i = 0; i < numRecords; i++) {
        final offset = _readUint32(bytes, 78 + i * 8);
        recordOffsets.add(offset);
      }

      // 读取第一个记录（PalmDOC 头部）
      final record0Start = recordOffsets[0];
      final record0End =
          recordOffsets.length > 1 ? recordOffsets[1] : bytes.length;
      final record0 = bytes.sublist(record0Start, record0End);

      // 解析 PalmDOC 头部
      final compression = _readUint16(record0, 0);
      final textLength = _readUint32(record0, 4);
      final recordCount = _readUint16(record0, 8);

      // 检查是否有 MOBI 头部
      String? author;
      var textEncoding = 'cp1252';

      if (record0.length >= 132) {
        final mobiId = String.fromCharCodes(record0.sublist(16, 20));
        if (mobiId == 'MOBI') {
          // 读取编码
          final encoding = _readUint32(record0, 28);
          if (encoding == 65001) {
            textEncoding = 'utf-8';
          }

          // 检查 EXTH 头部
          final exthFlags = _readUint32(record0, 128);
          if ((exthFlags & 0x40) != 0) {
            // 有 EXTH 头部
            final mobiHeaderLength = _readUint32(record0, 20);
            final exthStart = 16 + mobiHeaderLength;
            if (record0.length > exthStart + 12) {
              author = _parseExthAuthor(record0, exthStart);
            }
          }
        }
      }

      // 解压文本记录
      final textBuffer = StringBuffer();
      final textRecordCount = recordCount < recordOffsets.length
          ? recordCount
          : recordOffsets.length - 1;

      for (var i = 1; i <= textRecordCount; i++) {
        if (i >= recordOffsets.length) break;

        final recordStart = recordOffsets[i];
        final recordEnd =
            i + 1 < recordOffsets.length ? recordOffsets[i + 1] : bytes.length;
        final recordData = bytes.sublist(recordStart, recordEnd);

        String text;
        if (compression == 1) {
          // 无压缩
          text = _decodeText(recordData, textEncoding);
        } else if (compression == 2) {
          // PalmDOC 压缩
          final decompressed = _decompressPalmDoc(recordData);
          text = _decodeText(decompressed, textEncoding);
        } else {
          // HUFF/CDIC 压缩，暂不支持
          return MobiParseResult.failure(
            'MOBI 文件使用 HUFF/CDIC 压缩\n\n'
            '此压缩格式较复杂，建议使用 Calibre 转换为 EPUB 格式\n\n'
            '${_getCalibreInstallHint()}',
          );
        }

        textBuffer.write(text);

        // 检查是否已达到文本长度
        if (textBuffer.length >= textLength) break;
      }

      // 清理 HTML 标签，提取纯文本
      var content = textBuffer.toString();
      content = _cleanHtml(content);

      return MobiParseResult.fromContent(
        content: content,
        title: title.isNotEmpty ? title : null,
        author: author,
      );
    } on Exception catch (e) {
      logger.e('MOBI 解析失败', e);
      return MobiParseResult.failure('MOBI 解析失败: $e');
    }
  }

  /// 读取 16 位无符号整数（大端序）
  int _readUint16(List<int> bytes, int offset) =>
      (bytes[offset] << 8) | bytes[offset + 1];

  /// 读取 32 位无符号整数（大端序）
  int _readUint32(List<int> bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  /// 解码文本
  String _decodeText(List<int> bytes, String encoding) {
    if (encoding == 'utf-8') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    // CP1252 编码，使用 latin1 作为近似
    return latin1.decode(bytes);
  }

  /// PalmDOC 解压缩 (LZ77)
  Uint8List _decompressPalmDoc(List<int> compressed) {
    final output = <int>[];
    var i = 0;

    while (i < compressed.length) {
      final byte = compressed[i++];

      if (byte == 0) {
        // 字面量 0
        output.add(byte);
      } else if (byte >= 1 && byte <= 8) {
        // 复制接下来的 1-8 个字节
        for (var j = 0; j < byte && i < compressed.length; j++) {
          output.add(compressed[i++]);
        }
      } else if (byte >= 9 && byte <= 0x7F) {
        // 字面量字节
        output.add(byte);
      } else if (byte >= 0x80 && byte <= 0xBF) {
        // 距离-长度对
        if (i >= compressed.length) break;
        final nextByte = compressed[i++];
        final distance = ((byte & 0x3F) << 5) | (nextByte >> 3);
        final length = (nextByte & 0x07) + 3;

        for (var j = 0; j < length; j++) {
          if (output.length >= distance) {
            output.add(output[output.length - distance]);
          }
        }
      } else {
        // 0xC0-0xFF: 空格 + 字符
        output
          ..add(0x20) // 空格
          ..add(byte ^ 0x80);
      }
    }

    return Uint8List.fromList(output);
  }

  /// 解析 EXTH 头部中的作者信息
  String? _parseExthAuthor(List<int> record, int exthStart) {
    try {
      final exthId =
          String.fromCharCodes(record.sublist(exthStart, exthStart + 4));
      if (exthId != 'EXTH') return null;

      final recordCount = _readUint32(record, exthStart + 8);

      var offset = exthStart + 12;
      for (var i = 0; i < recordCount; i++) {
        if (offset + 8 > record.length) break;

        final recordType = _readUint32(record, offset);
        final recordLength = _readUint32(record, offset + 4);

        if (recordType == 100) {
          // 作者
          final authorBytes = record.sublist(offset + 8, offset + recordLength);
          return utf8.decode(authorBytes, allowMalformed: true);
        }

        offset += recordLength;
      }
    } on Exception catch (_) {
      // 忽略解析错误
    }
    return null;
  }

  /// 清理 HTML 标签
  String _cleanHtml(String html) {
    // 移除 HTML 标签
    var text = html.replaceAll(RegExp('<[^>]*>'), '');

    // 解码 HTML 实体
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        // 清理多余的空白
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\n\s*\n'), '\n\n');

    return text.trim();
  }

  /// 获取 Calibre 安装提示
  String _getCalibreInstallHint() {
    if (Platform.isMacOS) {
      return 'macOS 安装 Calibre：\n'
          'brew install --cask calibre\n'
          '或从 https://calibre-ebook.com 下载';
    } else if (Platform.isWindows) {
      return 'Windows 安装 Calibre：\n从 https://calibre-ebook.com 下载安装';
    } else {
      return 'Linux 安装 Calibre：\n'
          'sudo apt install calibre\n'
          '或从 https://calibre-ebook.com 下载';
    }
  }
}
