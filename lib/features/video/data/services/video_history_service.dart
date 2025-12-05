import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 视频播放历史服务
class VideoHistoryService {
  VideoHistoryService._();

  static VideoHistoryService? _instance;
  static VideoHistoryService get instance => _instance ??= VideoHistoryService._();

  late Box<dynamic> _historyBox;
  late Box<dynamic> _progressBox;
  bool _initialized = false;

  /// 初始化
  Future<void> init() async {
    if (_initialized) return;

    // Hive.initFlutter() 已在 main.dart 中调用，这里直接打开 box
    _historyBox = await Hive.openBox('video_history');
    _progressBox = await Hive.openBox('video_progress');
    _initialized = true;

    logger.i('VideoHistoryService: 初始化完成');
  }

  /// 保存播放进度
  Future<void> saveProgress({
    required String videoPath,
    required Duration position,
    required Duration duration,
  }) async {
    if (!_initialized) await init();

    final progress = VideoProgress(
      videoPath: videoPath,
      position: position,
      duration: duration,
      updatedAt: DateTime.now(),
    );

    await _progressBox.put(videoPath, progress.toJson());
    logger.d('VideoHistoryService: 保存进度 $videoPath => ${position.inSeconds}s');
  }

  /// 获取播放进度
  Future<VideoProgress?> getProgress(String videoPath) async {
    if (!_initialized) await init();

    final data = _progressBox.get(videoPath);
    if (data == null) return null;

    try {
      return VideoProgress.fromJson(data as Map<dynamic, dynamic>);
    } on Exception catch (e) {
      logger.e('VideoHistoryService: 解析进度失败', e);
      return null;
    }
  }

  /// 批量获取播放进度 - 避免 N+1 查询问题
  Future<Map<String, VideoProgress>> getProgressBatch(List<String> videoPaths) async {
    if (!_initialized) await init();

    final result = <String, VideoProgress>{};
    for (final path in videoPaths) {
      final data = _progressBox.get(path);
      if (data != null) {
        try {
          result[path] = VideoProgress.fromJson(data as Map<dynamic, dynamic>);
        } on Exception catch (e) {
          logger.w('VideoHistoryService: 解析进度失败 $path');
        }
      }
    }
    return result;
  }

  /// 获取所有播放进度 - 一次性读取整个 box
  Future<Map<String, VideoProgress>> getAllProgress() async {
    if (!_initialized) await init();

    final result = <String, VideoProgress>{};
    for (final key in _progressBox.keys) {
      final data = _progressBox.get(key);
      if (data != null) {
        try {
          result[key as String] = VideoProgress.fromJson(data as Map<dynamic, dynamic>);
        } on Exception catch (e) {
          logger.w('VideoHistoryService: 解析进度失败 $key');
        }
      }
    }
    return result;
  }

  /// 清除播放进度
  Future<void> clearProgress(String videoPath) async {
    if (!_initialized) await init();
    await _progressBox.delete(videoPath);
  }

  /// 添加到播放历史
  Future<void> addToHistory(VideoHistoryItem item) async {
    if (!_initialized) await init();

    // 获取现有历史
    final history = await getHistory();

    // 移除已存在的相同视频
    history.removeWhere((h) => h.videoPath == item.videoPath);

    // 添加到最前面
    history.insert(0, item);

    // 限制历史记录数量（最多100条）
    if (history.length > 100) {
      history.removeRange(100, history.length);
    }

    // 保存
    await _historyBox.put(
      'list',
      history.map((h) => h.toJson()).toList(),
    );

    logger.d('VideoHistoryService: 添加历史 ${item.videoName}, thumbnailUrl=${item.thumbnailUrl}');
  }

  /// 获取播放历史
  Future<List<VideoHistoryItem>> getHistory({int limit = 50}) async {
    if (!_initialized) await init();

    final data = _historyBox.get('list') as List<dynamic>?;
    if (data == null) return [];

    try {
      final history = data
          .map((e) => VideoHistoryItem.fromJson(e as Map<dynamic, dynamic>))
          .take(limit)
          .toList();
      return history;
    } on Exception catch (e) {
      logger.e('VideoHistoryService: 解析历史失败', e);
      return [];
    }
  }

  /// 获取继续观看列表（有进度且未看完的视频）- 优化：批量获取进度
  Future<List<VideoHistoryItem>> getContinueWatching({int limit = 10}) async {
    final history = await getHistory(limit: 50);
    if (history.isEmpty) return [];

    logger.d('VideoHistoryService: 获取继续观看, 历史记录数: ${history.length}');

    // 批量获取所有需要的进度，避免 N+1 查询
    final videoPaths = history.map((h) => h.videoPath).toList();
    final progressMap = await getProgressBatch(videoPaths);

    final continueList = <VideoHistoryItem>[];
    for (final item in history) {
      final progress = progressMap[item.videoPath];
      if (progress != null && progress.progressPercent > 0.05 && progress.progressPercent < 0.95) {
        continueList.add(item.copyWith(
          lastPosition: progress.position,
          duration: progress.duration,
        ));
        if (continueList.length >= limit) break;
      }
    }

    logger.d('VideoHistoryService: 继续观看列表数: ${continueList.length}');
    return continueList;
  }

  /// 清除所有历史
  Future<void> clearAllHistory() async {
    if (!_initialized) await init();
    await _historyBox.clear();
    await _progressBox.clear();
    logger.i('VideoHistoryService: 清除所有历史');
  }

  /// 从历史中移除
  Future<void> removeFromHistory(String videoPath) async {
    if (!_initialized) await init();

    final history = await getHistory();
    history.removeWhere((h) => h.videoPath == videoPath);

    await _historyBox.put(
      'list',
      history.map((h) => h.toJson()).toList(),
    );
  }
}

/// 视频播放进度
class VideoProgress {
  const VideoProgress({
    required this.videoPath,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final String videoPath;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  double get progressPercent =>
      duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0;

  Map<String, dynamic> toJson() => {
        'videoPath': videoPath,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory VideoProgress.fromJson(Map<dynamic, dynamic> json) => VideoProgress(
        videoPath: json['videoPath'] as String,
        position: Duration(milliseconds: json['positionMs'] as int),
        duration: Duration(milliseconds: json['durationMs'] as int),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

/// 视频历史记录项
class VideoHistoryItem {
  const VideoHistoryItem({
    required this.videoPath,
    required this.videoName,
    required this.videoUrl,
    this.sourceId,
    this.thumbnailUrl,
    this.size = 0,
    this.lastPosition,
    this.duration,
    required this.watchedAt,
  });

  final String videoPath;
  final String videoName;
  final String videoUrl;
  final String? sourceId;
  final String? thumbnailUrl;
  final int size;
  final Duration? lastPosition;
  final Duration? duration;
  final DateTime watchedAt;

  double get progressPercent {
    if (lastPosition == null || duration == null || duration!.inMilliseconds == 0) {
      return 0;
    }
    return lastPosition!.inMilliseconds / duration!.inMilliseconds;
  }

  VideoHistoryItem copyWith({
    String? videoPath,
    String? videoName,
    String? videoUrl,
    String? sourceId,
    String? thumbnailUrl,
    int? size,
    Duration? lastPosition,
    Duration? duration,
    DateTime? watchedAt,
  }) =>
      VideoHistoryItem(
        videoPath: videoPath ?? this.videoPath,
        videoName: videoName ?? this.videoName,
        videoUrl: videoUrl ?? this.videoUrl,
        sourceId: sourceId ?? this.sourceId,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        size: size ?? this.size,
        lastPosition: lastPosition ?? this.lastPosition,
        duration: duration ?? this.duration,
        watchedAt: watchedAt ?? this.watchedAt,
      );

  Map<String, dynamic> toJson() => {
        'videoPath': videoPath,
        'videoName': videoName,
        'videoUrl': videoUrl,
        'sourceId': sourceId,
        'thumbnailUrl': thumbnailUrl,
        'size': size,
        'lastPositionMs': lastPosition?.inMilliseconds,
        'durationMs': duration?.inMilliseconds,
        'watchedAt': watchedAt.toIso8601String(),
      };

  factory VideoHistoryItem.fromJson(Map<dynamic, dynamic> json) => VideoHistoryItem(
        videoPath: json['videoPath'] as String,
        videoName: json['videoName'] as String,
        videoUrl: json['videoUrl'] as String,
        sourceId: json['sourceId'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        size: json['size'] as int? ?? 0,
        lastPosition: json['lastPositionMs'] != null
            ? Duration(milliseconds: json['lastPositionMs'] as int)
            : null,
        duration: json['durationMs'] != null
            ? Duration(milliseconds: json['durationMs'] as int)
            : null,
        watchedAt: DateTime.parse(json['watchedAt'] as String),
      );
}
