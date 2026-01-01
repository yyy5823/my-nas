import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';

/// 媒体服务器播放进度上报服务
///
/// 负责向 Jellyfin/Emby/Plex 等媒体服务器上报播放状态和进度，
/// 用于同步观看进度和统计。
class MediaServerPlaybackReporter {
  MediaServerPlaybackReporter(this._ref);

  final Ref _ref;

  /// 当前正在上报的 session
  String? _currentSourceId;
  String? _currentItemId;
  Timer? _progressTimer;
  bool _hasReportedStart = false;

  /// 开始播放上报
  ///
  /// [sourceId] 源 ID
  /// [serverItemId] 媒体服务器中的项目 ID
  /// [positionTicks] 起始播放位置（ticks，1秒=10,000,000 ticks）
  Future<void> reportStart({
    required String sourceId,
    required String serverItemId,
    int positionTicks = 0,
  }) async {
    final connection = _ref.read(activeMediaServerConnectionsProvider)[sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      logger.w('MediaServerPlaybackReporter: 无法上报开始播放 - 连接不存在或未连接');
      return;
    }

    _currentSourceId = sourceId;
    _currentItemId = serverItemId;
    _hasReportedStart = true;

    try {
      final report = PlaybackReport(
        itemId: serverItemId,
        reportType: PlaybackReportType.start,
        positionTicks: positionTicks,
        isPaused: false,
      );

      await connection.adapter.reportPlayback(report);
      logger.i('MediaServerPlaybackReporter: 上报播放开始 itemId=$serverItemId');

      // 启动定时进度上报（每 10 秒）
      _startProgressTimer();
    } on Exception catch (e, st) {
      logger.w('MediaServerPlaybackReporter: 上报播放开始失败', e, st);
    }
  }

  /// 上报播放进度
  ///
  /// [positionTicks] 当前播放位置（ticks）
  /// [isPaused] 是否暂停
  Future<void> reportProgress({
    required int positionTicks,
    bool isPaused = false,
  }) async {
    if (_currentSourceId == null || _currentItemId == null) return;
    if (!_hasReportedStart) return;

    final connection = _ref.read(activeMediaServerConnectionsProvider)[_currentSourceId];
    if (connection == null || connection.status != SourceStatus.connected) return;

    try {
      final report = PlaybackReport(
        itemId: _currentItemId!,
        reportType: PlaybackReportType.progress,
        positionTicks: positionTicks,
        isPaused: isPaused,
      );

      await connection.adapter.reportPlayback(report);
      logger.d('MediaServerPlaybackReporter: 上报播放进度 position=${positionTicks ~/ 10000000}s');
    } on Exception catch (e) {
      // 进度上报失败不影响播放
      logger.d('MediaServerPlaybackReporter: 上报进度失败 $e');
    }
  }

  /// 上报播放停止
  ///
  /// [positionTicks] 停止时的播放位置（ticks）
  Future<void> reportStop({
    required int positionTicks,
  }) async {
    _stopProgressTimer();

    if (_currentSourceId == null || _currentItemId == null) return;
    if (!_hasReportedStart) return;

    final connection = _ref.read(activeMediaServerConnectionsProvider)[_currentSourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      _reset();
      return;
    }

    try {
      final report = PlaybackReport(
        itemId: _currentItemId!,
        reportType: PlaybackReportType.stop,
        positionTicks: positionTicks,
        isPaused: true,
      );

      await connection.adapter.reportPlayback(report);
      logger.i('MediaServerPlaybackReporter: 上报播放停止 position=${positionTicks ~/ 10000000}s');
    } on Exception catch (e, st) {
      logger.w('MediaServerPlaybackReporter: 上报播放停止失败', e, st);
    } finally {
      _reset();
    }
  }

  /// 上报暂停
  Future<void> reportPause({required int positionTicks}) async {
    await reportProgress(positionTicks: positionTicks, isPaused: true);
    _stopProgressTimer();
  }

  /// 上报继续播放
  Future<void> reportResume({required int positionTicks}) async {
    await reportProgress(positionTicks: positionTicks, isPaused: false);
    _startProgressTimer();
  }

  void _startProgressTimer() {
    _stopProgressTimer();
    // 每 10 秒上报一次进度
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      // 进度上报由外部调用 reportProgress
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _reset() {
    _currentSourceId = null;
    _currentItemId = null;
    _hasReportedStart = false;
  }

  /// 当前是否有活跃的媒体服务器播放会话
  bool get hasActiveSession =>
      _currentSourceId != null && _currentItemId != null && _hasReportedStart;

  /// 当前播放的源 ID
  String? get currentSourceId => _currentSourceId;

  /// 当前播放的项目 ID
  String? get currentItemId => _currentItemId;

  void dispose() {
    _stopProgressTimer();
    _reset();
  }
}

/// 媒体服务器播放上报 Provider
final mediaServerPlaybackReporterProvider = Provider<MediaServerPlaybackReporter>((ref) {
  final reporter = MediaServerPlaybackReporter(ref);
  ref.onDispose(reporter.dispose);
  return reporter;
});
