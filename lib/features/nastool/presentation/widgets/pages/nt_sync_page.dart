import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/common/nt_common_widgets.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

class NtSyncPage extends ConsumerWidget {
  const NtSyncPage({super.key, required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dirsAsync = ref.watch(nastoolSyncDirsProvider(sourceId));

    return dirsAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(
        message: '加载失败: $e',
        isDark: isDark,
        onRetry: () => ref.invalidate(nastoolSyncDirsProvider(sourceId)),
      ),
      data: (dirs) {
        if (dirs.isEmpty) {
          return NtEmptyState(
            icon: Icons.folder_copy_rounded,
            message: '暂无同步目录\n在 NASTool 后台添加同步目录',
            isDark: isDark,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolSyncDirsProvider(sourceId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: dirs.length,
            itemBuilder: (context, index) => _SyncDirCard(
              dir: dirs[index],
              isDark: isDark,
              onSync: () => _syncDir(context, dirs[index], ref),
              onViewHistory: () => _showHistory(context, dirs[index], ref),
            ),
          ),
        );
      },
    );
  }

  void _syncDir(BuildContext context, NtSyncDir dir, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('立即同步'),
        content: Text('确定要立即同步「${dir.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(nastoolActionsProvider(sourceId)).runSyncDir(dir.id ?? 0);
              context.showSuccessToast('同步任务已启动');
            },
            child: const Text('同步'),
          ),
        ],
      ),
    );
  }

  void _showHistory(BuildContext context, NtSyncDir dir, WidgetRef ref) {
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
                      '${dir.name} - 同步历史',
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
                child: FutureBuilder<List<NtSyncHistory>>(
                  future: ref.read(nastoolActionsProvider(sourceId)).getSyncHistory(dir.id ?? 0),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const NtLoading();
                    }
                    if (snapshot.hasError) {
                      return NtError(message: '加载失败: ${snapshot.error}', isDark: isDark);
                    }
                    final history = snapshot.data ?? [];
                    if (history.isEmpty) {
                      return NtEmptyState(icon: Icons.history_rounded, message: '暂无同步历史', isDark: isDark);
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      itemCount: history.length,
                      itemBuilder: (context, index) => _SyncHistoryTile(history: history[index], isDark: isDark),
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

class _SyncDirCard extends StatelessWidget {
  const _SyncDirCard({
    required this.dir,
    required this.isDark,
    this.onSync,
    this.onViewHistory,
  });

  final NtSyncDir dir;
  final bool isDark;
  final VoidCallback? onSync;
  final VoidCallback? onViewHistory;

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
                      colors: dir.state == 'Y'
                          ? [NtColors.success, NtColors.successLight]
                          : [NtColors.onSurfaceVariant(isDark), NtColors.onSurfaceVariant(isDark).withValues(alpha: 0.5)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    dir.state == 'Y' ? Icons.sync_rounded : Icons.sync_disabled_rounded,
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
                        dir.name ?? '未命名目录',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: NtColors.onSurface(isDark),
                            ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          NtChip(
                            label: dir.state == 'Y' ? '启用' : '禁用',
                            color: dir.state == 'Y' ? NtColors.success : NtColors.onSurfaceVariant(isDark),
                          ),
                          if (dir.mode != null) ...[
                            const SizedBox(width: 8),
                            NtChip(label: _modeLabel(dir.mode!), color: NtColors.info),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _PathRow(icon: Icons.folder_rounded, label: '来源', path: dir.from ?? '-'),
            const SizedBox(height: 8),
            _PathRow(icon: Icons.folder_open_rounded, label: '目标', path: dir.to ?? '-'),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (dir.include != null && dir.include!.isNotEmpty)
                  Expanded(child: NtChip(label: '包含: ${dir.include}', color: NtColors.success)),
                if (dir.exclude != null && dir.exclude!.isNotEmpty)
                  Expanded(child: NtChip(label: '排除: ${dir.exclude}', color: NtColors.error)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                NtButton(
                  label: '同步历史',
                  icon: Icons.history_rounded,
                  isOutlined: true,
                  onPressed: onViewHistory,
                ),
                const SizedBox(width: AppSpacing.sm),
                NtButton(
                  label: '立即同步',
                  icon: Icons.sync_rounded,
                  onPressed: onSync,
                ),
              ],
            ),
          ],
        ),
      );

  String _modeLabel(String mode) {
    switch (mode.toLowerCase()) {
      case 'link':
        return '硬链接';
      case 'softlink':
        return '软链接';
      case 'copy':
        return '复制';
      case 'move':
        return '移动';
      default:
        return mode;
    }
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({required this.icon, required this.label, required this.path});
  final IconData icon;
  final String label;
  final String path;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: NtColors.primary),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          Expanded(
            child: Text(
              path,
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}

class _SyncHistoryTile extends StatelessWidget {
  const _SyncHistoryTile({required this.history, required this.isDark});
  final NtSyncHistory history;
  final bool isDark;

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  history.success ?? false ? Icons.check_circle_rounded : Icons.error_rounded,
                  size: 16,
                  color: history.success ?? false ? NtColors.success : NtColors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    history.sourceFilename ?? history.sourcePath ?? '',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: NtColors.onSurface(isDark),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (history.destPath != null) ...[
              const SizedBox(height: 4),
              Text(
                '→ ${history.destPath}',
                style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (history.mode != null) NtChip(label: history.mode!),
                const Spacer(),
                Text(
                  history.date ?? '',
                  style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      );
}
