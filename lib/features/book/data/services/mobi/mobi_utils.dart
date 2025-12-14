// MOBI 工具函数
//
// 基于 KindleUnpack 的解析逻辑移植到 Dart
// 参考: https://wiki.mobileread.com/wiki/MOBI

import 'dart:convert';
import 'dart:typed_data';

/// 读取大端序 16 位无符号整数
int readUint16BE(List<int> bytes, int offset) {
  if (offset + 2 > bytes.length) return 0;
  return (bytes[offset] << 8) | bytes[offset + 1];
}

/// 读取大端序 32 位无符号整数
int readUint32BE(List<int> bytes, int offset) {
  if (offset + 4 > bytes.length) return 0;
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

/// 读取可变宽度整数（前向编码）
///
/// MOBI 格式使用可变宽度整数，每字节 7 位数据，
/// 最高位表示是否继续。前向编码时，最后一个字节的最高位为 1。
(int value, int bytesRead) readVariableWidthIntForward(
  List<int> bytes,
  int offset,
) {
  var value = 0;
  var bytesRead = 0;

  for (var i = offset; i < bytes.length; i++) {
    final byte = bytes[i];
    bytesRead++;
    value = (value << 7) | (byte & 0x7F);

    if ((byte & 0x80) != 0) {
      // 最高位为 1，表示结束
      break;
    }
  }

  return (value, bytesRead);
}

/// 读取可变宽度整数（后向编码）
///
/// 从末尾向前读取，第一个字节的最高位为 1。
(int value, int bytesRead) readVariableWidthIntBackward(
  List<int> bytes,
  int endOffset,
) {
  var value = 0;
  var bytesRead = 0;
  var shift = 0;

  for (var i = endOffset - 1; i >= 0; i--) {
    final byte = bytes[i];
    bytesRead++;
    value |= (byte & 0x7F) << shift;
    shift += 7;

    if ((byte & 0x80) != 0) {
      // 最高位为 1，表示开始
      break;
    }
  }

  return (value, bytesRead);
}

/// 解码文本内容
///
/// 支持 UTF-8 和 CP1252 编码，自动检测 GBK
Future<String> decodeText(Uint8List bytes, {bool isUtf8 = false}) async {
  if (isUtf8) {
    return utf8.decode(bytes, allowMalformed: true);
  }

  // 尝试 UTF-8
  try {
    final text = utf8.decode(bytes);
    // 检查是否解码成功（无替换字符）
    if (!text.contains('\uFFFD')) {
      return text;
    }
  } on FormatException {
    // 继续尝试其他编码
  }

  // 检测是否为 GBK 编码
  if (_looksLikeGbk(bytes)) {
    return _decodeGbkFallback(bytes);
  }

  // 默认使用 Latin1 (CP1252 近似)
  return latin1.decode(bytes);
}

/// 检测是否可能是 GBK 编码
bool _looksLikeGbk(List<int> bytes) {
  if (bytes.isEmpty) return false;

  var gbkPairs = 0;
  var totalPairs = 0;

  for (var i = 0; i < bytes.length - 1; i++) {
    final high = bytes[i];
    final low = bytes[i + 1];

    if (high >= 0x81 && high <= 0xFE) {
      totalPairs++;
      if ((low >= 0x40 && low <= 0x7E) || (low >= 0x80 && low <= 0xFE)) {
        gbkPairs++;
        i++;
      }
    }
  }

  return totalPairs > 10 && gbkPairs > totalPairs * 0.3;
}

/// GBK 解码回退方案
String _decodeGbkFallback(List<int> bytes) {
  final result = StringBuffer();
  var i = 0;

  while (i < bytes.length) {
    final byte = bytes[i];

    if (byte < 0x80) {
      result.writeCharCode(byte);
      i++;
    } else if (byte >= 0x81 && byte <= 0xFE && i + 1 < bytes.length) {
      // GBK 双字节：简化处理，使用替代字符
      result.write('\uFFFD');
      i += 2;
    } else {
      result.write('\uFFFD');
      i++;
    }
  }

  return result.toString();
}

/// 读取以 null 结尾的字符串
String readNullTerminatedString(List<int> bytes, int offset, int maxLength) {
  var end = offset;
  while (end < offset + maxLength && end < bytes.length && bytes[end] != 0) {
    end++;
  }
  return utf8.decode(bytes.sublist(offset, end), allowMalformed: true);
}

/// 读取固定长度字符串（去除尾部 null）
String readFixedString(List<int> bytes, int offset, int len) {
  var effectiveLength = len;
  if (offset + effectiveLength > bytes.length) {
    effectiveLength = bytes.length - offset;
  }
  if (effectiveLength <= 0) return '';

  final data = bytes.sublist(offset, offset + effectiveLength);
  final nullIndex = data.indexOf(0);
  final finalLength = nullIndex >= 0 ? nullIndex : effectiveLength;

  return utf8.decode(data.sublist(0, finalLength), allowMalformed: true);
}

/// 安全获取子列表
Uint8List safeSublist(Uint8List bytes, int start, [int? end]) {
  final safeStart = start.clamp(0, bytes.length);
  final safeEnd = (end ?? bytes.length).clamp(safeStart, bytes.length);
  return bytes.sublist(safeStart, safeEnd);
}
