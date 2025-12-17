import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/features/music/data/services/fingerprint/fingerprint_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;

/// 自动刮削对话框
///
/// 显示刮削进度和结果，允许用户选择下载封面和歌词
class AutoScrapeDialog extends ConsumerStatefulWidget {
  const AutoScrapeDialog({
    super.key,
    required this.music,
    this.fileSystem,
  });

  final MusicItem music;
  final NasFileSystem? fileSystem;

  /// 显示自动刮削对话框
  static Future<bool?> show(
    BuildContext context,
    MusicItem music, {
    NasFileSystem? fileSystem,
  }) => showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AutoScrapeDialog(
          music: music,
          fileSystem: fileSystem,
        ),
      );

  @override
  ConsumerState<AutoScrapeDialog> createState() => _AutoScrapeDialogState();
}

class _AutoScrapeDialogState extends ConsumerState<AutoScrapeDialog> {
  // 状态
  _ScrapeStatus _status = _ScrapeStatus.searching;
  String _statusMessage = '正在搜索...';
  double? _progress;

  // 结果
  MusicScraperDetail? _detail;
  CoverScraperResult? _cover;
  LyricScraperResult? _lyrics;
  FingerprintResult? _fingerprintResult;

  // 下载选项
  bool _downloadCover = true;
  bool _downloadLyrics = true;

  // 错误信息
  String? _errorMessage;

  // 识别方式
  bool _usedFingerprint = false;

  @override
  void initState() {
    super.initState();
    _startScraping();
  }

  /// 获取本地文件路径
  ///
  /// 如果 url 是 file:// 协议则返回本地路径，否则返回 null
  String? get _localFilePath {
    final url = widget.music.url;
    if (url.startsWith('file://')) {
      return Uri.parse(url).toFilePath();
    }
    // 桌面端可能直接使用本地路径
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (File(url).existsSync()) {
        return url;
      }
    }
    return null;
  }

  /// 检查是否可以使用音纹识别
  bool get _canUseFingerprint {
    // 需要本地文件路径且指纹服务可用
    final localPath = _localFilePath;
    if (localPath == null || localPath.isEmpty) return false;
    if (!File(localPath).existsSync()) return false;

    final service = FingerprintService.getInstance();
    return service?.isAvailable ?? false;
  }

  Future<void> _startScraping() async {
    try {
      final manager = ref.read(musicScraperManagerProvider);
      await manager.init();

      // 优先尝试音纹识别（如果可用）
      if (_canUseFingerprint) {
        final fingerprintSuccess = await _tryFingerprintRecognition();
        if (fingerprintSuccess) return;
      }

      // 回退到普通元数据搜索
      await _searchByMetadata();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '自动刮削失败');
      if (mounted) {
        setState(() {
          _status = _ScrapeStatus.error;
          _statusMessage = '刮削失败';
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// 尝试音纹识别
  Future<bool> _tryFingerprintRecognition() async {
    final localPath = _localFilePath;
    if (localPath == null) return false;

    setState(() {
      _statusMessage = '正在生成音频指纹...';
      _progress = 0.1;
    });

    try {
      final service = FingerprintService.getInstance();
      if (service == null) return false;

      // 生成指纹
      final fpData = await service.generateFingerprint(localPath);

      setState(() {
        _statusMessage = '正在识别音乐...';
        _progress = 0.4;
      });

      // 查询 AcoustID
      final manager = ref.read(musicScraperManagerProvider);
      final result = await manager.lookupByFingerprint(
        fpData.fingerprint,
        fpData.duration,
      );

      if (result == null || result.isEmpty) {
        // 音纹识别无结果，回退到元数据搜索
        return false;
      }

      setState(() {
        _statusMessage = '获取详细信息...';
        _progress = 0.7;
        _fingerprintResult = result;
        _usedFingerprint = true;
      });

      // 使用最佳匹配获取详细信息
      final bestMatch = result.bestMatch;
      if (bestMatch != null) {
        final scrapeResult = await manager.scrape(
          title: bestMatch.title ?? widget.music.displayTitle,
          artist: bestMatch.artist,
          album: bestMatch.album,
          getCover: true,
          getLyrics: true,
        );

        _handleScrapeResult(scrapeResult);
        return true;
      }

      return false;
    } on FingerprintException catch (e) {
      // 指纹服务异常，回退到元数据搜索
      debugPrint('Fingerprint failed: $e');
      return false;
    }
  }

  /// 通过元数据搜索
  Future<void> _searchByMetadata() async {
    final title = widget.music.displayTitle;
    final artist = widget.music.displayArtist;

    setState(() {
      _statusMessage = '搜索 "$title"...';
      _progress = 0.2;
    });

    final manager = ref.read(musicScraperManagerProvider);
    final result = await manager.scrape(
      title: title,
      artist: artist.isNotEmpty ? artist : null,
      album: widget.music.album,
      getCover: true,
      getLyrics: true,
    );

    _handleScrapeResult(result);
  }

  /// 处理刮削结果
  void _handleScrapeResult(MusicScrapeResult result) {
    if (!mounted) return;

    if (result.detail == null && result.cover == null && result.lyrics == null) {
      setState(() {
        _status = _ScrapeStatus.notFound;
        _statusMessage = '未找到匹配结果';
        if (result.errors.isNotEmpty) {
          _errorMessage = result.errors.join('\n');
        }
      });
      return;
    }

    setState(() {
      _status = _ScrapeStatus.found;
      _statusMessage = _usedFingerprint ? '音纹识别成功' : '找到匹配结果';
      _progress = 1.0;
      _detail = result.detail;
      _cover = result.cover;
      _lyrics = result.lyrics;

      // 如果已有封面，默认不下载
      if (widget.music.coverUrl != null || widget.music.coverData != null) {
        _downloadCover = false;
      }
    });
  }

  Future<void> _downloadFiles() async {
    if (widget.fileSystem == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法访问文件系统')),
        );
      }
      return;
    }

    setState(() {
      _status = _ScrapeStatus.downloading;
      _statusMessage = '正在下载...';
      _progress = 0;
    });

    final fileSystem = widget.fileSystem!;
    final musicPath = widget.music.path;
    final musicDir = p.dirname(musicPath);
    final baseName = p.basenameWithoutExtension(musicPath);

    var downloadedCount = 0;
    final totalDownloads = (_downloadCover && _cover != null ? 1 : 0) +
        (_downloadLyrics && _lyrics != null ? 1 : 0);

    try {
      // 下载封面
      if (_downloadCover && _cover != null) {
        setState(() {
          _statusMessage = '下载封面...';
        });

        await _downloadCover_(fileSystem, musicDir, baseName);
        downloadedCount++;
        setState(() {
          _progress = downloadedCount / totalDownloads;
        });
      }

      // 下载歌词
      if (_downloadLyrics && _lyrics != null) {
        setState(() {
          _statusMessage = '下载歌词...';
        });

        await _downloadLyrics_(fileSystem, musicDir, baseName);
        downloadedCount++;
        setState(() {
          _progress = downloadedCount / totalDownloads;
        });
      }

      setState(() {
        _status = _ScrapeStatus.completed;
        _statusMessage = '下载完成';
        _progress = 1.0;
      });

      // 延迟关闭
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '下载文件失败');
      setState(() {
        _status = _ScrapeStatus.error;
        _statusMessage = '下载失败';
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _downloadCover_(
    NasFileSystem fileSystem,
    String musicDir,
    String baseName,
  ) async {
    if (_cover == null) return;

    try {
      final dio = Dio();
      final response = await dio.get<List<int>>(
        _cover!.coverUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data == null) return;

      final coverData = Uint8List.fromList(response.data!);

      // 确定文件扩展名
      final ext = _cover!.coverUrl.contains('.png') ? 'png' : 'jpg';

      // 尝试保存为 folder.jpg，如果已存在则保存为 {filename}-cover.jpg
      final folderCoverPath = p.join(musicDir, 'folder.$ext');
      var exists = false;
      try {
        await fileSystem.getFileInfo(folderCoverPath);
        exists = true;
      } on Exception {
        exists = false;
      }

      final coverPath = exists
          ? p.join(musicDir, '$baseName-cover.$ext')
          : folderCoverPath;

      await fileSystem.writeFile(coverPath, coverData);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '下载封面失败');
    }
  }

  Future<void> _downloadLyrics_(
    NasFileSystem fileSystem,
    String musicDir,
    String baseName,
  ) async {
    if (_lyrics == null || !_lyrics!.hasLyrics) return;

    try {
      final lrcContent = _lyrics!.lrcContent ?? _lyrics!.plainText ?? '';
      if (lrcContent.isEmpty) return;

      final lrcPath = p.join(musicDir, '$baseName.lrc');
      await fileSystem.writeFile(lrcPath, Uint8List.fromList(lrcContent.codeUnits));
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '下载歌词失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      title: Row(
        children: [
          Icon(
            Icons.auto_fix_high_rounded,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('自动识别'),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 当前音乐信息
            _buildMusicInfo(theme, isDark),
            const SizedBox(height: 16),

            // 状态/进度
            _buildStatus(theme, isDark),

            // 结果预览
            if (_status == _ScrapeStatus.found) ...[
              const SizedBox(height: 16),
              _buildResults(theme, isDark),
            ],

            // 错误信息
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red[700],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: _buildActions(isDark),
    );
  }

  Widget _buildMusicInfo(ThemeData theme, bool isDark) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // 封面
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: AppColors.primary.withValues(alpha: 0.1),
            ),
            clipBehavior: Clip.antiAlias,
            child: _buildCoverImage(),
          ),
          const SizedBox(width: 12),

          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.music.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.music.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

  Widget _buildCoverImage() {
    // 如果有 coverData，优先使用
    if (widget.music.coverData != null) {
      return Image.memory(
        Uint8List.fromList(widget.music.coverData!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.music_note_rounded,
          color: AppColors.primary,
        ),
      );
    }

    // 如果有 coverUrl
    if (widget.music.coverUrl != null) {
      return Image.network(
        widget.music.coverUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.music_note_rounded,
          color: AppColors.primary,
        ),
      );
    }

    // 默认图标
    return Icon(
      Icons.music_note_rounded,
      color: AppColors.primary,
    );
  }

  Widget _buildStatus(ThemeData theme, bool isDark) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 状态文字
        Row(
          children: [
            if (_status == _ScrapeStatus.searching ||
                _status == _ScrapeStatus.downloading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            else if (_status == _ScrapeStatus.found ||
                _status == _ScrapeStatus.completed)
              Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: Colors.green,
              )
            else if (_status == _ScrapeStatus.notFound)
              Icon(
                Icons.search_off_rounded,
                size: 16,
                color: Colors.orange,
              )
            else if (_status == _ScrapeStatus.error)
              Icon(
                Icons.error_rounded,
                size: 16,
                color: Colors.red,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _statusMessage,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
            ),
          ],
        ),

        // 进度条
        if (_progress != null &&
            (_status == _ScrapeStatus.searching ||
                _status == _ScrapeStatus.downloading)) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
            color: AppColors.primary,
          ),
        ],
      ],
    );

  Widget _buildResults(ThemeData theme, bool isDark) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '找到以下内容:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey[300] : Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),

        // 元数据
        if (_detail != null)
          _buildResultRow(
            isDark,
            Icons.info_outline_rounded,
            '元数据',
            '${_detail!.title} - ${_detail!.artist ?? "未知"}',
            source: _detail!.source,
          ),

        // 封面
        if (_cover != null)
          _buildResultRow(
            isDark,
            Icons.image_rounded,
            '封面',
            '来自 ${_cover!.source.displayName}',
            source: _cover!.source,
            trailing: Checkbox(
              value: _downloadCover,
              onChanged: (v) => setState(() => _downloadCover = v ?? true),
              visualDensity: VisualDensity.compact,
            ),
          ),

        // 歌词
        if (_lyrics != null && _lyrics!.hasLyrics)
          _buildResultRow(
            isDark,
            Icons.lyrics_rounded,
            '歌词',
            _lyrics!.isLrc ? 'LRC (时间同步)' : '纯文本',
            source: _lyrics!.source,
            trailing: Checkbox(
              value: _downloadLyrics,
              onChanged: (v) => setState(() => _downloadLyrics = v ?? true),
              visualDensity: VisualDensity.compact,
            ),
          ),

        // 无封面/歌词时提示
        if (_cover == null && _lyrics == null && _detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '未找到封面和歌词',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
          ),
      ],
    );

  Widget _buildResultRow(
    bool isDark,
    IconData icon,
    String label,
    String value, {
    MusicScraperType? source,
    Widget? trailing,
  }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );

  List<Widget> _buildActions(bool isDark) {
    switch (_status) {
      case _ScrapeStatus.searching:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
        ];

      case _ScrapeStatus.found:
        final hasDownloadable = (_downloadCover && _cover != null) ||
            (_downloadLyrics && _lyrics != null);
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          if (hasDownloadable && widget.fileSystem != null)
            FilledButton(
              onPressed: _downloadFiles,
              child: const Text('下载'),
            ),
        ];

      case _ScrapeStatus.downloading:
        return [];

      case _ScrapeStatus.completed:
        return [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('完成'),
          ),
        ];

      case _ScrapeStatus.notFound:
      case _ScrapeStatus.error:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _status = _ScrapeStatus.searching;
                _statusMessage = '正在搜索...';
                _progress = null;
                _errorMessage = null;
              });
              _startScraping();
            },
            child: const Text('重试'),
          ),
        ];
    }
  }
}

enum _ScrapeStatus {
  searching,
  found,
  downloading,
  completed,
  notFound,
  error,
}
