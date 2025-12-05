import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/music/data/services/music_favorites_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';

/// 收藏列表状态
class MusicFavoritesState {
  const MusicFavoritesState({
    this.favorites = const [],
    this.isLoading = false,
  });

  final List<MusicFavoriteItem> favorites;
  final bool isLoading;

  MusicFavoritesState copyWith({
    List<MusicFavoriteItem>? favorites,
    bool? isLoading,
  }) =>
      MusicFavoritesState(
        favorites: favorites ?? this.favorites,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// 收藏管理
class MusicFavoritesNotifier extends StateNotifier<MusicFavoritesState> {
  MusicFavoritesNotifier() : super(const MusicFavoritesState()) {
    _load();
  }

  final _service = MusicFavoritesService.instance;

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    final favorites = await _service.getAllFavorites();
    state = MusicFavoritesState(favorites: favorites);
  }

  /// 刷新列表
  Future<void> refresh() async {
    await _load();
  }

  /// 添加收藏
  Future<void> addFavorite(MusicItem item) async {
    await _service.addToFavorites(item);
    await _load();
  }

  /// 移除收藏
  Future<void> removeFavorite(String musicPath) async {
    await _service.removeFromFavorites(musicPath);
    await _load();
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(MusicItem item) async {
    final result = await _service.toggleFavorite(item);
    await _load();
    return result;
  }

  /// 清空所有收藏
  Future<void> clearAll() async {
    await _service.clearAllFavorites();
    state = const MusicFavoritesState();
  }
}

/// 收藏列表 provider
final musicFavoritesProvider =
    StateNotifierProvider<MusicFavoritesNotifier, MusicFavoritesState>((ref) => MusicFavoritesNotifier());

/// 检查特定音乐是否已收藏
final isMusicFavoriteProvider =
    FutureProvider.family<bool, String>((ref, musicPath) async {
  // 监听 favorites 变化
  ref.watch(musicFavoritesProvider);
  return MusicFavoritesService.instance.isFavorite(musicPath);
});

// ==================== 播放历史相关 ====================

/// 播放历史状态
class MusicHistoryState {
  const MusicHistoryState({
    this.history = const [],
    this.isLoading = false,
  });

  final List<MusicHistoryItem> history;
  final bool isLoading;

  MusicHistoryState copyWith({
    List<MusicHistoryItem>? history,
    bool? isLoading,
  }) =>
      MusicHistoryState(
        history: history ?? this.history,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// 播放历史管理
class MusicHistoryNotifier extends StateNotifier<MusicHistoryState> {
  MusicHistoryNotifier() : super(const MusicHistoryState()) {
    _load();
  }

  final _service = MusicFavoritesService.instance;

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    final history = await _service.getAllHistory();
    state = MusicHistoryState(history: history);
  }

  /// 刷新列表
  Future<void> refresh() async {
    await _load();
  }

  /// 添加到历史
  Future<void> addToHistory(MusicItem item) async {
    await _service.addToHistory(item);
    await _load();
  }

  /// 更新播放位置
  Future<void> updatePlayPosition(String musicPath, Duration position) async {
    await _service.updatePlayPosition(musicPath, position);
  }

  /// 从历史中移除
  Future<void> removeFromHistory(String musicPath) async {
    await _service.removeFromHistory(musicPath);
    await _load();
  }

  /// 清空所有历史
  Future<void> clearAll() async {
    await _service.clearAllHistory();
    state = const MusicHistoryState();
  }
}

/// 播放历史 provider
final musicHistoryProvider =
    StateNotifierProvider<MusicHistoryNotifier, MusicHistoryState>((ref) => MusicHistoryNotifier());

/// 最近播放 provider
final recentMusicProvider =
    FutureProvider<List<MusicHistoryItem>>((ref) async {
  // 监听 history 变化
  ref.watch(musicHistoryProvider);
  return MusicFavoritesService.instance.getRecentHistory();
});

/// 最近播放 - 返回 MusicItem 列表
final recentTracksProvider = Provider<List<MusicItem>>((ref) {
  final historyState = ref.watch(musicHistoryProvider);
  return historyState.history
      .take(50)
      .map((h) => h.toMusicItem())
      .toList();
});
