import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:my_nas/features/transfer/presentation/widgets/cache_list_view.dart';
import 'package:my_nas/features/transfer/presentation/widgets/transfer_task_tile.dart';

/// 传输管理页面
class TransferManagerPage extends ConsumerStatefulWidget {
  const TransferManagerPage({super.key, this.initialTab = 0});

  /// 初始选中的 Tab（0: 下载, 1: 上传, 2: 缓存）
  final int initialTab;

  @override
  ConsumerState<TransferManagerPage> createState() => _TransferManagerPageState();
}

class _TransferManagerPageState extends ConsumerState<TransferManagerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transferTasksProvider);
    final uploadTasks = ref.watch(uploadTasksProvider);
    final downloadTasks = ref.watch(downloadTasksProvider);
    final cacheTasks = ref.watch(cacheTasksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('传输管理'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            _buildTab(
              icon: Icons.download,
              label: '下载',
              count: downloadTasks.where(_isActive).length,
            ),
            _buildTab(
              icon: Icons.upload,
              label: '上传',
              count: uploadTasks.where(_isActive).length,
            ),
            _buildTab(
              icon: Icons.storage,
              label: '缓存',
              count: cacheTasks.where((t) => t.isCompleted).length,
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_completed_downloads',
                child: Text('清除已完成下载'),
              ),
              const PopupMenuItem(
                value: 'clear_completed_uploads',
                child: Text('清除已完成上传'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear_all_cache',
                child: Text('清空所有缓存'),
              ),
            ],
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // 下载列表
                _buildTaskList(
                  tasks: downloadTasks,
                  emptyIcon: Icons.download_done,
                  emptyText: '暂无下载任务',
                ),
                // 上传列表
                _buildTaskList(
                  tasks: uploadTasks,
                  emptyIcon: Icons.cloud_upload_outlined,
                  emptyText: '暂无上传任务',
                ),
                // 缓存列表
                CacheListView(
                  activeTasks: cacheTasks.where((t) => !t.isCompleted).toList(),
                  onDeleteCache: _handleDeleteCacheItem,
                  onClearAll: () => _handleClearAllCache(null),
                ),
              ],
            ),
    );
  }

  bool _isActive(TransferTask task) =>
      task.status == TransferStatus.transferring ||
      task.status == TransferStatus.queued ||
      task.status == TransferStatus.pending;

  Widget _buildTab({
    required IconData icon,
    required String label,
    required int count,
  }) => Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 4),
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );

  Widget _buildTaskList({
    required List<TransferTask> tasks,
    required IconData emptyIcon,
    required String emptyText,
  }) {
    if (tasks.isEmpty) {
      return _buildEmptyState(icon: emptyIcon, text: emptyText);
    }

    // 按状态排序：进行中 > 排队中 > 等待中 > 暂停 > 失败 > 完成
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedTasks.length,
      itemBuilder: (context, index) {
        final task = sortedTasks[index];
        return TransferTaskTile(
          task: task,
          onPause: () => _handlePause(task),
          onResume: () => _handleResume(task),
          onCancel: () => _handleCancel(task),
          onRetry: () => _handleRetry(task),
          onDelete: () => _handleDelete(task),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String text,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'clear_completed_downloads':
        ref.read(transferTasksProvider.notifier).clearCompletedDownloads();
      case 'clear_completed_uploads':
        ref.read(transferTasksProvider.notifier).clearCompletedUploads();
      case 'clear_all_cache':
        _showClearCacheConfirmDialog();
    }
  }

  Future<void> _showClearCacheConfirmDialog() async {
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

    if (confirmed == true && mounted) {
      await _handleClearAllCache(null);
    }
  }

  void _handlePause(TransferTask task) {
    ref.read(transferTasksProvider.notifier).pauseTask(task.id);
  }

  void _handleResume(TransferTask task) {
    ref.read(transferTasksProvider.notifier).resumeTask(task.id);
  }

  void _handleCancel(TransferTask task) {
    ref.read(transferTasksProvider.notifier).cancelTask(task.id);
  }

  void _handleRetry(TransferTask task) {
    ref.read(transferTasksProvider.notifier).retryTask(task.id);
  }

  void _handleDelete(TransferTask task) {
    ref.read(transferTasksProvider.notifier).deleteTask(task.id);
  }

  Future<void> _handleDeleteCacheItem(CachedMediaItem item) async {
    await ref.read(transferTasksProvider.notifier).deleteCache(
          item.sourceId,
          item.sourcePath,
        );
  }

  Future<void> _handleClearAllCache(MediaType? mediaType) async {
    await ref.read(transferTasksProvider.notifier).clearAllCache(
          mediaType: mediaType,
        );
  }
}
