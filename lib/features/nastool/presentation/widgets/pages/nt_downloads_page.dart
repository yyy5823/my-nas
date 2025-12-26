import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/common/nt_common_widgets.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';

class NtDownloadsPage extends ConsumerStatefulWidget {
  const NtDownloadsPage({super.key, required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  ConsumerState<NtDownloadsPage> createState() => _NtDownloadsPageState();
}

class _NtDownloadsPageState extends ConsumerState<NtDownloadsPage> with SingleTickerProviderStateMixin {
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
              Tab(text: '下载中', icon: Icon(Icons.downloading_rounded, size: 20)),
              Tab(text: '下载历史', icon: Icon(Icons.history_rounded, size: 20)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _DownloadingTab(sourceId: widget.sourceId, isDark: widget.isDark),
              _DownloadHistoryTab(sourceId: widget.sourceId, isDark: widget.isDark),
            ],
          ),
        ),
      ],
    );
}

class _DownloadingTab extends ConsumerWidget {
  const _DownloadingTab({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsAsync = ref.watch(nastoolDownloadsProvider(sourceId));

    return downloadsAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(message: '加载失败: $e', isDark: isDark, onRetry: () => ref.invalidate(nastoolDownloadsProvider(sourceId))),
      data: (downloads) {
        if (downloads.isEmpty) {
          return NtEmptyState(icon: Icons.download_done_rounded, message: '暂无下载任务', isDark: isDark);
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolDownloadsProvider(sourceId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: downloads.length,
            itemBuilder: (context, index) => _DownloadTaskCard(
              task: downloads[index],
              isDark: isDark,
              onStart: () => ref.read(nastoolActionsProvider(sourceId)).startDownload(downloads[index].id),
              onStop: () => ref.read(nastoolActionsProvider(sourceId)).stopDownload(downloads[index].id),
              onRemove: () => _confirmRemove(context, downloads[index], ref),
            ),
          ),
        );
      },
    );
  }

  void _confirmRemove(BuildContext context, NtDownloadTask task, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除下载任务「${task.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(nastoolActionsProvider(sourceId)).removeDownload(task.id);
            },
            child: Text('删除', style: TextStyle(color: NtColors.error)),
          ),
        ],
      ),
    );
  }
}

class _DownloadHistoryTab extends ConsumerWidget {
  const _DownloadHistoryTab({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(nastoolDownloadHistoryProvider(sourceId));

    return historyAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(message: '加载失败: $e', isDark: isDark, onRetry: () => ref.invalidate(nastoolDownloadHistoryProvider(sourceId))),
      data: (history) {
        if (history.isEmpty) {
          return NtEmptyState(icon: Icons.history_rounded, message: '暂无下载历史', isDark: isDark);
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolDownloadHistoryProvider(sourceId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final item = history[index];
              return NtCard(
                isDark: isDark,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: NtColors.onSurface(isDark),
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        if (item.site != null) NtChip(label: item.site!, color: NtColors.info),
                        const Spacer(),
                        Text(
                          NtFormatter.date(item.date),
                          style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _DownloadTaskCard extends StatelessWidget {
  const _DownloadTaskCard({
    required this.task,
    required this.isDark,
    this.onStart,
    this.onStop,
    this.onRemove,
  });

  final NtDownloadTask task;
  final bool isDark;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final VoidCallback? onRemove;

  Color get _statusColor {
    if (task.isCompleted) return NtColors.success;
    if (task.isDownloading) return NtColors.primary;
    return NtColors.warning;
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
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    task.isCompleted ? Icons.check_circle_rounded : Icons.downloading_rounded,
                    color: _statusColor,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: NtColors.onSurface(isDark),
                            ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (task.downloader != null)
                            Text(
                              task.downloader!,
                              style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 12),
                            ),
                          if (task.size != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              NtFormatter.bytes(task.size),
                              style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 12),
                            ),
                          ],
                          if (task.speed != null && task.speed! > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${NtFormatter.bytes(task.speed)}/s',
                              style: TextStyle(color: NtColors.success, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(task.progress * 100).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _statusColor,
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            NtProgressBar(progress: task.progress, isDark: isDark, color: _statusColor),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!task.isCompleted) ...[
                  if (task.isDownloading)
                    NtIconButton(icon: Icons.pause_rounded, isDark: isDark, onPressed: onStop ?? () {}, tooltip: '暂停')
                  else
                    NtIconButton(icon: Icons.play_arrow_rounded, isDark: isDark, onPressed: onStart ?? () {}, tooltip: '开始'),
                  const SizedBox(width: AppSpacing.sm),
                ],
                NtIconButton(
                  icon: Icons.delete_rounded,
                  isDark: isDark,
                  onPressed: onRemove ?? () {},
                  tooltip: '删除',
                  color: NtColors.error,
                ),
              ],
            ),
          ],
        ),
      );
}
