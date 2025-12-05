import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';

/// 播放列表状态
class PlaylistState {
  const PlaylistState({
    this.items = const [],
    this.currentIndex = -1,
    this.repeatMode = RepeatMode.none,
    this.shuffleEnabled = false,
  });

  final List<VideoItem> items;
  final int currentIndex;
  final RepeatMode repeatMode;
  final bool shuffleEnabled;

  VideoItem? get currentItem => currentIndex >= 0 && currentIndex < items.length
      ? items[currentIndex]
      : null;

  bool get hasNext => currentIndex < items.length - 1;

  bool get hasPrevious => currentIndex > 0;

  bool get isEmpty => items.isEmpty;

  int get length => items.length;

  PlaylistState copyWith({
    List<VideoItem>? items,
    int? currentIndex,
    RepeatMode? repeatMode,
    bool? shuffleEnabled,
  }) => PlaylistState(
    items: items ?? this.items,
    currentIndex: currentIndex ?? this.currentIndex,
    repeatMode: repeatMode ?? this.repeatMode,
    shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
  );
}

/// 重复模式
enum RepeatMode {
  none, // 不重复
  all, // 列表循环
  one, // 单曲循环
}

/// 播放列表管理
class PlaylistNotifier extends StateNotifier<PlaylistState> {
  PlaylistNotifier() : super(const PlaylistState());

  List<int>? _shuffleOrder;

  /// 设置播放列表
  void setPlaylist(List<VideoItem> items, {int startIndex = 0}) {
    state = PlaylistState(
      items: items,
      currentIndex: startIndex.clamp(0, items.length - 1),
      repeatMode: state.repeatMode,
      shuffleEnabled: state.shuffleEnabled,
    );
    if (state.shuffleEnabled) {
      _generateShuffleOrder();
    }
  }

  /// 添加到播放列表
  void addToPlaylist(VideoItem item) {
    state = state.copyWith(items: [...state.items, item]);
  }

  /// 批量添加到播放列表
  void addAllToPlaylist(List<VideoItem> items) {
    state = state.copyWith(items: [...state.items, ...items]);
  }

  /// 从播放列表移除
  void removeFromPlaylist(int index) {
    if (index < 0 || index >= state.items.length) return;

    final newItems = [...state.items]..removeAt(index);
    var newIndex = state.currentIndex;

    if (index < state.currentIndex) {
      newIndex--;
    } else if (index == state.currentIndex) {
      newIndex = newIndex.clamp(0, newItems.length - 1);
    }

    state = state.copyWith(
      items: newItems,
      currentIndex: newItems.isEmpty ? -1 : newIndex,
    );
  }

  /// 清空播放列表
  void clearPlaylist() {
    state = const PlaylistState();
    _shuffleOrder = null;
  }

  /// 播放指定索引
  void playAt(int index) {
    if (index < 0 || index >= state.items.length) return;
    state = state.copyWith(currentIndex: index);
  }

  /// 播放下一个
  VideoItem? playNext() {
    if (state.isEmpty) return null;

    int nextIndex;

    if (state.shuffleEnabled && _shuffleOrder != null) {
      final currentShuffleIndex = _shuffleOrder!.indexOf(state.currentIndex);
      if (currentShuffleIndex < _shuffleOrder!.length - 1) {
        nextIndex = _shuffleOrder![currentShuffleIndex + 1];
      } else {
        // 随机列表结束
        if (state.repeatMode == RepeatMode.all) {
          _generateShuffleOrder();
          nextIndex = _shuffleOrder![0];
        } else {
          return null;
        }
      }
    } else {
      if (state.currentIndex < state.items.length - 1) {
        nextIndex = state.currentIndex + 1;
      } else if (state.repeatMode == RepeatMode.all) {
        nextIndex = 0;
      } else {
        return null;
      }
    }

    state = state.copyWith(currentIndex: nextIndex);
    return state.currentItem;
  }

  /// 播放上一个
  VideoItem? playPrevious() {
    if (state.isEmpty) return null;

    int prevIndex;

    if (state.shuffleEnabled && _shuffleOrder != null) {
      final currentShuffleIndex = _shuffleOrder!.indexOf(state.currentIndex);
      if (currentShuffleIndex > 0) {
        prevIndex = _shuffleOrder![currentShuffleIndex - 1];
      } else {
        return null;
      }
    } else {
      if (state.currentIndex > 0) {
        prevIndex = state.currentIndex - 1;
      } else if (state.repeatMode == RepeatMode.all) {
        prevIndex = state.items.length - 1;
      } else {
        return null;
      }
    }

    state = state.copyWith(currentIndex: prevIndex);
    return state.currentItem;
  }

  /// 获取下一个视频（不改变状态）
  VideoItem? peekNext() {
    if (state.isEmpty) return null;

    int nextIndex;

    if (state.repeatMode == RepeatMode.one) {
      return state.currentItem;
    }

    if (state.shuffleEnabled && _shuffleOrder != null) {
      final currentShuffleIndex = _shuffleOrder!.indexOf(state.currentIndex);
      if (currentShuffleIndex < _shuffleOrder!.length - 1) {
        nextIndex = _shuffleOrder![currentShuffleIndex + 1];
      } else if (state.repeatMode == RepeatMode.all) {
        nextIndex = _shuffleOrder![0];
      } else {
        return null;
      }
    } else {
      if (state.currentIndex < state.items.length - 1) {
        nextIndex = state.currentIndex + 1;
      } else if (state.repeatMode == RepeatMode.all) {
        nextIndex = 0;
      } else {
        return null;
      }
    }

    return state.items[nextIndex];
  }

  /// 切换重复模式
  void toggleRepeatMode() {
    final nextMode = switch (state.repeatMode) {
      RepeatMode.none => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.none,
    };
    state = state.copyWith(repeatMode: nextMode);
  }

  /// 设置重复模式
  void setRepeatMode(RepeatMode mode) {
    state = state.copyWith(repeatMode: mode);
  }

  /// 切换随机播放
  void toggleShuffle() {
    final newShuffle = !state.shuffleEnabled;
    state = state.copyWith(shuffleEnabled: newShuffle);
    if (newShuffle) {
      _generateShuffleOrder();
    } else {
      _shuffleOrder = null;
    }
  }

  /// 设置随机播放
  void setShuffle({required bool enabled}) {
    state = state.copyWith(shuffleEnabled: enabled);
    if (enabled) {
      _generateShuffleOrder();
    } else {
      _shuffleOrder = null;
    }
  }

  /// 移动播放列表项
  void moveItem(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= state.items.length ||
        newIndex < 0 ||
        newIndex >= state.items.length) {
      return;
    }

    final items = [...state.items];
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);

    var currentIndex = state.currentIndex;
    if (oldIndex == currentIndex) {
      currentIndex = newIndex;
    } else if (oldIndex < currentIndex && newIndex >= currentIndex) {
      currentIndex--;
    } else if (oldIndex > currentIndex && newIndex <= currentIndex) {
      currentIndex++;
    }

    state = state.copyWith(items: items, currentIndex: currentIndex);
  }

  void _generateShuffleOrder() {
    final indices = List.generate(state.items.length, (i) => i)..shuffle();

    // 确保当前播放的在第一位
    if (state.currentIndex >= 0) {
      indices
        ..remove(state.currentIndex)
        ..insert(0, state.currentIndex);
    }

    _shuffleOrder = indices;
  }
}

/// 播放列表 provider
final playlistProvider = StateNotifierProvider<PlaylistNotifier, PlaylistState>(
  (ref) => PlaylistNotifier(),
);
