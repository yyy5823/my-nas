import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/nastool/api/nastool_api.dart';
import 'package:my_nas/service_adapters/nastool/nastool_adapter.dart';

/// NASTool 详情页面
class NasToolDetailPage extends ConsumerStatefulWidget {
  const NasToolDetailPage({
    required this.source,
    super.key,
  });

  final SourceEntity source;

  @override
  ConsumerState<NasToolDetailPage> createState() => _NasToolDetailPageState();
}

class _NasToolDetailPageState extends ConsumerState<NasToolDetailPage>
    with SingleTickerProviderStateMixin {
  bool _hasConnected = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
    });
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final tab = NasToolTab.values[_tabController.index];
    ref.read(nastoolCurrentTabProvider(widget.source.id).notifier).state = tab;
  }

  Future<void> _connect() async {
    if (_hasConnected) return;
    _hasConnected = true;

    await ref
        .read(nastoolConnectionProvider(widget.source.id).notifier)
        .connect(widget.source);
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(nastoolConnectionProvider(widget.source.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          _buildHeader(context, isDark, connection),
          if (connection?.status == NasToolConnectionStatus.connected)
            _buildTabBar(context, isDark),
          Expanded(child: _buildBody(context, isDark, connection)),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    bool isDark,
    NasToolConnection? connection,
  ) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: connection?.status == NasToolConnectionStatus.connected
                        ? () => _showSystemInfoDialog(context, connection!)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.source.displayName,
                          style: context.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                        ),
                        if (connection?.adapter.systemInfo != null)
                          Text(
                            'v${connection!.adapter.systemInfo!.version}',
                            style: context.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // 刷新按钮
                if (connection?.status == NasToolConnectionStatus.connected)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: '刷新',
                    onPressed: () {
                      ref.read(nastoolActionsProvider(widget.source.id)).refreshAll();
                    },
                  ),
                // 更多操作菜单
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: isDark ? AppColors.darkOnSurface : null,
                  ),
                  onSelected: (value) => _handleMenuAction(value, context),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'refresh_library',
                      child: ListTile(
                        leading: Icon(Icons.library_books),
                        title: Text('刷新媒体库'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'system_info',
                      child: ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('系统信息'),
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

  Widget _buildTabBar(BuildContext context, bool isDark) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColors.primary,
          unselectedLabelColor:
              isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '订阅'),
            Tab(text: '下载'),
            Tab(text: '历史'),
            Tab(text: '搜索'),
          ],
        ),
      );

  Widget _buildBody(
    BuildContext context,
    bool isDark,
    NasToolConnection? connection,
  ) {
    if (connection == null ||
        connection.status == NasToolConnectionStatus.connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接...'),
          ],
        ),
      );
    }

    if (connection.status == NasToolConnectionStatus.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('连接失败', style: context.textTheme.titleLarge),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                connection.errorMessage ?? '未知错误',
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium?.copyWith(color: Colors.red),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                _hasConnected = false;
                _connect();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _OverviewTab(sourceId: widget.source.id, isDark: isDark),
        _SubscribesTab(sourceId: widget.source.id, isDark: isDark),
        _DownloadsTab(sourceId: widget.source.id, isDark: isDark),
        _HistoryTab(sourceId: widget.source.id, isDark: isDark),
        _SearchTab(sourceId: widget.source.id, isDark: isDark),
      ],
    );
  }

  void _handleMenuAction(String action, BuildContext context) {
    switch (action) {
      case 'refresh_library':
        _refreshMediaLibrary();
      case 'system_info':
        final connection = ref.read(nastoolConnectionProvider(widget.source.id));
        if (connection != null) {
          _showSystemInfoDialog(context, connection);
        }
    }
  }

  Future<void> _refreshMediaLibrary() async {
    try {
      await ref
          .read(nastoolActionsProvider(widget.source.id))
          .refreshMediaLibrary();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('媒体库刷新任务已启动'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刷新失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showSystemInfoDialog(BuildContext context, NasToolConnection connection) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final systemInfo = connection.adapter.systemInfo;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : null,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.info_outline, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            const Text('系统信息'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(
              label: '服务名称',
              value: widget.source.displayName,
              isDark: isDark,
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: '版本',
              value: systemInfo?.version ?? '未知',
              isDark: isDark,
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: '服务器地址',
              value: '${widget.source.host}:${widget.source.port}',
              isDark: isDark,
            ),
            if (systemInfo?.serverName != null) ...[
              const SizedBox(height: 12),
              _InfoRow(
                label: '服务器名称',
                value: systemInfo!.serverName!,
                isDark: isDark,
              ),
            ],
            if (systemInfo?.cpuUsage != null) ...[
              const SizedBox(height: 12),
              _InfoRow(
                label: 'CPU 使用率',
                value: '${(systemInfo!.cpuUsage! * 100).toStringAsFixed(1)}%',
                isDark: isDark,
              ),
            ],
            if (systemInfo?.memoryUsage != null) ...[
              const SizedBox(height: 12),
              _InfoRow(
                label: '内存使用率',
                value: '${(systemInfo!.memoryUsage! * 100).toStringAsFixed(1)}%',
                isDark: isDark,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// 概览标签页
class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.sourceId, required this.isDark});

  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(nastoolOverviewAutoRefreshProvider(sourceId));

    if (overviewAsync == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(nastoolOverviewAutoRefreshProvider(sourceId));
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // 媒体统计卡片
          _buildStatsSection(context, overviewAsync),
          const SizedBox(height: AppSpacing.lg),
          // 任务统计卡片
          _buildTasksSection(context, overviewAsync),
        ],
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context, NasToolOverviewStats stats) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '媒体库',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.movie,
                  label: '电影',
                  value: stats.movieCount.toString(),
                  color: AppColors.primary,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatCard(
                  icon: Icons.tv,
                  label: '剧集',
                  value: stats.tvCount.toString(),
                  color: AppColors.success,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatCard(
                  icon: Icons.animation,
                  label: '动漫',
                  value: stats.animeCount.toString(),
                  color: AppColors.warning,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      );

  Widget _buildTasksSection(BuildContext context, NasToolOverviewStats stats) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '任务统计',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.bookmark,
                  label: '订阅',
                  value: stats.subscribeCount.toString(),
                  color: Colors.purple,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatCard(
                  icon: Icons.downloading,
                  label: '下载中',
                  value: stats.activeDownloads.toString(),
                  color: AppColors.primary,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatCard(
                  icon: Icons.check_circle,
                  label: '已完成',
                  value: stats.completedDownloads.toString(),
                  color: AppColors.success,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      );
}

/// 统计卡片
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
              : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : color.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              style: context.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : color,
              ),
            ),
            Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );
}

/// 订阅标签页
class _SubscribesTab extends ConsumerWidget {
  const _SubscribesTab({required this.sourceId, required this.isDark});

  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscribesAsync = ref.watch(nastoolSubscribesProvider(sourceId));

    return subscribesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('加载失败: $error')),
      data: (subscribes) {
        if (subscribes.isEmpty) {
          return _buildEmptyState(context);
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(nastoolSubscribesProvider(sourceId));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: subscribes.length,
            itemBuilder: (context, index) => _SubscribeTile(
              subscribe: subscribes[index],
              sourceId: sourceId,
              isDark: isDark,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bookmark_border, size: 48, color: Colors.purple),
            ),
            const SizedBox(height: 24),
            Text(
              '暂无订阅',
              style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              '添加订阅后会自动搜索下载',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );
}

/// 订阅项
class _SubscribeTile extends ConsumerWidget {
  const _SubscribeTile({
    required this.subscribe,
    required this.sourceId,
    required this.isDark,
  });

  final NasToolSubscribe subscribe;
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3) : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : AppColors.lightOutline.withValues(alpha: 0.3),
          ),
        ),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getTypeColor().withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_getTypeIcon(), color: _getTypeColor(), size: 20),
          ),
          title: Text(
            subscribe.name,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.darkOnSurface : null,
            ),
          ),
          subtitle: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getTypeColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getTypeLabel(),
                  style: TextStyle(
                    fontSize: 11,
                    color: _getTypeColor(),
                  ),
                ),
              ),
              if (subscribe.season != null) ...[
                const SizedBox(width: 8),
                Text(
                  '第${subscribe.season}季',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                ),
              ],
              if (subscribe.state != null) ...[
                const SizedBox(width: 8),
                Text(
                  subscribe.state!,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.error),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ),
      );

  IconData _getTypeIcon() {
    switch (subscribe.type.toLowerCase()) {
      case 'movie':
        return Icons.movie;
      case 'tv':
        return Icons.tv;
      case 'anime':
        return Icons.animation;
      default:
        return Icons.bookmark;
    }
  }

  Color _getTypeColor() {
    switch (subscribe.type.toLowerCase()) {
      case 'movie':
        return AppColors.primary;
      case 'tv':
        return AppColors.success;
      case 'anime':
        return AppColors.warning;
      default:
        return Colors.purple;
    }
  }

  String _getTypeLabel() {
    switch (subscribe.type.toLowerCase()) {
      case 'movie':
        return '电影';
      case 'tv':
        return '剧集';
      case 'anime':
        return '动漫';
      default:
        return subscribe.type;
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除订阅 "${subscribe.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(nastoolActionsProvider(sourceId))
                  .deleteSubscribe(subscribe.id);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 下载标签页
class _DownloadsTab extends ConsumerWidget {
  const _DownloadsTab({required this.sourceId, required this.isDark});

  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(nastoolDownloadTasksProvider(sourceId));

    return tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('加载失败: $error')),
      data: (tasks) {
        if (tasks.isEmpty) {
          return _buildEmptyState(context);
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(nastoolDownloadTasksProvider(sourceId));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: tasks.length,
            itemBuilder: (context, index) => _DownloadTaskTile(
              task: tasks[index],
              isDark: isDark,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.download_done, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              '暂无下载任务',
              style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              '搜索资源后可添加下载任务',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );
}

/// 下载任务项
class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({required this.task, required this.isDark});

  final NasToolDownloadTask task;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isCompleted = task.progress >= 1.0;
    final statusColor = isCompleted ? AppColors.success : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
            : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : AppColors.lightOutline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isCompleted ? Icons.check_circle : Icons.downloading,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task.name,
                  style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.darkOnSurface : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (!isCompleted) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                backgroundColor: isDark
                    ? AppColors.darkSurfaceElevated
                    : AppColors.lightSurfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (task.speed != null && task.speed! > 0)
                  Row(
                    children: [
                      const Icon(Icons.arrow_downward, size: 12, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text(
                        _formatSpeed(task.speed!),
                        style: context.textTheme.labelSmall?.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  )
                else
                  const SizedBox.shrink(),
                Text(
                  '${(task.progress * 100).toStringAsFixed(1)}%',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

/// 历史标签页
class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.sourceId, required this.isDark});

  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(nastoolTransferHistoryProvider(sourceId));

    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('加载失败: $error')),
      data: (history) {
        if (history.isEmpty) {
          return _buildEmptyState(context);
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(nastoolTransferHistoryProvider(sourceId));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: history.length,
            itemBuilder: (context, index) => _HistoryTile(
              history: history[index],
              isDark: isDark,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history, size: 48, color: AppColors.success),
            ),
            const SizedBox(height: 24),
            Text(
              '暂无转移记录',
              style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              '下载完成后会自动整理到媒体库',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );
}

/// 历史记录项
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.history, required this.isDark});

  final NasToolTransferHistory history;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isSuccess = history.success ?? true;
    final statusColor = isSuccess ? AppColors.success : AppColors.error;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
            : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : AppColors.lightOutline.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isSuccess ? Icons.check : Icons.close,
            color: statusColor,
            size: 20,
          ),
        ),
        title: Text(
          history.title,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.darkOnSurface : null,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getTypeColor().withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getTypeLabel(),
                    style: TextStyle(fontSize: 11, color: _getTypeColor()),
                  ),
                ),
                if (history.transferTime != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    _formatTime(history.transferTime!),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor() {
    switch (history.type.toLowerCase()) {
      case 'movie':
        return AppColors.primary;
      case 'tv':
        return AppColors.success;
      case 'anime':
        return AppColors.warning;
      default:
        return Colors.grey;
    }
  }

  String _getTypeLabel() {
    switch (history.type.toLowerCase()) {
      case 'movie':
        return '电影';
      case 'tv':
        return '剧集';
      case 'anime':
        return '动漫';
      default:
        return history.type;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays > 0) return '${diff.inDays}天前';
    if (diff.inHours > 0) return '${diff.inHours}小时前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分钟前';
    return '刚刚';
  }
}

/// 搜索标签页
class _SearchTab extends ConsumerStatefulWidget {
  const _SearchTab({required this.sourceId, required this.isDark});

  final String sourceId;
  final bool isDark;

  @override
  ConsumerState<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<_SearchTab> {
  final _searchController = TextEditingController();
  List<NasToolSearchResult> _results = [];
  bool _isSearching = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final results = await ref
          .read(nastoolActionsProvider(widget.sourceId))
          .searchResources(keyword: keyword);
      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索资源...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _search,
                      ),
                filled: true,
                fillColor: widget.isDark
                    ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                    : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          // 结果列表
          Expanded(
            child: _buildResults(context),
          ),
        ],
      );

  Widget _buildResults(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text('搜索失败', style: context.textTheme.titleMedium),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: widget.isDark
                  ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.5)
                  : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '输入关键词搜索资源',
              style: context.textTheme.bodyMedium?.copyWith(
                color: widget.isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: _results.length,
      itemBuilder: (context, index) => _SearchResultTile(
        result: _results[index],
        sourceId: widget.sourceId,
        isDark: widget.isDark,
      ),
    );
  }
}

/// 搜索结果项
class _SearchResultTile extends ConsumerWidget {
  const _SearchResultTile({
    required this.result,
    required this.sourceId,
    required this.isDark,
  });

  final NasToolSearchResult result;
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
              : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : AppColors.lightOutline.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.title,
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.darkOnSurface : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // 大小
                _buildTag(context, _formatSize(result.size), Icons.storage),
                const SizedBox(width: 8),
                // 种子数
                _buildTag(
                  context,
                  '${result.seeders}',
                  Icons.arrow_upward,
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                // 下载数
                _buildTag(
                  context,
                  '${result.leechers}',
                  Icons.arrow_downward,
                  color: AppColors.primary,
                ),
                const Spacer(),
                // 下载按钮
                if (result.url != null)
                  IconButton(
                    icon: const Icon(Icons.download, color: AppColors.primary),
                    onPressed: () => _download(context, ref),
                    tooltip: '下载',
                  ),
              ],
            ),
            if (result.site != null || result.resolution != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (result.site != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        result.site!,
                        style: const TextStyle(fontSize: 11, color: Colors.purple),
                      ),
                    ),
                  if (result.resolution != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        result.resolution!,
                        style: const TextStyle(fontSize: 11, color: AppColors.primary),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      );

  Widget _buildTag(BuildContext context, String text, IconData icon, {Color? color}) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)),
          const SizedBox(width: 4),
          Text(
            text,
            style: context.textTheme.bodySmall?.copyWith(
              color: color ?? (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
            ),
          ),
        ],
      );

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    if (result.url == null) return;

    try {
      await ref
          .read(nastoolActionsProvider(sourceId))
          .downloadResource(url: result.url!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('下载任务已添加'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

/// 信息行组件
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.isDark,
  });

  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
}
