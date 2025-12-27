import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/common/nt_common_widgets.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

class NtSitesPage extends ConsumerStatefulWidget {
  const NtSitesPage({super.key, required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  ConsumerState<NtSitesPage> createState() => _NtSitesPageState();
}

class _NtSitesPageState extends ConsumerState<NtSitesPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
      children: [
        ColoredBox(
          color: NtColors.surface(widget.isDark),
          child: TabBar(
            controller: _tabController,
            labelColor: NtColors.primary,
            unselectedLabelColor: NtColors.onSurfaceVariant(widget.isDark),
            indicatorColor: NtColors.primary,
            tabs: const [
              Tab(text: '站点列表', icon: Icon(Icons.list_rounded, size: 20)),
              Tab(text: '数据统计', icon: Icon(Icons.bar_chart_rounded, size: 20)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _SiteListTab(sourceId: widget.sourceId, isDark: widget.isDark),
              _SiteStatsTab(sourceId: widget.sourceId, isDark: widget.isDark),
            ],
          ),
        ),
      ],
    );
}

class _SiteListTab extends ConsumerWidget {
  const _SiteListTab({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitesAsync = ref.watch(nastoolSitesProvider(sourceId));

    return sitesAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(message: '加载失败: $e', isDark: isDark, onRetry: () => ref.invalidate(nastoolSitesProvider(sourceId))),
      data: (sites) {
        if (sites.isEmpty) {
          return NtEmptyState(icon: Icons.language_rounded, message: '暂无站点', isDark: isDark);
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolSitesProvider(sourceId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: sites.length,
            itemBuilder: (context, index) => _SiteCard(
              site: sites[index],
              isDark: isDark,
              onTest: () => _testSite(context, sites[index], ref),
            ),
          ),
        );
      },
    );
  }

  Future<void> _testSite(BuildContext context, NtSite site, WidgetRef ref) async {
    context.showInfoToast('正在测试站点 ${site.name}...');
    try {
      final success = await ref.read(nastoolActionsProvider(sourceId)).testSite(site.id);
      if (context.mounted) {
        context.showSuccessToast(success ? '站点 ${site.name} 测试成功' : '站点 ${site.name} 测试失败');
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorToast('测试失败: $e');
      }
    }
  }
}

class _SiteStatsTab extends ConsumerWidget {
  const _SiteStatsTab({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(nastoolSiteStatisticsProvider(sourceId));

    return statsAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(message: '加载失败: $e', isDark: isDark, onRetry: () => ref.invalidate(nastoolSiteStatisticsProvider(sourceId))),
      data: (stats) {
        if (stats.isEmpty) {
          return NtEmptyState(icon: Icons.bar_chart_rounded, message: '暂无统计数据', isDark: isDark);
        }

        // 排序：按上传量降序
        final sortedStats = List<NtSiteStatistics>.from(stats)..sort((a, b) => (b.upload ?? 0).compareTo(a.upload ?? 0));

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolSiteStatisticsProvider(sourceId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: sortedStats.length,
            itemBuilder: (context, index) => _SiteStatCard(stat: sortedStats[index], isDark: isDark, rank: index + 1),
          ),
        );
      },
    );
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({required this.site, required this.isDark, this.onTest});
  final NtSite site;
  final bool isDark;
  final VoidCallback? onTest;

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [NtColors.primary, NtColors.primaryLight]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.language_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    site.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: NtColors.onSurface(isDark),
                        ),
                  ),
                  if (site.signUrl != null)
                    Text(
                      site.signUrl!,
                      style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            NtIconButton(icon: Icons.speed_rounded, isDark: isDark, onPressed: onTest ?? () {}, tooltip: '测试连接'),
          ],
        ),
      );
}

class _SiteStatCard extends StatelessWidget {
  const _SiteStatCard({required this.stat, required this.isDark, required this.rank});
  final NtSiteStatistics stat;
  final bool isDark;
  final int rank;

  Color get _rankColor {
    if (rank == 1) return const Color(0xFFFFD700);
    if (rank == 2) return const Color(0xFFC0C0C0);
    if (rank == 3) return const Color(0xFFCD7F32);
    return NtColors.onSurfaceVariant(isDark);
  }

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _rankColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '#$rank',
                      style: TextStyle(color: _rankColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    stat.siteName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: NtColors.onSurface(isDark),
                        ),
                  ),
                ),
                if (stat.ratio != null)
                  NtChip(
                    label: '分享率 ${stat.ratio!.toStringAsFixed(2)}',
                    color: stat.ratio! >= 1 ? NtColors.success : NtColors.warning,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _StatItem(icon: Icons.upload_rounded, label: '上传', value: NtFormatter.bytes(stat.upload), color: NtColors.success),
                _StatItem(icon: Icons.download_rounded, label: '下载', value: NtFormatter.bytes(stat.download), color: NtColors.info),
                _StatItem(icon: Icons.cloud_upload_rounded, label: '做种', value: '${stat.seedingCount ?? 0}', color: NtColors.primary),
                _StatItem(icon: Icons.stars_rounded, label: '积分', value: NtFormatter.number(stat.bonus?.toInt() ?? 0), color: NtColors.warning),
              ],
            ),
          ],
        ),
      );
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
            Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 10)),
          ],
        ),
      );
}
