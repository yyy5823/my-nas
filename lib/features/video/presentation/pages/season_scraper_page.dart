import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/data/services/scraper_manager_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/domain/entities/scraper_result.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';

/// 整季刮削页面
/// 批量刮削电视剧的一整季
class SeasonScraperPage extends ConsumerStatefulWidget {
  const SeasonScraperPage({
    super.key,
    required this.showDirectory,
    required this.sourceId,
    this.tmdbId,
    this.fileSystem,
    this.initialSeasonNumber,
  });

  /// 电视剧目录
  final String showDirectory;

  /// 来源 ID
  final String sourceId;

  /// TMDB ID（如果已有）
  final int? tmdbId;

  /// 文件系统
  final NasFileSystem? fileSystem;

  /// 初始选中的季号
  final int? initialSeasonNumber;

  @override
  ConsumerState<SeasonScraperPage> createState() => _SeasonScraperPageState();
}

class _SeasonScraperPageState extends ConsumerState<SeasonScraperPage> {
  final VideoMetadataService _metadataService = VideoMetadataService();
  final ScraperManagerService _scraperManager = ScraperManagerService();

  // 本地剧集
  Map<int, Map<int, VideoMetadata>> _localEpisodes = {};

  // 搜索状态
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  Map<ScraperType, List<ScraperMediaItem>> _searchResults = {};
  String? _errorMessage;

  // 选中的电视剧
  ScraperTvDetail? _selectedTvDetail;
  bool _isLoadingDetail = false;

  // 季选择
  int _selectedSeason = 1;
  ScraperSeasonDetail? _seasonDetail;
  bool _isLoadingSeasonDetail = false;

  // 刮削状态
  bool _isScraping = false;
  int _scrapeProgress = 0;
  int _scrapeTotal = 0;
  String? _currentScraping;

  // 刮削选项
  bool _updateMetadata = true;
  bool _downloadPoster = true;
  bool _downloadFanart = true;
  bool _generateNfo = true;

  @override
  void initState() {
    super.initState();
    _loadLocalEpisodes();
    if (widget.initialSeasonNumber != null) {
      _selectedSeason = widget.initialSeasonNumber!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalEpisodes() async {
    await _metadataService.init();
    final episodes = await _metadataService.getEpisodesByShowDirectory(widget.showDirectory);
    setState(() {
      _localEpisodes = episodes;
    });

    // 从第一个剧集提取搜索关键词
    if (episodes.isNotEmpty) {
      final firstSeason = episodes.values.first;
      if (firstSeason.isNotEmpty) {
        final firstEpisode = firstSeason.values.first;
        // 使用剧集的 title 或从文件名解析
        final info = VideoFileNameParser.parse(firstEpisode.fileName);
        _searchController.text = firstEpisode.title ?? info.cleanTitle;

        // 如果有 tmdbId 则直接加载详情
        if (widget.tmdbId != null) {
          AppError.fireAndForget(
            _loadTvDetailByTmdbId(widget.tmdbId!),
            action: 'SeasonScraperPage._loadTvDetailByTmdbId',
          );
        } else {
          // 自动搜索
          WidgetsBinding.instance.addPostFrameCallback((_) => _search());
        }
      }
    }
  }

  Future<void> _loadTvDetailByTmdbId(int tmdbId) async {
    setState(() {
      _isLoadingDetail = true;
      _errorMessage = null;
    });

    try {
      final detail = await _scraperManager.getTvDetail(
        externalId: tmdbId.toString(),
        source: ScraperType.tmdb,
      );

      if (detail != null) {
        setState(() {
          _selectedTvDetail = detail;
          _isLoadingDetail = false;
        });
        // 加载季详情
        await _loadSeasonDetail();
      } else {
        setState(() {
          _isLoadingDetail = false;
        });
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SeasonScraperPage._loadTvDetailByTmdbId');
      setState(() {
        _errorMessage = '获取详情失败: $e';
        _isLoadingDetail = false;
      });
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _searchResults.clear();
      _selectedTvDetail = null;
      _seasonDetail = null;
    });

    try {
      final result = await _scraperManager.searchTvShows(query);

      final grouped = <ScraperType, List<ScraperMediaItem>>{};
      for (final item in result.items) {
        grouped.putIfAbsent(item.source, () => []).add(item);
      }

      setState(() {
        _searchResults = grouped;
        _isSearching = false;
      });
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SeasonScraperPage._search');
      setState(() {
        _errorMessage = '搜索失败: $e';
        _isSearching = false;
      });
    }
  }

  Future<void> _selectItem(ScraperMediaItem item) async {
    setState(() {
      _isLoadingDetail = true;
      _errorMessage = null;
    });

    try {
      final detail = await _scraperManager.getTvDetail(
        externalId: item.externalId,
        source: item.source,
      );
      setState(() {
        _selectedTvDetail = detail;
        _isLoadingDetail = false;
      });
      // 加载季详情
      await _loadSeasonDetail();
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SeasonScraperPage._selectItem');
      setState(() {
        _errorMessage = '获取详情失败: $e';
        _isLoadingDetail = false;
      });
    }
  }

  Future<void> _loadSeasonDetail() async {
    if (_selectedTvDetail == null) return;

    setState(() {
      _isLoadingSeasonDetail = true;
    });

    try {
      final detail = await _scraperManager.getSeasonDetail(
        tvId: _selectedTvDetail!.externalId,
        seasonNumber: _selectedSeason,
        source: _selectedTvDetail!.source,
      );
      setState(() {
        _seasonDetail = detail;
        _isLoadingSeasonDetail = false;
      });
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SeasonScraperPage._loadSeasonDetail');
      setState(() {
        _isLoadingSeasonDetail = false;
      });
    }
  }

  Future<void> _startScraping() async {
    if (_selectedTvDetail == null || _seasonDetail == null) return;

    final localSeasonEpisodes = _localEpisodes[_selectedSeason] ?? {};
    if (localSeasonEpisodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该季没有本地剧集可刮削')),
      );
      return;
    }

    setState(() {
      _isScraping = true;
      _scrapeProgress = 0;
      _scrapeTotal = localSeasonEpisodes.length;
    });

    var successCount = 0;
    var failCount = 0;

    final options = ScrapeOptions(
      updateMetadata: _updateMetadata,
      downloadPoster: _downloadPoster,
      downloadFanart: _downloadFanart,
      generateNfo: _generateNfo,
    );

    for (final entry in localSeasonEpisodes.entries) {
      final episodeNumber = entry.key;
      final metadata = entry.value;

      // 获取对应的 TMDB 剧集
      final scraperEpisode = _seasonDetail!.getEpisode(episodeNumber);

      setState(() {
        _currentScraping = '${metadata.displayTitle} (S${_selectedSeason}E$episodeNumber)';
      });

      try {
        await _metadataService.scrapeAndSave(
          metadata: metadata,
          tvDetail: _selectedTvDetail,
          seasonNumber: _selectedSeason,
          episodeNumber: episodeNumber,
          episodeTitle: scraperEpisode?.name,
          fileSystem: widget.fileSystem,
          options: options,
        );
        successCount++;
      } on Exception catch (e, st) {
        AppError.handle(e, st, 'SeasonScraperPage._startScraping');
        failCount++;
      }

      setState(() {
        _scrapeProgress++;
      });
    }

    setState(() {
      _isScraping = false;
      _currentScraping = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('刮削完成：成功 $successCount 集${failCount > 0 ? '，失败 $failCount 集' : ''}'),
        ),
      );

      if (successCount > 0) {
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSelection = _selectedTvDetail != null;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        title: Text(hasSelection ? '选择季并刮削' : '选择电视剧'),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        actions: [
          if (hasSelection)
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedTvDetail = null;
                  _seasonDetail = null;
                });
              },
              child: const Text('重新搜索'),
            ),
        ],
      ),
      body: _isScraping
          ? _buildScrapingProgress(isDark)
          : hasSelection
              ? _buildSeasonView(isDark)
              : _buildSearchView(isDark),
      bottomNavigationBar: hasSelection && !_isScraping
          ? _buildBottomBar(isDark)
          : null,
    );
  }

  Widget _buildScrapingProgress(bool isDark) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                value: _scrapeTotal > 0 ? _scrapeProgress / _scrapeTotal : null,
              ),
              const SizedBox(height: 24),
              Text(
                '正在刮削...',
                style: context.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (_currentScraping != null)
                Text(
                  _currentScraping!,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 16),
              Text(
                '$_scrapeProgress / $_scrapeTotal',
                style: context.textTheme.titleMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildSearchView(bool isDark) => Column(
        children: [
          // 本地剧集统计
          _buildLocalEpisodesInfo(isDark),

          // 搜索栏
          _buildSearchBar(isDark),

          // 搜索结果
          Expanded(
            child: _buildSearchResults(isDark),
          ),
        ],
      );

  Widget _buildLocalEpisodesInfo(bool isDark) {
    final totalEpisodes = _localEpisodes.values
        .fold<int>(0, (sum, season) => sum + season.length);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_special_rounded,
            size: 40,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本地剧集',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '共 ${_localEpisodes.length} 季，$totalEpisodes 集',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索电视剧',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  isDense: true,
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _isSearching ? null : _search,
              child: _isSearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('搜索'),
            ),
          ],
        ),
      );

  Widget _buildSearchResults(bool isDark) {
    if (_isSearching || _isLoadingDetail) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: Colors.red[300])),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '搜索电视剧以开始刮削',
              style: context.textTheme.titleMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final entry = _searchResults.entries.elementAt(index);
        return _buildSourceGroup(entry.key, entry.value, isDark);
      },
    );
  }

  Widget _buildSourceGroup(
    ScraperType source,
    List<ScraperMediaItem> items,
    bool isDark,
  ) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getSourceColor(source).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    source.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getSourceColor(source),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${items.length} 个结果',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          ...items.map((item) => _buildSearchResultItem(item, isDark)),
          const SizedBox(height: 16),
        ],
      );

  Widget _buildSearchResultItem(ScraperMediaItem item, bool isDark) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: isDark ? AppColors.darkSurfaceElevated : null,
        child: InkWell(
          onTap: _isLoadingDetail ? null : () => _selectItem(item),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 50,
                    height: 75,
                    child: item.posterUrl != null
                        ? AdaptiveImage(
                            imageUrl: item.posterUrl!,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                            child: const Icon(Icons.tv),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.originalTitle != null &&
                          item.originalTitle != item.title) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.originalTitle!,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (item.year != null) ...[
                            Text('${item.year}', style: context.textTheme.bodySmall),
                            const SizedBox(width: 8),
                          ],
                          if (item.rating != null && item.rating! > 0) ...[
                            const Icon(Icons.star, size: 14, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              item.rating!.toStringAsFixed(1),
                              style: context.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );

  Widget _buildSeasonView(bool isDark) {
    final tvDetail = _selectedTvDetail!;
    final availableSeasons = _localEpisodes.keys.toList()..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 电视剧信息
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 100,
                  height: 150,
                  child: tvDetail.posterUrl != null
                      ? AdaptiveImage(
                          imageUrl: tvDetail.posterUrl!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          child: const Icon(Icons.tv, size: 48),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tvDetail.title,
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (tvDetail.originalTitle != null &&
                        tvDetail.originalTitle != tvDetail.title) ...[
                      const SizedBox(height: 4),
                      Text(
                        tvDetail.originalTitle!,
                        style: context.textTheme.titleMedium?.copyWith(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (tvDetail.year != null) ...[
                          Text('${tvDetail.year}', style: context.textTheme.bodyMedium),
                          const SizedBox(width: 12),
                        ],
                        if (tvDetail.rating != null && tvDetail.rating! > 0) ...[
                          const Icon(Icons.star, size: 18, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            tvDetail.rating!.toStringAsFixed(1),
                            style: context.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getSourceColor(tvDetail.source).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tvDetail.source.displayName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getSourceColor(tvDetail.source),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 季选择
          Text(
            '选择要刮削的季',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availableSeasons.map((season) {
              final episodeCount = _localEpisodes[season]?.length ?? 0;
              final isSelected = season == _selectedSeason;

              return ChoiceChip(
                label: Text('第 $season 季 ($episodeCount 集)'),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedSeason = season);
                    _loadSeasonDetail();
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // 剧集匹配预览
          _buildEpisodeMatchPreview(isDark),
          const SizedBox(height: 24),

          // 刮削选项
          _buildScrapeOptions(isDark),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildEpisodeMatchPreview(bool isDark) {
    final localSeasonEpisodes = _localEpisodes[_selectedSeason] ?? {};

    return Card(
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows, size: 20),
                const SizedBox(width: 8),
                Text(
                  '剧集匹配预览',
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoadingSeasonDetail)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (localSeasonEpisodes.isEmpty)
              const Text('该季没有本地剧集')
            else
              ...localSeasonEpisodes.entries.map((entry) {
                final episodeNumber = entry.key;
                final metadata = entry.value;
                final scraperEpisode = _seasonDetail?.getEpisode(episodeNumber);
                final hasMatch = scraperEpisode != null;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        hasMatch ? Icons.check_circle : Icons.help_outline,
                        size: 18,
                        color: hasMatch ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'E$episodeNumber: ${metadata.fileName}',
                              style: context.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (hasMatch)
                              Text(
                                '-> ${scraperEpisode.name ?? '第 $episodeNumber 集'}',
                                style: context.textTheme.bodySmall?.copyWith(
                                  color: Colors.green,
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
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildScrapeOptions(bool isDark) => Card(
        color: isDark ? AppColors.darkSurfaceElevated : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '刮削选项',
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('更新元数据'),
                subtitle: const Text('保存到本地数据库'),
                value: _updateMetadata,
                onChanged: (v) => setState(() => _updateMetadata = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('下载海报'),
                subtitle: const Text('保存到视频目录'),
                value: _downloadPoster,
                onChanged: (v) => setState(() => _downloadPoster = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('下载背景图'),
                subtitle: const Text('保存到视频目录'),
                value: _downloadFanart,
                onChanged: (v) => setState(() => _downloadFanart = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('生成 NFO 文件'),
                subtitle: const Text('Kodi/Jellyfin 兼容格式'),
                value: _generateNfo,
                onChanged: (v) => setState(() => _generateNfo = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      );

  Widget _buildBottomBar(bool isDark) {
    final localSeasonEpisodes = _localEpisodes[_selectedSeason] ?? {};

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _selectedTvDetail = null;
                    _seasonDetail = null;
                  });
                },
                child: const Text('返回搜索'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: localSeasonEpisodes.isEmpty ? null : _startScraping,
                child: Text('刮削 ${localSeasonEpisodes.length} 集'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getSourceColor(ScraperType source) => switch (source) {
        ScraperType.tmdb => Colors.blue,
        ScraperType.doubanApi => Colors.green,
        ScraperType.doubanWeb => Colors.orange,
      };
}
