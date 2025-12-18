import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/domain/entities/video_category_config.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';

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

        // 收集有海报的视频
        final posterUrls = videos
            .where((v) => v.posterUrl != null && v.posterUrl!.isNotEmpty)
            .map((v) => v.posterUrl!)
            .toList();

        categories.add(_CategoryCardData(
          name: filter,
          posterUrls: posterUrls,
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
        // 卡片列表
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _categories!.length,
            itemBuilder: (context, index) {
              final category = _categories![index];
              return _InfuseStyleCard(
                data: category,
                isDark: widget.isDark,
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
    required this.posterUrls,
  });

  final String name;
  final List<String> posterUrls;
}

/// Infuse 风格的分类卡片
///
/// 特点：
/// - 多张海报拼贴作为背景
/// - 毛玻璃效果的中央标签
/// - 圆角设计
/// - 显示分类名称和数量
class _InfuseStyleCard extends StatelessWidget {
  const _InfuseStyleCard({
    required this.data,
    required this.isDark,
    required this.onTap,
  });

  final _CategoryCardData data;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 海报拼贴背景
                  _buildPosterGrid(),
                  // 暗色叠加层
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.1),
                          Colors.black.withValues(alpha: 0.5),
                        ],
                      ),
                    ),
                  ),
                  // 毛玻璃标签
                  Center(
                    child: _buildGlassLabel(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  /// 构建海报拼贴网格
  Widget _buildPosterGrid() {
    if (data.posterUrls.isEmpty) {
      return _buildPlaceholder();
    }

    // 根据海报数量决定布局
    final count = data.posterUrls.length;

    if (count == 1) {
      return _buildPosterImage(data.posterUrls[0]);
    }

    if (count == 2) {
      return Row(
        children: [
          Expanded(child: _buildPosterImage(data.posterUrls[0])),
          Expanded(child: _buildPosterImage(data.posterUrls[1])),
        ],
      );
    }

    if (count == 3) {
      return Row(
        children: [
          Expanded(child: _buildPosterImage(data.posterUrls[0])),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _buildPosterImage(data.posterUrls[1])),
                Expanded(child: _buildPosterImage(data.posterUrls[2])),
              ],
            ),
          ),
        ],
      );
    }

    // 4张及以上：2x2 网格
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildPosterImage(data.posterUrls[0])),
              Expanded(child: _buildPosterImage(data.posterUrls[1])),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildPosterImage(data.posterUrls[2 % count])),
              Expanded(child: _buildPosterImage(data.posterUrls[3 % count])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPosterImage(String url) => CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: isDark ? Colors.grey[800] : Colors.grey[300],
        ),
        errorWidget: (context, url, error) => Container(
          color: isDark ? Colors.grey[800] : Colors.grey[300],
          child: Icon(
            Icons.movie_outlined,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
        ),
      );

  Widget _buildPlaceholder() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [Colors.grey[800]!, Colors.grey[900]!]
                : [Colors.grey[300]!, Colors.grey[400]!],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.movie_outlined,
            size: 32,
            color: isDark ? Colors.grey[600] : Colors.grey[500],
          ),
        ),
      );

  /// 构建毛玻璃效果的标签
  Widget _buildGlassLabel() => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                width: 0.5,
              ),
            ),
            child: Text(
              data.name,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
}
