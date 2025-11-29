import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/shared/providers/download_provider.dart';
import 'package:my_nas/shared/services/download_service.dart';

/// 显示下载管理器
void showDownloadManager(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const DownloadManagerSheet(),
  );
}

class DownloadManagerSheet extends ConsumerWidget {
  const DownloadManagerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(downloadTasksProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // 拖动指示器
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '下载管理',
                  style: context.textTheme.titleLarge,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    final service = ref.read(downloadServiceProvider);
                    for (final task in service.tasks) {
                      if (task.status == DownloadStatus.completed ||
                          task.status == DownloadStatus.cancelled ||
                          task.status == DownloadStatus.failed) {
                        service.removeTask(task.id);
                      }
                    }
                  },
                  child: const Text('清除已完成'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 任务列表
          Expanded(
            child: tasksAsync.when(
              data: (tasks) {
                if (tasks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.download_done,
                          size: 64,
                          color: context.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '暂无下载任务',
                          style: context.textTheme.bodyLarge?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: scrollController,
                  padding: AppSpacing.paddingSm,
                  itemCount: tasks.length,
                  itemBuilder: (context, index) =>
                      _DownloadTaskTile(task: tasks[index]),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('错误: $error')),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadTaskTile extends ConsumerWidget {
  const _DownloadTaskTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(downloadServiceProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文件名和状态图标
            Row(
              children: [
                _buildStatusIcon(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    task.fileName,
                    style: context.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildActionButton(context, service),
              ],
            ),
            const SizedBox(height: 8),
            // 进度条
            if (task.status == DownloadStatus.downloading ||
                task.status == DownloadStatus.paused)
              Column(
                children: [
                  LinearProgressIndicator(
                    value: task.progress,
                    backgroundColor: context.colorScheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        task.sizeText,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        task.progressText,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            // 错误信息
            if (task.status == DownloadStatus.failed && task.errorMessage != null)
              Text(
                task.errorMessage!,
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) => switch (task.status) {
        DownloadStatus.pending => Icon(
            Icons.schedule,
            color: context.colorScheme.onSurfaceVariant,
          ),
        DownloadStatus.downloading => SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: task.progress,
            ),
          ),
        DownloadStatus.paused => Icon(
            Icons.pause_circle,
            color: context.colorScheme.primary,
          ),
        DownloadStatus.completed => Icon(
            Icons.check_circle,
            color: context.colorScheme.primary,
          ),
        DownloadStatus.failed => Icon(
            Icons.error,
            color: context.colorScheme.error,
          ),
        DownloadStatus.cancelled => Icon(
            Icons.cancel,
            color: context.colorScheme.onSurfaceVariant,
          ),
      };

  Widget _buildActionButton(BuildContext context, DownloadService service) =>
      switch (task.status) {
        DownloadStatus.pending => IconButton(
            onPressed: () => service.startDownload(task.id),
            icon: const Icon(Icons.play_arrow),
            tooltip: '开始',
          ),
        DownloadStatus.downloading => IconButton(
            onPressed: () => service.pauseDownload(task.id),
            icon: const Icon(Icons.pause),
            tooltip: '暂停',
          ),
        DownloadStatus.paused => IconButton(
            onPressed: () => service.resumeDownload(task.id),
            icon: const Icon(Icons.play_arrow),
            tooltip: '继续',
          ),
        DownloadStatus.completed => IconButton(
            onPressed: () => service.openFile(task.id),
            icon: const Icon(Icons.folder_open),
            tooltip: '打开',
          ),
        DownloadStatus.failed => IconButton(
            onPressed: () => service.retryDownload(task.id),
            icon: const Icon(Icons.refresh),
            tooltip: '重试',
          ),
        DownloadStatus.cancelled => IconButton(
            onPressed: () => service.removeTask(task.id),
            icon: const Icon(Icons.delete),
            tooltip: '删除',
          ),
      };
}
