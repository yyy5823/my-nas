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

    // 移动端使用横向滚动列表
    if (!isDesktop) {
      return SizedBox(
        height: 100,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: categories.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final category = categories[index];
            return _CategoryCard(
              category: category,
              count: counts[category] ?? 0,
              isDark: isDark,
              onTap: () => onCategoryTap(category),
            );
          },
        ),
      );
    }

    // 桌面端保持网格布局
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.2,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return _CategoryCard(
          category: category,
          count: counts[category] ?? 0,
          isDark: isDark,
          isDesktop: true,
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
  Widget build(BuildContext context) {
    // 移动端：现代化的正方形卡片
    if (!isDesktop) {
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  category.color,
                  category.color.withValues(alpha: 0.7),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: category.color.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // 装饰性大图标
                Positioned(
                  right: -15,
                  top: -15,
                  child: Icon(
                    category.icon,
                    size: 70,
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                // 内容
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 主图标
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          category.icon,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const Spacer(),
                      // 标题
                      Text(
                        category.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      // 数量
                      if (count > 0)
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 桌面端：保持原有样式但优化
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
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
                  size: 60,
                  color: category.color.withValues(alpha: 0.15),
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: category.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        category.icon,
                        color: category.color,
                        size: 22,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      category.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 12,
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
}

/// 快捷访问卡片网格（我喜欢、最近播放、歌单、全部）
class QuickAccessGrid extends StatelessWidget {
  const QuickAccessGrid({
    required this.isDark,
    required this.favoritesCount,
    required this.recentCount,
    required this.totalCount,
    required this.onFavoritesTap,
    required this.onRecentTap,
    required this.onAllTap,
    @Deprecated('随机播放已集成到 HeroPlayerCard') this.onShuffleTap,
    this.playlistCount = 0,
    this.onPlaylistTap,
    this.isDesktop = false,
    super.key,
  });

  final bool isDark;
  final bool isDesktop;
  final int favoritesCount;
  final int recentCount;
  final int totalCount;
  final int playlistCount;
  final VoidCallback onFavoritesTap;
  final VoidCallback onRecentTap;
  final VoidCallback onAllTap;
  @Deprecated('随机播放已集成到 HeroPlayerCard')
  final VoidCallback? onShuffleTap;
  final VoidCallback? onPlaylistTap;

  @override
  Widget build(BuildContext context) {
    // 顺序：我喜欢 -> 全部歌曲 -> 最近播放（歌单已移至单独标签）
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
        icon: Icons.queue_music_rounded,
        label: '全部歌曲',
        subtitle: '$totalCount 首',
        color: AppColors.primary,
        isDark: isDark,
        isDesktop: isDesktop,
        onTap: onAllTap,
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
    ];

    // 移动端使用2列网格布局，类似Spotify风格
    if (!isDesktop) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards,
        ),
      );
    }

    // 桌面端保持网格布局
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 5,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.5,
      children: cards,
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
  Widget build(BuildContext context) {
    // 移动端：Spotify风格的紧凑卡片
    if (!isDesktop) {
      // 计算卡片宽度：(屏幕宽度 - 左右padding - 中间间距) / 2
      final screenWidth = MediaQuery.of(context).size.width;
      final cardWidth = (screenWidth - 32 - 10) / 2;

      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: cardWidth,
            height: 56,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                // 左侧彩色图标区域
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color,
                        color.withValues(alpha: 0.8),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(2, 0),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                // 右侧文字区域
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
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
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 桌面端：保持原有样式
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
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
                        fontSize: 12,
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
}
