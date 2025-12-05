import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';

/// 音乐收藏项
class MusicFavoriteItem {
  const MusicFavoriteItem({
    required this.musicPath,
    required this.musicName,
    required this.musicUrl,
    required this.addedAt, this.artist,
    this.album,
    this.coverUrl,
    this.duration,
  });

  factory MusicFavoriteItem.fromMap(Map<dynamic, dynamic> map) =>
      MusicFavoriteItem(
        musicPath: map['musicPath'] as String,
        musicName: map['musicName'] as String,
        musicUrl: map['musicUrl'] as String,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        coverUrl: map['coverUrl'] as String?,
        duration: map['duration'] != null
            ? Duration(milliseconds: map['duration'] as int)
            : null,
        addedAt: DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int),
      );

  factory MusicFavoriteItem.fromMusicItem(MusicItem item) => MusicFavoriteItem(
        musicPath: item.path,
        musicName: item.name,
        musicUrl: item.url,
        artist: item.artist,
        album: item.album,
        coverUrl: item.coverUrl,
        duration: item.duration,
        addedAt: DateTime.now(),
      );

  final String musicPath;
  final String musicName;
  final String musicUrl;
  final String? artist;
  final String? album;
  final String? coverUrl;
  final Duration? duration;
  final DateTime addedAt;

  Map<String, dynamic> toMap() => {
        'musicPath': musicPath,
        'musicName': musicName,
        'musicUrl': musicUrl,
        'artist': artist,
        'album': album,
        'coverUrl': coverUrl,
        'duration': duration?.inMilliseconds,
        'addedAt': addedAt.millisecondsSinceEpoch,
      };

  MusicItem toMusicItem() => MusicItem(
        id: musicPath,
        name: musicName,
        path: musicPath,
        url: musicUrl,
        artist: artist,
        album: album,
        coverUrl: coverUrl,
        duration: duration,
      );
}

/// 音乐播放历史项
class MusicHistoryItem {
  const MusicHistoryItem({
    required this.musicPath,
    required this.musicName,
    required this.musicUrl,
    required this.playedAt, this.artist,
    this.album,
    this.coverUrl,
    this.duration,
    this.lastPosition,
  });

  factory MusicHistoryItem.fromMusicItem(MusicItem item) => MusicHistoryItem(
        musicPath: item.path,
        musicName: item.name,
        musicUrl: item.url,
        artist: item.artist,
        album: item.album,
        coverUrl: item.coverUrl,
        duration: item.duration,
        playedAt: DateTime.now(),
        lastPosition: item.lastPosition,
      );

  factory MusicHistoryItem.fromMap(Map<dynamic, dynamic> map) =>
      MusicHistoryItem(
        musicPath: map['musicPath'] as String,
        musicName: map['musicName'] as String,
        musicUrl: map['musicUrl'] as String,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        coverUrl: map['coverUrl'] as String?,
        duration: map['duration'] != null
            ? Duration(milliseconds: map['duration'] as int)
            : null,
        playedAt: DateTime.fromMillisecondsSinceEpoch(map['playedAt'] as int),
        lastPosition: map['lastPosition'] != null
            ? Duration(milliseconds: map['lastPosition'] as int)
            : null,
      );

  final String musicPath;
  final String musicName;
  final String musicUrl;
  final String? artist;
  final String? album;
  final String? coverUrl;
  final Duration? duration;
  final DateTime playedAt;
  final Duration? lastPosition;

  Map<String, dynamic> toMap() => {
        'musicPath': musicPath,
        'musicName': musicName,
        'musicUrl': musicUrl,
        'artist': artist,
        'album': album,
        'coverUrl': coverUrl,
        'duration': duration?.inMilliseconds,
        'playedAt': playedAt.millisecondsSinceEpoch,
        'lastPosition': lastPosition?.inMilliseconds,
      };

  MusicItem toMusicItem() => MusicItem(
        id: musicPath,
        name: musicName,
        path: musicPath,
        url: musicUrl,
        artist: artist,
        album: album,
        coverUrl: coverUrl,
        duration: duration,
        lastPosition: lastPosition ?? Duration.zero,
      );
}

/// 音乐收藏和历史服务
class MusicFavoritesService {
  factory MusicFavoritesService() => _instance ??= MusicFavoritesService._();
  MusicFavoritesService._();

  static MusicFavoritesService? _instance;

  static const _favoritesBoxName = 'music_favorites';
  static const _historyBoxName = 'music_history';
  static const _maxHistoryItems = 100;

  Box<Map<dynamic, dynamic>>? _favoritesBox;
  Box<Map<dynamic, dynamic>>? _historyBox;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    try {
      _favoritesBox = await Hive.openBox<Map<dynamic, dynamic>>(_favoritesBoxName);
      _historyBox = await Hive.openBox<Map<dynamic, dynamic>>(_historyBoxName);
      _initialized = true;
      logger.i('MusicFavoritesService: 初始化完成');
    } on Exception catch (e) {
      logger.e('MusicFavoritesService: 初始化失败', e);
    }
  }

  // ==================== 收藏相关 ====================

  /// 添加到收藏
  Future<void> addToFavorites(MusicItem item) async {
    await init();
    if (_favoritesBox == null) return;

    final favorite = MusicFavoriteItem.fromMusicItem(item);
    await _favoritesBox!.put(item.path, favorite.toMap());
    logger.i('MusicFavoritesService: 添加收藏 ${item.name}');
  }

  /// 从收藏移除
  Future<void> removeFromFavorites(String musicPath) async {
    await init();
    if (_favoritesBox == null) return;

    await _favoritesBox!.delete(musicPath);
    logger.i('MusicFavoritesService: 移除收藏 $musicPath');
  }

  /// 检查是否已收藏
  Future<bool> isFavorite(String musicPath) async {
    await init();
    if (_favoritesBox == null) return false;

    return _favoritesBox!.containsKey(musicPath);
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(MusicItem item) async {
    final isFav = await isFavorite(item.path);
    if (isFav) {
      await removeFromFavorites(item.path);
      return false;
    } else {
      await addToFavorites(item);
      return true;
    }
  }

  /// 获取所有收藏
  Future<List<MusicFavoriteItem>> getAllFavorites() async {
    await init();
    if (_favoritesBox == null) return [];

    final favorites = <MusicFavoriteItem>[];
    for (final key in _favoritesBox!.keys) {
      final data = _favoritesBox!.get(key);
      if (data != null) {
        try {
          favorites.add(MusicFavoriteItem.fromMap(data));
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
    logger.i('MusicFavoritesService: 清空所有收藏');
  }

  // ==================== 历史相关 ====================

  /// 添加到播放历史
  Future<void> addToHistory(MusicItem item) async {
    await init();
    if (_historyBox == null) return;

    final history = MusicHistoryItem.fromMusicItem(item);
    await _historyBox!.put(item.path, history.toMap());

    // 限制历史记录数量
    await _trimHistory();

    logger.d('MusicFavoritesService: 添加播放历史 ${item.name}');
  }

  /// 更新播放位置
  Future<void> updatePlayPosition(String musicPath, Duration position) async {
    await init();
    if (_historyBox == null) return;

    final data = _historyBox!.get(musicPath);
    if (data != null) {
      final history = MusicHistoryItem.fromMap(data);
      final updated = MusicHistoryItem(
        musicPath: history.musicPath,
        musicName: history.musicName,
        musicUrl: history.musicUrl,
        artist: history.artist,
        album: history.album,
        coverUrl: history.coverUrl,
        duration: history.duration,
        playedAt: DateTime.now(),
        lastPosition: position,
      );
      await _historyBox!.put(musicPath, updated.toMap());
    }
  }

  /// 获取所有播放历史
  Future<List<MusicHistoryItem>> getAllHistory() async {
    await init();
    if (_historyBox == null) return [];

    final history = <MusicHistoryItem>[];
    for (final key in _historyBox!.keys) {
      final data = _historyBox!.get(key);
      if (data != null) {
        try {
          history.add(MusicHistoryItem.fromMap(data));
        } on Exception catch (_) {
          // 跳过无效数据
        }
      }
    }

    // 按播放时间倒序排列
    history.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return history;
  }

  /// 获取最近播放
  Future<List<MusicHistoryItem>> getRecentHistory({int limit = 20}) async {
    final all = await getAllHistory();
    return all.take(limit).toList();
  }

  /// 清空播放历史
  Future<void> clearAllHistory() async {
    await init();
    if (_historyBox == null) return;

    await _historyBox!.clear();
    logger.i('MusicFavoritesService: 清空播放历史');
  }

  /// 从历史中移除
  Future<void> removeFromHistory(String musicPath) async {
    await init();
    if (_historyBox == null) return;

    await _historyBox!.delete(musicPath);
  }

  /// 限制历史记录数量
  Future<void> _trimHistory() async {
    if (_historyBox == null) return;

    if (_historyBox!.length > _maxHistoryItems) {
      final history = await getAllHistory();
      final toRemove = history.skip(_maxHistoryItems).toList();
      for (final item in toRemove) {
        await _historyBox!.delete(item.musicPath);
      }
    }
  }
}
