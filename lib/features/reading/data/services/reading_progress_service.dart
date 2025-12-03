import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 阅读进度信息
class ReadingProgress {
  ReadingProgress({
    required this.itemId,
    required this.itemType,
    this.position = 0,
    this.totalPositions = 0,
    this.chapter,
    this.chapterTitle,
    this.lastReadAt,
    this.scrollOffset = 0,
  });

  /// 唯一标识（路径+sourceId）
  final String itemId;

  /// 类型：book, comic, epub, pdf
  final String itemType;

  /// 当前位置（页码/章节索引/滚动位置百分比）
  final double position;

  /// 总位置数
  final int totalPositions;

  /// 当前章节索引
  final int? chapter;

  /// 章节标题
  final String? chapterTitle;

  /// 最后阅读时间
  final DateTime? lastReadAt;

  /// 滚动偏移（用于精确恢复位置）
  final double scrollOffset;

  /// 阅读进度百分比
  double get progressPercent {
    if (totalPositions <= 0) return 0;
    return (position / totalPositions).clamp(0.0, 1.0);
  }

  /// 格式化的进度文本
  String get progressText {
    final percent = (progressPercent * 100).toStringAsFixed(0);
    return '$percent%';
  }

  Map<String, dynamic> toMap() => {
        'itemId': itemId,
        'itemType': itemType,
        'position': position,
        'totalPositions': totalPositions,
        'chapter': chapter,
        'chapterTitle': chapterTitle,
        'lastReadAt': lastReadAt?.toIso8601String(),
        'scrollOffset': scrollOffset,
      };

  factory ReadingProgress.fromMap(Map<dynamic, dynamic> map) {
    return ReadingProgress(
      itemId: map['itemId'] as String,
      itemType: map['itemType'] as String,
      position: (map['position'] as num?)?.toDouble() ?? 0,
      totalPositions: (map['totalPositions'] as num?)?.toInt() ?? 0,
      chapter: map['chapter'] as int?,
      chapterTitle: map['chapterTitle'] as String?,
      lastReadAt: map['lastReadAt'] != null
          ? DateTime.tryParse(map['lastReadAt'] as String)
          : null,
      scrollOffset: (map['scrollOffset'] as num?)?.toDouble() ?? 0,
    );
  }

  ReadingProgress copyWith({
    String? itemId,
    String? itemType,
    double? position,
    int? totalPositions,
    int? chapter,
    String? chapterTitle,
    DateTime? lastReadAt,
    double? scrollOffset,
  }) {
    return ReadingProgress(
      itemId: itemId ?? this.itemId,
      itemType: itemType ?? this.itemType,
      position: position ?? this.position,
      totalPositions: totalPositions ?? this.totalPositions,
      chapter: chapter ?? this.chapter,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      scrollOffset: scrollOffset ?? this.scrollOffset,
    );
  }
}

/// 书签
class Bookmark {
  Bookmark({
    required this.id,
    required this.itemId,
    required this.title,
    required this.position,
    this.note,
    this.createdAt,
  });

  final String id;
  final String itemId;
  final String title;
  final double position;
  final String? note;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'itemId': itemId,
        'title': title,
        'position': position,
        'note': note,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory Bookmark.fromMap(Map<dynamic, dynamic> map) {
    return Bookmark(
      id: map['id'] as String,
      itemId: map['itemId'] as String,
      title: map['title'] as String,
      position: (map['position'] as num).toDouble(),
      note: map['note'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
    );
  }
}

/// 阅读进度服务
class ReadingProgressService {
  ReadingProgressService._();

  static ReadingProgressService? _instance;
  static ReadingProgressService get instance =>
      _instance ??= ReadingProgressService._();

  static const String _progressBoxName = 'reading_progress';
  static const String _bookmarksBoxName = 'reading_bookmarks';
  static const String _recentBoxName = 'recent_reading';

  Box<dynamic>? _progressBox;
  Box<dynamic>? _bookmarksBox;
  Box<dynamic>? _recentBox;

  /// 初始化
  Future<void> init() async {
    if (_progressBox != null && _progressBox!.isOpen) return;

    try {
      _progressBox = await Hive.openBox(_progressBoxName);
      _bookmarksBox = await Hive.openBox(_bookmarksBoxName);
      _recentBox = await Hive.openBox(_recentBoxName);
      logger.i('ReadingProgressService: 初始化完成');
    } catch (e) {
      logger.e('ReadingProgressService: 初始化失败', e);
      // 删除损坏的数据并重新创建
      await Hive.deleteBoxFromDisk(_progressBoxName);
      await Hive.deleteBoxFromDisk(_bookmarksBoxName);
      await Hive.deleteBoxFromDisk(_recentBoxName);
      _progressBox = await Hive.openBox(_progressBoxName);
      _bookmarksBox = await Hive.openBox(_bookmarksBoxName);
      _recentBox = await Hive.openBox(_recentBoxName);
    }
  }

  /// 生成唯一ID
  String generateItemId(String sourceId, String path) => '${sourceId}_$path';

  // ============ 阅读进度 ============

  /// 获取阅读进度
  ReadingProgress? getProgress(String itemId) {
    final data = _progressBox?.get(itemId);
    if (data == null) return null;
    try {
      return ReadingProgress.fromMap(data as Map<dynamic, dynamic>);
    } catch (e) {
      logger.w('ReadingProgressService: 解析进度数据失败', e);
      return null;
    }
  }

  /// 保存阅读进度
  Future<void> saveProgress(ReadingProgress progress) async {
    await _progressBox?.put(progress.itemId, progress.toMap());

    // 同时更新最近阅读
    await _updateRecent(progress.itemId, progress.itemType);
  }

  /// 删除阅读进度
  Future<void> deleteProgress(String itemId) async {
    await _progressBox?.delete(itemId);
  }

  /// 获取所有有进度的项目
  List<ReadingProgress> getAllProgress() {
    if (_progressBox == null) return [];
    final results = <ReadingProgress>[];
    for (final key in _progressBox!.keys) {
      final data = _progressBox!.get(key);
      if (data != null) {
        try {
          results.add(ReadingProgress.fromMap(data as Map<dynamic, dynamic>));
        } catch (e) {
          // 跳过无效数据
        }
      }
    }
    return results;
  }

  // ============ 书签 ============

  /// 获取指定项目的所有书签
  List<Bookmark> getBookmarks(String itemId) {
    final data = _bookmarksBox?.get(itemId);
    if (data == null) return [];
    try {
      final list = jsonDecode(data as String) as List;
      return list.map((e) => Bookmark.fromMap(e as Map<dynamic, dynamic>)).toList();
    } catch (e) {
      logger.w('ReadingProgressService: 解析书签数据失败', e);
      return [];
    }
  }

  /// 添加书签
  Future<void> addBookmark(Bookmark bookmark) async {
    final bookmarks = getBookmarks(bookmark.itemId);
    bookmarks.add(bookmark);
    await _bookmarksBox?.put(
      bookmark.itemId,
      jsonEncode(bookmarks.map((e) => e.toMap()).toList()),
    );
  }

  /// 删除书签
  Future<void> deleteBookmark(String itemId, String bookmarkId) async {
    final bookmarks = getBookmarks(itemId);
    bookmarks.removeWhere((b) => b.id == bookmarkId);
    if (bookmarks.isEmpty) {
      await _bookmarksBox?.delete(itemId);
    } else {
      await _bookmarksBox?.put(
        itemId,
        jsonEncode(bookmarks.map((e) => e.toMap()).toList()),
      );
    }
  }

  // ============ 最近阅读 ============

  /// 更新最近阅读记录
  Future<void> _updateRecent(String itemId, String itemType) async {
    final data = {
      'itemId': itemId,
      'itemType': itemType,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await _recentBox?.put(itemId, jsonEncode(data));
  }

  /// 获取最近阅读列表
  List<({String itemId, String itemType, DateTime timestamp})> getRecentReading({
    int limit = 20,
  }) {
    if (_recentBox == null) return [];

    final results = <({String itemId, String itemType, DateTime timestamp})>[];
    for (final key in _recentBox!.keys) {
      final data = _recentBox!.get(key);
      if (data != null) {
        try {
          final map = jsonDecode(data as String) as Map<String, dynamic>;
          results.add((
            itemId: map['itemId'] as String,
            itemType: map['itemType'] as String,
            timestamp: DateTime.parse(map['timestamp'] as String),
          ));
        } catch (e) {
          // 跳过无效数据
        }
      }
    }

    // 按时间倒序排序
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results.take(limit).toList();
  }

  /// 清除最近阅读记录
  Future<void> clearRecentReading() async {
    await _recentBox?.clear();
  }

  // ============ 清理 ============

  /// 清除所有数据
  Future<void> clearAll() async {
    await _progressBox?.clear();
    await _bookmarksBox?.clear();
    await _recentBox?.clear();
    logger.i('ReadingProgressService: 所有数据已清除');
  }
}
