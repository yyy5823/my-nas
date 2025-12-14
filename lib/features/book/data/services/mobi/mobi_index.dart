// MOBI 索引解析器
//
// 解析 INDX 记录和 NCX 导航结构
// 基于 KindleUnpack 的解析逻辑移植到 Dart
// 参考: https://wiki.mobileread.com/wiki/MOBI

import 'dart:typed_data';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_header.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_record.dart';
import 'package:my_nas/features/book/data/services/mobi/mobi_utils.dart';

/// INDX 记录元数据
class IndxMeta {
  const IndxMeta({
    required this.type,
    required this.entryCount,
    required this.idxtOffset,
    required this.tagxOffset,
  });

  /// 索引类型 (0=主索引, 2=inflection)
  final int type;

  /// 条目数量
  final int entryCount;

  /// IDXT 偏移量
  final int idxtOffset;

  /// TAGX 偏移量
  final int tagxOffset;
}

/// 索引条目
class IndexEntry {
  const IndexEntry({
    required this.label,
    required this.tagMap,
  });

  /// 条目标签/文本
  final String label;

  /// 标签键值对
  final Map<int, List<int>> tagMap;

  /// 获取位置偏移量（Tag 1）
  int? get positionOffset => tagMap[1]?.firstOrNull;

  /// 获取长度（Tag 2）
  int? get length => tagMap[2]?.firstOrNull;

  /// 获取父索引（Tag 21）
  int? get parentIndex => tagMap[21]?.firstOrNull;

  /// 获取第一个子索引（Tag 22）
  int? get firstChildIndex => tagMap[22]?.firstOrNull;

  /// 获取最后一个子索引（Tag 23）
  int? get lastChildIndex => tagMap[23]?.firstOrNull;
}

/// MOBI 索引解析器
class MobiIndexParser {
  /// 从 MOBI 头部解析目录结构
  static List<MobiChapter> parseChapters(MobiHeader header) {
    if (!header.hasNcx || header.ncxIndex == null) {
      logger.d('MOBI 没有 NCX 索引，尝试从 HTML 标题提取章节');
      return [];
    }

    try {
      // NCX 索引通常由两个连续的 INDX 记录组成
      // 第一个是元数据记录，第二个包含实际条目
      final ncxIndex = header.ncxIndex!;
      if (ncxIndex >= header.records.length) {
        logger.w('NCX 索引超出范围: $ncxIndex');
        return [];
      }

      // 解析主 INDX 记录
      final mainIndx = header.records[ncxIndex].data;
      final meta = _parseIndxMeta(mainIndx);
      if (meta == null) {
        logger.w('无法解析 INDX 元数据');
        return [];
      }

      logger.d('INDX: type=${meta.type}, entries=${meta.entryCount}');

      // 解析 TAGX 表
      final tagTable = _parseTagx(mainIndx, meta.tagxOffset);
      if (tagTable.isEmpty) {
        logger.w('无法解析 TAGX 表');
        return [];
      }

      // 解析索引条目
      // 条目可能在同一记录中(IDXT)或后续记录中
      final entries = <IndexEntry>[];

      // 首先尝试从后续记录中获取条目
      for (var i = 1; i <= meta.entryCount && ncxIndex + i < header.records.length; i++) {
        final recData = header.records[ncxIndex + i].data;

        // 检查是否是 INDX 记录
        if (recData.length >= 4 && readFixedString(recData, 0, 4) == 'INDX') {
          final subMeta = _parseIndxMeta(recData);
          if (subMeta != null && subMeta.idxtOffset > 0) {
            final subEntries = _parseIndxEntries(recData, subMeta, tagTable);
            entries.addAll(subEntries);
          }
        }
      }

      // 如果没有从子记录获取，尝试从主记录的 IDXT 获取
      if (entries.isEmpty && meta.idxtOffset > 0) {
        entries.addAll(_parseIndxEntries(mainIndx, meta, tagTable));
      }

      logger.d('解析到 ${entries.length} 个索引条目');

      // 转换为章节
      return _convertToChapters(entries);
    } on Exception catch (e, st) {
      logger.e('解析 NCX 索引失败', e, st);
      return [];
    }
  }

  /// 解析 INDX 元数据
  static IndxMeta? _parseIndxMeta(Uint8List data) {
    if (data.length < 192) return null;

    final magic = readFixedString(data, 0, 4);
    if (magic != 'INDX') return null;

    final headerLength = readUint32BE(data, 4);
    final type = readUint32BE(data, 8);
    final idxtOffset = readUint32BE(data, 20);
    final entryCount = readUint32BE(data, 24);

    // TAGX 紧跟在 INDX 头部之后
    final tagxOffset = headerLength;

    return IndxMeta(
      type: type,
      entryCount: entryCount,
      idxtOffset: idxtOffset,
      tagxOffset: tagxOffset,
    );
  }

  /// 解析 TAGX 表
  ///
  /// TAGX 定义了如何解码索引条目中的标签值
  static List<_TagxEntry> _parseTagx(Uint8List data, int offset) {
    if (offset + 12 > data.length) return [];

    final magic = readFixedString(data, offset, 4);
    if (magic != 'TAGX') return [];

    final length = readUint32BE(data, offset + 4);
    // controlByteCount at offset 8 (unused)

    final entries = <_TagxEntry>[];
    var pos = offset + 12;

    // 每个 TAGX 条目 4 字节
    while (pos + 4 <= offset + length) {
      final tag = data[pos];
      final numValues = data[pos + 1];
      final mask = data[pos + 2];
      final endFlag = data[pos + 3];

      if (endFlag == 0x01) {
        // 结束标记
        break;
      }

      entries.add(_TagxEntry(
        tag: tag,
        numValues: numValues,
        mask: mask,
      ));

      pos += 4;
    }

    return entries;
  }

  /// 解析 INDX 条目
  static List<IndexEntry> _parseIndxEntries(
    Uint8List data,
    IndxMeta meta,
    List<_TagxEntry> tagTable,
  ) {
    final entries = <IndexEntry>[];

    if (meta.idxtOffset <= 0 || meta.idxtOffset >= data.length) {
      return entries;
    }

    // IDXT 头部
    final idxtMagic = readFixedString(data, meta.idxtOffset, 4);
    if (idxtMagic != 'IDXT') {
      logger.w('无效的 IDXT 标记: $idxtMagic');
      return entries;
    }

    // IDXT 包含条目偏移量列表
    final entryOffsets = <int>[];
    var pos = meta.idxtOffset + 4;

    // 读取条目偏移量（每个 2 字节）
    for (var i = 0; i < meta.entryCount && pos + 2 <= data.length; i++) {
      final offset = readUint16BE(data, pos);
      if (offset > 0 && offset < data.length) {
        entryOffsets.add(offset);
      }
      pos += 2;
    }

    // 解析每个条目
    for (var i = 0; i < entryOffsets.length; i++) {
      final entryOffset = entryOffsets[i];
      final nextOffset = i + 1 < entryOffsets.length
          ? entryOffsets[i + 1]
          : meta.idxtOffset;

      if (entryOffset >= data.length) continue;

      // 条目格式: <label_length> <label> <control_bytes> <values>
      final labelLength = data[entryOffset];
      final labelEnd = entryOffset + 1 + labelLength;

      if (labelEnd > data.length) continue;

      final label = readFixedString(data, entryOffset + 1, labelLength);

      // 解析标签值
      final tagMap = _parseTagValues(
        data,
        labelEnd,
        nextOffset,
        tagTable,
      );

      entries.add(IndexEntry(label: label, tagMap: tagMap));
    }

    return entries;
  }

  /// 解析标签值
  static Map<int, List<int>> _parseTagValues(
    Uint8List data,
    int start,
    int end,
    List<_TagxEntry> tagTable,
  ) {
    final result = <int, List<int>>{};

    if (start >= end || start >= data.length) return result;

    // 控制字节
    var pos = start;
    final controlByte = data[pos++];

    for (final entry in tagTable) {
      if ((controlByte & entry.mask) == entry.mask) {
        // 该标签存在，读取值
        final values = <int>[];

        for (var v = 0; v < entry.numValues && pos < end; v++) {
          final (value, bytesRead) = readVariableWidthIntForward(data, pos);
          values.add(value);
          pos += bytesRead;
        }

        result[entry.tag] = values;
      }
    }

    return result;
  }

  /// 转换索引条目为章节列表
  static List<MobiChapter> _convertToChapters(List<IndexEntry> entries) {
    final chapters = <MobiChapter>[];

    for (final entry in entries) {
      final offset = entry.positionOffset;
      if (offset == null) continue;

      // 确定层级
      var level = 1;
      if (entry.parentIndex != null && entry.parentIndex! >= 0) {
        level = 2;
      }

      chapters.add(MobiChapter(
        title: entry.label.trim(),
        startOffset: offset,
        endOffset: entry.length != null ? offset + entry.length! : null,
        level: level,
      ));
    }

    // 按偏移量排序
    chapters.sort((a, b) => a.startOffset.compareTo(b.startOffset));

    return chapters;
  }
}

/// TAGX 表条目
class _TagxEntry {
  const _TagxEntry({
    required this.tag,
    required this.numValues,
    required this.mask,
  });

  final int tag;
  final int numValues;
  final int mask;
}
