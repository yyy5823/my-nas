import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/data/services/video_favorites_service.dart';
import 'package:uuid/uuid.dart';

/// 收藏列表状态
class FavoritesState {
  const FavoritesState({
    this.favorites = const [],
    this.isLoading = false,
  });

  final List<VideoFavoriteItem> favorites;
  final bool isLoading;

  FavoritesState copyWith({
    List<VideoFavoriteItem>? favorites,
    bool? isLoading,
  }) =>
      FavoritesState(
        favorites: favorites ?? this.favorites,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// 收藏管理
class FavoritesNotifier extends StateNotifier<FavoritesState> {
  FavoritesNotifier() : super(const FavoritesState()) {
    _load();
  }

  final _service = VideoFavoritesService();

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    final favorites = await _service.getAllFavorites();
    state = FavoritesState(favorites: favorites);
  }

  /// 刷新列表
  Future<void> refresh() async {
    await _load();
  }

  /// 添加收藏
  Future<void> addFavorite(VideoFavoriteItem item) async {
    await _service.addToFavorites(item);
    await _load();
  }

  /// 移除收藏
  Future<void> removeFavorite(String videoPath) async {
    await _service.removeFromFavorites(videoPath);
    await _load();
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(VideoFavoriteItem item) async {
    final result = await _service.toggleFavorite(item);
    await _load();
    return result;
  }

  /// 检查是否已收藏
  Future<bool> isFavorite(String videoPath) async => _service.isFavorite(videoPath);

  /// 清空所有收藏
  Future<void> clearAll() async {
    await _service.clearAllFavorites();
    state = const FavoritesState();
  }
}

/// 收藏列表 provider
final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, FavoritesState>((ref) => FavoritesNotifier());

/// 检查特定视频是否已收藏
final isFavoriteProvider =
    FutureProvider.family<bool, String>((ref, videoPath) async {
  // 监听 favorites 变化
  ref.watch(favoritesProvider);
  return VideoFavoritesService().isFavorite(videoPath);
});

// ==================== 书签相关 ====================

/// 书签列表状态
class BookmarksState {
  const BookmarksState({
    this.bookmarks = const [],
    this.isLoading = false,
  });

  final List<VideoBookmarkItem> bookmarks;
  final bool isLoading;

  BookmarksState copyWith({
    List<VideoBookmarkItem>? bookmarks,
    bool? isLoading,
  }) =>
      BookmarksState(
        bookmarks: bookmarks ?? this.bookmarks,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// 书签管理
class BookmarksNotifier extends StateNotifier<BookmarksState> {
  BookmarksNotifier() : super(const BookmarksState()) {
    _load();
  }

  final _service = VideoFavoritesService();
  final _uuid = const Uuid();

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    final bookmarks = await _service.getAllBookmarks();
    state = BookmarksState(bookmarks: bookmarks);
  }

  /// 刷新列表
  Future<void> refresh() async {
    await _load();
  }

  /// 添加书签
  Future<void> addBookmark({
    required String videoPath,
    required String videoName,
    required Duration position,
    String? note,
  }) async {
    final bookmark = VideoBookmarkItem(
      id: _uuid.v4(),
      videoPath: videoPath,
      videoName: videoName,
      position: position,
      note: note,
      createdAt: DateTime.now(),
    );
    await _service.addBookmark(bookmark);
    await _load();
  }

  /// 删除书签
  Future<void> removeBookmark(String bookmarkId) async {
    await _service.removeBookmark(bookmarkId);
    await _load();
  }

  /// 更新书签备注
  Future<void> updateNote(String bookmarkId, String? note) async {
    await _service.updateBookmarkNote(bookmarkId, note);
    await _load();
  }

  /// 清空所有书签
  Future<void> clearAll() async {
    await _service.clearAllBookmarks();
    state = const BookmarksState();
  }

  /// 清空视频的所有书签
  Future<void> clearForVideo(String videoPath) async {
    await _service.clearBookmarksForVideo(videoPath);
    await _load();
  }
}

/// 书签列表 provider
final bookmarksProvider =
    StateNotifierProvider<BookmarksNotifier, BookmarksState>((ref) => BookmarksNotifier());

/// 获取特定视频的书签
final videoBookmarksProvider =
    FutureProvider.family<List<VideoBookmarkItem>, String>((ref, videoPath) async {
  // 监听 bookmarks 变化
  ref.watch(bookmarksProvider);
  return VideoFavoritesService().getBookmarksForVideo(videoPath);
});
