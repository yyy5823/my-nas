import 'dart:async';

import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
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
      case VideoScanPhase.savingToDb:
        return '正在保存到数据库 ($scannedCount/$totalCount)';
      case VideoScanPhase.scraping:
        if (currentFile != null) {
          return '正在刮削: $currentFile ($scannedCount/$totalCount)';
        }
        return '正在刮削元数据 ($scannedCount/$totalCount)';
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

  /// 保存到数据库
  savingToDb,

  /// 刮削元数据（NFO/TMDB/缩略图）
  scraping,

  /// 完成
  completed,

  /// 错误
  error,
}

/// 视频扫描服务
///
/// 负责：
/// 1. 扫描配置的视频目录（快速，创建基础记录）
/// 2. 后台刮削信息（NFO > TMDB > 生成缩略图）
/// 3. 保存到 SQLite 数据库
class VideoScannerService {
  factory VideoScannerService() => _instance ??= VideoScannerService._();
  VideoScannerService._();

  static VideoScannerService? _instance;

  final VideoLibraryCacheService _cacheService = VideoLibraryCacheService();
  final VideoMetadataService _metadataService = VideoMetadataService();
  final VideoDatabaseService _dbService = VideoDatabaseService();

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  bool _isScraping = false;
  bool get isScraping => _isScraping;

  bool _shouldStopScraping = false;

  /// 扫描进度流
  final _progressController = StreamController<VideoScanProgress>.broadcast();
  Stream<VideoScanProgress> get progressStream => _progressController.stream;

  /// 刮削统计信息流
  final _scrapeStatsController = StreamController<ScrapeStats>.broadcast();
  Stream<ScrapeStats> get scrapeStatsStream => _scrapeStatsController.stream;

  /// 仅扫描文件（快速，不刮削元数据）
  ///
  /// 扫描完成后立即返回，视频可以在影院页面展示
  /// 刮削会在后台自动进行
  Future<int> scanFilesOnly({
    required List<MediaLibraryPath> paths,
    required Map<String, SourceConnection> connections,
    int maxDepth = 10,
  }) async {
    if (_isScanning) {
      logger.w('VideoScannerService: 扫描正在进行中，跳过');
      return 0;
    }

    _isScanning = true;
    final allVideos = <_ScannedVideo>[];
    final sourceIds = <String>{};

    try {
      // 初始化服务
      await _cacheService.init();
      await _dbService.init();

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

      logger.i('VideoScannerService: 文件扫描完成，共 ${allVideos.length} 个视频');

      // 保存视频列表到 Hive 缓存（用于快速启动）
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

      // 阶段2：保存基础记录到 SQLite
      _emitProgress(VideoScanProgress(
        phase: VideoScanPhase.savingToDb,
        totalCount: allVideos.length,
      ));

      await _saveBasicMetadataToDb(allVideos);

      // 完成文件扫描
      _emitProgress(VideoScanProgress(
        phase: VideoScanPhase.completed,
        scannedCount: allVideos.length,
      ));

      return allVideos.length;
    } catch (e, st) {
      logger.e('VideoScannerService: 扫描失败', e, st);
      _emitProgress(const VideoScanProgress(phase: VideoScanPhase.error));
      rethrow;
    } finally {
      _isScanning = false;
    }
  }

  /// 保存基础元数据到数据库（不刮削）
  Future<void> _saveBasicMetadataToDb(List<_ScannedVideo> videos) async {
    final total = videos.length;
    const batchSize = 50;

    for (var i = 0; i < videos.length; i += batchSize) {
      final batch = videos.skip(i).take(batchSize).toList();
      final metadataList = <VideoMetadata>[];

      for (final video in batch) {
        // 检查是否已存在
        final existing = await _dbService.get(video.sourceId, video.file.path);
        if (existing != null) {
          // 已存在，跳过
          continue;
        }

        // 创建基础元数据
        final metadata = VideoMetadata(
          sourceId: video.sourceId,
          filePath: video.file.path,
          fileName: video.file.name,
          thumbnailUrl: video.file.thumbnailUrl,
          fileSize: video.file.size,
          fileModifiedTime: video.file.modifiedTime,
        );
        metadataList.add(metadata);
      }

      if (metadataList.isNotEmpty) {
        await _dbService.upsertBatch(metadataList);
      }

      _emitProgress(VideoScanProgress(
        phase: VideoScanPhase.savingToDb,
        scannedCount: (i + batch.length).clamp(0, total),
        totalCount: total,
      ));
    }
  }

  /// 完整扫描（扫描文件 + 刮削元数据）
  ///
  /// [paths] 要扫描的路径列表
  /// [connections] 源连接映射
  /// [maxDepth] 最大扫描深度，默认10
  Future<List<VideoMetadata>> scan({
    required List<MediaLibraryPath> paths,
    required Map<String, SourceConnection> connections,
    int maxDepth = 10,
  }) async {
    // 先扫描文件
    final count = await scanFilesOnly(
      paths: paths,
      connections: connections,
      maxDepth: maxDepth,
    );

    if (count == 0) return [];

    // 然后刮削元数据
    await scrapeMetadata(connections: connections);

    // 返回所有元数据
    return _dbService.getPage(limit: count);
  }

  /// 后台刮削元数据
  ///
  /// 可以随时调用，会自动处理待刮削的视频
  Future<void> scrapeMetadata({
    required Map<String, SourceConnection> connections,
    int batchSize = 20,
  }) async {
    if (_isScraping) {
      logger.w('VideoScannerService: 刮削正在进行中，跳过');
      return;
    }

    _isScraping = true;
    _shouldStopScraping = false;

    try {
      await _metadataService.init();
      await _dbService.init();

      // 重置可能中断的刮削状态
      await _dbService.resetScrapingToPending();

      while (!_shouldStopScraping) {
        // 获取待刮削的视频
        final pendingVideos = await _dbService.getPendingScrape(limit: batchSize);

        if (pendingVideos.isEmpty) {
          logger.i('VideoScannerService: 所有视频刮削完成');
          break;
        }

        // 获取刮削统计
        final stats = await _dbService.getScrapeStats();
        _scrapeStatsController.add(stats);

        for (final video in pendingVideos) {
          if (_shouldStopScraping) break;

          _emitProgress(VideoScanProgress(
            phase: VideoScanPhase.scraping,
            scannedCount: stats.processed,
            totalCount: stats.total,
            currentFile: video.fileName,
          ));

          await _scrapeOneVideo(video, connections);

          // 添加延迟避免 API 限制
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        // 更新统计
        final newStats = await _dbService.getScrapeStats();
        _scrapeStatsController.add(newStats);
      }

      _emitProgress(VideoScanProgress(
        phase: VideoScanPhase.completed,
        scannedCount: (await _dbService.getScrapeStats()).total,
      ));
    } on Exception catch (e, st) {
      logger.e('VideoScannerService: 刮削失败', e, st);
      _emitProgress(const VideoScanProgress(phase: VideoScanPhase.error));
    } finally {
      _isScraping = false;
    }
  }

  /// 刮削单个视频
  Future<void> _scrapeOneVideo(
    VideoMetadata video,
    Map<String, SourceConnection> connections,
  ) async {
    try {
      // 标记为刮削中
      await _dbService.updateScrapeStatus(
        video.sourceId,
        video.filePath,
        ScrapeStatus.scraping,
      );

      final conn = connections[video.sourceId];
      String? videoUrl;
      NasFileSystem? fileSystem;

      if (conn != null && conn.status == SourceStatus.connected) {
        fileSystem = conn.adapter.fileSystem;
        try {
          videoUrl = await fileSystem.getFileUrl(video.filePath);
        } on Exception catch (e) {
          logger.w('VideoScannerService: 获取视频URL失败 ${video.filePath}，错误原因 $e');
        }
      }

      // 获取元数据
      final metadata = await _metadataService.getOrFetch(
        sourceId: video.sourceId,
        filePath: video.filePath,
        fileName: video.fileName,
        fileSystem: fileSystem,
        videoUrl: videoUrl,
      );

      // 根据结果更新刮削状态
      if (metadata.hasMetadata) {
        metadata.scrapeStatus = ScrapeStatus.completed;
      } else {
        metadata.scrapeStatus = ScrapeStatus.failed;
      }

      // 保留文件信息
      metadata..fileSize = video.fileSize
      ..fileModifiedTime = video.fileModifiedTime;

      await _metadataService.save(metadata);
    } on Exception catch (e) {
      logger.w('VideoScannerService: 刮削失败 ${video.fileName}', e);

      // 标记为失败
      await _dbService.updateScrapeStatus(
        video.sourceId,
        video.filePath,
        ScrapeStatus.failed,
      );
    }
  }

  /// 停止刮削
  void stopScraping() {
    _shouldStopScraping = true;
  }

  /// 获取刮削统计
  Future<ScrapeStats> getScrapeStats() async {
    await _dbService.init();
    return _dbService.getScrapeStats();
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
