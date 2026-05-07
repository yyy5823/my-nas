import 'package:audio_service/audio_service.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/features/music/data/services/music_favorites_service.dart';
import 'package:my_nas/features/music/data/services/playlist_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';

/// MediaBrowserService 树根 ID
const String kMediaRootId = 'root';
const String kMediaFavoritesId = 'favorites';
const String kMediaRecentId = 'recent';
const String kMediaPlaylistsId = 'playlists';
const String _kPlaylistPrefix = 'playlist:';
const String _kTrackPrefix = 'track:';

/// 提供给 Android Auto / CarPlay 浏览的内容树。
///
/// 树结构：
///   root
///   ├─ favorites      (用户收藏的曲目)
///   ├─ recent         (最近播放)
///   └─ playlists
///      └─ `<id>`      (播放列表的曲目)
///
/// 播放回调由播放层注入：在 MusicPlayerNotifier 初始化时把
/// `playQueueByPaths` 函数注册到 [playFromPathsHandler]。当用户在车载界面
/// 触发播放时，本服务负责把 mediaId → 路径列表，再交给注入的回调真正起播。
class MusicBrowserService {
  MusicBrowserService._();
  static final MusicBrowserService instance = MusicBrowserService._();

  /// 由播放层注入：把一组路径加入队列并起播。
  /// 第二个参数为初始播放索引。
  Future<void> Function(List<String> paths, int startIndex)?
      playFromPathsHandler;

  /// 根节点 / 所有可浏览节点
  Future<List<MediaItem>> getChildren(String parentMediaId) async {
    try {
      if (parentMediaId == AudioService.browsableRootId ||
          parentMediaId == kMediaRootId) {
        return _rootChildren();
      }
      if (parentMediaId == kMediaFavoritesId) return _favoriteChildren();
      if (parentMediaId == kMediaRecentId) return _recentChildren();
      if (parentMediaId == kMediaPlaylistsId) return _playlistFolderChildren();
      if (parentMediaId.startsWith(_kPlaylistPrefix)) {
        return _playlistTrackChildren(
          parentMediaId.substring(_kPlaylistPrefix.length),
        );
      }
      return const [];
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'browser.getChildren', {'parent': parentMediaId});
      return const [];
    }
  }

  Future<MediaItem?> getMediaItem(String mediaId) async {
    if (mediaId == kMediaFavoritesId) {
      return _folder(kMediaFavoritesId, '收藏');
    }
    if (mediaId == kMediaRecentId) {
      return _folder(kMediaRecentId, '最近播放');
    }
    if (mediaId == kMediaPlaylistsId) {
      return _folder(kMediaPlaylistsId, '播放列表');
    }
    return null;
  }

  /// 用户在 Auto / CarPlay 选中曲目后回调进来。
  Future<void> playFromMediaId(String mediaId) async {
    final handler = playFromPathsHandler;
    if (handler == null) return;

    if (mediaId.startsWith(_kTrackPrefix)) {
      // 单曲：在「全部收藏」或「最近播放」上下文里选了一首，构造单条队列
      final path = mediaId.substring(_kTrackPrefix.length);
      await handler([path], 0);
      return;
    }

    if (mediaId.startsWith(_kPlaylistPrefix)) {
      // 整张歌单：从头开始播
      final id = mediaId.substring(_kPlaylistPrefix.length);
      final entry = await PlaylistService().getPlaylist(id);
      if (entry != null && entry.trackPaths.isNotEmpty) {
        await handler(entry.trackPaths, 0);
      }
      return;
    }

    if (mediaId == kMediaFavoritesId) {
      final favs = await MusicFavoritesService().getAllFavorites();
      final paths = favs.map((f) => f.musicPath).toList();
      if (paths.isNotEmpty) await handler(paths, 0);
    }
  }

  /// 语音搜索：按曲目名 / 歌手匹配收藏 + 最近播放。
  Future<void> playFromSearch(String query) async {
    final handler = playFromPathsHandler;
    if (handler == null || query.trim().isEmpty) return;
    final results = await search(query);
    if (results.isEmpty) return;
    final paths = results
        .map((m) => m.id.startsWith(_kTrackPrefix)
            ? m.id.substring(_kTrackPrefix.length)
            : null)
        .whereType<String>()
        .toList();
    if (paths.isNotEmpty) await handler(paths, 0);
  }

  Future<List<MediaItem>> search(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return const [];
    final favSvc = MusicFavoritesService();
    await favSvc.init();
    final favs = await favSvc.getAllFavorites();
    final history = await favSvc.getRecentHistory(limit: 200);

    final hits = <MediaItem>[];
    final seen = <String>{};
    for (final f in favs) {
      final name = f.musicName.toLowerCase();
      final artist = (f.artist ?? '').toLowerCase();
      if ((name.contains(q) || artist.contains(q)) && seen.add(f.musicPath)) {
        hits.add(_trackItem(
          path: f.musicPath,
          title: f.musicName,
          artist: f.artist,
          album: f.album,
          coverUrl: f.coverUrl,
          duration: f.duration,
        ));
      }
    }
    for (final h in history) {
      final name = h.musicName.toLowerCase();
      final artist = (h.artist ?? '').toLowerCase();
      if ((name.contains(q) || artist.contains(q)) && seen.add(h.musicPath)) {
        hits.add(_trackItem(
          path: h.musicPath,
          title: h.musicName,
          artist: h.artist,
          album: h.album,
          coverUrl: h.coverUrl,
          duration: h.duration,
        ));
      }
    }
    return hits;
  }

  // ============ 私有：构建子项 ============

  List<MediaItem> _rootChildren() => [
        _folder(kMediaFavoritesId, '收藏'),
        _folder(kMediaRecentId, '最近播放'),
        _folder(kMediaPlaylistsId, '播放列表'),
      ];

  Future<List<MediaItem>> _favoriteChildren() async {
    final svc = MusicFavoritesService();
    await svc.init();
    final list = await svc.getAllFavorites();
    return [
      for (final f in list)
        _trackItem(
          path: f.musicPath,
          title: f.musicName,
          artist: f.artist,
          album: f.album,
          coverUrl: f.coverUrl,
          duration: f.duration,
        ),
    ];
  }

  Future<List<MediaItem>> _recentChildren() async {
    final svc = MusicFavoritesService();
    await svc.init();
    final list = await svc.getRecentHistory(limit: 100);
    return [
      for (final h in list)
        _trackItem(
          path: h.musicPath,
          title: h.musicName,
          artist: h.artist,
          album: h.album,
          coverUrl: h.coverUrl,
          duration: h.duration,
        ),
    ];
  }

  Future<List<MediaItem>> _playlistFolderChildren() async {
    final list = await PlaylistService().getAllPlaylists();
    return [
      for (final p in list)
        MediaItem(
          id: '$_kPlaylistPrefix${p.id}',
          title: p.name,
          album: '${p.trackCount} 首',
          playable: false,
          extras: const {'browsable': true},
        ),
    ];
  }

  Future<List<MediaItem>> _playlistTrackChildren(String playlistId) async {
    final entry = await PlaylistService().getPlaylist(playlistId);
    if (entry == null) return const [];
    return [
      for (final p in entry.trackPaths)
        _trackItem(path: p, title: _basenameOf(p)),
    ];
  }

  MediaItem _folder(String id, String title) => MediaItem(
        id: id,
        title: title,
        playable: false,
        extras: const {'browsable': true},
      );

  MediaItem _trackItem({
    required String path,
    required String title,
    String? artist,
    String? album,
    String? coverUrl,
    Duration? duration,
  }) {
    final art =
        coverUrl != null && coverUrl.isNotEmpty ? Uri.tryParse(coverUrl) : null;
    return MediaItem(
      id: '$_kTrackPrefix$path',
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      artUri: art,
      playable: true,
    );
  }

  String _basenameOf(String path) {
    final i = path.lastIndexOf('/');
    if (i < 0) return path;
    return path.substring(i + 1);
  }

  /// 由播放层调用：根据收藏/历史里的元数据构造一个最小可播放的 [MusicItem]。
  /// 若信息不全，调用方仍需在拿到队列后用真正的源管理器解析 url。
  static MusicItem buildMusicItemFromFavorite(MusicFavoriteItem f) =>
      MusicItem(
        id: '${f.sourceId ?? ''}_${f.musicPath}',
        name: f.musicName,
        path: f.musicPath,
        url: f.musicUrl,
        sourceId: f.sourceId,
        title: f.musicName,
        artist: f.artist,
        album: f.album,
        coverUrl: f.coverUrl,
        duration: f.duration,
      );
}
