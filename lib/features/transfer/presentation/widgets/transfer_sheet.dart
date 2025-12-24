import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';

/// 传输类型
enum TransferSheetType {
  download,
  upload,
  cache,
}

/// 显示下载任务列表
void showTransferDownloads(BuildContext context) {
  _showTransferSheet(context, TransferSheetType.download);
}

/// 显示上传任务列表
void showTransferUploads(BuildContext context) {
  _showTransferSheet(context, TransferSheetType.upload);
}

/// 显示缓存列表
void showTransferCache(BuildContext context) {
  _showTransferSheet(context, TransferSheetType.cache);
}

void _showTransferSheet(BuildContext context, TransferSheetType type) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TransferSheet(type: type),
  );
}

class _TransferSheet extends ConsumerWidget {
  const _TransferSheet({required this.type});

  final TransferSheetType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tasks = switch (type) {
      TransferSheetType.download => ref.watch(downloadTasksProvider),
      TransferSheetType.upload => ref.watch(uploadTasksProvider),
      TransferSheetType.cache => ref.watch(cacheTasksProvider),
    };

    final (icon, title, emptyIcon, emptyText) = switch (type) {
      TransferSheetType.download => (
          Icons.download_rounded,
          '下载任务',
          Icons.download_done_rounded,
          '暂无下载任务',
        ),
      TransferSheetType.upload => (
          Icons.upload_rounded,
          '上传任务',
          Icons.cloud_upload_outlined,
          '暂无上传任务',
        ),
      TransferSheetType.cache => (
          Icons.storage_rounded,
          '缓存管理',
          Icons.storage_outlined,
          '暂无缓存内容',
        ),
    };

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface.withValues(alpha: 0.95)
                  : AppColors.lightSurface.withValues(alpha: 0.98),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.glassStroke : AppColors.lightOutline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Column(
              children: [
                // 拖动指示器
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                        : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 标题栏
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        title,
                        style: context.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkOnSurface : null,
                        ),
                      ),
                      const Spacer(),
                      _buildClearButton(context, ref, isDark, tasks),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Divider(
                    height: 1,
                    color: isDark
                        ? AppColors.darkOutline.withValues(alpha: 0.2)
                        : AppColors.lightOutline.withValues(alpha: 0.3),
                  ),
                ),
                // 缓存统计（仅缓存类型显示）
                if (type == TransferSheetType.cache) _CacheStats(isDark: isDark),
                // 任务列表
                Expanded(
                  child: tasks.isEmpty
                      ? _buildEmptyState(context, isDark, emptyIcon, emptyText)
                      : _buildTaskList(context, ref, scrollController, tasks, isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClearButton(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    List<TransferTask> tasks,
  ) {
    final hasCompleted = tasks.any((t) => t.isCompleted);
    if (!hasCompleted && type != TransferSheetType.cache) {
      return const SizedBox.shrink();
    }

    final buttonText = type == TransferSheetType.cache ? '清空缓存' : '清除已完成';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleClear(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                : AppColors.lightSurfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            buttonText,
            style: context.textTheme.labelMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleClear(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(transferTasksProvider.notifier);

    if (type == TransferSheetType.cache) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('清空缓存'),
          content: const Text('确定要清空所有缓存吗？此操作无法恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await notifier.clearAllCache();
      }
    } else if (type == TransferSheetType.download) {
      await notifier.clearCompletedDownloads();
    } else {
      await notifier.clearCompletedUploads();
    }
  }

  Widget _buildEmptyState(
    BuildContext context,
    bool isDark,
    IconData icon,
    String text,
  ) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppColors.success),
            ),
            const SizedBox(height: 16),
            Text(
              text,
              style: context.textTheme.titleMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              type == TransferSheetType.cache ? '缓存的内容可以离线访问' : '任务完成后将显示在这里',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  Widget _buildTaskList(
    BuildContext context,
    WidgetRef ref,
    ScrollController scrollController,
    List<TransferTask> tasks,
    bool isDark,
  ) {
    // 按状态排序
    final sortedTasks = List<TransferTask>.from(tasks)
      ..sort((a, b) {
        final statusOrder = {
          TransferStatus.transferring: 0,
          TransferStatus.queued: 1,
          TransferStatus.pending: 2,
          TransferStatus.paused: 3,
          TransferStatus.failed: 4,
          TransferStatus.completed: 5,
          TransferStatus.cancelled: 6,
        };
        final aOrder = statusOrder[a.status] ?? 99;
        final bOrder = statusOrder[b.status] ?? 99;
        if (aOrder != bOrder) return aOrder.compareTo(bOrder);
        return b.createdAt.compareTo(a.createdAt);
      });

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: sortedTasks.length,
      itemBuilder: (context, index) => _TransferTaskTile(
        task: sortedTasks[index],
        isDark: isDark,
        type: type,
      ),
    );
  }
}

/// 缓存统计
class _CacheStats extends ConsumerWidget {
  const _CacheStats({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(cacheStatsProvider);

    return statsAsync.when(
      data: (stats) {
        var totalCount = 0;
        var totalSize = 0;
        for (final entry in stats.entries) {
          totalCount += entry.value.count;
          totalSize += entry.value.size;
        }

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : AppColors.lightSurfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '缓存占用',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatBytes(totalSize),
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkOnSurface : null,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: isDark
                    ? AppColors.darkOutline.withValues(alpha: 0.3)
                    : AppColors.lightOutline.withValues(alpha: 0.3),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '缓存数量',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$totalCount 个',
                        style: context.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkOnSurface : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 传输任务卡片
class _TransferTaskTile extends ConsumerWidget {
  const _TransferTaskTile({
    required this.task,
    required this.isDark,
    required this.type,
  });

  final TransferTask task;
  final bool isDark;
  final TransferSheetType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(transferTasksProvider.notifier);
    final isActive = task.status == TransferStatus.transferring ||
        task.status == TransferStatus.queued ||
        task.status == TransferStatus.pending;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
            : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : AppColors.lightOutline.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文件名和操作按钮
            Row(
              children: [
                _buildStatusIcon(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppColors.darkOnSurface : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (type == TransferSheetType.cache && task.isCompleted)
                        Text(
                          task.fileSizeText,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                _buildActionButton(context, notifier),
              ],
            ),
            // 进度条（仅活动任务显示）
            if (isActive) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progress,
                  backgroundColor: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceVariant,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    task.status == TransferStatus.paused ? AppColors.warning : AppColors.primary,
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    task.sizeProgressText,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                  Text(
                    task.progressText,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            // 错误信息
            if (task.status == TransferStatus.failed && task.error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.error!,
                        style: context.textTheme.labelSmall?.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    final (icon, color, showProgress) = switch (task.status) {
      TransferStatus.pending => (Icons.schedule_rounded, AppColors.warning, false),
      TransferStatus.queued => (Icons.queue_rounded, AppColors.info, false),
      TransferStatus.transferring => (null, AppColors.primary, true),
      TransferStatus.paused => (Icons.pause_circle_rounded, AppColors.warning, false),
      TransferStatus.completed => (Icons.check_circle_rounded, AppColors.success, false),
      TransferStatus.failed => (Icons.error_rounded, AppColors.error, false),
      TransferStatus.cancelled => (Icons.cancel_rounded, AppColors.fileOther, false),
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: showProgress
          ? Padding(
              padding: const EdgeInsets.all(10),
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                value: task.progress,
                color: color,
              ),
            )
          : Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildActionButton(BuildContext context, TransferTasksNotifier notifier) {
    // 缓存类型只显示删除按钮
    if (type == TransferSheetType.cache) {
      return _buildIconButton(
        context,
        icon: Icons.delete_outline_rounded,
        tooltip: '删除缓存',
        onTap: () => notifier.deleteCache(task.sourceId, task.sourcePath),
      );
    }

    final (icon, tooltip, onTap) = switch (task.status) {
      TransferStatus.pending || TransferStatus.queued => (
          Icons.close_rounded,
          '取消',
          () => notifier.cancelTask(task.id),
        ),
      TransferStatus.transferring => (
          Icons.pause_rounded,
          '暂停',
          () => notifier.pauseTask(task.id),
        ),
      TransferStatus.paused => (
          Icons.play_arrow_rounded,
          '继续',
          () => notifier.resumeTask(task.id),
        ),
      TransferStatus.completed => (
          Icons.delete_outline_rounded,
          '删除',
          () => notifier.deleteTask(task.id),
        ),
      TransferStatus.failed => (
          Icons.refresh_rounded,
          '重试',
          () => notifier.retryTask(task.id),
        ),
      TransferStatus.cancelled => (
          Icons.delete_outline_rounded,
          '删除',
          () => notifier.deleteTask(task.id),
        ),
    };

    return _buildIconButton(context, icon: icon, tooltip: tooltip, onTap: onTap);
  }

  Widget _buildIconButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
          ),
        ),
      );
}
