import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/media_tracking/presentation/providers/trakt_provider.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/service_adapters/trakt/api/trakt_api.dart';

/// Trakt Scrobble 服务
///
/// 负责向 Trakt 上报播放状态（开始、暂停、停止）
/// 当播放进度 >= 80% 时，Trakt 会自动标记为已观看
class TraktScrobbleService {
  TraktScrobbleService(this._ref);

  final Ref _ref;

  /// 当前正在 scrobble 的媒体信息
  TraktMediaItem? _currentMedia;
  bool _hasReportedStart = false;

  /// 获取 Trakt API 实例
  TraktApi? get _api => _ref.read(traktConnectionProvider.notifier).api;

  /// 是否已连接 Trakt
  bool get isConnected =>
      _ref.read(traktConnectionProvider).status == TraktConnectionStatus.connected;

  /// 当前是否有活跃的 scrobble 会话
  bool get hasActiveSession => _currentMedia != null && _hasReportedStart;

  /// 开始 Scrobble
  ///
  /// [video] 当前播放的视频
  /// [progress] 播放进度 (0.0 - 100.0)
  Future<void> reportStart({
    required VideoItem video,
    double progress = 0.0,
  }) async {
    if (!isConnected || _api == null) {
      logger.d('TraktScrobble: 未连接 Trakt，跳过上报');
      return;
    }

    // 解析媒体信息
    final media = await _resolveMedia(video);
    if (media == null) {
      logger.d('TraktScrobble: 无法解析媒体信息，跳过上报');
      return;
    }

    _currentMedia = media;

    try {
      final request = TraktScrobbleRequest(
        media: media,
        progress: progress,
        appVersion: '1.0.0', // TODO: 从 package_info 获取
      );

      final response = await _api!.scrobbleStart(request);
      _hasReportedStart = true;

      if (response != null) {
        logger.i('TraktScrobble: 开始播放上报成功 - ${media.title ?? media.tmdbId}');
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'TraktScrobble 开始上报失败（非关键错误）');
    }
  }

  /// 暂停 Scrobble
  ///
  /// [progress] 播放进度 (0.0 - 100.0)
  Future<void> reportPause({required double progress}) async {
    if (!isConnected || _api == null || _currentMedia == null || !_hasReportedStart) {
      return;
    }

    try {
      final request = TraktScrobbleRequest(
        media: _currentMedia!,
        progress: progress,
      );

      await _api!.scrobblePause(request);
      logger.d('TraktScrobble: 暂停上报成功 - 进度 ${progress.toStringAsFixed(1)}%');
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'TraktScrobble 暂停上报失败（非关键错误）');
    }
  }

  /// 停止 Scrobble
  ///
  /// [progress] 播放进度 (0.0 - 100.0)
  /// 注意：如果进度 >= 80%，Trakt 会自动标记为已观看
  Future<void> reportStop({required double progress}) async {
    if (!isConnected || _api == null || _currentMedia == null || !_hasReportedStart) {
      _reset();
      return;
    }

    try {
      final request = TraktScrobbleRequest(
        media: _currentMedia!,
        progress: progress,
      );

      final response = await _api!.scrobbleStop(request);

      if (response != null) {
        final action = response.action;
        if (action == 'scrobble') {
          logger.i('TraktScrobble: 播放完成，已标记为已观看');
        } else {
          logger.d('TraktScrobble: 停止上报成功 - 进度 ${progress.toStringAsFixed(1)}%');
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'TraktScrobble 停止上报失败（非关键错误）');
    } finally {
      _reset();
    }
  }

  /// 解析视频的媒体信息
  ///
  /// 尝试从以下来源获取 TMDB/IMDB ID：
  /// 1. 媒体服务器的 providerIds
  /// 2. 本地视频数据库的元数据
  Future<TraktMediaItem?> _resolveMedia(VideoItem video) async {
    // 1. 尝试从媒体服务器获取
    if (video.serverItemId != null && video.sourceId != null) {
      final mediaItem = await _getMediaServerItem(video.sourceId!, video.serverItemId!);
      if (mediaItem != null) {
        return mediaItem;
      }
    }

    // 2. 尝试从本地数据库获取
    final metadata = await _getLocalMetadata(video.path, video.sourceId);
    if (metadata != null) {
      return _createMediaItemFromMetadata(metadata);
    }

    return null;
  }

  /// 从媒体服务器获取媒体项信息
  Future<TraktMediaItem?> _getMediaServerItem(String sourceId, String itemId) async {
    try {
      final connections = _ref.read(activeMediaServerConnectionsProvider);
      final connection = connections[sourceId];
      if (connection == null) return null;

      // 获取媒体项详情
      final item = await connection.adapter.getItemDetail(itemId);

      final tmdbId = item.tmdbId != null ? int.tryParse(item.tmdbId!) : null;
      final tvdbId = item.tvdbId != null ? int.tryParse(item.tvdbId!) : null;

      // 判断媒体类型
      final isEpisode = item.type.name == 'episode';

      return TraktMediaItem(
        type: isEpisode ? 'episode' : 'movie',
        imdbId: item.imdbId,
        tmdbId: tmdbId,
        tvdbId: tvdbId,
        season: item.parentIndexNumber,
        episode: item.indexNumber,
        title: isEpisode ? item.seriesName : item.name,
        year: item.productionYear,
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '从媒体服务器获取媒体信息失败');
      return null;
    }
  }

  /// 从本地数据库获取元数据
  Future<VideoMetadata?> _getLocalMetadata(String videoPath, String? sourceId) async {
    try {
      final dbService = VideoDatabaseService();
      await dbService.init();

      return await dbService.get(sourceId ?? '', videoPath);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '从本地数据库获取元数据失败');
      return null;
    }
  }

  /// 从本地元数据创建 TraktMediaItem
  TraktMediaItem? _createMediaItemFromMetadata(VideoMetadata metadata) {
    if (metadata.tmdbId == null && metadata.imdbId == null) {
      return null;
    }

    final isEpisode = metadata.category == MediaCategory.tvShow &&
        metadata.seasonNumber != null &&
        metadata.episodeNumber != null;

    return TraktMediaItem(
      type: isEpisode ? 'episode' : 'movie',
      imdbId: metadata.imdbId,
      tmdbId: metadata.tmdbId,
      season: metadata.seasonNumber,
      episode: metadata.episodeNumber,
      title: metadata.title,
      year: metadata.year,
    );
  }

  /// 重置状态
  void _reset() {
    _currentMedia = null;
    _hasReportedStart = false;
  }

  /// 释放资源
  void dispose() {
    _reset();
  }
}

/// Trakt Scrobble Provider
final traktScrobbleServiceProvider = Provider<TraktScrobbleService>((ref) {
  final service = TraktScrobbleService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// Trakt Scrobble 设置状态
class TraktScrobbleSettings {
  const TraktScrobbleSettings({
    this.enabled = true,
    this.minProgress = 80.0, // 最小标记已观看进度
  });

  final bool enabled;
  final double minProgress;

  TraktScrobbleSettings copyWith({
    bool? enabled,
    double? minProgress,
  }) =>
      TraktScrobbleSettings(
        enabled: enabled ?? this.enabled,
        minProgress: minProgress ?? this.minProgress,
      );
}

/// Trakt Scrobble 设置 Provider
final traktScrobbleSettingsProvider =
    StateProvider<TraktScrobbleSettings>((ref) => const TraktScrobbleSettings());
