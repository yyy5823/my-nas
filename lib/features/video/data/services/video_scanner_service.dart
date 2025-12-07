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
///
/// 生命周期特性：
/// - 全局单例，不随页面生命周期销毁
/// - 支持应用重启后自动恢复未完成的刮削
/// - 页面切换不影响刮削进度
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

  // 用于恢复刮削的 connections 缓存（预留用于源断开重连场景）
  // ignore: unused_field
  Map<String, SourceConnection>? _cachedConnections;

  /// 扫描进度流
  final _progressController = StreamController<VideoScanProgress>.broadcast();

  Stream<VideoScanProgress> get progressStream => _progressController.stream;

  /// 刮削统计信息流
  final _scrapeStatsController = StreamController<ScrapeStats>.broadcast();

  Stream<ScrapeStats> get scrapeStatsStream => _scrapeStatsController.stream;

  /// 检查并恢复未完成的刮削任务
  ///
  /// 在应用启动时调用，检查是否有待刮削的视频
  /// 如果有，自动开始刮削
  Future<void> checkAndResumeScraping(
    Map<String, SourceConnection> connections,
  ) async {
    if (_isScraping) {
      logger.d('VideoScannerService: 刮削已在进行中，跳过恢复检查');
      return;
    }

    try {
      await _dbService.init();
      final stats = await _dbService.getScrapeStats();

      if (stats.pending > 0) {
        logger.i('''
        VideoScannerService: 发现 ${stats.pending} 个待刮削视频，
          自动恢复刮削
          ''');
        // 缓存 connections 并开始刮削
        _cachedConnections = connections;
        unawaited(scrapeMetadata(connections: connections));
      }
    } on Exception catch (e) {
      logger.w('VideoScannerService: 检查恢复刮削失败', e);
    }
  }

  /// 更新 connections 缓存（用于源重连后恢复刮削）
  void updateConnections(Map<String, SourceConnection> connections) {
    _cachedConnections = connections;
  }

  /// 仅扫描文件（快速，不刮削元数据）
  ///
  /// 扫描完成后立即返回，视频可以在影院页面展示
  /// 刮削会在后台自动进行
  ///
  /// 注意：无深度限制，会递归扫描所有子目录
  Future<int> scanFilesOnly({
    required List<MediaLibraryPath> paths,
    required Map<String, SourceConnection> connections,
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
        );
      }

      logger.i('VideoScannerService: 文件扫描完成，共 ${allVideos.length} 个视频');

      // 保存视频列表到 Hive 缓存（用于快速启动）
      final cacheEntries = allVideos
          .map(
            (v) => VideoLibraryCacheEntry(
              sourceId: v.sourceId,
              filePath: v.file.path,
              fileName: v.file.name,
              thumbnailUrl: v.file.thumbnailUrl,
              size: v.file.size,
              modifiedTime: v.file.modifiedTime,
            ),
          )
          .toList();

      final cache = VideoLibraryCache(
        videos: cacheEntries,
        lastUpdated: DateTime.now(),
        sourceIds: sourceIds.toList(),
      );
      await _cacheService.saveCache(cache);

      // 阶段2：保存基础记录到 SQLite
      _emitProgress(
        VideoScanProgress(
          phase: VideoScanPhase.savingToDb,
          totalCount: allVideos.length,
        ),
      );

      await _saveBasicMetadataToDb(allVideos);

      // 完成文件扫描
      _emitProgress(
        VideoScanProgress(
          phase: VideoScanPhase.completed,
          scannedCount: allVideos.length,
        ),
      );

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
      final nfoFlags = <({String sourceId, String filePath, bool hasNfo})>[];

      for (final video in batch) {
        // 检查是否已存在
        final existing = await _dbService.get(video.sourceId, video.file.path);
        if (existing != null) {
          // 已存在，但仍需更新 NFO 标志（可能目录内容有变化）
          if (video.hasNfoInDirectory) {
            nfoFlags.add((
              sourceId: video.sourceId,
              filePath: video.file.path,
              hasNfo: true,
            ));
          }
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

        // 记录 NFO 标志（新视频）
        if (video.hasNfoInDirectory) {
          nfoFlags.add((
            sourceId: video.sourceId,
            filePath: video.file.path,
            hasNfo: true,
          ));
        }
      }

      if (metadataList.isNotEmpty) {
        await _dbService.upsertBatch(metadataList);
      }

      // 批量更新 NFO 标志
      if (nfoFlags.isNotEmpty) {
        await _dbService.updateNfoFlagBatch(nfoFlags);
      }

      _emitProgress(
        VideoScanProgress(
          phase: VideoScanPhase.savingToDb,
          scannedCount: (i + batch.length).clamp(0, total),
          totalCount: total,
        ),
      );
    }
  }

  /// 完整扫描（扫描文件 + 刮削元数据）
  ///
  /// [paths] 要扫描的路径列表
  /// [connections] 源连接映射
  ///
  /// 注意：无深度限制，会递归扫描所有子目录
  Future<List<VideoMetadata>> scan({
    required List<MediaLibraryPath> paths,
    required Map<String, SourceConnection> connections,
  }) async {
    // 先扫描文件
    final count = await scanFilesOnly(paths: paths, connections: connections);

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
        final pendingVideos = await _dbService.getPendingScrape(
          limit: batchSize,
        );

        if (pendingVideos.isEmpty) {
          logger.i('VideoScannerService: 所有视频刮削完成');
          break;
        }

        // 获取刮削统计
        final stats = await _dbService.getScrapeStats();
        _scrapeStatsController.add(stats);

        for (final video in pendingVideos) {
          if (_shouldStopScraping) break;

          // 获取当前进度（每个视频开始前）
          final currentStats = await _dbService.getScrapeStats();
          _emitProgress(
            VideoScanProgress(
              phase: VideoScanPhase.scraping,
              scannedCount: currentStats.processed,
              totalCount: currentStats.total,
              currentFile: video.fileName,
            ),
          );

          await _scrapeOneVideo(video, connections);

          // 刮削完成后立即更新统计
          final updatedStats = await _dbService.getScrapeStats();
          _scrapeStatsController.add(updatedStats);

          // 添加延迟避免 API 限制
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }

      _emitProgress(
        VideoScanProgress(
          phase: VideoScanPhase.completed,
          scannedCount: (await _dbService.getScrapeStats()).total,
        ),
      );
    } on Exception catch (e, st) {
      logger.e('VideoScannerService: 刮削失败', e, st);
      _emitProgress(const VideoScanProgress(phase: VideoScanPhase.error));
    } finally {
      _isScraping = false;
    }
  }

  /// 刮削单个视频（带重试机制）
  ///
  /// 网络错误时自动重试，最多重试 [maxRetries] 次
  Future<void> _scrapeOneVideo(
    VideoMetadata video,
    Map<String, SourceConnection> connections, {
    int maxRetries = 3,
  }) async {
    var retryCount = 0;
    Exception? lastError;

    while (retryCount <= maxRetries) {
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
            logger.w(
              'VideoScannerService: 获取视频URL失败 ${video.filePath}，错误原因 $e',
            );
          }
        }

        // 获取元数据（跳过缩略图生成以加速刮削，缩略图会在后台异步生成）
        final metadata = await _metadataService.getOrFetch(
          sourceId: video.sourceId,
          filePath: video.filePath,
          fileName: video.fileName,
          fileSystem: fileSystem,
          videoUrl: videoUrl,
          skipThumbnail: true, // 刮削时跳过缩略图，后续单独处理
        );

        // 根据结果更新刮削状态
        if (metadata.hasMetadata) {
          metadata.scrapeStatus = ScrapeStatus.completed;
        } else {
          metadata.scrapeStatus = ScrapeStatus.failed;
        }

        // 保留文件信息
        metadata
          ..fileSize = video.fileSize
          ..fileModifiedTime = video.fileModifiedTime;

        await _metadataService.save(metadata);

        // 成功，退出重试循环
        return;
      } on Exception catch (e) {
        lastError = e;
        retryCount++;

        // 判断是否是可重试的网络错误
        if (_isRetryableError(e) && retryCount <= maxRetries) {
          final delay = Duration(seconds: retryCount * 2); // 指数退避
          logger.w(
            'VideoScannerService: 刮削失败 ${video.fileName}，'
            '$delay 后重试 ($retryCount/$maxRetries)',
            e,
          );
          await Future<void>.delayed(delay);
          continue;
        }

        // 不可重试的错误或重试次数用尽
        break;
      }
    }

    // 所有重试都失败
    logger.w('''
      VideoScannerService: 刮削最终失败 ${video.fileName}，
      重试 $retryCount 次后放弃,
      ''',
      lastError,
    );

    // 标记为失败
    await _dbService.updateScrapeStatus(
      video.sourceId,
      video.filePath,
      ScrapeStatus.failed,
    );
  }

  /// 判断是否是可重试的错误
  bool _isRetryableError(Exception e) {
    final errorStr = e.toString().toLowerCase();
    // 网络相关错误
    if (errorStr.contains('socket') ||
        errorStr.contains('timeout') ||
        errorStr.contains('connection') ||
        errorStr.contains('network') ||
        errorStr.contains('handshake') ||
        errorStr.contains('http') ||
        errorStr.contains('failed host lookup')) {
      return true;
    }
    // TMDB API 限流
    if (errorStr.contains('429') || errorStr.contains('rate limit')) {
      return true;
    }
    return false;
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

  /// 获取需要重试的视频数量
  ///
  /// 包括刮削失败的和刮削完成但没有 TMDB 数据的
  Future<int> getRetryableCount() async {
    await _dbService.init();
    return _dbService.getRetryableCount();
  }

  /// 重试刮削失败和无 TMDB 数据的视频
  ///
  /// 只会刮削失败的和完成但无 TMDB ID 的视频，
  /// 不会重新刮削已成功获取 TMDB 数据的视频
  Future<void> retryScrapeFailedVideos({
    required Map<String, SourceConnection> connections,
  }) async {
    if (_isScraping) {
      logger.w('VideoScannerService: 刮削正在进行中，跳过重试');
      return;
    }

    try {
      await _dbService.init();

      // 获取需要重试的数量
      final retryableCount = await _dbService.getRetryableCount();
      if (retryableCount == 0) {
        logger.i('VideoScannerService: 没有需要重试的视频');
        return;
      }

      logger.i('VideoScannerService: 开始重试刮削 $retryableCount 个视频');

      // 重置需要重试的视频状态为 pending
      await _dbService.resetRetryableVideos();

      // 开始刮削
      await scrapeMetadata(connections: connections);
    } on Exception catch (e, st) {
      logger.e('VideoScannerService: 重试刮削失败', e, st);
    }
  }

  /// 递归扫描目录（无深度限制）
  ///
  /// 会跳过以下目录：
  /// - 隐藏目录（以 . 开头）
  /// - 系统目录（以 @ 开头、#recycle、eaDir）
  Future<void> _scanDirectory({
    required NasFileSystem fileSystem,
    required String sourceId,
    required String path,
    required List<_ScannedVideo> videos,
  }) async {
    _emitProgress(
      VideoScanProgress(
        phase: VideoScanPhase.scanning,
        currentPath: path,
        scannedCount: videos.length,
      ),
    );

    try {
      final items = await fileSystem.listDirectory(path);

      // 检测当前目录是否包含 NFO 文件（用于设置刮削优先级）
      final hasNfo = items.any((item) =>
          !item.isDirectory &&
          (item.name.toLowerCase().endsWith('.nfo') ||
           item.name.toLowerCase() == 'movie.nfo' ||
           item.name.toLowerCase() == 'tvshow.nfo'));

      for (final item in items) {
        if (item.isDirectory) {
          // 跳过隐藏目录和系统目录
          if (_shouldSkipDirectory(item.name)) {
            continue;
          }

          // 递归扫描子目录
          await _scanDirectory(
            fileSystem: fileSystem,
            sourceId: sourceId,
            path: item.path,
            videos: videos,
          );
        } else if (item.type == FileType.video) {
          videos.add(_ScannedVideo(
            sourceId: sourceId,
            file: item,
            hasNfoInDirectory: hasNfo,
          ));

          // 每扫描到一定数量更新进度
          if (videos.length % 10 == 0) {
            _emitProgress(
              VideoScanProgress(
                phase: VideoScanPhase.scanning,
                currentPath: path,
                scannedCount: videos.length,
              ),
            );
          }
        }
      }
    } on Exception catch (e) {
      logger.w('VideoScannerService: 扫描目录失败 $path', e);
    }
  }

  /// 判断是否应该跳过该目录
  bool _shouldSkipDirectory(String name) =>
      name.startsWith('.') ||
      name.startsWith('@') ||
      name.startsWith('#recycle') ||
      name == 'eaDir' ||
      name == '@eaDir';

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
    this.hasNfoInDirectory = false,
  });

  final String sourceId;
  final FileItem file;
  final bool hasNfoInDirectory; // 同目录下是否有 NFO 文件
}
