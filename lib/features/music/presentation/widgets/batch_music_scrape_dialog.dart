import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/data/services/music_scraper_manager_service.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;

/// 批量音乐刮削对话框
///
/// 对指定文件夹下的所有音乐进行批量刮削，复用自动识别功能
class BatchMusicScrapeDialog extends ConsumerStatefulWidget {
  const BatchMusicScrapeDialog({
    super.key,
    required this.sourceId,
    required this.pathPrefix,
    required this.connection,
  });

  final String sourceId;
  final String pathPrefix;
  final SourceConnection connection;

  /// 显示批量刮削对话框
  static Future<bool?> show(
    BuildContext context, {
    required String sourceId,
    required String pathPrefix,
    required SourceConnection connection,
  }) =>
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => BatchMusicScrapeDialog(
          sourceId: sourceId,
          pathPrefix: pathPrefix,
          connection: connection,
        ),
      );

  @override
  ConsumerState<BatchMusicScrapeDialog> createState() =>
      _BatchMusicScrapeDialogState();
}

class _BatchMusicScrapeDialogState
    extends ConsumerState<BatchMusicScrapeDialog> {
  // 状态
  _BatchScrapeStatus _status = _BatchScrapeStatus.preparing;
  String _statusMessage = '准备中...';
  double _progress = 0;

  // 统计
  int _totalCount = 0;
  int _processedCount = 0;
  int _successCount = 0;
  int _skipCount = 0;
  int _failCount = 0;
  String? _currentTrack;

  // 取消标记
  bool _cancelled = false;

  // 服务
  final _db = MusicDatabaseService();
  final _coverCache = MusicCoverCacheService();

  // 文件系统
  NasFileSystem? get _fileSystem => widget.connection.adapter.fileSystem;

  @override
  void initState() {
    super.initState();
    _prepareAndStart();
  }

  /// 准备并直接开始刮削（无需用户确认）
  Future<void> _prepareAndStart() async {
    try {
      await _db.init();
      await _coverCache.init();

      // 获取该路径下的所有音乐数量
      final count = await _db.getCount(
        sourceId: widget.sourceId,
        pathPrefix: widget.pathPrefix,
      );

      if (count == 0) {
        if (mounted) {
          setState(() {
            _status = _BatchScrapeStatus.completed;
            _statusMessage = '没有需要刮削的音乐';
          });
        }
        return;
      }

      _totalCount = count;

      // 直接开始刮削
      await _startScraping();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '准备批量刮削数据失败');
      if (mounted) {
        setState(() {
          _status = _BatchScrapeStatus.error;
          _statusMessage = '准备失败: $e';
        });
      }
    }
  }

  Future<void> _startScraping() async {
    if (_totalCount == 0) {
      if (mounted) {
        setState(() {
          _status = _BatchScrapeStatus.completed;
          _statusMessage = '没有需要刮削的音乐';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _status = _BatchScrapeStatus.scraping;
        _statusMessage = '正在刮削...';
        _progress = 0;
        _processedCount = 0;
        _successCount = 0;
        _skipCount = 0;
        _failCount = 0;
      });
    }

    try {
      final manager = ref.read(musicScraperManagerProvider);
      await manager.init();

      // 分批获取音乐（避免一次性加载太多）
      const batchSize = 50;
      var offset = 0;

      while (!_cancelled) {
        final tracks = await _db.getPage(
          limit: batchSize,
          offset: offset,
          enabledPaths: [(sourceId: widget.sourceId, path: widget.pathPrefix)],
        );

        if (tracks.isEmpty) break;

        for (final track in tracks) {
          if (_cancelled) break;

          if (mounted) {
            setState(() {
              _currentTrack = track.displayTitle;
            });
          }

          await _processTrack(track, manager);

          _processedCount++;
          if (mounted) {
            setState(() {
              _progress = _processedCount / _totalCount;
            });
          }

          // 稍微延迟，避免请求过快
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }

        offset += batchSize;
      }

      if (mounted) {
        setState(() {
          _status =
              _cancelled ? _BatchScrapeStatus.cancelled : _BatchScrapeStatus.completed;
          _statusMessage = _cancelled
              ? '已取消'
              : '完成！成功: $_successCount, 跳过: $_skipCount, 失败: $_failCount';
          _progress = 1;
        });
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'batchMusicScrape');
      if (mounted) {
        setState(() {
          _status = _BatchScrapeStatus.error;
          _statusMessage = '刮削失败: $e';
        });
      }
    }
  }

  Future<void> _processTrack(
    MusicTrackEntity track,
    MusicScraperManagerService manager,
  ) async {
    try {
      // 检查各项是否已有
      final hasCover = track.coverPath != null && track.coverPath!.isNotEmpty;
      final hasTitle = track.title != null && track.title!.isNotEmpty;
      final hasArtist = track.artist != null && track.artist!.isNotEmpty;
      final hasAlbum = track.album != null && track.album!.isNotEmpty;
      final hasYear = track.year != null;
      final hasGenre = track.genre != null && track.genre!.isNotEmpty;

      // 检查是否已有歌词文件
      final hasLyrics = await _checkLyricsExists(track.filePath);

      // 如果全部都有，直接跳过
      if (hasCover && hasTitle && hasArtist && hasAlbum && hasLyrics) {
        _skipCount++;
        return;
      }

      // 确定需要获取什么
      final needCover = !hasCover;
      final needLyrics = !hasLyrics;
      // 缺少任何元数据字段都需要尝试获取
      final needAnyMetadata = !hasTitle || !hasArtist || !hasAlbum || !hasYear || !hasGenre;

      // 搜索元数据（使用现有数据或从文件名解析）
      final searchTitle = hasTitle ? track.title! : track.displayTitle;
      final searchArtist = hasArtist ? track.artist : null;

      final result = await manager.scrape(
        title: searchTitle,
        artist: searchArtist,
        album: hasAlbum ? track.album : null,
        getCover: needCover,
        getLyrics: needLyrics,
      );

      // 检查是否有任何有用的结果
      final hasUsefulResult = (needAnyMetadata && result.detail != null) ||
          (needCover && result.cover != null) ||
          (needLyrics && result.lyrics != null && result.lyrics!.hasLyrics);

      if (!hasUsefulResult) {
        _failCount++;
        return;
      }

      // 应用结果（只补充缺失的内容）
      await _applyResult(
        track,
        result,
        needCover: needCover,
        needLyrics: needLyrics,
        hasTitle: hasTitle,
        hasArtist: hasArtist,
        hasAlbum: hasAlbum,
        hasYear: hasYear,
        hasGenre: hasGenre,
      );
      _successCount++;
    } on Exception catch (e) {
      logger.w('BatchMusicScrape: 处理失败 ${track.displayTitle}: $e');
      _failCount++;
    }
  }

  /// 检查歌词文件是否存在
  Future<bool> _checkLyricsExists(String musicPath) async {
    if (_fileSystem == null) return false;

    try {
      final musicDir = p.dirname(musicPath);
      final baseName = p.basenameWithoutExtension(musicPath);
      final lrcPath = p.join(musicDir, '$baseName.lrc');

      // 尝试获取文件信息，如果成功则文件存在
      await _fileSystem!.getFileInfo(lrcPath);
      return true;
    } on Exception {
      // 文件不存在或获取失败
      return false;
    }
  }

  Future<void> _applyResult(
    MusicTrackEntity track,
    MusicScrapeResult result, {
    required bool needCover,
    required bool needLyrics,
    required bool hasTitle,
    required bool hasArtist,
    required bool hasAlbum,
    required bool hasYear,
    required bool hasGenre,
  }) async {
    var updatedTrack = track;

    // 下载封面（仅当缺少封面时）
    if (needCover && result.cover != null) {
      try {
        final dio = Dio();
        final response = await dio.get<List<int>>(
          result.cover!.coverUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        if (response.data != null) {
          final coverData = Uint8List.fromList(response.data!);

          // 保存封面到本地缓存
          final uniqueKey = '${track.sourceId}_${track.filePath}';
          final localCoverPath = await _coverCache.saveCover(uniqueKey, coverData);

          if (localCoverPath != null) {
            updatedTrack = updatedTrack.copyWith(coverPath: localCoverPath);
          }
        }
      } on Exception catch (e) {
        logger.w('BatchMusicScrape: 下载封面失败: $e');
      }
    }

    // 下载歌词到 NAS（仅当缺少歌词时）
    if (needLyrics && result.lyrics != null && result.lyrics!.hasLyrics && _fileSystem != null) {
      try {
        final lrcContent = result.lyrics!.lrcContent ?? result.lyrics!.plainText ?? '';
        if (lrcContent.isNotEmpty) {
          final musicDir = p.dirname(track.filePath);
          final baseName = p.basenameWithoutExtension(track.filePath);
          final lrcPath = p.join(musicDir, '$baseName.lrc');
          final utf8Bytes = const Utf8Encoder().convert(lrcContent);
          await _fileSystem!.writeFile(lrcPath, Uint8List.fromList(utf8Bytes));
        }
      } on Exception catch (e) {
        logger.w('BatchMusicScrape: 下载歌词失败: $e');
      }
    }

    // 补充缺失的元数据字段（不覆盖已有数据）
    if (result.detail != null) {
      final detail = result.detail!;
      updatedTrack = updatedTrack.copyWith(
        // 只补充缺失的字段
        title: hasTitle ? track.title : detail.title,
        artist: hasArtist ? track.artist : detail.artist,
        album: hasAlbum ? track.album : detail.album,
        year: hasYear ? track.year : detail.year,
        trackNumber: track.trackNumber ?? detail.trackNumber,
        genre: hasGenre ? track.genre : detail.genres?.join(', '),
      );
    }

    // 保存更新
    if (updatedTrack != track) {
      await _db.upsert(updatedTrack);
    }
  }

  void _cancel() {
    _cancelled = true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      title: Row(
        children: [
          Icon(Icons.auto_fix_high_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          const Expanded(child: Text('批量刮削')),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 状态信息
            _buildStatusRow(isDark),

            // 刮削中：显示进度
            if (_status == _BatchScrapeStatus.scraping) ...[
              const SizedBox(height: 16),
              _buildProgress(isDark),
            ],

            // 完成：显示统计
            if (_status == _BatchScrapeStatus.completed ||
                _status == _BatchScrapeStatus.cancelled) ...[
              const SizedBox(height: 16),
              _buildStats(isDark),
            ],

            // 说明文字
            if (_status == _BatchScrapeStatus.preparing ||
                _status == _BatchScrapeStatus.scraping) ...[
              const SizedBox(height: 12),
              Text(
                '• 已有元数据/封面/歌词的将自动跳过\n• 不会覆盖本地已有数据',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildStatusRow(bool isDark) => Row(
        children: [
          if (_status == _BatchScrapeStatus.preparing ||
              _status == _BatchScrapeStatus.scraping)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            )
          else if (_status == _BatchScrapeStatus.completed)
            Icon(Icons.check_circle, size: 16, color: AppColors.success)
          else if (_status == _BatchScrapeStatus.cancelled)
            Icon(Icons.cancel, size: 16, color: AppColors.warning)
          else if (_status == _BatchScrapeStatus.error)
            Icon(Icons.error, size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ),
        ],
      );

  Widget _buildProgress(bool isDark) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 当前处理的歌曲
          if (_currentTrack != null)
            Text(
              '正在处理: $_currentTrack',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 8),
          // 进度条
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
            color: AppColors.primary,
          ),
          const SizedBox(height: 8),
          // 统计
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_processedCount / $_totalCount',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              Text(
                '成功: $_successCount  跳过: $_skipCount  失败: $_failCount',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                ),
              ),
            ],
          ),
        ],
      );

  Widget _buildStats(bool isDark) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            _buildStatRow('总计', _totalCount, isDark),
            _buildStatRow('成功', _successCount, isDark, color: AppColors.success),
            _buildStatRow('跳过', _skipCount, isDark, color: AppColors.warning),
            _buildStatRow('失败', _failCount, isDark, color: AppColors.error),
          ],
        ),
      );

  Widget _buildStatRow(String label, int value, bool isDark, {Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color ?? (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ],
        ),
      );

  List<Widget> _buildActions() {
    switch (_status) {
      case _BatchScrapeStatus.preparing:
      case _BatchScrapeStatus.scraping:
        return [
          TextButton(
            onPressed: _cancel,
            child: const Text('停止'),
          ),
        ];

      case _BatchScrapeStatus.completed:
      case _BatchScrapeStatus.cancelled:
      case _BatchScrapeStatus.error:
        return [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_successCount > 0),
            child: const Text('完成'),
          ),
        ];
    }
  }
}

enum _BatchScrapeStatus {
  preparing,
  scraping,
  completed,
  cancelled,
  error,
}
