import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/providers/video_detail_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';

/// 统一剧集选择器
///
/// 智能判断数据来源：
/// - 有 TMDB ID：从 TMDB 获取剧集详情（图片、标题、简介等）
/// - 无 TMDB ID：使用本地元数据，尝试显示本地缩略图
class UnifiedEpisodeSelector extends ConsumerStatefulWidget {
  const UnifiedEpisodeSelector({
    required this.localEpisodes,
    required this.onEpisodePlay,
    this.tmdbId,
    this.tmdbSeasons,
    this.initialSeason,
    this.episodeProgress = const {},
    super.key,
  });

  /// TMDB ID（如果有）
  final int? tmdbId;

  /// TMDB 季信息（如果有）
  final List<TmdbSeason>? tmdbSeasons;

  /// 本地剧集 `Map<seasonNumber, Map<episodeNumber, VideoMetadata>>`
  final Map<int, Map<int, VideoMetadata>> localEpisodes;

  /// 剧集播放回调
  final void Function(VideoMetadata localFile, {TmdbEpisode? tmdbEpisode}) onEpisodePlay;

  /// 初始选中的季
  final int? initialSeason;

  /// 剧集播放进度 `Map<filePath, progress 0.0-1.0>`
  final Map<String, double> episodeProgress;

  @override
  ConsumerState<UnifiedEpisodeSelector> createState() => _UnifiedEpisodeSelectorState();
}

class _UnifiedEpisodeSelectorState extends ConsumerState<UnifiedEpisodeSelector> {
  late int _selectedSeason;

  bool get _hasTmdb => widget.tmdbId != null && widget.tmdbSeasons != null;

  @override
  void initState() {
    super.initState();
    _initSelectedSeason();
  }

  void _initSelectedSeason() {
    if (widget.initialSeason != null) {
      _selectedSeason = widget.initialSeason!;
      return;
    }

    // 优先从本地剧集中选择第一个非特别篇的季
    final localSeasons = widget.localEpisodes.keys.toList()..sort();
    final nonSpecialSeason = localSeasons.where((s) => s > 0).firstOrNull;
    if (nonSpecialSeason != null) {
      _selectedSeason = nonSpecialSeason;
      return;
    }

    // 从 TMDB 季中选择
    if (_hasTmdb) {
      final tmdbSeason = widget.tmdbSeasons!
          .where((s) => s.seasonNumber > 0 && s.episodeCount > 0)
          .firstOrNull;
      if (tmdbSeason != null) {
        _selectedSeason = tmdbSeason.seasonNumber;
        return;
      }
    }

    _selectedSeason = localSeasons.firstOrNull ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 获取可用的季列表
    final availableSeasons = _getAvailableSeasons();
    if (availableSeasons.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题和季选择器
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '剧集',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
              const Spacer(),
              _buildSeasonDropdown(availableSeasons, isDark),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 剧集列表
        _buildEpisodeList(isDark),
      ],
    );
  }

  /// 获取可用的季列表（合并 TMDB 和本地数据）
  List<_SeasonInfo> _getAvailableSeasons() {
    final seasons = <int, _SeasonInfo>{};

    // 添加本地季
    for (final entry in widget.localEpisodes.entries) {
      seasons[entry.key] = _SeasonInfo(
        seasonNumber: entry.key,
        localEpisodeCount: entry.value.length,
        tmdbEpisodeCount: 0,
      );
    }

    // 合并 TMDB 季信息
    if (_hasTmdb) {
      for (final tmdbSeason in widget.tmdbSeasons!) {
        if (tmdbSeason.episodeCount > 0) {
          final existing = seasons[tmdbSeason.seasonNumber];
          if (existing != null) {
            seasons[tmdbSeason.seasonNumber] = existing.copyWith(
              tmdbEpisodeCount: tmdbSeason.episodeCount,
            );
          } else {
            seasons[tmdbSeason.seasonNumber] = _SeasonInfo(
              seasonNumber: tmdbSeason.seasonNumber,
              localEpisodeCount: 0,
              tmdbEpisodeCount: tmdbSeason.episodeCount,
            );
          }
        }
      }
    }

    final result = seasons.values.toList()
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    return result;
  }

  Widget _buildSeasonDropdown(List<_SeasonInfo> seasons, bool isDark) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? AppColors.darkOutline : Colors.grey[300]!,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _selectedSeason,
            isDense: true,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
            dropdownColor: isDark ? AppColors.darkSurface : Colors.white,
            items: seasons.map((season) {
              final label = season.seasonNumber == 0 ? '特别篇' : '第${season.seasonNumber}季';
              final countText = _hasTmdb
                  ? '(${season.localEpisodeCount}/${season.tmdbEpisodeCount}集)'
                  : '(${season.localEpisodeCount}集)';

              return DropdownMenuItem(
                value: season.seasonNumber,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      countText,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedSeason = value);
              }
            },
          ),
        ),
      );

  Widget _buildEpisodeList(bool isDark) {
    if (_hasTmdb) {
      return _buildTmdbEpisodeList(isDark);
    }
    return _buildLocalEpisodeList(isDark);
  }

  /// 使用 TMDB 数据构建剧集列表
  Widget _buildTmdbEpisodeList(bool isDark) {
    final seasonDetailAsync = ref.watch(
      seasonDetailProvider((tvId: widget.tmdbId!, seasonNumber: _selectedSeason)),
    );

    return seasonDetailAsync.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _buildLocalEpisodeList(isDark), // 失败时回退到本地数据
      data: (seasonDetail) {
        if (seasonDetail == null || seasonDetail.episodes.isEmpty) {
          return _buildLocalEpisodeList(isDark); // 无数据时回退到本地
        }

        final episodes = seasonDetail.episodes;
        final localSeasonEpisodes = widget.localEpisodes[_selectedSeason] ?? {};

        return SizedBox(
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final tmdbEpisode = episodes[index];
              final localFile = localSeasonEpisodes[tmdbEpisode.episodeNumber];
              final isAvailable = localFile != null;
              final progress = localFile != null
                  ? widget.episodeProgress[localFile.filePath]
                  : null;

              final onTapCallback = localFile != null
                  ? () => widget.onEpisodePlay(localFile, tmdbEpisode: tmdbEpisode)
                  : null;

              return Padding(
                padding: EdgeInsets.only(right: index < episodes.length - 1 ? 16 : 0),
                child: _UnifiedEpisodeCard(
                  episodeNumber: tmdbEpisode.episodeNumber,
                  title: tmdbEpisode.name,
                  imageUrl: tmdbEpisode.stillUrl,
                  runtime: tmdbEpisode.runtime,
                  airDate: tmdbEpisode.airDate,
                  rating: tmdbEpisode.voteAverage,
                  isAvailable: isAvailable,
                  watchProgress: progress,
                  onTap: onTapCallback,
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// 使用本地数据构建剧集列表
  Widget _buildLocalEpisodeList(bool isDark) {
    final seasonEpisodes = widget.localEpisodes[_selectedSeason] ?? {};
    if (seasonEpisodes.isEmpty) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Text(
            '暂无剧集',
            style: TextStyle(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final episodeNumbers = seasonEpisodes.keys.toList()..sort();

    return SizedBox(
      height: 240,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: episodeNumbers.length,
        itemBuilder: (context, index) {
          final episodeNum = episodeNumbers[index];
          final episode = seasonEpisodes[episodeNum]!;
          final progress = widget.episodeProgress[episode.filePath];

          // 尝试获取本地缩略图
          final thumbnailUrl = episode.posterUrl ?? episode.backdropUrl;

          return Padding(
            padding: EdgeInsets.only(right: index < episodeNumbers.length - 1 ? 16 : 0),
            child: _UnifiedEpisodeCard(
              episodeNumber: episodeNum,
              title: episode.episodeTitle ?? episode.fileName,
              imageUrl: thumbnailUrl,
              isAvailable: true,
              watchProgress: progress,
              onTap: () => widget.onEpisodePlay(episode),
            ),
          );
        },
      ),
    );
  }
}

/// 季信息
class _SeasonInfo {
  const _SeasonInfo({
    required this.seasonNumber,
    required this.localEpisodeCount,
    required this.tmdbEpisodeCount,
  });

  final int seasonNumber;
  final int localEpisodeCount;
  final int tmdbEpisodeCount;

  _SeasonInfo copyWith({
    int? seasonNumber,
    int? localEpisodeCount,
    int? tmdbEpisodeCount,
  }) =>
      _SeasonInfo(
        seasonNumber: seasonNumber ?? this.seasonNumber,
        localEpisodeCount: localEpisodeCount ?? this.localEpisodeCount,
        tmdbEpisodeCount: tmdbEpisodeCount ?? this.tmdbEpisodeCount,
      );
}

/// 统一的剧集卡片
class _UnifiedEpisodeCard extends StatefulWidget {
  const _UnifiedEpisodeCard({
    required this.episodeNumber,
    required this.title,
    this.imageUrl,
    this.runtime,
    this.airDate,
    this.rating,
    this.isAvailable = false,
    this.watchProgress,
    this.onTap,
  });

  final int episodeNumber;
  final String title;
  final String? imageUrl;
  final int? runtime;
  final String? airDate;
  final double? rating;
  final bool isAvailable;
  final double? watchProgress;
  final VoidCallback? onTap;
  static const double width = 200;

  @override
  State<_UnifiedEpisodeCard> createState() => _UnifiedEpisodeCardState();
}

class _UnifiedEpisodeCardState extends State<_UnifiedEpisodeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
    const aspectRatio = 16 / 9;
    const cardWidth = _UnifiedEpisodeCard.width;
    const imageHeight = cardWidth / aspectRatio;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.isAvailable ? widget.onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: widget.isAvailable ? 1.0 : 0.5,
          child: Container(
            width: cardWidth,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _isHovered ? 0.2 : 0.1),
                  blurRadius: _isHovered ? 12 : 6,
                  offset: Offset(0, _isHovered ? 4 : 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 缩略图区域
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: SizedBox(
                        width: cardWidth,
                        height: imageHeight,
                        child: hasImage
                            ? AdaptiveImage(
                                imageUrl: widget.imageUrl!,
                                placeholder: (_) => _buildPlaceholder(isDark),
                                errorWidget: (_, _) => _buildPlaceholder(isDark),
                              )
                            : _buildPlaceholder(isDark),
                      ),
                    ),
                    // 播放图标
                    if (widget.isAvailable && _isHovered)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            color: Colors.black.withValues(alpha: 0.4),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    // 时长标签
                    if (widget.runtime != null && widget.runtime! > 0)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formatRuntime(widget.runtime!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    // 不可用标签
                    if (!widget.isAvailable)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '无资源',
                            style: TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                        ),
                      ),
                  ],
                ),
                // 进度条
                if (widget.watchProgress != null && widget.watchProgress! > 0)
                  ClipRRect(
                    child: LinearProgressIndicator(
                      value: widget.watchProgress!.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: isDark ? AppColors.darkOutline : Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.watchProgress! >= 0.9 ? AppColors.success : AppColors.primary,
                      ),
                    ),
                  ),
                // 信息区域
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 集数和评分
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'E${widget.episodeNumber}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          if (widget.rating != null && widget.rating! > 0) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.star_rounded, size: 14, color: Colors.amber[600]),
                            const SizedBox(width: 2),
                            Text(
                              widget.rating!.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : AppColors.lightOnSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 标题
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                      ),
                      // 播出日期
                      if (widget.airDate != null && widget.airDate!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.airDate!,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) => Container(
        color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[200],
        child: Center(
          child: Icon(
            Icons.movie_rounded,
            size: 40,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
        ),
      );

  String _formatRuntime(int minutes) {
    if (minutes < 60) return '$minutes分钟';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '$hours小时$mins分钟' : '$hours小时';
  }
}
