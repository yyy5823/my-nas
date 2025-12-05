import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/music/data/services/playlist_service.dart';

export 'package:my_nas/features/music/data/services/playlist_service.dart' show PlaylistEntry;

/// 播放列表状态
class PlaylistState {
  const PlaylistState({
    this.playlists = const [],
    this.isLoading = false,
  });

  final List<PlaylistEntry> playlists;
  final bool isLoading;

  PlaylistState copyWith({
    List<PlaylistEntry>? playlists,
    bool? isLoading,
  }) =>
      PlaylistState(
        playlists: playlists ?? this.playlists,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// 播放列表管理
class PlaylistNotifier extends StateNotifier<PlaylistState> {
  PlaylistNotifier() : super(const PlaylistState()) {
    _load();
  }

  final _service = PlaylistService.instance;

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    final playlists = await _service.getAllPlaylists();
    state = PlaylistState(playlists: playlists);
  }

  /// 刷新列表
  Future<void> refresh() async {
    await _load();
  }

  /// 创建新播放列表
  Future<PlaylistEntry?> createPlaylist({
    required String name,
    String? description,
    List<String> initialTracks = const [],
  }) async {
    final playlist = await _service.createPlaylist(
      name: name,
      description: description,
      initialTracks: initialTracks,
    );
    await _load();
    return playlist;
  }

  /// 删除播放列表
  Future<void> deletePlaylist(String id) async {
    await _service.deletePlaylist(id);
    await _load();
  }

  /// 重命名播放列表
  Future<void> renamePlaylist(String id, String newName) async {
    await _service.renamePlaylist(id, newName);
    await _load();
  }

  /// 添加歌曲到播放列表
  Future<void> addToPlaylist(String playlistId, String trackPath) async {
    await _service.addToPlaylist(playlistId, trackPath);
    await _load();
  }

  /// 批量添加歌曲到播放列表
  Future<void> addTracksToPlaylist(String playlistId, List<String> trackPaths) async {
    await _service.addTracksToPlaylist(playlistId, trackPaths);
    await _load();
  }

  /// 从播放列表移除歌曲
  Future<void> removeFromPlaylist(String playlistId, String trackPath) async {
    await _service.removeFromPlaylist(playlistId, trackPath);
    await _load();
  }

  /// 重新排序播放列表
  Future<void> reorderPlaylist(String playlistId, int oldIndex, int newIndex) async {
    await _service.reorderPlaylist(playlistId, oldIndex, newIndex);
    await _load();
  }

  /// 清空播放列表
  Future<void> clearPlaylist(String playlistId) async {
    await _service.clearPlaylist(playlistId);
    await _load();
  }

  /// 清空所有播放列表
  Future<void> clearAll() async {
    await _service.clearAll();
    state = const PlaylistState();
  }
}

/// 播放列表 provider
final playlistProvider =
    StateNotifierProvider<PlaylistNotifier, PlaylistState>((ref) => PlaylistNotifier());

/// 单个播放列表 provider
final playlistByIdProvider =
    FutureProvider.family<PlaylistEntry?, String>((ref, id) async {
  // 监听列表变化
  ref.watch(playlistProvider);
  return PlaylistService.instance.getPlaylist(id);
});
