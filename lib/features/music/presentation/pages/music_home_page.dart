import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/music/presentation/pages/playlist_detail_page.dart';
import 'package:my_nas/features/music/presentation/providers/playlist_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/browse_category_grid.dart';
import 'package:my_nas/features/music/presentation/widgets/hero_player_card.dart';
import 'package:my_nas/features/music/presentation/widgets/music_stats_card.dart';
import 'package:my_nas/features/music/presentation/widgets/recent_tracks_section.dart';

/// 音乐主页内容组件 - 现代化设计
/// 用于嵌入到 MusicListPage 中
class MusicHomeContent extends ConsumerWidget {
  const MusicHomeContent({
    required this.tracks,
    required this.recentTracks,
    required this.favoriteTracks,
    required this.onTrackTap,
    required this.onCategoryTap,
    this.onShuffleTap,
    this.totalCount = 0,
    this.artistCount = 0,
    this.albumCount = 0,
    this.genreCount = 0,
    this.yearCount = 0,
    this.folderCount = 0,
    this.playlistCount = 0,
    this.favoritesCount = 0,
    this.recentCount = 0,
    super.key,
  });

  final List<MusicFileWithSource> tracks;
  final List<MusicFileWithSource> recentTracks;
  final List<MusicFileWithSource> favoriteTracks;
  final int totalCount; // 数据库中的歌曲总数
  final int artistCount;
  final int albumCount;
  final int genreCount;
  final int yearCount;
  final int folderCount;
  final int playlistCount;
  final int favoritesCount; // 收藏总数（直接从 provider 获取）
  final int recentCount; // 最近播放总数（直接从 provider 获取）

  /// 点击播放曲目的回调
  final void Function(MusicFileWithSource track, List<MusicFileWithSource> allTracks) onTrackTap;

  /// 点击分类的回调
  final void Function(MusicCategory category) onCategoryTap;

  /// 随机播放回调
  final VoidCallback? onShuffleTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    final isTablet = screenWidth >= 600 && screenWidth < 900;

    if (isDesktop) {
      return _buildDesktopLayout(context, isDark);
    }

    return _buildMobileLayout(context, isDark, isTablet);
  }

  /// 移动端布局
  Widget _buildMobileLayout(BuildContext context, bool isDark, bool isTablet) => SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          // 1. 开始探索你的音乐 - Hero 播放卡片
          HeroPlayerCard(
            isDark: isDark,
            onShuffleTap: onShuffleTap,
          ),
          const SizedBox(height: 16),
          // 2. 快捷访问
          _buildSectionTitle('快捷访问', isDark),
          const SizedBox(height: 8),
          QuickAccessGrid(
            isDark: isDark,
            favoritesCount: favoritesCount > 0 ? favoritesCount : favoriteTracks.length,
            recentCount: recentCount > 0 ? recentCount : recentTracks.length,
            totalCount: totalCount > 0 ? totalCount : tracks.length,
            playlistCount: playlistCount,
            onFavoritesTap: () => onCategoryTap(MusicCategory.favorites),
            onRecentTap: () => onCategoryTap(MusicCategory.recent),
            onAllTap: () => onCategoryTap(MusicCategory.all),
            onPlaylistTap: () => onCategoryTap(MusicCategory.playlists),
          ),
          const SizedBox(height: 16),
          // 3. 为你推荐
          if (tracks.isNotEmpty) ...[
            PopularTracksSection(
              tracks: _getRandomTracks(5),
              isDark: isDark,
              title: '为你推荐',
              onTrackTap: (track) => onTrackTap(track, tracks),
              onMoreTap: () => onCategoryTap(MusicCategory.all),
            ),
            const SizedBox(height: 16),
          ],
          // 4. 歌单
          if (playlistCount > 0) ...[
            _PlaylistsSection(
              isDark: isDark,
              playlistCount: playlistCount,
              onMoreTap: () => onCategoryTap(MusicCategory.playlists),
            ),
            const SizedBox(height: 16),
          ],
          // 5. 最近播放
          if (recentTracks.isNotEmpty) ...[
            RecentTracksSection(
              tracks: recentTracks,
              isDark: isDark,
              onTrackTap: (track) => onTrackTap(track, tracks),
              onMoreTap: () => onCategoryTap(MusicCategory.recent),
            ),
            const SizedBox(height: 16),
          ],
          // 6. 浏览音乐库
          _buildSectionTitle('浏览音乐库', isDark),
          const SizedBox(height: 8),
          BrowseCategoryGrid(
            isDark: isDark,
            counts: _getCategoryCounts(),
            onCategoryTap: _onBrowseCategoryTap,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );

  /// 桌面端布局
  Widget _buildDesktopLayout(BuildContext context, bool isDark) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧边栏
        _buildDesktopSidebar(context, isDark),
        // 主内容区域
        Expanded(
          child: _buildDesktopMainContent(context, isDark),
        ),
      ],
    );

  /// 桌面端侧边栏
  Widget _buildDesktopSidebar(BuildContext context, bool isDark) => Container(
      width: 280,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        border: Border(
          right: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Column(
        children: [
          // Logo 区域
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '音乐库',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 统计卡片
          Padding(
            padding: const EdgeInsets.all(16),
            child: MusicStatsCard(
              totalTracks: tracks.length,
              totalArtists: artistCount,
              totalAlbums: albumCount,
              isDark: isDark,
              isDesktop: true,
            ),
          ),
          const Divider(height: 1),
          // 快捷导航
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSidebarItem(
                  icon: Icons.favorite_rounded,
                  label: '我喜欢',
                  count: favoritesCount > 0 ? favoritesCount : favoriteTracks.length,
                  color: const Color(0xFFE91E63),
                  isDark: isDark,
                  onTap: () => onCategoryTap(MusicCategory.favorites),
                ),
                _buildSidebarItem(
                  icon: Icons.history_rounded,
                  label: '最近播放',
                  count: recentCount > 0 ? recentCount : recentTracks.length,
                  color: const Color(0xFF2196F3),
                  isDark: isDark,
                  onTap: () => onCategoryTap(MusicCategory.recent),
                ),
                _buildSidebarItem(
                  icon: Icons.queue_music_rounded,
                  label: '全部歌曲',
                  count: totalCount > 0 ? totalCount : tracks.length,
                  color: AppColors.primary,
                  isDark: isDark,
                  onTap: () => onCategoryTap(MusicCategory.all),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '分类浏览',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white38 : Colors.black38,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                _buildSidebarItem(
                  icon: Icons.person_rounded,
                  label: '艺术家',
                  count: artistCount,
                  color: const Color(0xFF9C27B0),
                  isDark: isDark,
                  onTap: () => onCategoryTap(MusicCategory.artists),
                ),
                _buildSidebarItem(
                  icon: Icons.album_rounded,
                  label: '专辑',
                  count: albumCount,
                  color: const Color(0xFFFF9800),
                  isDark: isDark,
                  onTap: () => onCategoryTap(MusicCategory.albums),
                ),
                _buildSidebarItem(
                  icon: Icons.category_rounded,
                  label: '流派',
                  count: genreCount,
                  color: const Color(0xFFE91E63),
                  isDark: isDark,
                  onTap: () => onCategoryTap(MusicCategory.genres),
                ),
                _buildSidebarItem(
                  icon: Icons.folder_rounded,
                  label: '文件夹',
                  count: folderCount,
                  color: const Color(0xFF795548),
                  isDark: isDark,
                  onTap: () => onCategoryTap(MusicCategory.folders),
                ),
              ],
            ),
          ),
        ],
      ),
    );

  Widget _buildSidebarItem({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        ),
      ),
    );

  /// 桌面端主内容区域
  Widget _buildDesktopMainContent(BuildContext context, bool isDark) => CustomScrollView(
      slivers: [
        // 顶部 Hero 区域
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 欢迎语
                Text(
                  _getGreeting(),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 24),
                // Hero 播放卡片
                HeroPlayerCard(
                  isDark: isDark,
                  isDesktop: true,
                  onShuffleTap: onShuffleTap,
                ),
              ],
            ),
          ),
        ),
        // 快捷访问
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '快捷访问',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                QuickAccessGrid(
                  isDark: isDark,
                  isDesktop: true,
                  favoritesCount: favoritesCount > 0 ? favoritesCount : favoriteTracks.length,
                  recentCount: recentCount > 0 ? recentCount : recentTracks.length,
                  totalCount: totalCount > 0 ? totalCount : tracks.length,
                  playlistCount: playlistCount,
                  onFavoritesTap: () => onCategoryTap(MusicCategory.favorites),
                  onRecentTap: () => onCategoryTap(MusicCategory.recent),
                  onAllTap: () => onCategoryTap(MusicCategory.all),
                  onPlaylistTap: () => onCategoryTap(MusicCategory.playlists),
                ),
              ],
            ),
          ),
        ),
        // 最近播放
        if (recentTracks.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: RecentTracksSection(
                tracks: recentTracks,
                isDark: isDark,
                isDesktop: true,
                onTrackTap: (track) => onTrackTap(track, tracks),
                onMoreTap: () => onCategoryTap(MusicCategory.recent),
              ),
            ),
          ),
        // 推荐歌曲
        if (tracks.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: PopularTracksSection(
                tracks: _getRandomTracks(8),
                isDark: isDark,
                isDesktop: true,
                title: '为你推荐',
                maxItems: 8,
                onTrackTap: (track) => onTrackTap(track, tracks),
                onMoreTap: () => onCategoryTap(MusicCategory.all),
              ),
            ),
          ),
        // 底部间距
        const SliverToBoxAdapter(
          child: SizedBox(height: 100),
        ),
      ],
    );

  Widget _buildSectionTitle(String title, bool isDark) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
    );

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 12) return '早上好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  Map<MusicBrowseCategory, int> _getCategoryCounts() => {
      MusicBrowseCategory.all: tracks.length,
      MusicBrowseCategory.favorites: favoriteTracks.length,
      MusicBrowseCategory.recent: recentTracks.length,
      MusicBrowseCategory.artists: artistCount,
      MusicBrowseCategory.albums: albumCount,
      MusicBrowseCategory.genres: genreCount,
      MusicBrowseCategory.years: yearCount,
      MusicBrowseCategory.folders: folderCount,
    };

  List<MusicFileWithSource> _getRandomTracks(int count) {
    if (tracks.isEmpty) return [];
    final shuffled = List<MusicFileWithSource>.from(tracks)..shuffle();
    return shuffled.take(count).toList();
  }

  void _onBrowseCategoryTap(MusicBrowseCategory browseCategory) {
    // 将 MusicBrowseCategory 转换为 MusicCategory
    switch (browseCategory) {
      case MusicBrowseCategory.all:
        onCategoryTap(MusicCategory.all);
      case MusicBrowseCategory.favorites:
        onCategoryTap(MusicCategory.favorites);
      case MusicBrowseCategory.recent:
        onCategoryTap(MusicCategory.recent);
      case MusicBrowseCategory.artists:
        onCategoryTap(MusicCategory.artists);
      case MusicBrowseCategory.albums:
        onCategoryTap(MusicCategory.albums);
      case MusicBrowseCategory.genres:
        onCategoryTap(MusicCategory.genres);
      case MusicBrowseCategory.years:
        onCategoryTap(MusicCategory.years);
      case MusicBrowseCategory.folders:
        onCategoryTap(MusicCategory.folders);
    }
  }
}

/// 歌单区块 - 展示所有歌单
class _PlaylistsSection extends ConsumerWidget {
  const _PlaylistsSection({
    required this.isDark,
    required this.playlistCount,
    required this.onMoreTap,
  });

  final bool isDark;
  final int playlistCount;
  final VoidCallback onMoreTap;

  // 歌单渐变色列表
  static const List<List<Color>> _gradientColors = [
    [Color(0xFF9C27B0), Color(0xFF7B1FA2)], // 紫色
    [Color(0xFF2196F3), Color(0xFF1976D2)], // 蓝色
    [Color(0xFFE91E63), Color(0xFFC2185B)], // 粉色
    [Color(0xFF00BCD4), Color(0xFF0097A7)], // 青色
    [Color(0xFFFF9800), Color(0xFFF57C00)], // 橙色
    [Color(0xFF4CAF50), Color(0xFF388E3C)], // 绿色
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistState = ref.watch(playlistProvider);
    final playlists = playlistState.playlists;

    if (playlists.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '歌单',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              if (playlists.length > 5)
                GestureDetector(
                  onTap: onMoreTap,
                  child: Text(
                    '查看全部',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 歌单横向滚动列表
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlists.length > 10 ? 10 : playlists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final colors = _gradientColors[index % _gradientColors.length];
              return _PlaylistCard(
                playlist: playlist,
                isDark: isDark,
                gradientColors: colors,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 歌单卡片 - 现代化设计
class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.isDark,
    required this.gradientColors,
  });

  final PlaylistEntry playlist;
  final bool isDark;
  final List<Color> gradientColors;

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => PlaylistDetailPage.open(context, playlist),
        child: Container(
          width: 120,
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            boxShadow: [
              BoxShadow(
                color: gradientColors[0].withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // 装饰性大图标
              Positioned(
                right: -20,
                top: -20,
                child: Icon(
                  Icons.playlist_play_rounded,
                  size: 80,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 图标
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.playlist_play_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const Spacer(),
                    // 歌单名称
                    Text(
                      playlist.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // 歌曲数量
                    Text(
                      '${playlist.trackPaths.length} 首',
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
