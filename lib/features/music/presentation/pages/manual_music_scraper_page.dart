import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/data/services/music_tag_writer_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_tag_write_queue_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';
import 'package:path/path.dart' as p;

/// 手动音乐刮削页面
class ManualMusicScraperPage extends ConsumerStatefulWidget {
  const ManualMusicScraperPage({
    super.key,
    required this.music,
    this.fileSystem,
  });

  final MusicItem music;
  final NasFileSystem? fileSystem;

  @override
  ConsumerState<ManualMusicScraperPage> createState() => _ManualMusicScraperPageState();
}

class _ManualMusicScraperPageState extends ConsumerState<ManualMusicScraperPage> {
  // 搜索控制器
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _artistController = TextEditingController();

  // 状态
  bool _isSearching = false;
  bool _isLoadingDetail = false;
  bool _isScraping = false;
  String? _errorMessage;

  // 搜索结果（按来源分组）
  Map<MusicScraperType, List<MusicScraperItem>> _searchResults = {};

  // 选中的详情
  MusicScraperDetail? _selectedDetail;
  LyricScraperResult? _selectedLyrics;
  CoverScraperResult? _selectedCover;

  // 刮削选项
  bool _downloadCover = true;
  bool _downloadLyrics = true;
  bool _writeToFile = true;

  // 标签写入服务
  final _tagWriter = MusicTagWriterService();
  SupportedAudioFormat? _audioFormat;

  @override
  void initState() {
    super.initState();
    _audioFormat = _tagWriter.getFormat(widget.music.path);
    _initFromMusic();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  void _initFromMusic() {
    // 使用现有元数据或从文件名解析
    _titleController.text = widget.music.displayTitle;
    _artistController.text = widget.music.displayArtist;

    // 自动搜索
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  Future<void> _search() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _searchResults.clear();
      _selectedDetail = null;
      _selectedLyrics = null;
      _selectedCover = null;
    });

    try {
      final manager = ref.read(musicScraperManagerProvider);
      await manager.init();

      final results = await manager.search(
        title,
        artist: _artistController.text.trim().isNotEmpty
            ? _artistController.text.trim()
            : null,
      );

      // 按来源分组
      final grouped = <MusicScraperType, List<MusicScraperItem>>{};
      for (final result in results) {
        for (final item in result.items) {
          grouped.putIfAbsent(item.source, () => []).add(item);
        }
      }

      setState(() {
        _searchResults = grouped;
        _isSearching = false;
      });
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'ManualMusicScraperPage._search');
      setState(() {
        _errorMessage = '搜索失败: $e';
        _isSearching = false;
      });
    }
  }

  Future<void> _selectItem(MusicScraperItem item) async {
    setState(() {
      _isLoadingDetail = true;
      _errorMessage = null;
    });

    try {
      final manager = ref.read(musicScraperManagerProvider);

      // 获取详情
      final detail = await manager.getDetail(item.externalId, item.source);

      // 获取歌词
      LyricScraperResult? lyrics;
      if (item.source.supportsLyrics) {
        final sources = await manager.getSources();
        final source = sources.where((s) => s.type == item.source).firstOrNull;
        if (source != null) {
          final scraper = await manager.getScraper(source.id);
          if (scraper != null) {
            lyrics = await scraper.getLyrics(item.externalId);
          }
        }
      }

      // 获取封面
      CoverScraperResult? cover;
      if (item.coverUrl != null) {
        cover = CoverScraperResult(
          source: item.source,
          coverUrl: item.coverUrl!,
        );
      }

      setState(() {
        _selectedDetail = detail;
        _selectedLyrics = lyrics;
        _selectedCover = cover;
        _isLoadingDetail = false;
      });
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'ManualMusicScraperPage._selectItem');
      setState(() {
        _errorMessage = '获取详情失败: $e';
        _isLoadingDetail = false;
      });
    }
  }

  Future<void> _confirmAndScrape() async {
    if (_selectedDetail == null && _selectedCover == null && _selectedLyrics == null) {
      return;
    }

    // 获取文件系统
    var fileSystem = widget.fileSystem;
    if (fileSystem == null && widget.music.sourceId != null) {
      final connections = ref.read(activeConnectionsProvider);
      final connection = connections[widget.music.sourceId];
      if (connection?.status == SourceStatus.connected) {
        fileSystem = connection!.adapter.fileSystem;
      }
    }

    if (fileSystem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法访问文件系统')),
      );
      return;
    }

    setState(() => _isScraping = true);

    try {
      final musicDir = p.dirname(widget.music.path);
      final baseName = p.basenameWithoutExtension(widget.music.path);

      // 下载封面数据（用于写入标签和保存文件）
      Uint8List? coverData;
      String? coverMimeType;

      // 下载封面
      if (_downloadCover && _selectedCover != null) {
        final result = await _downloadCoverData();
        coverData = result.$1;
        coverMimeType = result.$2;

        // 保存封面文件到目录（这是小文件，可以快速完成）
        await _saveCoverFile(fileSystem, musicDir, baseName, coverData);

        // 立即同步封面到本地缓存，确保 UI 立即显示
        if (coverData != null) {
          await _syncCoverToLocalCache(coverData);
        }
      }

      // 下载歌词（同样是小文件）
      if (_downloadLyrics && (_selectedLyrics?.hasLyrics ?? false)) {
        await _downloadLyricsToFile(fileSystem, musicDir, baseName);
      }

      // 立即更新当前播放音乐的元数据（如果正在播放此歌曲）
      _updateCurrentMusicMetadata(coverData);

      // 将文件标签写入加入后台队列（如果需要）
      if (_writeToFile && _audioFormat != null && _selectedDetail != null) {
        _queueTagWrite(coverData, coverMimeType);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('刮削完成，标签后台写入中...')),
      );

      Navigator.pop(context, true);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'ManualMusicScraperPage._confirmAndScrape');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刮削失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScraping = false);
      }
    }
  }

  /// 同步封面到本地磁盘缓存和数据库
  /// 确保刮削后的封面能够被正确显示，无需重新提取
  Future<void> _syncCoverToLocalCache(Uint8List coverData) async {
    final sourceId = widget.music.sourceId;
    if (sourceId == null) return;

    try {
      // 1. 保存封面到本地磁盘缓存
      final coverCache = MusicCoverCacheService();
      await coverCache.init();

      final uniqueKey = '${sourceId}_${widget.music.path}';
      final localCoverPath = await coverCache.saveCover(uniqueKey, coverData);

      if (localCoverPath == null) return;

      // 2. 更新数据库中的封面路径
      final db = MusicDatabaseService();
      await db.init();

      // 获取现有的曲目数据并更新封面路径
      final existing = await db.get(sourceId, widget.music.path);
      if (existing != null) {
        await db.upsert(existing.copyWith(coverPath: localCoverPath));
      } else {
        // 如果数据库中没有这首歌，创建一个基本条目
        await db.upsert(MusicTrackEntity(
          sourceId: sourceId,
          filePath: widget.music.path,
          fileName: widget.music.name,
          title: _selectedDetail?.title ?? widget.music.title,
          artist: _selectedDetail?.artist ?? widget.music.artist,
          album: _selectedDetail?.album ?? widget.music.album,
          coverPath: localCoverPath,
          duration: widget.music.duration?.inMilliseconds,
          lastUpdated: DateTime.now(),
        ));
      }
    } on Exception catch (e, st) {
      // 非关键功能，静默失败
      AppError.ignore(e, st, '同步封面到本地缓存失败');
    }
  }

  /// 立即更新当前播放音乐的元数据（如果正在播放此歌曲）
  void _updateCurrentMusicMetadata(Uint8List? coverData) {
    final currentMusic = ref.read(currentMusicProvider);
    if (currentMusic?.id != widget.music.id) return;

    // 更新 currentMusicProvider 状态
    ref.read(currentMusicProvider.notifier).state = currentMusic!.copyWith(
      title: _selectedDetail?.title ?? currentMusic.title,
      artist: _selectedDetail?.artist ?? currentMusic.artist,
      album: _selectedDetail?.album ?? currentMusic.album,
      lyrics: _selectedLyrics?.lrcContent ?? _selectedLyrics?.plainText ?? currentMusic.lyrics,
      coverData: coverData?.toList() ?? currentMusic.coverData,
    );
  }

  /// 将标签写入任务加入后台队列
  void _queueTagWrite(Uint8List? coverData, String? coverMimeType) {
    final writeQueue = ref.read(musicTagWriteQueueProvider);

    // 构建标签数据
    final tagData = MusicTagData(
      title: _selectedDetail?.title,
      artist: _selectedDetail?.artist,
      album: _selectedDetail?.album,
      albumArtist: _selectedDetail?.albumArtist,
      year: _selectedDetail?.year,
      trackNumber: _selectedDetail?.trackNumber,
      discNumber: _selectedDetail?.discNumber,
      genre: _selectedDetail?.genres?.join(', '),
      lyrics: _selectedLyrics?.lrcContent ?? _selectedLyrics?.plainText,
    );

    // 加入后台写入队列
    writeQueue.addTask(
      musicPath: widget.music.path,
      sourceId: widget.music.sourceId,
      tagData: tagData,
      coverData: coverData,
      coverMimeType: coverMimeType,
    );
  }

  /// 下载封面数据
  Future<(Uint8List?, String?)> _downloadCoverData() async {
    if (_selectedCover == null) return (null, null);

    try {
      final dio = Dio();
      final response = await dio.get<List<int>>(
        _selectedCover!.coverUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data == null) return (null, null);

      final coverData = Uint8List.fromList(response.data!);
      final mimeType = _selectedCover!.coverUrl.contains('.png') ? 'image/png' : 'image/jpeg';

      return (coverData, mimeType);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '下载封面数据失败');
      return (null, null);
    }
  }

  /// 保存封面文件到目录
  Future<void> _saveCoverFile(
    NasFileSystem fileSystem,
    String musicDir,
    String baseName,
    Uint8List? coverData,
  ) async {
    if (coverData == null || _selectedCover == null) return;

    try {
      final ext = _selectedCover!.coverUrl.contains('.png') ? 'png' : 'jpg';

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
      AppError.ignore(e, st, '保存封面文件失败');
    }
  }


  Future<void> _downloadLyricsToFile(
    NasFileSystem fileSystem,
    String musicDir,
    String baseName,
  ) async {
    if (_selectedLyrics == null || !_selectedLyrics!.hasLyrics) return;

    try {
      final lrcContent = _selectedLyrics!.lrcContent ?? _selectedLyrics!.plainText ?? '';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('手动刮削'),
      ),
      body: Column(
        children: [
          // 文件信息
          _buildFileInfo(theme, isDark),

          // 搜索栏
          _buildSearchBar(theme, isDark),

          // 内容区域
          Expanded(
            child: _selectedDetail != null || _selectedCover != null || _selectedLyrics != null
                ? _buildDetailView(theme, isDark)
                : _buildSearchResults(theme, isDark),
          ),
        ],
      ),
      bottomNavigationBar: _selectedDetail != null || _selectedCover != null || _selectedLyrics != null
          ? _buildBottomBar(theme, isDark)
          : null,
    );
  }

  Widget _buildFileInfo(ThemeData theme, bool isDark) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurface
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkOutline : theme.dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 封面
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: AppColors.fileAudio.withValues(alpha: 0.1),
            ),
            child: widget.music.coverUrl != null || widget.music.coverData != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: widget.music.coverData != null
                        ? Image.memory(
                            Uint8List.fromList(widget.music.coverData!),
                            fit: BoxFit.cover,
                          )
                        : AdaptiveImage(
                            imageUrl: widget.music.coverUrl!,
                            fit: BoxFit.cover,
                          ),
                  )
                : Icon(
                    Icons.music_note_rounded,
                    color: AppColors.fileAudio,
                    size: 28,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.music.displayTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.music.path,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );

  Widget _buildSearchBar(ThemeData theme, bool isDark) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 标题搜索框
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: '歌曲名称',
              hintText: '输入歌曲名称',
              prefixIcon: const Icon(Icons.music_note_outlined),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                onPressed: _isSearching ? null : _search,
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 12),
          // 艺术家过滤
          TextField(
            controller: _artistController,
            decoration: const InputDecoration(
              labelText: '艺术家（可选）',
              hintText: '输入艺术家名称以缩小搜索范围',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _search(),
          ),
        ],
      ),
    );

  Widget _buildSearchResults(ThemeData theme, bool isDark) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _search,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: isDark ? AppColors.darkOnSurfaceVariant : theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '未找到结果',
              style: theme.textTheme.titleMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '尝试调整搜索关键词',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final entry = _searchResults.entries.elementAt(index);
        return _buildSourceSection(entry.key, entry.value, theme, isDark);
      },
    );
  }

  Widget _buildSourceSection(
    MusicScraperType source,
    List<MusicScraperItem> items,
    ThemeData theme,
    bool isDark,
  ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 来源标签
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(source.icon, size: 16, color: source.themeColor),
              const SizedBox(width: 8),
              Text(
                source.displayName,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: source.themeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: source.themeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${items.length} 个结果',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: source.themeColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 结果列表
        ...items.take(5).map((item) => _buildSearchResultItem(item, theme, isDark)),
        const SizedBox(height: 16),
      ],
    );

  Widget _buildSearchResultItem(MusicScraperItem item, ThemeData theme, bool isDark) => Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: item.source.themeColor.withValues(alpha: 0.1),
          ),
          child: item.coverUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: AdaptiveImage(
                    imageUrl: item.coverUrl!,
                    fit: BoxFit.cover,
                  ),
                )
              : Icon(Icons.music_note, color: item.source.themeColor),
        ),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            // 歌词指示器
            if (item.source.supportsLyrics) ...[
              Icon(
                Icons.lyrics_rounded,
                size: 14,
                color: isDark ? Colors.cyan[300] : Colors.cyan[700],
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                [
                  if (item.artist != null) item.artist,
                  if (item.album != null) item.album,
                  if (item.durationText.isNotEmpty) item.durationText,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        trailing: item.score != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.scoreText,
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            : const Icon(Icons.chevron_right),
        onTap: () => _selectItem(item),
      ),
    );

  Widget _buildDetailView(ThemeData theme, bool isDark) {
    if (_isLoadingDetail) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 返回搜索按钮
          TextButton.icon(
            onPressed: () {
              setState(() {
                _selectedDetail = null;
                _selectedCover = null;
                _selectedLyrics = null;
              });
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('返回搜索结果'),
          ),
          const SizedBox(height: 16),

          // 详情卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面和基本信息
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 封面
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: _selectedDetail?.source.themeColor.withValues(alpha: 0.1) ??
                              AppColors.fileAudio.withValues(alpha: 0.1),
                        ),
                        child: _selectedCover?.coverUrl != null || _selectedDetail?.coverUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: AdaptiveImage(
                                  imageUrl: _selectedCover?.coverUrl ?? _selectedDetail!.coverUrl!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Icon(
                                Icons.album,
                                size: 48,
                                color: _selectedDetail?.source.themeColor ?? AppColors.fileAudio,
                              ),
                      ),
                      const SizedBox(width: 16),
                      // 基本信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedDetail?.title ?? '未知标题',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_selectedDetail?.artist != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _selectedDetail!.artist!,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                            if (_selectedDetail?.album != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _selectedDetail!.album!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            // 来源标签
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _selectedDetail?.source.themeColor.withValues(alpha: 0.1) ??
                                    Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _selectedDetail?.source.displayName ?? '未知来源',
                                style: TextStyle(
                                  color: _selectedDetail?.source.themeColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // 其他元数据
                  if (_selectedDetail != null) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildMetadataRow('年份', _selectedDetail!.year?.toString()),
                    _buildMetadataRow('时长', _selectedDetail!.durationText),
                    _buildMetadataRow('音轨', _selectedDetail!.trackInfo),
                    _buildMetadataRow('流派', _selectedDetail!.genresText),
                    _buildMetadataRow('ISRC', _selectedDetail!.isrc),
                  ],

                  // 歌词预览
                  if (_selectedLyrics?.hasLyrics ?? false) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.lyrics, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '歌词预览',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          _selectedLyrics!.lrcContent ?? _selectedLyrics!.plainText ?? '',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 刮削选项
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '刮削选项',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('下载封面'),
                    subtitle: Text(
                      _selectedCover != null ? '保存到音乐文件所在目录' : '封面不可用',
                    ),
                    value: _downloadCover && _selectedCover != null,
                    onChanged: _selectedCover != null
                        ? (value) => setState(() => _downloadCover = value)
                        : null,
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('下载歌词'),
                    subtitle: Text(
                      _selectedLyrics?.hasLyrics ?? false
                          ? '保存为同名 .lrc 文件'
                          : '歌词不可用',
                    ),
                    value: _downloadLyrics && (_selectedLyrics?.hasLyrics ?? false),
                    onChanged: _selectedLyrics?.hasLyrics ?? false
                        ? (value) => setState(() => _downloadLyrics = value)
                        : null,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(height: 16),
                  // 写入到文件标签选项
                  if (_audioFormat != null)
                    SwitchListTile(
                      title: const Text('写入文件标签'),
                      subtitle: Text('${_audioFormat!.displayName} (${_audioFormat!.tagType})'),
                      value: _writeToFile,
                      onChanged: (value) => setState(() => _writeToFile = value),
                      contentPadding: EdgeInsets.zero,
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '该格式不支持写入标签，仅保存外部文件',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: context.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme, bool isDark) => SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.darkOutline : theme.dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isScraping
                    ? null
                    : () {
                        setState(() {
                          _selectedDetail = null;
                          _selectedCover = null;
                          _selectedLyrics = null;
                        });
                      },
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _isScraping ? null : _confirmAndScrape,
                icon: _isScraping
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download),
                label: const Text('确认刮削'),
              ),
            ),
          ],
        ),
      ),
    );
}
