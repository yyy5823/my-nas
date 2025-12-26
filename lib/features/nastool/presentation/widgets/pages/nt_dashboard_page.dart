import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/common/nt_common_widgets.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';
import 'package:my_nas/service_adapters/nastool/nastool_adapter.dart';

class NtDashboardPage extends ConsumerWidget {
  const NtDashboardPage({super.key, required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(nastoolStatsProvider(sourceId));
    final subscribesAsync = ref.watch(nastoolSubscribesProvider(sourceId));
    final transfersAsync = ref.watch(nastoolTransferHistoryProvider(sourceId));
    final sitesAsync = ref.watch(nastoolSiteStatisticsProvider(sourceId));

    return statsAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(message: '加载失败: $e', isDark: isDark, onRetry: () => ref.invalidate(nastoolStatsProvider(sourceId))),
      data: (stats) => RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(nastoolStatsProvider(sourceId))
            ..invalidate(nastoolSubscribesProvider(sourceId))
            ..invalidate(nastoolTransferHistoryProvider(sourceId))
            ..invalidate(nastoolSiteStatisticsProvider(sourceId));
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _buildStatsSection(context, stats),
            const SizedBox(height: AppSpacing.xl),
            _buildSiteStatsSection(context, sitesAsync),
            const SizedBox(height: AppSpacing.xl),
            _buildSubscribesPreview(context, ref, subscribesAsync),
            const SizedBox(height: AppSpacing.xl),
            _buildTransferHistory(context, transfersAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context, NasToolOverviewStats? stats) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NtSectionHeader(title: '媒体库概览', isDark: isDark),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = ((constraints.maxWidth - AppSpacing.md * 3) / 4).clamp(140.0, 220.0);
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: NtStatCard(
                      icon: Icons.movie_rounded,
                      label: '电影',
                      value: NtFormatter.number(stats?.movieCount ?? 0),
                      gradient: [NtColors.primary, NtColors.primaryLight],
                      isDark: isDark,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: NtStatCard(
                      icon: Icons.live_tv_rounded,
                      label: '剧集',
                      value: NtFormatter.number(stats?.tvCount ?? 0),
                      gradient: [NtColors.success, NtColors.successLight],
                      isDark: isDark,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: NtStatCard(
                      icon: Icons.bookmark_rounded,
                      label: '订阅中',
                      value: NtFormatter.number(stats?.subscribeCount ?? 0),
                      gradient: [NtColors.warning, NtColors.warningLight],
                      isDark: isDark,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: NtStatCard(
                      icon: Icons.downloading_rounded,
                      label: '下载中',
                      value: NtFormatter.number(stats?.activeDownloads ?? 0),
                      gradient: [NtColors.error, NtColors.errorLight],
                      isDark: isDark,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );

  Widget _buildSiteStatsSection(BuildContext context, AsyncValue<List<NtSiteStatistics>> sitesAsync) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NtSectionHeader(title: '站点数据', isDark: isDark),
          const SizedBox(height: AppSpacing.md),
          sitesAsync.when(
            loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => NtCard(
              isDark: isDark,
              child: Text('加载失败: $e', style: TextStyle(color: NtColors.error)),
            ),
            data: (sites) {
              if (sites.isEmpty) {
                return NtCard(
                  isDark: isDark,
                  child: const Center(child: Text('暂无站点数据')),
                );
              }

              // 计算总上传、下载、做种数
              var totalUpload = 0;
              var totalDownload = 0;
              var totalSeeding = 0;
              var totalBonus = 0;

              for (final site in sites) {
                totalUpload += site.upload ?? 0;
                totalDownload += site.download ?? 0;
                totalSeeding += site.seedingCount ?? 0;
                totalBonus += site.bonus?.toInt() ?? 0;
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = ((constraints.maxWidth - AppSpacing.md * 3) / 4).clamp(140.0, 220.0);
                  return Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: NtStatCard(
                          icon: Icons.upload_rounded,
                          label: '总上传',
                          value: NtFormatter.bytes(totalUpload),
                          gradient: const [Color(0xFF059669), Color(0xFF10B981)],
                          isDark: isDark,
                          subtitle: '${sites.length}个站点',
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: NtStatCard(
                          icon: Icons.download_rounded,
                          label: '总下载',
                          value: NtFormatter.bytes(totalDownload),
                          gradient: const [Color(0xFF2563EB), Color(0xFF3B82F6)],
                          isDark: isDark,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: NtStatCard(
                          icon: Icons.cloud_upload_rounded,
                          label: '做种数',
                          value: NtFormatter.number(totalSeeding),
                          gradient: const [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
                          isDark: isDark,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: NtStatCard(
                          icon: Icons.stars_rounded,
                          label: '总积分',
                          value: NtFormatter.number(totalBonus),
                          gradient: const [Color(0xFFD97706), Color(0xFFF59E0B)],
                          isDark: isDark,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      );

  Widget _buildSubscribesPreview(BuildContext context, WidgetRef ref, AsyncValue<List<NtSubscribe>> subscribesAsync) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NtSectionHeader(title: '订阅中', isDark: isDark, action: () {}, actionLabel: '查看全部'),
          const SizedBox(height: AppSpacing.md),
          subscribesAsync.when(
            loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => NtCard(isDark: isDark, child: Text('加载失败: $e')),
            data: (subscribes) {
              if (subscribes.isEmpty) {
                return NtCard(
                  isDark: isDark,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: NtEmptyState(icon: Icons.bookmark_border_rounded, message: '暂无订阅', isDark: isDark),
                );
              }
              return SizedBox(
                height: 280,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: subscribes.length.clamp(0, 10),
                  itemBuilder: (context, index) => Padding(
                    padding: EdgeInsets.only(right: index < subscribes.length - 1 ? AppSpacing.md : 0),
                    child: SizedBox(
                      width: 150,
                      child: NtPosterCard(
                        isDark: isDark,
                        title: subscribes[index].name,
                        posterUrl: subscribes[index].posterPath,
                        subtitle: subscribes[index].isMovie
                            ? subscribes[index].year
                            : '${subscribes[index].currentEp}/${subscribes[index].totalEp ?? "?"}集',
                        progress: subscribes[index].isMovie ? null : subscribes[index].progress,
                        chips: [
                          NtChip(
                            label: subscribes[index].isMovie ? '电影' : (subscribes[index].seasonDisplay ?? '剧集'),
                            color: subscribes[index].isMovie ? NtColors.primary : NtColors.success,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      );

  Widget _buildTransferHistory(BuildContext context, AsyncValue<List<NtTransferHistory>> transfersAsync) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NtSectionHeader(title: '最近转移', isDark: isDark, action: () {}, actionLabel: '查看全部'),
          const SizedBox(height: AppSpacing.md),
          transfersAsync.when(
            loading: () => const SizedBox(height: 150, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => NtCard(isDark: isDark, child: Text('加载失败: $e')),
            data: (transfers) {
              if (transfers.isEmpty) {
                return NtCard(
                  isDark: isDark,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: NtEmptyState(icon: Icons.history_rounded, message: '暂无转移记录', isDark: isDark),
                );
              }
              return NtCard(
                isDark: isDark,
                padding: EdgeInsets.zero,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  itemCount: transfers.length.clamp(0, 5),
                  separatorBuilder: (_, _) => Divider(height: 1, color: NtColors.divider(isDark)),
                  itemBuilder: (context, index) {
                    final transfer = transfers[index];
                    return NtListTile(
                      isDark: isDark,
                      title: transfer.title,
                      subtitle: '${transfer.seasonEpisode ?? ""} ${transfer.category ?? ""}',
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: NtColors.surfaceVariant(isDark),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          transfer.type == '电影' ? Icons.movie_rounded : Icons.live_tv_rounded,
                          color: transfer.type == '电影' ? NtColors.primary : NtColors.success,
                          size: 22,
                        ),
                      ),
                      trailing: Text(
                        NtFormatter.date(transfer.date),
                        style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 12),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      );
}
