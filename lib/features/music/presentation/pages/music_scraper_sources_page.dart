import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/music/data/services/music_scraper_factory.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/presentation/pages/music_scraper_form_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';

/// 音乐刮削源管理页面
class MusicScraperSourcesPage extends ConsumerStatefulWidget {
  const MusicScraperSourcesPage({super.key});

  @override
  ConsumerState<MusicScraperSourcesPage> createState() => _MusicScraperSourcesPageState();
}

class _MusicScraperSourcesPageState extends ConsumerState<MusicScraperSourcesPage> {
  bool _isReorderMode = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(musicScraperSourcesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐刮削源'),
        actions: [
          // 排序模式切换按钮
          if (state.sources.isNotEmpty)
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
      body: _buildBody(state),
    );
  }

  Widget _buildBody(MusicScraperSourcesState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('加载失败: ${state.error}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(musicScraperSourcesProvider.notifier).load(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (state.sources.isEmpty) {
      return _buildEmptyState(context);
    }

    if (_isReorderMode) {
      return _buildReorderableList(state.sources);
    }

    return _buildSourcesList(state.sources);
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_note_outlined,
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
            '添加刮削源以获取音乐元数据、封面和歌词',
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

  Widget _buildSourcesList(List<MusicScraperSourceEntity> sources) => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sources.length,
        itemBuilder: (context, index) {
          final source = sources[index];
          return _MusicScraperSourceCard(
            source: source,
            priorityNumber: index + 1,
            onToggle: (enabled) => ref
                .read(musicScraperSourcesProvider.notifier)
                .toggleSource(source.id, isEnabled: enabled),
            onEdit: () => _editSource(source),
            onDelete: () => _confirmDelete(source),
            onTest: () => _testConnection(source),
          );
        },
      );

  Widget _buildReorderableList(List<MusicScraperSourceEntity> sources) => ReorderableListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sources.length,
        onReorder: (oldIndex, newIndex) {
          ref.read(musicScraperSourcesProvider.notifier).reorder(oldIndex, newIndex);
        },
        itemBuilder: (context, index) {
          final source = sources[index];
          return _MusicScraperSourceReorderCard(
            key: ValueKey(source.id),
            source: source,
            priorityNumber: index + 1,
          );
        },
      );

  void _showAddScraperSheet(BuildContext context) {
    showModalBottomSheet<MusicScraperType>(
      context: context,
      builder: (context) => const _MusicScraperTypeSelectionSheet(),
    ).then((type) {
      if (type != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MusicScraperFormPage(type: type),
          ),
        );
      }
    });
  }

  void _editSource(MusicScraperSourceEntity source) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MusicScraperFormPage(
          type: source.type,
          existingSource: source,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(MusicScraperSourceEntity source) async {
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
      await ref.read(musicScraperSourcesProvider.notifier).removeSource(source.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除「${source.displayName}」')),
        );
      }
    }
  }

  Future<void> _testConnection(MusicScraperSourceEntity source) async {
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
      final manager = ref.read(musicScraperManagerProvider);
      await manager.init();
      final scraper = await manager.getScraper(source.id);
      final success = scraper != null && await scraper.testConnection();

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
class _MusicScraperSourceCard extends StatelessWidget {
  const _MusicScraperSourceCard({
    required this.source,
    required this.priorityNumber,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
  });

  final MusicScraperSourceEntity source;
  final int priorityNumber;
  final void Function(bool) onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isImplemented = MusicScraperFactory.isImplemented(source.type);

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
                  color: source.isEnabled && isImplemented
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$priorityNumber',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: source.isEnabled && isImplemented
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
                color: source.isEnabled && isImplemented
                    ? source.type.themeColor
                    : colorScheme.outline,
              ),
              const SizedBox(width: 16),

              // 名称和类型
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            source.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: source.isEnabled && isImplemented
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isImplemented) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '待实现',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getCapabilitiesText(source.type),
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
                onChanged: isImplemented ? onToggle : null,
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
                  if (isImplemented)
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

  String _getCapabilitiesText(MusicScraperType type) {
    final caps = <String>[];
    if (type.supportsMetadata) caps.add('元数据');
    if (type.supportsCover) caps.add('封面');
    if (type.supportsLyrics) caps.add('歌词');
    if (type.supportsFingerprint) caps.add('声纹');
    return caps.isEmpty ? type.displayName : caps.join(' · ');
  }
}

/// 排序模式下的刮削源卡片
class _MusicScraperSourceReorderCard extends StatelessWidget {
  const _MusicScraperSourceReorderCard({
    super.key,
    required this.source,
    required this.priorityNumber,
  });

  final MusicScraperSourceEntity source;
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
              color: source.type.themeColor,
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
class _MusicScraperTypeSelectionSheet extends StatelessWidget {
  const _MusicScraperTypeSelectionSheet();

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
            const SizedBox(height: 8),
            Text(
              '推荐添加: MusicBrainz (元数据) + 网易云音乐 (歌词封面)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            ...MusicScraperType.values.map((type) => _MusicScraperTypeTile(type: type)),
          ],
        ),
      ),
    );
  }
}

/// 刮削源类型选项
class _MusicScraperTypeTile extends StatelessWidget {
  const _MusicScraperTypeTile({required this.type});

  final MusicScraperType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isImplemented = MusicScraperFactory.isImplemented(type);

    return ListTile(
      leading: Icon(
        type.icon,
        color: isImplemented ? type.themeColor : colorScheme.outline,
      ),
      title: Row(
        children: [
          Text(
            type.displayName,
            style: TextStyle(
              color: isImplemented ? null : colorScheme.onSurfaceVariant,
            ),
          ),
          if (!isImplemented) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '即将支持',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(type.description),
      trailing: _buildCapabilityChips(context, type),
      onTap: () => Navigator.pop(context, type),
    );
  }

  Widget _buildCapabilityChips(BuildContext context, MusicScraperType type) {
    final chips = <Widget>[];
    final colorScheme = Theme.of(context).colorScheme;

    if (type.supportsMetadata) {
      chips.add(_buildChip(context, '元数据', colorScheme.primaryContainer));
    }
    if (type.supportsCover) {
      chips.add(_buildChip(context, '封面', colorScheme.secondaryContainer));
    }
    if (type.supportsLyrics) {
      chips.add(_buildChip(context, '歌词', colorScheme.tertiaryContainer));
    }
    if (type.supportsFingerprint) {
      chips.add(_buildChip(context, '声纹', colorScheme.errorContainer));
    }

    return Wrap(
      spacing: 4,
      children: chips,
    );
  }

  Widget _buildChip(BuildContext context, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      );
}
