import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 播放列表项
class PlaylistEntry {
  const PlaylistEntry({
    required this.id,
    required this.name,
    this.description,
    this.coverUrl,
    required this.trackPaths,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final String? coverUrl;
  final List<String> trackPaths;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get trackCount => trackPaths.length;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'coverUrl': coverUrl,
        'trackPaths': trackPaths,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory PlaylistEntry.fromMap(Map<dynamic, dynamic> map) => PlaylistEntry(
        id: map['id'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
        coverUrl: map['coverUrl'] as String?,
        trackPaths: (map['trackPaths'] as List).cast<String>(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
      );

  PlaylistEntry copyWith({
    String? id,
    String? name,
    String? description,
    String? coverUrl,
    List<String>? trackPaths,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      PlaylistEntry(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        coverUrl: coverUrl ?? this.coverUrl,
        trackPaths: trackPaths ?? this.trackPaths,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );
}

/// 播放列表服务
class PlaylistService {
  PlaylistService._();
  static final instance = PlaylistService._();

  static const _boxName = 'music_playlists';

  Box<Map<dynamic, dynamic>>? _box;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    try {
      _box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
      _initialized = true;
      logger.i('PlaylistService: 初始化完成');
    } on Exception catch (e) {
      logger.e('PlaylistService: 初始化失败', e);
    }
  }

  /// 创建新播放列表
  Future<PlaylistEntry?> createPlaylist({
    required String name,
    String? description,
    List<String> initialTracks = const [],
  }) async {
    await init();
    if (_box == null) return null;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now();
    final playlist = PlaylistEntry(
      id: id,
      name: name,
      description: description,
      trackPaths: initialTracks,
      createdAt: now,
      updatedAt: now,
    );

    await _box!.put(id, playlist.toMap());
    logger.i('PlaylistService: 创建播放列表 $name');
    return playlist;
  }

  /// 获取所有播放列表
  Future<List<PlaylistEntry>> getAllPlaylists() async {
    await init();
    if (_box == null) return [];

    final playlists = <PlaylistEntry>[];
    for (final key in _box!.keys) {
      final data = _box!.get(key);
      if (data != null) {
        try {
          playlists.add(PlaylistEntry.fromMap(data));
        } on Exception catch (_) {
          // 跳过无效数据
        }
      }
    }

    // 按更新时间倒序排列
    playlists.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return playlists;
  }

  /// 获取单个播放列表
  Future<PlaylistEntry?> getPlaylist(String id) async {
    await init();
    if (_box == null) return null;

    final data = _box!.get(id);
    if (data != null) {
      try {
        return PlaylistEntry.fromMap(data);
      } on Exception catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 更新播放列表
  Future<void> updatePlaylist(PlaylistEntry playlist) async {
    await init();
    if (_box == null) return;

    await _box!.put(playlist.id, playlist.toMap());
    logger.i('PlaylistService: 更新播放列表 ${playlist.name}');
  }

  /// 删除播放列表
  Future<void> deletePlaylist(String id) async {
    await init();
    if (_box == null) return;

    await _box!.delete(id);
    logger.i('PlaylistService: 删除播放列表 $id');
  }

  /// 重命名播放列表
  Future<void> renamePlaylist(String id, String newName) async {
    final playlist = await getPlaylist(id);
    if (playlist != null) {
      await updatePlaylist(playlist.copyWith(name: newName));
    }
  }

  /// 添加歌曲到播放列表
  Future<void> addToPlaylist(String playlistId, String trackPath) async {
    final playlist = await getPlaylist(playlistId);
    if (playlist != null && !playlist.trackPaths.contains(trackPath)) {
      final newPaths = [...playlist.trackPaths, trackPath];
      await updatePlaylist(playlist.copyWith(trackPaths: newPaths));
    }
  }

  /// 批量添加歌曲到播放列表
  Future<void> addTracksToPlaylist(String playlistId, List<String> trackPaths) async {
    final playlist = await getPlaylist(playlistId);
    if (playlist != null) {
      final existingPaths = Set<String>.from(playlist.trackPaths);
      final newPaths = trackPaths.where((p) => !existingPaths.contains(p)).toList();
      if (newPaths.isNotEmpty) {
        await updatePlaylist(
          playlist.copyWith(trackPaths: [...playlist.trackPaths, ...newPaths]),
        );
      }
    }
  }

  /// 从播放列表移除歌曲
  Future<void> removeFromPlaylist(String playlistId, String trackPath) async {
    final playlist = await getPlaylist(playlistId);
    if (playlist != null) {
      final newPaths = playlist.trackPaths.where((p) => p != trackPath).toList();
      await updatePlaylist(playlist.copyWith(trackPaths: newPaths));
    }
  }

  /// 重新排序播放列表中的歌曲
  Future<void> reorderPlaylist(String playlistId, int oldIndex, int newIndex) async {
    final playlist = await getPlaylist(playlistId);
    if (playlist != null) {
      final newPaths = [...playlist.trackPaths];
      if (oldIndex < 0 || oldIndex >= newPaths.length) return;
      if (newIndex < 0 || newIndex >= newPaths.length) return;

      final item = newPaths.removeAt(oldIndex);
      newPaths.insert(newIndex, item);
      await updatePlaylist(playlist.copyWith(trackPaths: newPaths));
    }
  }

  /// 清空播放列表
  Future<void> clearPlaylist(String playlistId) async {
    final playlist = await getPlaylist(playlistId);
    if (playlist != null) {
      await updatePlaylist(playlist.copyWith(trackPaths: []));
    }
  }

  /// 清空所有播放列表
  Future<void> clearAll() async {
    await init();
    if (_box == null) return;

    await _box!.clear();
    logger.i('PlaylistService: 清空所有播放列表');
  }
}
