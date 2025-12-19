import 'dart:io';
import 'dart:typed_data';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// 移动端音乐库文件系统
///
/// 将系统音乐库映射为虚拟文件系统结构：
/// - /songs/          - 所有歌曲
/// - /albums/         - 按专辑分组
/// - /artists/        - 按艺术家分组
/// - /playlists/      - 播放列表
///
/// 路径格式：
/// - music://songs/{songId}
/// - music://albums/{albumId}/{songId}
/// - music://artists/{artistId}/{songId}
class MobileMusicFileSystem implements NasFileSystem {
  MobileMusicFileSystem();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  List<SongModel>? _cachedSongs;
  List<AlbumModel>? _cachedAlbums;
  List<ArtistModel>? _cachedArtists;
  final Map<int, SongModel> _songCache = {};

  /// 请求音乐库访问权限
  Future<bool> requestPermission() async {
    // Android 需要请求权限
    if (Platform.isAndroid) {
      final hasPermission = await _audioQuery.permissionsStatus();
      if (!hasPermission) {
        final granted = await _audioQuery.permissionsRequest();
        if (!granted) {
          logger.w('MobileMusicFileSystem: 权限被拒绝');
          return false;
        }
      }
    }
    // iOS 不需要额外权限
    return true;
  }

  /// 刷新缓存
  Future<void> refreshCache() async {
    _cachedSongs = null;
    _cachedAlbums = null;
    _cachedArtists = null;
    _songCache.clear();
  }

  /// 获取所有歌曲
  Future<List<SongModel>> _getSongs() async {
    if (_cachedSongs != null) return _cachedSongs!;

    _cachedSongs = await _audioQuery.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
    );

    // 缓存歌曲
    for (final song in _cachedSongs!) {
      _songCache[song.id] = song;
    }

    return _cachedSongs!;
  }

  /// 获取所有专辑
  Future<List<AlbumModel>> _getAlbums() async {
    if (_cachedAlbums != null) return _cachedAlbums!;

    _cachedAlbums = await _audioQuery.queryAlbums(
      sortType: AlbumSortType.ALBUM,
      orderType: OrderType.ASC_OR_SMALLER,
    );

    return _cachedAlbums!;
  }

  /// 获取所有艺术家
  Future<List<ArtistModel>> _getArtists() async {
    if (_cachedArtists != null) return _cachedArtists!;

    _cachedArtists = await _audioQuery.queryArtists(
      sortType: ArtistSortType.ARTIST,
      orderType: OrderType.ASC_OR_SMALLER,
    );

    return _cachedArtists!;
  }

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    logger.d('MobileMusicFileSystem: listDirectory - $path');

    // 根目录
    if (path == '/' || path.isEmpty) {
      return _listRoot();
    }

    // 所有歌曲
    if (path == '/songs' || path == '/songs/') {
      return _listAllSongs();
    }

    // 专辑列表
    if (path == '/albums' || path == '/albums/') {
      return _listAlbums();
    }

    // 艺术家列表
    if (path == '/artists' || path == '/artists/') {
      return _listArtists();
    }

    // 具体专辑内容
    if (path.startsWith('/albums/')) {
      final albumId = int.tryParse(path.replaceFirst('/albums/', '').replaceAll('/', ''));
      if (albumId != null) {
        return _listAlbumSongs(albumId);
      }
    }

    // 具体艺术家内容
    if (path.startsWith('/artists/')) {
      final artistId = int.tryParse(path.replaceFirst('/artists/', '').replaceAll('/', ''));
      if (artistId != null) {
        return _listArtistSongs(artistId);
      }
    }

    return [];
  }

  /// 列出根目录
  Future<List<FileItem>> _listRoot() async {
    final songs = await _getSongs();
    final albums = await _getAlbums();
    final artists = await _getArtists();

    return [
      FileItem(
        name: 'songs (${songs.length})',
        path: '/songs',
        isDirectory: true,
        size: songs.length,
      ),
      FileItem(
        name: 'albums (${albums.length})',
        path: '/albums',
        isDirectory: true,
        size: albums.length,
      ),
      FileItem(
        name: 'artists (${artists.length})',
        path: '/artists',
        isDirectory: true,
        size: artists.length,
      ),
    ];
  }

  /// 列出所有歌曲
  Future<List<FileItem>> _listAllSongs() async {
    final songs = await _getSongs();
    return songs.map((song) => _songToFileItem(song, '/songs')).toList();
  }

  /// 列出所有专辑
  Future<List<FileItem>> _listAlbums() async {
    final albums = await _getAlbums();
    return albums.map((album) => FileItem(
      name: album.album,
      path: '/albums/${album.id}',
      isDirectory: true,
      size: album.numOfSongs,
    )).toList();
  }

  /// 列出所有艺术家
  Future<List<FileItem>> _listArtists() async {
    final artists = await _getArtists();
    return artists.map((artist) => FileItem(
      name: artist.artist,
      path: '/artists/${artist.id}',
      isDirectory: true,
      size: artist.numberOfTracks ?? 0,
    )).toList();
  }

  /// 列出专辑内歌曲
  Future<List<FileItem>> _listAlbumSongs(int albumId) async {
    final songs = await _audioQuery.queryAudiosFrom(
      AudiosFromType.ALBUM_ID,
      albumId,
    );

    for (final song in songs) {
      _songCache[song.id] = song;
    }

    return songs.map((song) => _songToFileItem(song, '/albums/$albumId')).toList();
  }

  /// 列出艺术家的歌曲
  Future<List<FileItem>> _listArtistSongs(int artistId) async {
    final songs = await _audioQuery.queryAudiosFrom(
      AudiosFromType.ARTIST_ID,
      artistId,
    );

    for (final song in songs) {
      _songCache[song.id] = song;
    }

    return songs.map((song) => _songToFileItem(song, '/artists/$artistId')).toList();
  }

  /// 将 SongModel 转换为 FileItem
  FileItem _songToFileItem(SongModel song, String parentPath) {
    final extension = song.displayName.split('.').last;

    return FileItem(
      name: song.displayName,
      path: '$parentPath/${song.id}',
      isDirectory: false,
      size: song.size,
      modifiedTime: song.dateModified != null
          ? DateTime.fromMillisecondsSinceEpoch(song.dateModified! * 1000)
          : null,
      createdTime: song.dateAdded != null
          ? DateTime.fromMillisecondsSinceEpoch(song.dateAdded! * 1000)
          : null,
      extension: extension,
      mimeType: song.fileExtension,
    );
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    final songId = int.tryParse(path.split('/').last);
    if (songId == null) {
      throw Exception('Invalid song ID: $path');
    }

    final song = _songCache[songId];
    if (song == null) {
      throw Exception('Song not found: $songId');
    }

    return _songToFileItem(song, path.substring(0, path.lastIndexOf('/')));
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async {
    final songId = int.tryParse(path.split('/').last);
    if (songId == null) {
      throw Exception('Invalid song ID: $path');
    }

    final song = _songCache[songId];
    if (song == null) {
      throw Exception('Song not found: $songId');
    }

    final file = File(song.data);
    if (!await file.exists()) {
      throw Exception('File not found: ${song.data}');
    }

    if (range != null) {
      final length = await file.length();
      final end = range.end ?? length - 1;
      return file.openRead(range.start, end + 1);
    }

    return file.openRead();
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async {
    final songId = int.tryParse(path.split('/').last);
    if (songId == null) {
      throw Exception('Invalid song ID: $path');
    }

    final song = _songCache[songId];
    if (song == null) {
      throw Exception('Song not found: $songId');
    }

    return File(song.data).uri.toString();
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async {
    // on_audio_query 不支持缩略图 URL，返回 null
    return null;
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) {
    throw UnimplementedError('音乐库不支持 URL 流访问');
  }

  /// 获取专辑封面数据
  Future<Uint8List?> getAlbumArtwork(int albumId, {ThumbnailSize? size}) async {
    final thumbnailSize = size ?? ThumbnailSize.medium;
    return _audioQuery.queryArtwork(
      albumId,
      ArtworkType.ALBUM,
      size: thumbnailSize.pixels,
    );
  }

  /// 获取歌曲封面数据
  Future<Uint8List?> getSongArtwork(int songId, {ThumbnailSize? size}) async {
    final thumbnailSize = size ?? ThumbnailSize.medium;
    return _audioQuery.queryArtwork(
      songId,
      ArtworkType.AUDIO,
      size: thumbnailSize.pixels,
    );
  }

  /// 获取歌曲模型
  SongModel? getSong(int songId) => _songCache[songId];

  // ==================== 不支持的写操作 ====================

  @override
  Future<void> createDirectory(String path) async {
    throw UnsupportedError('音乐库不支持创建目录');
  }

  @override
  Future<void> delete(String path) async {
    throw UnsupportedError('音乐库不支持删除操作');
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    throw UnsupportedError('音乐库不支持重命名');
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    throw UnsupportedError('音乐库不支持复制');
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    throw UnsupportedError('音乐库不支持移动');
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    throw UnsupportedError('音乐库不支持上传');
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    throw UnsupportedError('音乐库不支持写入');
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    final songs = await _getSongs();
    final queryLower = query.toLowerCase();

    final results = <FileItem>[];
    for (final song in songs) {
      final title = song.title.toLowerCase();
      final artist = song.artist?.toLowerCase() ?? '';
      final album = song.album?.toLowerCase() ?? '';

      if (title.contains(queryLower) ||
          artist.contains(queryLower) ||
          album.contains(queryLower)) {
        results.add(_songToFileItem(song, '/songs'));
      }
    }

    return results;
  }
}
