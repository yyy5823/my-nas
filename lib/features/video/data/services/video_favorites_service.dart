import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 视频收藏项
class VideoFavoriteItem {
  const VideoFavoriteItem({
    required this.videoPath,
    required this.videoName,
    required this.videoUrl,
    this.thumbnailUrl,
    this.size = 0,
    required this.addedAt,
  });

  final String videoPath;
  final String videoName;
  final String videoUrl;
  final String? thumbnailUrl;
  final int size;
  final DateTime addedAt;

  Map<String, dynamic> toMap() => {
        'videoPath': videoPath,
        'videoName': videoName,
        'videoUrl': videoUrl,
        'thumbnailUrl': thumbnailUrl,
        'size': size,
        'addedAt': addedAt.millisecondsSinceEpoch,
      };

  factory VideoFavoriteItem.fromMap(Map<dynamic, dynamic> map) =>
      VideoFavoriteItem(
        videoPath: map['videoPath'] as String,
        videoName: map['videoName'] as String,
        videoUrl: map['videoUrl'] as String,
        thumbnailUrl: map['thumbnailUrl'] as String?,
        size: map['size'] as int? ?? 0,
        addedAt: DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int),
      );
}

/// 视频书签项
class VideoBookmarkItem {
  const VideoBookmarkItem({
    required this.id,
    required this.videoPath,
    required this.videoName,
    required this.position,
    this.note,
    required this.createdAt,
  });

  final String id;
  final String videoPath;
  final String videoName;
  final Duration position;
  final String? note;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'videoPath': videoPath,
        'videoName': videoName,
        'position': position.inMilliseconds,
        'note': note,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory VideoBookmarkItem.fromMap(Map<dynamic, dynamic> map) =>
      VideoBookmarkItem(
        id: map['id'] as String,
        videoPath: map['videoPath'] as String,
        videoName: map['videoName'] as String,
        position: Duration(milliseconds: map['position'] as int),
        note: map['note'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      );

  String get formattedPosition {
    final hours = position.inHours;
    final minutes = position.inMinutes.remainder(60);
    final seconds = position.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 视频收藏和书签服务
class VideoFavoritesService {
  VideoFavoritesService._();
  static final instance = VideoFavoritesService._();

  static const _favoritesBoxName = 'video_favorites';
  static const _bookmarksBoxName = 'video_bookmarks';

  Box<Map<dynamic, dynamic>>? _favoritesBox;
  Box<Map<dynamic, dynamic>>? _bookmarksBox;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    try {
      _favoritesBox = await Hive.openBox<Map<dynamic, dynamic>>(_favoritesBoxName);
      _bookmarksBox = await Hive.openBox<Map<dynamic, dynamic>>(_bookmarksBoxName);
      _initialized = true;
      logger.i('VideoFavoritesService: 初始化完成');
    } on Exception catch (e) {
      logger.e('VideoFavoritesService: 初始化失败', e);
    }
  }

  // ==================== 收藏相关 ====================

  /// 添加到收藏
  Future<void> addToFavorites(VideoFavoriteItem item) async {
    await init();
    if (_favoritesBox == null) return;

    await _favoritesBox!.put(item.videoPath, item.toMap());
    logger.i('VideoFavoritesService: 添加收藏 ${item.videoName}');
  }

  /// 从收藏移除
  Future<void> removeFromFavorites(String videoPath) async {
    await init();
    if (_favoritesBox == null) return;

    await _favoritesBox!.delete(videoPath);
    logger.i('VideoFavoritesService: 移除收藏 $videoPath');
  }

  /// 检查是否已收藏
  Future<bool> isFavorite(String videoPath) async {
    await init();
    if (_favoritesBox == null) return false;

    return _favoritesBox!.containsKey(videoPath);
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(VideoFavoriteItem item) async {
    final isFav = await isFavorite(item.videoPath);
    if (isFav) {
      await removeFromFavorites(item.videoPath);
      return false;
    } else {
      await addToFavorites(item);
      return true;
    }
  }

  /// 获取所有收藏
  Future<List<VideoFavoriteItem>> getAllFavorites() async {
    await init();
    if (_favoritesBox == null) return [];

    final favorites = <VideoFavoriteItem>[];
    for (final key in _favoritesBox!.keys) {
      final data = _favoritesBox!.get(key);
      if (data != null) {
        try {
          favorites.add(VideoFavoriteItem.fromMap(data));
        } on Exception catch (_) {
          // 跳过无效数据
        }
      }
    }

    // 按添加时间倒序排列
    favorites.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return favorites;
  }

  /// 清空所有收藏
  Future<void> clearAllFavorites() async {
    await init();
    if (_favoritesBox == null) return;

    await _favoritesBox!.clear();
    logger.i('VideoFavoritesService: 清空所有收藏');
  }

  // ==================== 书签相关 ====================

  /// 添加书签
  Future<void> addBookmark(VideoBookmarkItem item) async {
    await init();
    if (_bookmarksBox == null) return;

    await _bookmarksBox!.put(item.id, item.toMap());
    logger.i('VideoFavoritesService: 添加书签 ${item.videoName} at ${item.formattedPosition}');
  }

  /// 删除书签
  Future<void> removeBookmark(String bookmarkId) async {
    await init();
    if (_bookmarksBox == null) return;

    await _bookmarksBox!.delete(bookmarkId);
    logger.i('VideoFavoritesService: 删除书签 $bookmarkId');
  }

  /// 获取视频的所有书签
  Future<List<VideoBookmarkItem>> getBookmarksForVideo(String videoPath) async {
    await init();
    if (_bookmarksBox == null) return [];

    final bookmarks = <VideoBookmarkItem>[];
    for (final key in _bookmarksBox!.keys) {
      final data = _bookmarksBox!.get(key);
      if (data != null) {
        try {
          final bookmark = VideoBookmarkItem.fromMap(data);
          if (bookmark.videoPath == videoPath) {
            bookmarks.add(bookmark);
          }
        } on Exception catch (_) {
          // 跳过无效数据
        }
      }
    }

    // 按位置排序
    bookmarks.sort((a, b) => a.position.compareTo(b.position));
    return bookmarks;
  }

  /// 获取所有书签
  Future<List<VideoBookmarkItem>> getAllBookmarks() async {
    await init();
    if (_bookmarksBox == null) return [];

    final bookmarks = <VideoBookmarkItem>[];
    for (final key in _bookmarksBox!.keys) {
      final data = _bookmarksBox!.get(key);
      if (data != null) {
        try {
          bookmarks.add(VideoBookmarkItem.fromMap(data));
        } on Exception catch (_) {
          // 跳过无效数据
        }
      }
    }

    // 按创建时间倒序排列
    bookmarks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return bookmarks;
  }

  /// 更新书签备注
  Future<void> updateBookmarkNote(String bookmarkId, String? note) async {
    await init();
    if (_bookmarksBox == null) return;

    final data = _bookmarksBox!.get(bookmarkId);
    if (data != null) {
      final bookmark = VideoBookmarkItem.fromMap(data);
      final updated = VideoBookmarkItem(
        id: bookmark.id,
        videoPath: bookmark.videoPath,
        videoName: bookmark.videoName,
        position: bookmark.position,
        note: note,
        createdAt: bookmark.createdAt,
      );
      await _bookmarksBox!.put(bookmarkId, updated.toMap());
    }
  }

  /// 清空所有书签
  Future<void> clearAllBookmarks() async {
    await init();
    if (_bookmarksBox == null) return;

    await _bookmarksBox!.clear();
    logger.i('VideoFavoritesService: 清空所有书签');
  }

  /// 删除视频的所有书签
  Future<void> clearBookmarksForVideo(String videoPath) async {
    await init();
    if (_bookmarksBox == null) return;

    final keysToDelete = <dynamic>[];
    for (final key in _bookmarksBox!.keys) {
      final data = _bookmarksBox!.get(key);
      if (data != null && data['videoPath'] == videoPath) {
        keysToDelete.add(key);
      }
    }

    for (final key in keysToDelete) {
      await _bookmarksBox!.delete(key);
    }
    logger.i('VideoFavoritesService: 删除视频 $videoPath 的所有书签');
  }
}
