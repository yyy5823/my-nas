import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/media_tracking/presentation/providers/trakt_provider.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/service_adapters/trakt/api/trakt_api.dart';

/// Trakt 同步状态
class TraktSyncState {
  const TraktSyncState({
    this.playbackProgress = const [],
    this.isLoading = false,
    this.lastSyncTime,
    this.errorMessage,
  });

  final List<TraktPlaybackItem> playbackProgress;
  final bool isLoading;
  final DateTime? lastSyncTime;
  final String? errorMessage;

  TraktSyncState copyWith({
    List<TraktPlaybackItem>? playbackProgress,
    bool? isLoading,
    DateTime? lastSyncTime,
    String? errorMessage,
    bool clearError = false,
  }) =>
      TraktSyncState(
        playbackProgress: playbackProgress ?? this.playbackProgress,
        isLoading: isLoading ?? this.isLoading,
        lastSyncTime: lastSyncTime ?? this.lastSyncTime,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

/// Trakt 同步 Provider
final traktSyncProvider =
    StateNotifierProvider<TraktSyncNotifier, TraktSyncState>(
  TraktSyncNotifier.new,
);

class TraktSyncNotifier extends StateNotifier<TraktSyncState> {
  TraktSyncNotifier(this._ref) : super(const TraktSyncState());

  final Ref _ref;

  /// 获取 Trakt API 实例
  TraktApi? get _api => _ref.read(traktConnectionProvider.notifier).api;

  /// 是否已连接 Trakt
  bool get isConnected =>
      _ref.read(traktConnectionProvider).status == TraktConnectionStatus.connected;

  /// 刷新播放进度列表
  Future<void> refreshPlaybackProgress() async {
    if (!isConnected || _api == null) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final progress = await _api!.getPlaybackProgress();
      state = state.copyWith(
        playbackProgress: progress,
        isLoading: false,
        lastSyncTime: DateTime.now(),
      );
      logger.i('TraktSync: 获取播放进度成功，共 ${progress.length} 项');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'TraktSync.refreshPlaybackProgress');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// 根据 TMDB ID 查找播放进度
  TraktPlaybackItem? findProgressByTmdbId(int tmdbId, {int? season, int? episode}) {
    for (final item in state.playbackProgress) {
      if (item.tmdbId == tmdbId) {
        // 如果是剧集，还需要匹配季和集
        if (item.type == 'episode' && season != null && episode != null) {
          final epInfo = item.episodeInfo;
          if (epInfo != null && epInfo.$1 == season && epInfo.$2 == episode) {
            return item;
          }
        } else if (item.type == 'movie') {
          return item;
        }
      }
    }
    return null;
  }

  /// 根据 IMDB ID 查找播放进度
  TraktPlaybackItem? findProgressByImdbId(String imdbId, {int? season, int? episode}) {
    for (final item in state.playbackProgress) {
      if (item.imdbId == imdbId) {
        // 如果是剧集，还需要匹配季和集
        if (item.type == 'episode' && season != null && episode != null) {
          final epInfo = item.episodeInfo;
          if (epInfo != null && epInfo.$1 == season && epInfo.$2 == episode) {
            return item;
          }
        } else if (item.type == 'movie') {
          return item;
        }
      }
    }
    return null;
  }

  /// 删除播放进度
  Future<void> deleteProgress(int playbackId) async {
    if (!isConnected || _api == null) return;

    try {
      await _api!.deletePlaybackProgress(playbackId);
      // 从本地列表中移除
      state = state.copyWith(
        playbackProgress: state.playbackProgress
            .where((item) => item.id != playbackId)
            .toList(),
      );
      logger.i('TraktSync: 删除播放进度成功 id=$playbackId');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'TraktSync.deleteProgress');
    }
  }

  /// 获取本地视频对应的 Trakt 进度
  ///
  /// 根据视频元数据中的 TMDB/IMDB ID 匹配 Trakt 进度
  Future<TraktPlaybackItem?> getProgressForVideo(
    String videoPath,
    String sourceId,
  ) async {
    if (state.playbackProgress.isEmpty) {
      await refreshPlaybackProgress();
    }

    try {
      final dbService = VideoDatabaseService();
      await dbService.init();
      final metadata = await dbService.get(sourceId, videoPath);

      if (metadata == null) return null;

      // 尝试通过 TMDB ID 匹配
      if (metadata.tmdbId != null) {
        final progress = findProgressByTmdbId(
          metadata.tmdbId!,
          season: metadata.seasonNumber,
          episode: metadata.episodeNumber,
        );
        if (progress != null) return progress;
      }

      // 尝试通过 IMDB ID 匹配
      if (metadata.imdbId != null) {
        return findProgressByImdbId(
          metadata.imdbId!,
          season: metadata.seasonNumber,
          episode: metadata.episodeNumber,
        );
      }

      return null;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '获取视频 Trakt 进度失败');
      return null;
    }
  }

  /// 将 Trakt 进度转换为播放位置
  ///
  /// [progress] Trakt 进度 (0.0 - 100.0)
  /// [duration] 视频总时长
  Duration progressToDuration(double progress, Duration duration) =>
      Duration(
        milliseconds: (duration.inMilliseconds * progress / 100).round(),
      );
}

/// 获取继续观看列表（结合本地和 Trakt 进度）
///
/// 此 Provider 合并本地播放历史和 Trakt 进度，提供统一的继续观看列表
final combinedContinueWatchingProvider =
    FutureProvider<List<ContinueWatchingItem>>((ref) async {
  final traktSync = ref.watch(traktSyncProvider);
  final traktConnection = ref.watch(traktConnectionProvider);

  final items = <ContinueWatchingItem>[];

  // 如果已连接 Trakt，添加 Trakt 进度
  if (traktConnection.isConnected) {
    for (final progress in traktSync.playbackProgress) {
      items.add(ContinueWatchingItem(
        source: ContinueWatchingSource.trakt,
        traktProgress: progress,
        progress: progress.progress,
        updatedAt: progress.pausedAt,
      ));
    }
  }

  // 按更新时间排序
  items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  return items;
});

/// 继续观看来源
enum ContinueWatchingSource {
  local,
  trakt,
  mediaServer,
}

/// 继续观看项
class ContinueWatchingItem {
  const ContinueWatchingItem({
    required this.source,
    required this.progress,
    required this.updatedAt,
    this.videoPath,
    this.sourceId,
    this.traktProgress,
    this.metadata,
  });

  final ContinueWatchingSource source;
  final double progress; // 0.0 - 100.0
  final DateTime updatedAt;
  final String? videoPath;
  final String? sourceId;
  final TraktPlaybackItem? traktProgress;
  final VideoMetadata? metadata;

  /// 获取显示标题
  String get displayTitle {
    if (traktProgress != null) {
      if (traktProgress!.type == 'movie') {
        return traktProgress!.movie?.title ?? '未知电影';
      } else {
        final show = traktProgress!.show?.title ?? '未知剧集';
        final ep = traktProgress!.episode;
        if (ep != null) {
          return '$show S${ep.season.toString().padLeft(2, '0')}E${ep.number.toString().padLeft(2, '0')}';
        }
        return show;
      }
    }
    return metadata?.displayTitle ?? videoPath ?? '未知视频';
  }

  /// 获取海报 URL
  String? get posterUrl => metadata?.displayPosterUrl;

  /// 获取 TMDB ID
  int? get tmdbId {
    if (traktProgress != null) return traktProgress!.tmdbId;
    return metadata?.tmdbId;
  }
}

/// Trakt 观看历史 Provider
final traktWatchHistoryProvider =
    FutureProvider.autoDispose<List<TraktHistoryItem>>((ref) async {
  final traktConnection = ref.watch(traktConnectionProvider);
  if (!traktConnection.isConnected) return [];

  final api = ref.read(traktConnectionProvider.notifier).api;
  if (api == null) return [];

  try {
    return await api.getWatchedHistory(limit: 50);
  } on Exception catch (e, st) {
    AppError.handle(e, st, 'TraktWatchHistory.fetch');
    return [];
  }
});

/// Trakt 待看列表 Provider
final traktWatchlistProvider =
    FutureProvider.autoDispose<List<TraktWatchlistItem>>((ref) async {
  final traktConnection = ref.watch(traktConnectionProvider);
  if (!traktConnection.isConnected) return [];

  final api = ref.read(traktConnectionProvider.notifier).api;
  if (api == null) return [];

  try {
    return await api.getWatchlist(limit: 50);
  } on Exception catch (e, st) {
    AppError.handle(e, st, 'TraktWatchlist.fetch');
    return [];
  }
});
