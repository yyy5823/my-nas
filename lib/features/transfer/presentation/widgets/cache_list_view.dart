import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';

/// 缓存列表视图
class CacheListView extends ConsumerWidget {
  const CacheListView({
    super.key,
    required this.tasks,
    required this.onDeleteCache,
    required this.onClearAll,
  });

  final List<TransferTask> tasks;
  final Future<void> Function(TransferTask task) onDeleteCache;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 分组任务
    final activeTasks = tasks.where((t) => !t.isCompleted).toList();
    final completedTasks = tasks.where((t) => t.isCompleted).toList();

    // 按媒体类型分组已完成的缓存
    final groupedCache = <MediaType, List<TransferTask>>{};
    for (final task in completedTasks) {
      groupedCache.putIfAbsent(task.mediaType, () => []).add(task);
    }

    if (tasks.isEmpty) {
      return _buildEmptyState(context);
    }

    return CustomScrollView(
      slivers: [
        // 缓存统计
        SliverToBoxAdapter(
          child: _buildCacheStats(context, ref),
        ),

        // 正在缓存的任务
        if (activeTasks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '正在缓存',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final task = activeTasks[index];
                return _buildActiveCacheItem(context, task);
              },
              childCount: activeTasks.length,
            ),
          ),
        ],

        // 已缓存的内容
        if (completedTasks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    '已缓存',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onClearAll,
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
          ),

          // 按媒体类型显示
          for (final entry in groupedCache.entries) ...[
            SliverToBoxAdapter(
              child: _buildMediaTypeHeader(context, entry.key, entry.value.length),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final task = entry.value[index];
                  return _buildCachedItem(context, task);
                },
                childCount: entry.value.length,
              ),
            ),
          ],
        ],

        const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storage_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无缓存内容',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '缓存的音乐和视频可以离线播放',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCacheStats(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
            color: colorScheme.surfaceContainerLow,
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatBytes(totalSize),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: colorScheme.outlineVariant,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '缓存数量',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$totalCount 个',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
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

  Widget _buildMediaTypeHeader(
    BuildContext context,
    MediaType mediaType,
    int count,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (icon, label) = switch (mediaType) {
      MediaType.photo => (Icons.photo_library, '照片'),
      MediaType.music => (Icons.music_note, '音乐'),
      MediaType.video => (Icons.movie, '视频'),
      MediaType.book => (Icons.book, '图书'),
      MediaType.comic => (Icons.menu_book, '漫画'),
      MediaType.note => (Icons.note, '笔记'),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($count)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveCacheItem(BuildContext context, TransferTask task) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.fileName,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  task.progressText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 4,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              task.sizeProgressText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCachedItem(BuildContext context, TransferTask task) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: colorScheme.error,
        child: Icon(Icons.delete, color: colorScheme.onError),
      ),
      onDismissed: (_) => onDeleteCache(task),
      child: ListTile(
        leading: Icon(
          _getMediaTypeIcon(task.mediaType),
          color: colorScheme.onSurfaceVariant,
        ),
        title: Text(
          task.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(task.fileSizeText),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => onDeleteCache(task),
        ),
      ),
    );
  }

  IconData _getMediaTypeIcon(MediaType mediaType) => switch (mediaType) {
        MediaType.photo => Icons.photo,
        MediaType.music => Icons.audiotrack,
        MediaType.video => Icons.videocam,
        MediaType.book => Icons.book,
        MediaType.comic => Icons.menu_book,
        MediaType.note => Icons.note,
      };

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
