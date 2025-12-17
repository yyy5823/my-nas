import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/domain/entities/video_category_config.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';

/// 分类浏览卡片行
///
/// 显示一组分类卡片（如类型或地区），每个卡片使用随机视频海报作为背景，
/// 添加渐变遮罩以确保文字可读性。点击卡片可以查看该分类的所有内容。
class CategoryBrowseCardsRow extends StatefulWidget {
  const CategoryBrowseCardsRow({
    super.key,
    required this.category,
    required this.isDark,
    required this.onCategoryTap,
  });

  /// 分类类型（电影类型、电影地区、电视剧类型、电视剧地区）
  final VideoHomeCategory category;

  /// 是否暗色主题
  final bool isDark;

  /// 点击分类卡片回调
  final void Function(String filter) onCategoryTap;

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

  Future<void> _loadCategories() async {
    try {
      final db = VideoDatabaseService();
      await db.init();

      List<String> filters;
      MediaCategory? mediaCategory;

      switch (widget.category) {
        case VideoHomeCategory.byMovieGenre:
        case VideoHomeCategory.browseMovieGenres:
          filters = await db.getAvailableGenres(category: MediaCategory.movie);
          mediaCategory = MediaCategory.movie;
        case VideoHomeCategory.byMovieRegion:
        case VideoHomeCategory.browseMovieRegions:
          filters = await db.getAvailableCountries(category: MediaCategory.movie);
          mediaCategory = MediaCategory.movie;
        case VideoHomeCategory.byTvGenre:
        case VideoHomeCategory.browseTvGenres:
          filters = await db.getAvailableGenres(category: MediaCategory.tvShow);
          mediaCategory = MediaCategory.tvShow;
        case VideoHomeCategory.byTvRegion:
        case VideoHomeCategory.browseTvRegions:
          filters = await db.getAvailableCountries(category: MediaCategory.tvShow);
          mediaCategory = MediaCategory.tvShow;
        default:
          filters = [];
      }

      if (filters.isEmpty) {
        if (mounted) {
          setState(() {
            _categories = [];
            _loading = false;
          });
        }
        return;
      }

      // 为每个分类获取一个随机视频用于展示海报
      final categories = <_CategoryCardData>[];

      for (final filter in filters.take(15)) {
        // 最多显示15个
        VideoMetadata? sampleVideo;

        // 获取该分类下的一个随机视频
        if (widget.category.isGenreCategory) {
          final videos = mediaCategory == MediaCategory.movie
              ? await db.getMoviesByGenre(filter, limit: 5)
              : await db.getTvShowsByGenre(filter, limit: 5);
          if (videos.isNotEmpty) {
            videos.shuffle();
            sampleVideo = videos.first;
          }
        } else {
          final videos = mediaCategory == MediaCategory.movie
              ? await db.getMoviesByCountry(filter, limit: 5)
              : await db.getTvShowsByCountry(filter, limit: 5);
          if (videos.isNotEmpty) {
            videos.shuffle();
            sampleVideo = videos.first;
          }
        }

        categories.add(_CategoryCardData(
          name: filter,
          posterUrl: sampleVideo?.posterUrl,
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
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _categories!.length,
            itemBuilder: (context, index) {
              final category = _categories![index];
              return _CategoryCard(
                data: category,
                gradientColor: _getGradientColor(index),
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
      case VideoHomeCategory.byMovieGenre:
      case VideoHomeCategory.browseMovieGenres:
        return Icons.category_rounded;
      case VideoHomeCategory.byMovieRegion:
      case VideoHomeCategory.browseMovieRegions:
        return Icons.public_rounded;
      case VideoHomeCategory.byTvGenre:
      case VideoHomeCategory.browseTvGenres:
        return Icons.category_rounded;
      case VideoHomeCategory.byTvRegion:
      case VideoHomeCategory.browseTvRegions:
        return Icons.language_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Color _getIconColor() {
    switch (widget.category) {
      case VideoHomeCategory.byMovieGenre:
      case VideoHomeCategory.browseMovieGenres:
        return Colors.blue;
      case VideoHomeCategory.byMovieRegion:
      case VideoHomeCategory.browseMovieRegions:
        return Colors.green;
      case VideoHomeCategory.byTvGenre:
      case VideoHomeCategory.browseTvGenres:
        return Colors.orange;
      case VideoHomeCategory.byTvRegion:
      case VideoHomeCategory.browseTvRegions:
        return Colors.purple;
      default:
        return AppColors.primary;
    }
  }

  Color _getGradientColor(int index) {
    final colors = [
      Colors.blue,
      Colors.purple,
      Colors.pink,
      Colors.red,
      Colors.orange,
      Colors.amber,
      Colors.green,
      Colors.teal,
      Colors.cyan,
      Colors.indigo,
    ];
    return colors[index % colors.length];
  }
}

/// 分类卡片数据
class _CategoryCardData {
  _CategoryCardData({
    required this.name,
    this.posterUrl,
  });

  final String name;
  final String? posterUrl;
}

/// 分类卡片组件
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.data,
    required this.gradientColor,
    required this.isDark,
    required this.onTap,
  });

  final _CategoryCardData data;
  final Color gradientColor;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: gradientColor.withValues(alpha: 0.3),
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
                // 背景图片或渐变
                _buildBackground(),
                // 渐变遮罩
                _buildGradientOverlay(),
                // 分类名称
                _buildCategoryName(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackground() {
    if (data.posterUrl != null) {
      return Image.network(
        data.posterUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallbackBackground(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildFallbackBackground();
        },
      );
    }
    return _buildFallbackBackground();
  }

  Widget _buildFallbackBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            gradientColor.withValues(alpha: 0.8),
            gradientColor.withValues(alpha: 0.4),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            gradientColor.withValues(alpha: 0.1),
            gradientColor.withValues(alpha: 0.7),
            gradientColor.withValues(alpha: 0.9),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  Widget _buildCategoryName() {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Text(
        data.name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              blurRadius: 4,
              color: Colors.black54,
              offset: Offset(0, 2),
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
