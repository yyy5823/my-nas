import 'dart:async';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/video/data/services/video_library_cache_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 视频扫描进度
class VideoScanProgress {
  const VideoScanProgress({
    required this.phase,
    this.currentPath,
    this.scannedCount = 0,
    this.totalCount = 0,
    this.currentFile,
  });

  /// 扫描阶段
  final VideoScanPhase phase;

  /// 当前扫描的路径
  final String? currentPath;

  /// 已扫描数量
  final int scannedCount;

  /// 总数量（元数据阶段使用）
  final int totalCount;

  /// 当前处理的文件名
  final String? currentFile;

  /// 计算进度百分比
  double get progress {
    if (totalCount == 0) return 0;
    return scannedCount / totalCount;
  }

  /// 进度描述
  String get description {
    switch (phase) {
      case VideoScanPhase.scanning:
        return currentPath ?? '正在扫描...';
      case VideoScanPhase.metadata:
        if (currentFile != null) {
          return '正在获取元数据: $currentFile ($scannedCount/$totalCount)';
        }
        return '正在获取元数据 ($scannedCount/$totalCount)';
      case VideoScanPhase.completed:
        return '扫描完成，共 $scannedCount 个视频';
      case VideoScanPhase.error:
        return '扫描失败';
    }
  }
}

/// 扫描阶段
enum VideoScanPhase {
  /// 扫描文件系统
  scanning,

  /// 获取元数据（NFO/TMDB/缩略图）
  metadata,

  /// 完成
  completed,

  /// 错误
  error,
}

/// 视频扫描服务
///
/// 负责：
/// 1. 扫描配置的视频目录
/// 2. 获取刮削信息（NFO > TMDB > 生成缩略图）
/// 3. 保存到本地缓存
class VideoScannerService {
  factory VideoScannerService() => _instance ??= VideoScannerService._();
  VideoScannerService._();

  static VideoScannerService? _instance;

  final VideoLibraryCacheService _cacheService =
      VideoLibraryCacheService();
  final VideoMetadataService _metadataService = VideoMetadataService();

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  /// 扫描进度流
  final _progressController = StreamController<VideoScanProgress>.broadcast();
  Stream<VideoScanProgress> get progressStream => _progressController.stream;

  /// 扫描视频库
  ///
  /// [paths] 要扫描的路径列表
  /// [connections] 源连接映射
  /// [maxDepth] 最大扫描深度，默认10
  Future<List<VideoMetadata>> scan({
    required List<MediaLibraryPath> paths,
    required Map<String, SourceConnection> connections,
    int maxDepth = 10,
  }) async {
    if (_isScanning) {
      logger.w('VideoScannerService: 扫描正在进行中，跳过');
      return [];
    }

    _isScanning = true;
    final allVideos = <_ScannedVideo>[];
    final sourceIds = <String>{};

    try {
      // 初始化服务
      await _cacheService.init();
      await _metadataService.init();

      // 阶段1：扫描文件系统
      _emitProgress(const VideoScanProgress(phase: VideoScanPhase.scanning));

      for (final path in paths) {
        if (!path.isEnabled) continue;

        final conn = connections[path.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) {
          logger.w('VideoScannerService: 源 ${path.sourceId} 未连接，跳过');
          continue;
        }

        sourceIds.add(path.sourceId);
        final fileSystem = conn.adapter.fileSystem;

        await _scanDirectory(
          fileSystem: fileSystem,
          sourceId: path.sourceId,
          path: path.path,
          videos: allVideos,
          maxDepth: maxDepth,
          currentDepth: 0,
        );
      }

      logger.i('VideoScannerService: 扫描完成，共 ${allVideos.length} 个视频');

      // 保存视频列表到缓存
      final cacheEntries = allVideos
          .map((v) => VideoLibraryCacheEntry(
                sourceId: v.sourceId,
                filePath: v.file.path,
                fileName: v.file.name,
                thumbnailUrl: v.file.thumbnailUrl,
                size: v.file.size,
                modifiedTime: v.file.modifiedTime,
              ))
          .toList();

      final cache = VideoLibraryCache(
        videos: cacheEntries,
        lastUpdated: DateTime.now(),
        sourceIds: sourceIds.toList(),
      );
      await _cacheService.saveCache(cache);

      // 阶段2：获取元数据
      final metadataList = await _fetchMetadata(
        videos: allVideos,
        connections: connections,
      );

      // 完成
      _emitProgress(VideoScanProgress(
        phase: VideoScanPhase.completed,
        scannedCount: metadataList.length,
      ));

      return metadataList;
    } catch (e, st) {
      logger.e('VideoScannerService: 扫描失败', e, st);
      _emitProgress(const VideoScanProgress(phase: VideoScanPhase.error));
      rethrow;
    } finally {
      _isScanning = false;
    }
  }

  /// 递归扫描目录
  Future<void> _scanDirectory({
    required NasFileSystem fileSystem,
    required String sourceId,
    required String path,
    required List<_ScannedVideo> videos,
    required int maxDepth,
    required int currentDepth,
  }) async {
    if (currentDepth > maxDepth) return;

    _emitProgress(VideoScanProgress(
      phase: VideoScanPhase.scanning,
      currentPath: path,
      scannedCount: videos.length,
    ));

    try {
      final items = await fileSystem.listDirectory(path);

      for (final item in items) {
        if (item.isDirectory) {
          // 跳过隐藏目录和系统目录
          if (item.name.startsWith('.') ||
              item.name.startsWith('@') ||
              item.name.startsWith('#recycle') ||
              item.name == 'eaDir' ||
              item.name == '@eaDir') {
            continue;
          }

          // 递归扫描子目录
          await _scanDirectory(
            fileSystem: fileSystem,
            sourceId: sourceId,
            path: item.path,
            videos: videos,
            maxDepth: maxDepth,
            currentDepth: currentDepth + 1,
          );
        } else if (item.type == FileType.video) {
          videos.add(_ScannedVideo(
            sourceId: sourceId,
            file: item,
          ));

          // 每扫描到一定数量更新进度
          if (videos.length % 10 == 0) {
            _emitProgress(VideoScanProgress(
              phase: VideoScanPhase.scanning,
              currentPath: path,
              scannedCount: videos.length,
            ));
          }
        }
      }
    } on Exception catch (e) {
      logger.w('VideoScannerService: 扫描目录失败 $path', e);
    }
  }

  /// 获取元数据
  Future<List<VideoMetadata>> _fetchMetadata({
    required List<_ScannedVideo> videos,
    required Map<String, SourceConnection> connections,
  }) async {
    final results = <VideoMetadata>[];
    final total = videos.length;

    for (var i = 0; i < videos.length; i++) {
      final video = videos[i];
      final conn = connections[video.sourceId];

      _emitProgress(VideoScanProgress(
        phase: VideoScanPhase.metadata,
        scannedCount: i + 1,
        totalCount: total,
        currentFile: video.file.name,
      ));

      try {
        String? videoUrl;
        NasFileSystem? fileSystem;

        if (conn != null && conn.status == SourceStatus.connected) {
          fileSystem = conn.adapter.fileSystem;
          try {
            videoUrl = await fileSystem.getFileUrl(video.file.path);
          } on Exception catch (e) {
            logger.w('VideoScannerService: 获取视频URL失败 ${video.file.path}，错误原因 $e');
          }
        }

        final metadata = await _metadataService.getOrFetch(
          sourceId: video.sourceId,
          filePath: video.file.path,
          fileName: video.file.name,
          fileSystem: fileSystem,
          videoUrl: videoUrl,
        );

        // 如果没有缩略图，保存NAS原生缩略图
        if (metadata.thumbnailUrl == null && video.file.thumbnailUrl != null) {
          metadata.thumbnailUrl = video.file.thumbnailUrl;
          await _metadataService.save(metadata);
        }

        results.add(metadata);
      } on Exception catch (e) {
        logger.w('VideoScannerService: 获取元数据失败 ${video.file.name}', e);

        // 创建基础元数据
        final basicMetadata = VideoMetadata(
          sourceId: video.sourceId,
          filePath: video.file.path,
          fileName: video.file.name,
          thumbnailUrl: video.file.thumbnailUrl,
        );
        await _metadataService.save(basicMetadata);
        results.add(basicMetadata);
      }

      // 添加延迟避免API限制
      if (i < videos.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    return results;
  }

  void _emitProgress(VideoScanProgress progress) {
    _progressController.add(progress);
  }

  /// 释放资源
  void dispose() {
    _progressController.close();
  }
}

/// 扫描到的视频
class _ScannedVideo {
  const _ScannedVideo({
    required this.sourceId,
    required this.file,
  });

  final String sourceId;
  final FileItem file;
}
