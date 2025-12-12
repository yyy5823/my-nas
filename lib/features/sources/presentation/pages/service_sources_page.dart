import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/pt_sites/presentation/pages/pt_site_detail_page.dart';
import 'package:my_nas/features/qbittorrent/presentation/pages/qbittorrent_detail_page.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/source_form_page.dart';
import 'package:my_nas/features/sources/presentation/pages/source_type_selection_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';

/// 通用服务源列表页面
///
/// 用于展示下载器、媒体追踪、媒体管理等服务类源的列表
class ServiceSourcesPage extends ConsumerStatefulWidget {
  const ServiceSourcesPage({
    required this.title, required this.category, required this.emptyIcon, required this.emptyTitle, required this.emptySubtitle, super.key,
  });

  /// 页面标题
  final String title;

  /// 源分类
  final SourceCategory category;

  /// 空状态图标
  final IconData emptyIcon;

  /// 空状态标题
  final String emptyTitle;

  /// 空状态副标题
  final String emptySubtitle;

  @override
  ConsumerState<ServiceSourcesPage> createState() => _ServiceSourcesPageState();
}

class _ServiceSourcesPageState extends ConsumerState<ServiceSourcesPage> {
  bool _isReorderMode = false;

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourcesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
            onPressed: () => _showAddSourceSheet(context),
            tooltip: '添加',
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
                onPressed: () => ref.read(sourcesProvider.notifier).refresh(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (allSources) {
          // 按分类过滤
          final sources = allSources
              .where((s) => s.type.category == widget.category)
              .toList();

          if (sources.isEmpty) {
            return _buildEmptyState(context);
          }

          if (_isReorderMode) {
            return _buildReorderableList(sources);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sources.length,
            itemBuilder: (context, index) {
              final source = sources[index];
              return _ServiceSourceCard(
                source: source,
                category: widget.category,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildReorderableList(List<SourceEntity> sources) =>
      ReorderableListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sources.length,
        onReorder: (oldIndex, newIndex) {
          // 需要找到在全局列表中的真实索引
          final allSources = ref.read(sourcesProvider).valueOrNull ?? [];
          final sourceIds = sources.map((s) => s.id).toList();

          // 获取全局索引
          final oldGlobalIndex =
              allSources.indexWhere((s) => s.id == sourceIds[oldIndex]);
          final newGlobalIndex = oldIndex < newIndex
              ? allSources.indexWhere((s) => s.id == sourceIds[newIndex - 1]) +
                  1
              : allSources.indexWhere((s) => s.id == sourceIds[newIndex]);

          if (oldGlobalIndex != -1 && newGlobalIndex != -1) {
            ref
                .read(sourcesProvider.notifier)
                .reorderSources(oldGlobalIndex, newGlobalIndex);
          }
        },
        proxyDecorator: (child, index, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final elevation =
                Tween<double>(begin: 0, end: 8).evaluate(animation);
            return Material(
              elevation: elevation,
              borderRadius: BorderRadius.circular(12),
              child: child,
            );
          },
          child: child,
        ),
        itemBuilder: (context, index) {
          final source = sources[index];
          return _ReorderableServiceCard(
            key: ValueKey(source.id),
            source: source,
          );
        },
      );

  Widget _buildEmptyState(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.emptyIcon,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.emptyTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                widget.emptySubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _showAddSourceSheet(context),
                icon: const Icon(Icons.add),
                label: const Text('添加'),
              ),
            ],
          ),
        ),
      );

  void _showAddSourceSheet(BuildContext context) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) => SourceTypeSelectionPage(
          allowedCategories: [widget.category],
        ),
      ),
    );
  }
}

/// 排序模式下的服务源卡片
class _ReorderableServiceCard extends StatelessWidget {
  const _ReorderableServiceCard({
    required this.source, super.key,
  });

  final SourceEntity source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 拖动手柄
            ReorderableDragStartListener(
              index: 0,
              child: Icon(
                Icons.drag_handle,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),

            // 图标
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                source.type.icon,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 16),

            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${source.type.displayName} • ${source.host}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // 状态标签
            _buildStatusChip(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.touch_app,
              size: 14,
              color: Colors.blue,
            ),
            const SizedBox(width: 4),
            Text(
              '点击进入',
              style: TextStyle(
                color: Colors.blue,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}

/// 服务源卡片
class _ServiceSourceCard extends ConsumerStatefulWidget {
  const _ServiceSourceCard({
    required this.source,
    required this.category,
  });

  final SourceEntity source;
  final SourceCategory category;

  @override
  ConsumerState<_ServiceSourceCard> createState() => _ServiceSourceCardState();
}

class _ServiceSourceCardState extends ConsumerState<_ServiceSourceCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openDetailPage(context),
        onLongPress: () => _showSourceOptions(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.source.type.icon,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 16),

              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.source.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.source.type.displayName} • ${widget.source.host}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // 状态标签
              _buildStatusChip(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.touch_app,
              size: 14,
              color: Colors.blue,
            ),
            const SizedBox(width: 4),
            Text(
              '点击进入',
              style: TextStyle(
                color: Colors.blue,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  void _showSourceOptions(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动指示器
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[600]
                  : Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('打开'),
            onTap: () {
              Navigator.pop(context);
              _openDetailPage(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('编辑'),
            onTap: () {
              Navigator.pop(context);
              _editSource();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('删除', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _deleteSource();
            },
          ),
          // 底部安全区域
          SizedBox(height: bottomPadding > 0 ? bottomPadding : 16),
        ],
      ),
    );
  }

  Future<void> _openDetailPage(BuildContext context) async {
    // PT 站点不需要密码验证，直接跳转
    if (widget.source.type.category == SourceCategory.ptSites) {
      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PTSiteDetailPage(source: widget.source),
          ),
        );
      }
      return;
    }

    // 获取密码
    String? password;
    final manager = ref.read(sourceManagerProvider);
    final credential = await manager.getCredential(widget.source.id);
    password = credential?.password;

    // 如果没有保存的密码且源需要密码，提示输入
    if (password == null &&
        widget.source.apiKey == null &&
        widget.source.username.isNotEmpty) {
      if (mounted) {
        password = await _showPasswordDialog();
        if (password == null || password.isEmpty) {
          return;
        }
      }
    }

    if (!mounted) return;

    // 根据源类型打开对应的详情页
    switch (widget.source.type) {
      case SourceType.qbittorrent:
        if (context.mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => QBittorrentDetailPage(
                source: widget.source,
                password: password,
              ),
            ),
          );
        }
      case SourceType.transmission:
      case SourceType.aria2:
      case SourceType.trakt:
      case SourceType.nastool:
      case SourceType.moviepilot:
        // 其他服务类源暂未实现，显示提示
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${widget.source.type.displayName} 详情页暂未实现'),
            ),
          );
        }
      default:
        break;
    }
  }

  Future<String?> _showPasswordDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入密码'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            labelText: '密码',
            hintText: '${widget.source.username} 的密码',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _editSource() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (context) => SourceFormPage(
          sourceType: widget.source.type,
          existingSource: widget.source,
        ),
      ),
    );
  }

  Future<void> _deleteSource() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定要删除 "${widget.source.displayName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if ((confirm ?? false) && mounted) {
      try {
        await ref
            .read(sourcesProvider.notifier)
            .removeSource(widget.source.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除 "${widget.source.displayName}"')),
          );
        }
      } on Exception catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('删除失败: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
