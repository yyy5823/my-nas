import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';

/// 音乐分类
enum MusicBrowseCategory {
  all('全部歌曲', Icons.queue_music_rounded, Color(0xFF1DB954)),
  favorites('我喜欢', Icons.favorite_rounded, Color(0xFFE91E63)),
  recent('最近播放', Icons.history_rounded, Color(0xFF2196F3)),
  artists('艺术家', Icons.person_rounded, Color(0xFF9C27B0)),
  albums('专辑', Icons.album_rounded, Color(0xFFFF9800)),
  genres('流派', Icons.category_rounded, Color(0xFFE91E63)),
  years('年代', Icons.date_range_rounded, Color(0xFF00BCD4)),
  folders('文件夹', Icons.folder_rounded, Color(0xFF795548));

  const MusicBrowseCategory(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

/// 分类浏览网格
class BrowseCategoryGrid extends StatelessWidget {
  const BrowseCategoryGrid({
    required this.isDark,
    required this.onCategoryTap,
    this.isDesktop = false,
    this.counts = const {},
    super.key,
  });

  final bool isDark;
  final bool isDesktop;
  final Map<MusicBrowseCategory, int> counts;
  final void Function(MusicBrowseCategory category) onCategoryTap;

  @override
  Widget build(BuildContext context) {
    // 移动端显示的主要分类
    final mobileCategories = [
      MusicBrowseCategory.artists,
      MusicBrowseCategory.albums,
      MusicBrowseCategory.genres,
      MusicBrowseCategory.years,
      MusicBrowseCategory.folders,
    ];

    // 桌面端显示更多
    final desktopCategories = MusicBrowseCategory.values.where(
      (c) => c != MusicBrowseCategory.all &&
             c != MusicBrowseCategory.favorites &&
             c != MusicBrowseCategory.recent,
    ).toList();

    final categories = isDesktop ? desktopCategories : mobileCategories;
    final crossAxisCount = isDesktop ? 5 : 3;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: isDesktop ? 16 : 12,
        crossAxisSpacing: isDesktop ? 16 : 12,
        childAspectRatio: isDesktop ? 1.2 : 1.0,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return _CategoryCard(
          category: category,
          count: counts[category] ?? 0,
          isDark: isDark,
          isDesktop: isDesktop,
          onTap: () => onCategoryTap(category),
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.count,
    required this.isDark,
    required this.onTap,
    this.isDesktop = false,
  });

  final MusicBrowseCategory category;
  final int count;
  final bool isDark;
  final bool isDesktop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                category.color.withValues(alpha: isDark ? 0.3 : 0.15),
                category.color.withValues(alpha: isDark ? 0.15 : 0.05),
              ],
            ),
            border: Border.all(
              color: category.color.withValues(alpha: isDark ? 0.3 : 0.2),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              // 装饰图标
              Positioned(
                right: -10,
                bottom: -10,
                child: Icon(
                  category.icon,
                  size: isDesktop ? 60 : 50,
                  color: category.color.withValues(alpha: 0.15),
                ),
              ),
              // 内容
              Padding(
                padding: EdgeInsets.all(isDesktop ? 16 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: isDesktop ? 40 : 36,
                      height: isDesktop ? 40 : 36,
                      decoration: BoxDecoration(
                        color: category.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        category.icon,
                        color: category.color,
                        size: isDesktop ? 22 : 20,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      category.label,
                      style: TextStyle(
                        fontSize: isDesktop ? 14 : 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: isDesktop ? 12 : 11,
                          color: isDark ? Colors.white60 : Colors.black45,
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
    );
}

/// 快捷访问卡片网格（我喜欢、最近播放、全部、随机）
class QuickAccessGrid extends StatelessWidget {
  const QuickAccessGrid({
    required this.isDark,
    required this.favoritesCount,
    required this.recentCount,
    required this.totalCount,
    required this.onFavoritesTap,
    required this.onRecentTap,
    required this.onAllTap,
    required this.onShuffleTap,
    this.isDesktop = false,
    super.key,
  });

  final bool isDark;
  final bool isDesktop;
  final int favoritesCount;
  final int recentCount;
  final int totalCount;
  final VoidCallback onFavoritesTap;
  final VoidCallback onRecentTap;
  final VoidCallback onAllTap;
  final VoidCallback onShuffleTap;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _QuickCard(
        icon: Icons.favorite_rounded,
        label: '我喜欢',
        subtitle: '$favoritesCount 首',
        color: const Color(0xFFE91E63),
        isDark: isDark,
        isDesktop: isDesktop,
        onTap: onFavoritesTap,
      ),
      _QuickCard(
        icon: Icons.history_rounded,
        label: '最近播放',
        subtitle: '$recentCount 首',
        color: const Color(0xFF2196F3),
        isDark: isDark,
        isDesktop: isDesktop,
        onTap: onRecentTap,
      ),
      _QuickCard(
        icon: Icons.queue_music_rounded,
        label: '全部歌曲',
        subtitle: '$totalCount 首',
        color: AppColors.primary,
        isDark: isDark,
        isDesktop: isDesktop,
        onTap: onAllTap,
      ),
      _QuickCard(
        icon: Icons.shuffle_rounded,
        label: '随机播放',
        subtitle: '发现新歌',
        color: const Color(0xFF4CAF50),
        isDark: isDark,
        isDesktop: isDesktop,
        onTap: onShuffleTap,
      ),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: isDesktop ? 4 : 2,
        mainAxisSpacing: isDesktop ? 12 : 10,
        crossAxisSpacing: isDesktop ? 12 : 10,
        childAspectRatio: isDesktop ? 3.0 : 2.8,
        children: cards,
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.isDark,
    required this.onTap,
    this.isDesktop = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool isDark;
  final bool isDesktop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 14 : 12,
            vertical: isDesktop ? 12 : 10,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: isDesktop ? 44 : 40,
                height: isDesktop ? 44 : 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: isDesktop ? 22 : 20),
              ),
              SizedBox(width: isDesktop ? 12 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: isDesktop ? 14 : 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: isDesktop ? 12 : 11,
                        color: isDark ? Colors.white60 : Colors.black45,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.white30 : Colors.black26,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
}
