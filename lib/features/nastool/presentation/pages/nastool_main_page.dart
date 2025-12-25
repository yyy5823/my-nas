import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

/// NASTool 主页面
class NasToolMainPage extends ConsumerStatefulWidget {
  const NasToolMainPage({required this.source, super.key});

  final SourceEntity source;

  @override
  ConsumerState<NasToolMainPage> createState() => _NasToolMainPageState();
}

class _NasToolMainPageState extends ConsumerState<NasToolMainPage> {
  int _selectedIndex = 0;

  static const _navItems = [
    _NavItem(icon: Icons.dashboard, label: '仪表盘'),
    _NavItem(icon: Icons.bookmark, label: '订阅'),
    _NavItem(icon: Icons.download, label: '下载'),
    _NavItem(icon: Icons.search, label: '搜索'),
    _NavItem(icon: Icons.movie, label: '媒体'),
    _NavItem(icon: Icons.web, label: '站点'),
    _NavItem(icon: Icons.settings, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connection = ref.watch(nastoolConnectionProvider(widget.source.id));
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: Row(
        children: [
          // 导航栏
          _buildNavRail(context, isDark, isWide),
          // 内容区
          Expanded(
            child: Column(
              children: [
                _buildHeader(context, isDark, connection),
                Expanded(child: _buildContent(context, isDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavRail(BuildContext context, bool isDark, bool isWide) => Container(
        width: isWide ? 200 : 72,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          border: Border(
            right: BorderSide(
              color: isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.1)
                  : AppColors.lightOutline.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: Column(
          children: [
            // Logo区域
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                mainAxisAlignment: isWide ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryLight],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.movie_filter, size: 20, color: Colors.white),
                  ),
                  if (isWide) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'NASTool',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            // 导航项目
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                itemCount: _navItems.length,
                itemBuilder: (context, index) {
                  final item = _navItems[index];
                  final isSelected = _selectedIndex == index;
                  return _buildNavItem(
                    context,
                    item,
                    isSelected,
                    isDark,
                    isWide,
                    () => setState(() => _selectedIndex = index),
                  );
                },
              ),
            ),
            // 返回按钮
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: _buildNavItem(
                context,
                const _NavItem(icon: Icons.arrow_back, label: '返回'),
                false,
                isDark,
                isWide,
                () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      );

  Widget _buildNavItem(
    BuildContext context,
    _NavItem item,
    bool isSelected,
    bool isDark,
    bool isWide,
    VoidCallback onTap,
  ) {
    final color = isSelected
        ? AppColors.primary
        : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      child: Material(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 48,
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? AppSpacing.md : AppSpacing.sm,
            ),
            child: Row(
              mainAxisAlignment: isWide ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(item.icon, color: color, size: 22),
                if (isWide) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    item.label,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, NasToolConnection? connection) => Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.1)
                  : AppColors.lightOutline.withValues(alpha: 0.1),
            ),
          ),
        ),
        child: Row(
          children: [
            // 页面标题
            Text(
              _navItems[_selectedIndex].label,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
            const Spacer(),
            // 连接状态
            if (connection != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      connection.adapter.username ?? '已连接',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            // 刷新按钮
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                // TODO: 刷新当前页面数据
              },
              tooltip: '刷新',
            ),
          ],
        ),
      );

  Widget _buildContent(BuildContext context, bool isDark) {
    switch (_selectedIndex) {
      case 0:
        return _DashboardContent(sourceId: widget.source.id, isDark: isDark);
      case 1:
        return _SubscribesContent(sourceId: widget.source.id, isDark: isDark);
      case 2:
        return _DownloadsContent(sourceId: widget.source.id, isDark: isDark);
      case 3:
        return _SearchContent(sourceId: widget.source.id, isDark: isDark);
      case 4:
        return _MediaContent(sourceId: widget.source.id, isDark: isDark);
      case 5:
        return _SitesContent(sourceId: widget.source.id, isDark: isDark);
      case 6:
        return _SettingsContent(sourceId: widget.source.id, isDark: isDark);
      default:
        return const Center(child: Text('404'));
    }
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

// ============================================================
// 页面内容组件
// ============================================================

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(nastoolStatsProvider(sourceId));

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (stats) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(nastoolStatsProvider(sourceId));
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // 统计卡片
            Text(
              '媒体库',
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                _StatCard(
                  icon: Icons.movie,
                  label: '电影',
                  value: stats?.movieCount.toString() ?? '0',
                  color: AppColors.primary,
                  isDark: isDark,
                ),
                _StatCard(
                  icon: Icons.tv,
                  label: '剧集',
                  value: stats?.tvCount.toString() ?? '0',
                  color: AppColors.success,
                  isDark: isDark,
                ),
                _StatCard(
                  icon: Icons.bookmark,
                  label: '订阅',
                  value: stats?.subscribeCount.toString() ?? '0',
                  color: Colors.purple,
                  isDark: isDark,
                ),
                _StatCard(
                  icon: Icons.downloading,
                  label: '下载中',
                  value: stats?.activeDownloads.toString() ?? '0',
                  color: AppColors.warning,
                  isDark: isDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
        width: 160,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.1)
                : color.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              value,
              style: context.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : color,
              ),
            ),
            Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );
}

// 订阅页面
class _SubscribesContent extends ConsumerWidget {
  const _SubscribesContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscribesAsync = ref.watch(nastoolSubscribesProvider(sourceId));

    return subscribesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (subscribes) {
        if (subscribes.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bookmark_border,
                  size: 64,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '暂无订阅',
                  style: context.textTheme.titleMedium?.copyWith(
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(nastoolSubscribesProvider(sourceId));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: subscribes.length,
            itemBuilder: (context, index) {
              final sub = subscribes[index];
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ListTile(
                  leading: Icon(
                    sub.isMovie ? Icons.movie : Icons.tv,
                    color: sub.isMovie ? AppColors.primary : AppColors.success,
                  ),
                  title: Text(sub.name),
                  subtitle: Text(
                    '${sub.isMovie ? "电影" : "剧集"} ${sub.year ?? ""}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                    onPressed: () {
                      // TODO: 删除订阅
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// 下载页面
class _DownloadsContent extends ConsumerWidget {
  const _DownloadsContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsAsync = ref.watch(nastoolDownloadsProvider(sourceId));

    return downloadsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (downloads) {
        if (downloads.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.download_done,
                  size: 64,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '暂无下载任务',
                  style: context.textTheme.titleMedium?.copyWith(
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(nastoolDownloadsProvider(sourceId));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: downloads.length,
            itemBuilder: (context, index) {
              final task = downloads[index];
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ListTile(
                  leading: CircularProgressIndicator(
                    value: task.progress,
                    strokeWidth: 3,
                    backgroundColor: AppColors.lightOutline.withValues(alpha: 0.2),
                  ),
                  title: Text(
                    task.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${(task.progress * 100).toStringAsFixed(1)}%'),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// 搜索页面
class _SearchContent extends StatefulWidget {
  const _SearchContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  State<_SearchContent> createState() => _SearchContentState();
}

class _SearchContentState extends State<_SearchContent> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索资源...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    // TODO: 执行搜索
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (value) {
                // TODO: 执行搜索
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: Center(
                child: Text(
                  '输入关键词搜索资源',
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: widget.isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

// 媒体页面
class _MediaContent extends StatelessWidget {
  const _MediaContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          '媒体库功能开发中...',
          style: context.textTheme.bodyMedium?.copyWith(
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
        ),
      );
}

// 站点页面
class _SitesContent extends ConsumerWidget {
  const _SitesContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitesAsync = ref.watch(nastoolSitesProvider(sourceId));

    return sitesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (sites) {
        if (sites.isEmpty) {
          return Center(
            child: Text(
              '暂无站点',
              style: context.textTheme.titleMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(nastoolSitesProvider(sourceId));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: sites.length,
            itemBuilder: (context, index) {
              final site = sites[index];
              return Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.web, color: AppColors.primary),
                  ),
                  title: Text(site.name),
                  subtitle: Text(site.signUrl ?? ''),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// 设置页面
class _SettingsContent extends StatelessWidget {
  const _SettingsContent({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新媒体库'),
              subtitle: const Text('同步媒体库数据'),
              onTap: () {
                // TODO: 刷新媒体库
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.update),
              title: const Text('检查更新'),
              subtitle: const Text('检查 NASTool 更新'),
              onTap: () {
                // TODO: 检查更新
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: const Text('退出登录'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ),
        ],
      );
}
