import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/common/nt_common_widgets.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

class NtBrushTasksPage extends ConsumerWidget {
  const NtBrushTasksPage({super.key, required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(nastoolBrushTasksProvider(sourceId));

    return tasksAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(
        message: '加载失败: $e',
        isDark: isDark,
        onRetry: () => ref.invalidate(nastoolBrushTasksProvider(sourceId)),
      ),
      data: (tasks) {
        if (tasks.isEmpty) {
          return NtEmptyState(
            icon: Icons.auto_awesome_rounded,
            message: '暂无刷流任务\n在 NASTool 后台创建刷流任务后可在此管理',
            isDark: isDark,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolBrushTasksProvider(sourceId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: tasks.length,
            itemBuilder: (context, index) => _BrushTaskCard(
              task: tasks[index],
              isDark: isDark,
              onRun: () => _runTask(context, tasks[index], ref),
              onViewTorrents: () => _showTorrents(context, tasks[index], ref),
            ),
          ),
        );
      },
    );
  }

  void _runTask(BuildContext context, NtBrushTask task, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('立即执行'),
        content: Text('确定要立即执行刷流任务「${task.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(nastoolActionsProvider(sourceId)).runBrushTask(int.tryParse(task.id) ?? 0);
              context.showSuccessToast('任务已启动');
            },
            child: const Text('执行'),
          ),
        ],
      ),
    );
  }

  void _showTorrents(BuildContext context, NtBrushTask task, WidgetRef ref) {
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Text(
                      '${task.name} - 种子列表',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: NtColors.onSurface(isDark),
                          ),
                    ),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<NtBrushTorrent>>(
                  future: ref.read(nastoolActionsProvider(sourceId)).getBrushTaskTorrents(task.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const NtLoading();
                    }
                    if (snapshot.hasError) {
                      return NtError(message: '加载失败: ${snapshot.error}', isDark: isDark);
                    }
                    final torrents = snapshot.data ?? [];
                    if (torrents.isEmpty) {
                      return NtEmptyState(icon: Icons.folder_open_rounded, message: '暂无种子', isDark: isDark);
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      itemCount: torrents.length,
                      itemBuilder: (context, index) => _TorrentTile(torrent: torrents[index], isDark: isDark),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrushTaskCard extends StatelessWidget {
  const _BrushTaskCard({
    required this.task,
    required this.isDark,
    this.onRun,
    this.onViewTorrents,
  });

  final NtBrushTask task;
  final bool isDark;
  final VoidCallback? onRun;
  final VoidCallback? onViewTorrents;

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
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: task.state == 'ACTIVE'
                          ? [NtColors.success, NtColors.successLight]
                          : [NtColors.onSurfaceVariant(isDark), NtColors.onSurfaceVariant(isDark).withValues(alpha: 0.5)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    task.state == 'ACTIVE' ? Icons.play_circle_rounded : Icons.pause_circle_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: NtColors.onSurface(isDark),
                            ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          NtChip(
                            label: task.state == 'ACTIVE' ? '运行中' : '已暂停',
                            color: task.state == 'ACTIVE' ? NtColors.success : NtColors.onSurfaceVariant(isDark),
                          ),
                          if (task.site != null) ...[
                            const SizedBox(width: 8),
                            NtChip(label: '站点 ${task.site}', color: NtColors.info),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _TaskStatItem(label: '间隔', value: '${task.interval ?? 0}分钟', icon: Icons.timer_rounded),
                _TaskStatItem(label: '总大小', value: NtFormatter.bytes(task.totalSize), icon: Icons.storage_rounded),
                _TaskStatItem(label: '下载器', value: '${task.downloader ?? "-"}', icon: Icons.download_rounded),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                NtButton(
                  label: '查看种子',
                  icon: Icons.list_rounded,
                  isOutlined: true,
                  onPressed: onViewTorrents,
                ),
                const SizedBox(width: AppSpacing.sm),
                NtButton(
                  label: '立即执行',
                  icon: Icons.play_arrow_rounded,
                  onPressed: onRun,
                ),
              ],
            ),
          ],
        ),
      );
}

class _TaskStatItem extends StatelessWidget {
  const _TaskStatItem({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Row(
          children: [
            Icon(icon, size: 16, color: NtColors.primary),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 10)),
              ],
            ),
          ],
        ),
      );
}

class _TorrentTile extends StatelessWidget {
  const _TorrentTile({required this.torrent, required this.isDark});
  final NtBrushTorrent torrent;
  final bool isDark;

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              torrent.title ?? '',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: NtColors.onSurface(isDark),
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (torrent.size != null) NtChip(label: NtFormatter.bytes(torrent.size)),
                const SizedBox(width: 8),
                Icon(Icons.upload, size: 12, color: NtColors.success),
                Text(' ${NtFormatter.bytes(torrent.uploaded)}', style: const TextStyle(fontSize: 11)),
                const SizedBox(width: 8),
                Icon(Icons.download, size: 12, color: NtColors.info),
                Text(' ${NtFormatter.bytes(torrent.downloaded)}', style: const TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
      );
}
