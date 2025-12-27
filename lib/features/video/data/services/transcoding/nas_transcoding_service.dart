import 'dart:async';

import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/video/data/services/transcoding/transcoding_capability.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';

/// NAS 转码服务抽象接口
/// 定义了不同 NAS 类型的转码服务需要实现的方法
abstract class NasTranscodingService {
  /// 服务是否可用
  bool get isAvailable;

  /// 获取转码能力
  TranscodingCapability get capability;

  /// 获取转码流 URL
  ///
  /// [videoPath] 视频文件路径
  /// [quality] 目标清晰度
  /// [startPosition] 起始播放位置
  /// [audioStreamIndex] 音轨索引
  /// [subtitleStreamIndex] 字幕流索引 (-1 表示无字幕)
  ///
  /// 返回转码后的流 URL，如果不支持转码则返回 null
  Future<String?> getTranscodedStreamUrl({
    required String videoPath,
    required VideoQuality quality,
    Duration? startPosition,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  });

  /// 获取可用的清晰度列表
  ///
  /// [videoPath] 视频文件路径
  /// [originalWidth] 原始视频宽度
  /// [originalHeight] 原始视频高度
  Future<List<VideoQuality>> getAvailableQualities({
    required String videoPath,
    int? originalWidth,
    int? originalHeight,
  });

  /// 开始转码会话
  ///
  /// 某些 NAS 需要先开启会话才能获取转码流
  Future<TranscodingSession?> startSession({
    required String videoPath,
    required VideoQuality quality,
  });

  /// 停止转码会话
  Future<void> stopSession(String sessionId);

  /// 获取转码进度（如果支持）
  Future<TranscodingProgress?> getProgress(String sessionId);

  /// 释放资源
  Future<void> dispose();
}

/// 转码会话
class TranscodingSession {
  const TranscodingSession({
    required this.sessionId,
    required this.streamUrl,
    required this.quality,
    this.expiresAt,
  });

  /// 会话 ID
  final String sessionId;

  /// 流 URL
  final String streamUrl;

  /// 目标清晰度
  final VideoQuality quality;

  /// 过期时间
  final DateTime? expiresAt;

  /// 是否已过期
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

/// NAS 转码服务工厂
class NasTranscodingServiceFactory {
  NasTranscodingServiceFactory._();

  static final Map<SourceType, NasTranscodingService> _services = {};

  /// 获取指定源类型的转码服务
  static NasTranscodingService? getService(SourceType sourceType) =>
      _services[sourceType];

  /// 注册转码服务
  static void registerService(
    SourceType sourceType,
    NasTranscodingService service,
  ) {
    _services[sourceType] = service;
  }

  /// 注销转码服务
  static void unregisterService(SourceType sourceType) {
    _services.remove(sourceType);
  }

  /// 检查是否支持服务端转码
  static bool supportsServerSideTranscoding(SourceType sourceType) {
    final service = _services[sourceType];
    return service?.capability == TranscodingCapability.serverSide;
  }

  /// 获取所有已注册的服务
  static Map<SourceType, NasTranscodingService> get allServices =>
      Map.unmodifiable(_services);

  /// 清理所有服务
  static Future<void> disposeAll() async {
    for (final service in _services.values) {
      await service.dispose();
    }
    _services.clear();
  }
}

/// 不支持转码的默认实现
class NoTranscodingService implements NasTranscodingService {
  const NoTranscodingService();

  @override
  bool get isAvailable => false;

  @override
  TranscodingCapability get capability => TranscodingCapability.none;

  @override
  Future<String?> getTranscodedStreamUrl({
    required String videoPath,
    required VideoQuality quality,
    Duration? startPosition,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async =>
      null;

  @override
  Future<List<VideoQuality>> getAvailableQualities({
    required String videoPath,
    int? originalWidth,
    int? originalHeight,
  }) async =>
      [VideoQuality.original];

  @override
  Future<TranscodingSession?> startSession({
    required String videoPath,
    required VideoQuality quality,
  }) async =>
      null;

  @override
  Future<void> stopSession(String sessionId) async {}

  @override
  Future<TranscodingProgress?> getProgress(String sessionId) async => null;

  @override
  Future<void> dispose() async {}
}
