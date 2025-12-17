import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/presentation/pages/scraper_form_page.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart';

/// 刮削源管理页面
class ScraperSourcesPage extends ConsumerStatefulWidget {
  const ScraperSourcesPage({super.key});

  @override
  ConsumerState<ScraperSourcesPage> createState() => _ScraperSourcesPageState();
}

class _ScraperSourcesPageState extends ConsumerState<ScraperSourcesPage> {
  bool _isReorderMode = false;

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(scraperSourcesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('刮削源'),
        actions: [
          // 排序模式切换按钮
          IconButton(
            icon: Icon(_isReorderMode ? Icons.done : Icons.reorder),
            onPressed: () {
              setState(() {
                _isReorderMode = !_isReorderMode;
              });
            },
            tooltip: _isReorderMode ? '完成排序' : '调整顺序',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddScraperSheet(context),
            tooltip: '添加刮削源',
          ),
        ],
      ),
      body: sourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('加载失败: $e'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.read(scraperSourcesProvider.notifier).refresh(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (sources) {
          if (sources.isEmpty) {
            return _buildEmptyState(context);
          }

          if (_isReorderMode) {
            return _buildReorderableList(sources);
          }

          return _buildSourcesList(sources);
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 64,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无刮削源',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '添加刮削源以获取影视元数据',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showAddScraperSheet(context),
            icon: const Icon(Icons.add),
            label: const Text('添加刮削源'),
          ),
        ],
      ),
    );
  }

  Widget _buildSourcesList(List<ScraperSourceEntity> sources) => ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        return _ScraperSourceCard(
          source: source,
          priorityNumber: index + 1,
          onToggle: (enabled) => ref
              .read(scraperSourcesProvider.notifier)
              .toggleSource(source.id, enabled: enabled),
          onEdit: () => _editSource(source),
          onDelete: () => _confirmDelete(source),
          onTest: () => _testConnection(source),
        );
      },
    );

  Widget _buildReorderableList(List<ScraperSourceEntity> sources) => ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sources.length,
      onReorder: (oldIndex, newIndex) {
        ref.read(scraperSourcesProvider.notifier).reorderSources(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final source = sources[index];
        return _ScraperSourceReorderCard(
          key: ValueKey(source.id),
          source: source,
          priorityNumber: index + 1,
        );
      },
    );

  void _showAddScraperSheet(BuildContext context) {
    showModalBottomSheet<ScraperType>(
      context: context,
      builder: (context) => const _ScraperTypeSelectionSheet(),
    ).then((type) {
      if (type != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ScraperFormPage(type: type),
          ),
        );
      }
    });
  }

  void _editSource(ScraperSourceEntity source) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScraperFormPage(
          type: source.type,
          existingSource: source,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(ScraperSourceEntity source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除刮削源'),
        content: Text('确定要删除「${source.displayName}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && mounted) {
      await ref.read(scraperSourcesProvider.notifier).removeSource(source.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除「${source.displayName}」')),
        );
      }
    }
  }

  Future<void> _testConnection(ScraperSourceEntity source) async {
    // 显示加载对话框
    // ignore: unawaited_futures
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在测试连接...'),
          ],
        ),
      ),
    );

    try {
      final success =
          await ref.read(scraperSourcesProvider.notifier).testConnection(source);

      if (!mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '连接成功' : '连接失败'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('连接失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// 刮削源卡片
class _ScraperSourceCard extends StatelessWidget {
  const _ScraperSourceCard({
    required this.source,
    required this.priorityNumber,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
  });

  final ScraperSourceEntity source;
  final int priorityNumber;
  final void Function(bool) onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 优先级序号
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: source.isEnabled
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$priorityNumber',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: source.isEnabled
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // 图标
              Icon(
                source.type.icon,
                size: 40,
                color: source.isEnabled
                    ? colorScheme.primary
                    : colorScheme.outline,
              ),
              const SizedBox(width: 16),

              // 名称和类型
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: source.isEnabled
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      source.type.displayName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),

              // 启用开关
              Switch(
                value: source.isEnabled,
                onChanged: onToggle,
              ),

              // 更多操作
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'test':
                      onTest();
                    case 'edit':
                      onEdit();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'test',
                    child: ListTile(
                      leading: Icon(Icons.wifi_tethering),
                      title: Text('测试连接'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit),
                      title: Text('编辑'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete, color: Colors.red),
                      title: Text('删除', style: TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero,
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
}

/// 排序模式下的刮削源卡片
class _ScraperSourceReorderCard extends StatelessWidget {
  const _ScraperSourceReorderCard({
    super.key,
    required this.source,
    required this.priorityNumber,
  });

  final ScraperSourceEntity source;
  final int priorityNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 拖动手柄
            const Icon(Icons.drag_handle),
            const SizedBox(width: 12),

            // 优先级序号
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$priorityNumber',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // 图标
            Icon(
              source.type.icon,
              size: 32,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 16),

            // 名称
            Expanded(
              child: Text(
                source.displayName,
                style: theme.textTheme.titleMedium,
              ),
            ),

            // 状态指示
            if (!source.isEnabled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '已禁用',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 刮削源类型选择弹窗
class _ScraperTypeSelectionSheet extends StatelessWidget {
  const _ScraperTypeSelectionSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择刮削源类型',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ...ScraperType.values.map((type) => _ScraperTypeTile(type: type)),
          ],
        ),
      ),
    );
  }
}

/// 刮削源类型选项
class _ScraperTypeTile extends StatelessWidget {
  const _ScraperTypeTile({required this.type});

  final ScraperType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: Icon(type.icon, color: colorScheme.primary),
      title: Text(type.displayName),
      subtitle: Text(_getDescription(type)),
      onTap: () => Navigator.pop(context, type),
    );
  }

  String _getDescription(ScraperType type) => switch (type) {
        ScraperType.tmdb => '全球最大的影视数据库，数据全面',
        ScraperType.doubanApi => '使用第三方 API 获取豆瓣数据',
        ScraperType.doubanWeb => '直接解析豆瓣网页，需要登录 Cookie',
      };
}

/// ScraperType 扩展 - 图标
extension ScraperTypeIcon on ScraperType {
  IconData get icon => switch (this) {
        ScraperType.tmdb => Icons.movie_outlined,
        ScraperType.doubanApi => Icons.api,
        ScraperType.doubanWeb => Icons.language,
      };
}
