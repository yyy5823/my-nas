import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/common/nt_common_widgets.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';

class NtSubscribesPage extends ConsumerWidget {
  const NtSubscribesPage({super.key, required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscribesAsync = ref.watch(nastoolSubscribesProvider(sourceId));

    return subscribesAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(message: '加载失败: $e', isDark: isDark, onRetry: () => ref.invalidate(nastoolSubscribesProvider(sourceId))),
      data: (subscribes) {
        if (subscribes.isEmpty) {
          return NtEmptyState(
            icon: Icons.bookmark_border_rounded,
            message: '暂无订阅\n通过搜索添加想要追踪的影视作品',
            isDark: isDark,
          );
        }

        final movies = subscribes.where((s) => s.isMovie).toList();
        final tvShows = subscribes.where((s) => !s.isMovie).toList();

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolSubscribesProvider(sourceId)),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (movies.isNotEmpty) ...[
                NtSectionHeader(title: '电影', isDark: isDark, count: movies.length),
                const SizedBox(height: AppSpacing.md),
                _buildSubscribeGrid(context, movies, ref),
                const SizedBox(height: AppSpacing.xl),
              ],
              if (tvShows.isNotEmpty) ...[
                NtSectionHeader(title: '剧集', isDark: isDark, count: tvShows.length),
                const SizedBox(height: AppSpacing.md),
                _buildSubscribeGrid(context, tvShows, ref),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubscribeGrid(BuildContext context, List<NtSubscribe> subscribes, WidgetRef ref) => LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = (constraints.maxWidth / 170).floor().clamp(2, 8);
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.52,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
            ),
            itemCount: subscribes.length,
            itemBuilder: (context, index) {
              final sub = subscribes[index];
              return NtPosterCard(
                isDark: isDark,
                title: sub.name,
                posterUrl: sub.posterPath,
                subtitle: sub.isMovie ? sub.year : '${sub.currentEp}/${sub.totalEp ?? "?"}集',
                progress: sub.isMovie ? null : sub.progress,
                chips: [
                  NtChip(
                    label: sub.isMovie ? '电影' : (sub.seasonDisplay ?? '剧集'),
                    color: sub.isMovie ? NtColors.primary : NtColors.success,
                  ),
                  if (sub.isCompleted)
                    NtChip(label: '已完成', color: NtColors.success, icon: Icons.check_circle),
                ],
                onTap: () => _showSubscribeDetail(context, sub, ref),
              );
            },
          );
        },
      );

  void _showSubscribeDetail(BuildContext context, NtSubscribe sub, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) => DecoratedBox(
          decoration: BoxDecoration(
            color: NtColors.surface(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: NtColors.onSurfaceVariant(isDark),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: sub.posterPath != null
                        ? Image.network(sub.posterPath!, width: 120, height: 180, fit: BoxFit.cover)
                        : Container(
                            width: 120,
                            height: 180,
                            color: NtColors.surfaceVariant(isDark),
                            child: const Icon(Icons.movie, size: 40),
                          ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sub.name,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: NtColors.onSurface(isDark),
                              ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            NtChip(label: sub.isMovie ? '电影' : '剧集'),
                            if (sub.year != null) NtChip(label: sub.year!, color: NtColors.info),
                            if (sub.seasonDisplay != null) NtChip(label: sub.seasonDisplay!, color: NtColors.success),
                          ],
                        ),
                        if (!sub.isMovie && sub.totalEp != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            '进度: ${sub.currentEp}/${sub.totalEp}集',
                            style: TextStyle(color: NtColors.onSurfaceVariant(isDark)),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          NtProgressBar(progress: sub.progress, isDark: isDark, showLabel: true),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (sub.overview != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '简介',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: NtColors.onSurface(isDark),
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  sub.overview!,
                  style: TextStyle(color: NtColors.onSurfaceVariant(isDark), height: 1.5),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: NtButton(
                      label: '立即搜索',
                      icon: Icons.search_rounded,
                      onPressed: () {
                        Navigator.pop(context);
                        ref.read(nastoolActionsProvider(sourceId)).searchSubscribe(sub.id, sub.type);
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: NtButton(
                      label: '删除订阅',
                      icon: Icons.delete_rounded,
                      color: NtColors.error,
                      isOutlined: true,
                      onPressed: () {
                        Navigator.pop(context);
                        _confirmDelete(context, sub, ref);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, NtSubscribe sub, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除订阅「${sub.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(nastoolActionsProvider(sourceId)).deleteSubscribe(sub.id, sub.type);
            },
            child: Text('删除', style: TextStyle(color: NtColors.error)),
          ),
        ],
      ),
    );
  }
}
