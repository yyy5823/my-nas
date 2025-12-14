// MOBI 记录数据结构
//
// 基于 KindleUnpack 的解析逻辑移植到 Dart
// 参考: https://wiki.mobileread.com/wiki/MOBI

import 'dart:typed_data';

/// Palm Database 记录
class MobiRecord {
  const MobiRecord({
    required this.index,
    required this.offset,
    required this.data,
  });

  /// 记录索引
  final int index;

  /// 在文件中的偏移量
  final int offset;

  /// 记录数据
  final Uint8List data;

  /// 记录长度
  int get length => data.length;
}

/// MOBI 类型常量
enum MobiType {
  mobipocketBook(2, 'Mobipocket Book'),
  palmDocBook(3, 'PalmDoc Book'),
  audio(4, 'Audio'),
  kindlegen1(232, 'Kindlegen 1.x'),
  kf8(248, 'KF8'),
  news(257, 'News'),
  newsFeed(258, 'News Feed'),
  newsMagazine(259, 'News Magazine'),
  pics(513, 'PICS'),
  word(514, 'WORD'),
  xls(515, 'XLS'),
  ppt(516, 'PPT'),
  text(517, 'TEXT'),
  html(518, 'HTML'),
  unknown(0, 'Unknown');

  const MobiType(this.value, this.label);

  final int value;
  final String label;

  static MobiType fromValue(int value) => MobiType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => MobiType.unknown,
    );
}

/// 压缩类型
enum MobiCompression {
  none(1, 'No Compression'),
  palmDoc(2, 'PalmDOC'),
  huffCdic(17480, 'HUFF/CDIC');

  const MobiCompression(this.value, this.label);

  final int value;
  final String label;

  static MobiCompression fromValue(int value) => MobiCompression.values.firstWhere(
      (c) => c.value == value,
      orElse: () => MobiCompression.none,
    );
}

/// 文本编码
enum MobiEncoding {
  cp1252(1252, 'CP1252'),
  utf8(65001, 'UTF-8');

  const MobiEncoding(this.value, this.label);

  final int value;
  final String label;

  static MobiEncoding fromValue(int value) {
    if (value == 65001) return MobiEncoding.utf8;
    return MobiEncoding.cp1252;
  }
}

/// 章节信息
class MobiChapter {
  const MobiChapter({
    required this.title,
    required this.startOffset,
    this.endOffset,
    this.level = 1,
  });

  /// 章节标题
  final String title;

  /// 在 HTML 内容中的起始偏移
  final int startOffset;

  /// 在 HTML 内容中的结束偏移（可选）
  final int? endOffset;

  /// 层级（1=一级标题，2=二级...）
  final int level;

  @override
  String toString() => 'MobiChapter($title, offset=$startOffset, level=$level)';
}

/// 导航点（NCX）
class MobiNavPoint {
  const MobiNavPoint({
    required this.title,
    required this.contentOffset,
    this.playOrder = 0,
    this.children = const [],
  });

  /// 导航标题
  final String title;

  /// 内容偏移量
  final int contentOffset;

  /// 播放顺序
  final int playOrder;

  /// 子导航点（支持嵌套）
  final List<MobiNavPoint> children;

  @override
  String toString() => 'MobiNavPoint($title, offset=$contentOffset)';
}
