import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/services/nas_file_system_registry.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/domain/entities/video_category_config.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 分类浏览卡片行（Infuse 风格）
///
/// 显示一组分类卡片，每个卡片使用该分类下多张视频海报拼贴作为背景，
/// 中央有毛玻璃效果的标签显示分类名称。
class CategoryBrowseCardsRow extends StatefulWidget {
  const CategoryBrowseCardsRow({
    super.key,
    required this.category,
    required this.isDark,
    required this.onCategoryTap,
    required this.selectedFilters,
  });

  /// 分类类型（电影-类型、电影-地区、剧集-类型、剧集-地区）
  final VideoHomeCategory category;

  /// 是否暗色主题
  final bool isDark;

  /// 点击分类卡片回调
  final void Function(String filter) onCategoryTap;

  /// 用户选择的筛选条件（只显示这些卡片）
  final List<String> selectedFilters;

  @override
  State<CategoryBrowseCardsRow> createState() => _CategoryBrowseCardsRowState();
}

class _CategoryBrowseCardsRowState extends State<CategoryBrowseCardsRow> {
  List<_CategoryCardData>? _categories;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void didUpdateWidget(covariant CategoryBrowseCardsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFilters.length != widget.selectedFilters.length ||
        !_listEquals(oldWidget.selectedFilters, widget.selectedFilters)) {
      _loadCategories();
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _loadCategories() async {
    if (widget.selectedFilters.isEmpty) {
      if (mounted) {
        setState(() {
          _categories = [];
          _loading = false;
        });
      }
      return;
    }

    setState(() => _loading = true);

    try {
      final db = VideoDatabaseService();
      await db.init();

      MediaCategory? mediaCategory;

      switch (widget.category) {
        case VideoHomeCategory.browseMovieGenres:
        case VideoHomeCategory.browseMovieRegions:
          mediaCategory = MediaCategory.movie;
        case VideoHomeCategory.browseTvGenres:
        case VideoHomeCategory.browseTvRegions:
          mediaCategory = MediaCategory.tvShow;
        default:
          mediaCategory = MediaCategory.movie;
      }

      // 为每个用户选择的筛选条件获取多个视频用于海报拼贴
      final categories = <_CategoryCardData>[];

      for (final filter in widget.selectedFilters) {
        List<VideoMetadata> videos;

        // 获取该分类下的多个视频
        if (widget.category.isGenreCategory) {
          videos = mediaCategory == MediaCategory.movie
              ? await db.getMoviesByGenre(filter, limit: 6)
              : await db.getTvShowsByGenre(filter, limit: 6);
        } else {
          videos = mediaCategory == MediaCategory.movie
              ? await db.getMoviesByCountry(filter, limit: 6)
              : await db.getTvShowsByCountry(filter, limit: 6);
        }

        // 收集有海报的视频及其 sourceId（优先使用 displayPosterUrl 以支持本地 NFO 海报）
        final posterInfos = videos
            .where((v) => v.displayPosterUrl != null && v.displayPosterUrl!.isNotEmpty)
            .map((v) => (url: v.displayPosterUrl!, sourceId: v.sourceId))
            .toList();

        categories.add(_CategoryCardData(
          name: filter,
          posterInfos: posterInfos,
        ));
      }

      if (mounted) {
        setState(() {
          _categories = categories;
          _loading = false;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _categories = [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink();
    }

    if (_categories == null || _categories!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _getIconColor().withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_getIcon(), size: 18, color: _getIconColor()),
              ),
              const SizedBox(width: 10),
              Text(
                widget.category.displayName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        // 卡片列表（竖向海报风格，和普通电影/剧集卡片大小一致）
        SizedBox(
          height: 235, // 130 * 1.5 + 标题区域约 40
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _categories!.length,
            itemBuilder: (context, index) {
              final category = _categories![index];
              return _CategoryPosterCard(
                data: category,
                isDark: widget.isDark,
                colorIndex: index,
                onTap: () => widget.onCategoryTap(category.name),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getIcon() {
    switch (widget.category) {
      case VideoHomeCategory.browseMovieGenres:
        return Icons.category_rounded;
      case VideoHomeCategory.browseMovieRegions:
        return Icons.public_rounded;
      case VideoHomeCategory.browseTvGenres:
        return Icons.category_rounded;
      case VideoHomeCategory.browseTvRegions:
        return Icons.language_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Color _getIconColor() {
    switch (widget.category) {
      case VideoHomeCategory.browseMovieGenres:
        return Colors.blue;
      case VideoHomeCategory.browseMovieRegions:
        return Colors.green;
      case VideoHomeCategory.browseTvGenres:
        return Colors.orange;
      case VideoHomeCategory.browseTvRegions:
        return Colors.purple;
      default:
        return AppColors.primary;
    }
  }
}

/// 分类卡片数据
class _CategoryCardData {
  _CategoryCardData({
    required this.name,
    required this.posterInfos,
  });

  final String name;
  /// 海报信息列表：(url, sourceId)
  final List<({String url, String sourceId})> posterInfos;
}

/// 分类海报卡片（竖向，和普通电影/剧集卡片大小一致）
///
/// 特点：
/// - 2:3 海报比例，和普通电影/剧集卡片一致
/// - 单张海报作为背景
/// - 底部渐变叠加分类名称
class _CategoryPosterCard extends StatefulWidget {
  const _CategoryPosterCard({
    required this.data,
    required this.isDark,
    required this.colorIndex,
    required this.onTap,
  });

  final _CategoryCardData data;
  final bool isDark;
  final int colorIndex;
  final VoidCallback onTap;

  @override
  State<_CategoryPosterCard> createState() => _CategoryPosterCardState();
}

class _CategoryPosterCardState extends State<_CategoryPosterCard> {
  bool _isHovered = false;

  /// 渐变色配置（用于无海报时的占位符）
  static const List<List<Color>> _gradientColors = [
    [Color(0xFFE91E63), Color(0xFF9C27B0)],
    [Color(0xFF1565C0), Color(0xFF0D47A1)],
    [Color(0xFFFF5722), Color(0xFFE64A19)],
    [Color(0xFF512DA8), Color(0xFF311B92)],
    [Color(0xFF00ACC1), Color(0xFF006064)],
    [Color(0xFF43A047), Color(0xFF1B5E20)],
    [Color(0xFFFF8F00), Color(0xFFE65100)],
    [Color(0xFF3949AB), Color(0xFF1A237E)],
    [Color(0xFFC62828), Color(0xFF8E0000)],
    [Color(0xFF546E7A), Color(0xFF37474F)],
  ];

  List<Color> get _gradient =>
      _gradientColors[widget.colorIndex % _gradientColors.length];

  @override
  Widget build(BuildContext context) {
    const cardWidth = 130.0;
    const posterHeight = cardWidth * 1.5; // 2:3 比例

    return Container(
      width: cardWidth,
      margin: const EdgeInsets.only(right: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isHovered ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 海报区域
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: cardWidth,
                  height: posterHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: _gradient[0].withValues(alpha: _isHovered ? 0.5 : 0.3),
                        blurRadius: _isHovered ? 16 : 8,
                        offset: Offset(0, _isHovered ? 8 : 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 背景海报
                        _buildBackground(),
                        // 底部渐变遮罩
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: posterHeight * 0.5,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.9),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // 分类名称（底部居中）
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 12,
                          child: Text(
                            widget.data.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  color: Colors.black54,
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 悬停边框
                        if (_isHovered)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // 标题区域（分类名称已在海报上显示，这里显示数量提示）
                const SizedBox(height: 8),
                Text(
                  widget.data.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackground() {
    if (widget.data.posterInfos.isEmpty) {
      return _buildPlaceholder();
    }

    final posterInfo = widget.data.posterInfos[0];
    return _buildSmartImage(posterInfo.url, posterInfo.sourceId);
  }

  Widget _buildSmartImage(String imageUrl, String sourceId) {
    final isNasPath = imageUrl.startsWith('/') &&
        !imageUrl.startsWith('//') &&
        !imageUrl.contains('://');

    if (isNasPath) {
      final fileSystem = NasFileSystemRegistry.instance.get(sourceId);
      return StreamImage(
        path: imageUrl,
        fileSystem: fileSystem,
        fit: BoxFit.cover,
        placeholder: _buildPlaceholder(),
        errorWidget: _buildPlaceholder(),
      );
    }

    if (imageUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildPlaceholder(),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _gradient,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.category_rounded,
            size: 40,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      );
}
