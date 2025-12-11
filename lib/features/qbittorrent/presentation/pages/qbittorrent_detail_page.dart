import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/qbittorrent/presentation/providers/qbittorrent_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/qbittorrent/api/qbittorrent_api.dart';

/// qBittorrent 详情页面
class QBittorrentDetailPage extends ConsumerStatefulWidget {
  const QBittorrentDetailPage({
    required this.source,
    super.key,
    this.password,
  });

  final SourceEntity source;
  final String? password;

  @override
  ConsumerState<QBittorrentDetailPage> createState() =>
      _QBittorrentDetailPageState();
}

class _QBittorrentDetailPageState extends ConsumerState<QBittorrentDetailPage> {
  bool _hasConnected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connect();
    });
  }

  Future<void> _connect() async {
    if (_hasConnected) return;
    _hasConnected = true;

    await ref.read(qbittorrentConnectionProvider(widget.source.id).notifier).connect(
          widget.source,
          password: widget.password,
        );
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(qbittorrentConnectionProvider(widget.source.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          _buildHeader(context, isDark, connection),
          Expanded(child: _buildBody(context, isDark, connection)),
        ],
      ),
      floatingActionButton: connection?.status == QBConnectionStatus.connected
          ? FloatingActionButton(
              onPressed: () => _showAddTorrentDialog(context),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildHeader(
    BuildContext context,
    bool isDark,
    QBittorrentConnection? connection,
  ) {
    final transferInfo = ref.watch(qbTransferInfoAutoRefreshProvider(widget.source.id));
    final prefsAsync = ref.watch(qbPreferencesProvider(widget.source.id));

    return DecoratedBox(
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
          child: Column(
            children: [
              // 标题栏
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
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
                        if (connection?.adapter.info.version != null)
                          Text(
                            'qBittorrent ${connection!.adapter.info.version}',
                            style: context.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // 备用速度限制按钮
                  if (connection?.status == QBConnectionStatus.connected)
                    IconButton(
                      icon: Icon(
                        transferInfo?.useAltSpeedLimits == true
                            ? Icons.speed
                            : Icons.speed_outlined,
                        color: transferInfo?.useAltSpeedLimits == true
                            ? AppColors.warning
                            : null,
                      ),
                      tooltip: transferInfo?.useAltSpeedLimits == true
                          ? '关闭备用速度限制'
                          : '启用备用速度限制',
                      onPressed: () {
                        ref.read(qbittorrentActionsProvider(widget.source.id))
                            .toggleAlternativeSpeedLimits();
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
                        value: 'pause_all',
                        child: ListTile(
                          leading: Icon(Icons.pause),
                          title: Text('全部暂停'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'resume_all',
                        child: ListTile(
                          leading: Icon(Icons.play_arrow),
                          title: Text('全部开始'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'speed_limit',
                        child: ListTile(
                          leading: Icon(Icons.tune),
                          title: Text('速度限制设置'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'sort',
                        child: ListTile(
                          leading: Icon(Icons.sort),
                          title: Text('排序'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'refresh',
                        child: ListTile(
                          leading: Icon(Icons.refresh),
                          title: Text('刷新'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // 速度信息
              if (transferInfo != null &&
                  connection?.status == QBConnectionStatus.connected) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SpeedCard(
                        icon: Icons.download,
                        label: '下载',
                        speed: transferInfo.dlInfoSpeed,
                        total: transferInfo.dlInfoData,
                        limit: prefsAsync.valueOrNull?.dlLimit ?? 0,
                        color: AppColors.success,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SpeedCard(
                        icon: Icons.upload,
                        label: '上传',
                        speed: transferInfo.upInfoSpeed,
                        total: transferInfo.upInfoData,
                        limit: prefsAsync.valueOrNull?.upLimit ?? 0,
                        color: AppColors.primary,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    bool isDark,
    QBittorrentConnection? connection,
  ) {
    if (connection == null || connection.status == QBConnectionStatus.connecting) {
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

    if (connection.status == QBConnectionStatus.error) {
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

    return _TorrentList(sourceId: widget.source.id, isDark: isDark);
  }

  void _handleMenuAction(String action, BuildContext context) {
    final actions = ref.read(qbittorrentActionsProvider(widget.source.id));

    switch (action) {
      case 'pause_all':
        actions.pauseAll();
      case 'resume_all':
        actions.resumeAll();
      case 'speed_limit':
        _showSpeedLimitDialog(context);
      case 'sort':
        _showSortDialog(context);
      case 'refresh':
        ref.invalidate(qbittorrentAutoRefreshProvider(widget.source.id));
        ref.invalidate(qbTransferInfoAutoRefreshProvider(widget.source.id));
    }
  }

  void _showAddTorrentDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _AddTorrentDialog(sourceId: widget.source.id),
    );
  }

  void _showSpeedLimitDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _SpeedLimitDialog(sourceId: widget.source.id),
    );
  }

  void _showSortDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => _SortOptionsSheet(sourceId: widget.source.id),
    );
  }
}

/// 速度卡片
class _SpeedCard extends StatelessWidget {
  const _SpeedCard({
    required this.icon,
    required this.label,
    required this.speed,
    required this.total,
    required this.color,
    required this.isDark,
    this.limit = 0,
  });

  final IconData icon;
  final String label;
  final int speed;
  final int total;
  final int limit;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatSpeed(speed),
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : color,
                  ),
                ),
                Text(
                  limit > 0
                      ? '$label: ${_formatSize(total)} (限速: ${_formatSpeed(limit)})'
                      : '$label: ${_formatSize(total)}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Torrent 列表
class _TorrentList extends ConsumerWidget {
  const _TorrentList({required this.sourceId, required this.isDark});

  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final torrents = ref.watch(qbittorrentAutoRefreshProvider(sourceId));
    final sortSettings = ref.watch(qbSortSettingsProvider(sourceId));
    final categoriesAsync = ref.watch(qbCategoriesProvider(sourceId));
    final tagsAsync = ref.watch(qbTagsProvider(sourceId));

    if (torrents.isEmpty) {
      return _buildEmptyState(context);
    }

    // 过滤
    var filtered = torrents.toList();
    if (sortSettings.filterCategory != null) {
      filtered = filtered.where((t) => t.category == sortSettings.filterCategory).toList();
    }
    if (sortSettings.filterTag != null) {
      filtered = filtered
          .where((t) => t.tags?.split(',').contains(sortSettings.filterTag) ?? false)
          .toList();
    }

    // 排序
    filtered.sort((a, b) {
      int result;
      switch (sortSettings.sortMode) {
        case QBSortMode.name:
          result = a.name.compareTo(b.name);
        case QBSortMode.size:
          result = a.size.compareTo(b.size);
        case QBSortMode.progress:
          result = a.progress.compareTo(b.progress);
        case QBSortMode.dlSpeed:
          result = a.dlSpeed.compareTo(b.dlSpeed);
        case QBSortMode.upSpeed:
          result = a.upSpeed.compareTo(b.upSpeed);
        case QBSortMode.addedOn:
          result = (a.addedOn ?? 0).compareTo(b.addedOn ?? 0);
        case QBSortMode.ratio:
          result = (a.ratio ?? 0).compareTo(b.ratio ?? 0);
        case QBSortMode.eta:
          result = (a.eta ?? 0).compareTo(b.eta ?? 0);
      }
      return sortSettings.reverse ? -result : result;
    });

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(qbittorrentAutoRefreshProvider(sourceId));
      },
      child: Column(
        children: [
          // 筛选条
          _buildFilterBar(context, ref, sortSettings, categoriesAsync, tagsAsync),
          // 列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: filtered.length + 1, // +1 for bottom padding
              itemBuilder: (context, index) {
                if (index == filtered.length) {
                  return SizedBox(height: MediaQuery.of(context).padding.bottom + 80);
                }
                return _TorrentTile(
                  torrent: filtered[index],
                  sourceId: sourceId,
                  isDark: isDark,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    WidgetRef ref,
    QBSortSettings sortSettings,
    AsyncValue<Map<String, QBCategory>> categoriesAsync,
    AsyncValue<List<String>> tagsAsync,
  ) {
    final categories = categoriesAsync.valueOrNull ?? {};
    final tags = tagsAsync.valueOrNull ?? [];

    if (categories.isEmpty && tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // 分类筛选
          if (categories.isNotEmpty) ...[
            FilterChip(
              label: Text(sortSettings.filterCategory ?? '全部分类'),
              selected: sortSettings.filterCategory != null,
              onSelected: (_) {
                _showCategoryFilter(context, ref, categories.keys.toList());
              },
            ),
            const SizedBox(width: 8),
          ],
          // 标签筛选
          if (tags.isNotEmpty) ...[
            FilterChip(
              label: Text(sortSettings.filterTag ?? '全部标签'),
              selected: sortSettings.filterTag != null,
              onSelected: (_) {
                _showTagFilter(context, ref, tags);
              },
            ),
            const SizedBox(width: 8),
          ],
          // 排序
          ActionChip(
            avatar: Icon(
              sortSettings.reverse ? Icons.arrow_downward : Icons.arrow_upward,
              size: 16,
            ),
            label: Text(sortSettings.sortMode.label),
            onPressed: () {
              ref.read(qbSortSettingsProvider(sourceId).notifier).toggleReverse();
            },
          ),
        ],
      ),
    );
  }

  void _showCategoryFilter(
    BuildContext context,
    WidgetRef ref,
    List<String> categories,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('全部分类'),
              onTap: () {
                ref.read(qbSortSettingsProvider(sourceId).notifier).setFilterCategory(null);
                Navigator.pop(context);
              },
            ),
            ...categories.map(
              (c) => ListTile(
                title: Text(c.isEmpty ? '(未分类)' : c),
                onTap: () {
                  ref.read(qbSortSettingsProvider(sourceId).notifier).setFilterCategory(c);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTagFilter(
    BuildContext context,
    WidgetRef ref,
    List<String> tags,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('全部标签'),
              onTap: () {
                ref.read(qbSortSettingsProvider(sourceId).notifier).setFilterTag(null);
                Navigator.pop(context);
              },
            ),
            ...tags.map(
              (t) => ListTile(
                title: Text(t),
                onTap: () {
                  ref.read(qbSortSettingsProvider(sourceId).notifier).setFilterTag(t);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
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
          Text('暂无下载任务', style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(
            '点击右下角按钮添加任务',
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个 Torrent 项
class _TorrentTile extends ConsumerWidget {
  const _TorrentTile({
    required this.torrent,
    required this.sourceId,
    required this.isDark,
  });

  final QBTorrent torrent;
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (statusColor, statusIcon) = _getStatusInfo();
    final tagList = torrent.tags?.split(',').where((t) => t.isNotEmpty).toList() ?? [];

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
      child: InkWell(
        onTap: () => _showTorrentDetails(context, ref),
        onLongPress: () => _showTorrentActions(context, ref),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 名称和状态
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          torrent.name,
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              _formatSize(torrent.size),
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : AppColors.lightOnSurfaceVariant,
                              ),
                            ),
                            if (torrent.category != null && torrent.category!.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  torrent.category!,
                                  style: context.textTheme.labelSmall?.copyWith(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildQuickAction(context, ref),
                ],
              ),
              // 标签
              if (tagList.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: tagList.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  )).toList(),
                ),
              ],
              // 进度条
              if (torrent.isDownloading || torrent.isPaused) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: torrent.progress,
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
                    if (torrent.dlSpeed > 0 || torrent.upSpeed > 0)
                      Row(
                        children: [
                          if (torrent.dlSpeed > 0) ...[
                            const Icon(Icons.arrow_downward, size: 12, color: AppColors.success),
                            Text(
                              _formatSpeed(torrent.dlSpeed),
                              style: context.textTheme.labelSmall?.copyWith(color: AppColors.success),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (torrent.upSpeed > 0) ...[
                            const Icon(Icons.arrow_upward, size: 12, color: AppColors.primary),
                            Text(
                              _formatSpeed(torrent.upSpeed),
                              style: context.textTheme.labelSmall?.copyWith(color: AppColors.primary),
                            ),
                          ],
                        ],
                      )
                    else
                      const SizedBox.shrink(),
                    Text(
                      '${(torrent.progress * 100).toStringAsFixed(1)}%',
                      style: context.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              // 做种信息
              if (torrent.isUploading && torrent.isCompleted) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.arrow_upward, size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      _formatSpeed(torrent.upSpeed),
                      style: context.textTheme.bodySmall?.copyWith(color: AppColors.primary),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.sync, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '分享率: ${torrent.ratio?.toStringAsFixed(2) ?? '-'}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  (Color, IconData) _getStatusInfo() {
    if (torrent.hasError) return (AppColors.error, Icons.error);
    if (torrent.isPaused) return (AppColors.warning, Icons.pause_circle);
    if (torrent.isDownloading) return (AppColors.success, Icons.downloading);
    if (torrent.isUploading) return (AppColors.primary, Icons.upload);
    if (torrent.isCompleted) return (AppColors.success, Icons.check_circle);
    return (Colors.grey, Icons.help_outline);
  }

  Widget _buildQuickAction(BuildContext context, WidgetRef ref) {
    final actions = ref.read(qbittorrentActionsProvider(sourceId));

    if (torrent.isPaused) {
      return IconButton(
        icon: const Icon(Icons.play_arrow),
        onPressed: () => actions.resume([torrent.hash]),
        tooltip: '继续',
      );
    }

    if (torrent.isDownloading || torrent.isUploading) {
      return IconButton(
        icon: const Icon(Icons.pause),
        onPressed: () => actions.pause([torrent.hash]),
        tooltip: '暂停',
      );
    }

    return IconButton(
      icon: const Icon(Icons.more_vert),
      onPressed: () => _showTorrentActions(context, ref),
    );
  }

  void _showTorrentDetails(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              torrent.name,
              style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _DetailItem(label: '大小', value: _formatSize(torrent.size)),
            _DetailItem(label: '进度', value: '${(torrent.progress * 100).toStringAsFixed(1)}%'),
            _DetailItem(label: '状态', value: torrent.state),
            if (torrent.dlSpeed > 0)
              _DetailItem(label: '下载速度', value: _formatSpeed(torrent.dlSpeed)),
            if (torrent.upSpeed > 0)
              _DetailItem(label: '上传速度', value: _formatSpeed(torrent.upSpeed)),
            if (torrent.ratio != null)
              _DetailItem(label: '分享率', value: torrent.ratio!.toStringAsFixed(2)),
            if (torrent.numSeeds != null)
              _DetailItem(label: '种子数', value: torrent.numSeeds.toString()),
            if (torrent.numLeechers != null)
              _DetailItem(label: '下载者', value: torrent.numLeechers.toString()),
            if (torrent.category != null && torrent.category!.isNotEmpty)
              _DetailItem(label: '分类', value: torrent.category!),
            if (torrent.tags != null && torrent.tags!.isNotEmpty)
              _DetailItem(label: '标签', value: torrent.tags!),
            if (torrent.savePath != null)
              _DetailItem(label: '保存路径', value: torrent.savePath!),
            if (torrent.addedOn != null)
              _DetailItem(
                label: '添加时间',
                value: DateTime.fromMillisecondsSinceEpoch(torrent.addedOn! * 1000)
                    .toString()
                    .substring(0, 19),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: torrent.hash));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制 Hash')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('复制 Hash'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTorrentActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(torrent.isPaused ? Icons.play_arrow : Icons.pause),
              title: Text(torrent.isPaused ? '继续' : '暂停'),
              onTap: () {
                Navigator.pop(context);
                final actions = ref.read(qbittorrentActionsProvider(sourceId));
                if (torrent.isPaused) {
                  actions.resume([torrent.hash]);
                } else {
                  actions.pause([torrent.hash]);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('更改保存位置'),
              onTap: () {
                Navigator.pop(context);
                _showLocationDialog(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.category),
              title: const Text('修改分类'),
              onTap: () {
                Navigator.pop(context);
                _showCategoryDialog(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.label),
              title: const Text('管理标签'),
              onTap: () {
                Navigator.pop(context);
                _showTagsDialog(context, ref);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除任务'),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, ref, deleteFiles: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('删除任务和文件', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, ref, deleteFiles: true);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: torrent.name);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '新名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(qbittorrentActionsProvider(sourceId)).rename(
                    torrent.hash,
                    controller.text,
                  );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showLocationDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: torrent.savePath);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('更改保存位置'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '保存路径',
            hintText: '/path/to/save',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(qbittorrentActionsProvider(sourceId)).setLocation(
                [torrent.hash],
                controller.text,
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showCategoryDialog(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.read(qbCategoriesProvider(sourceId));
    final categories = categoriesAsync.valueOrNull?.keys.toList() ?? [];

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('无分类'),
              onTap: () {
                Navigator.pop(context);
                ref.read(qbittorrentActionsProvider(sourceId)).setCategory([torrent.hash], '');
              },
            ),
            ...categories.map(
              (c) => ListTile(
                title: Text(c),
                trailing: torrent.category == c ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(context);
                  ref.read(qbittorrentActionsProvider(sourceId)).setCategory([torrent.hash], c);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('创建新分类'),
              onTap: () {
                Navigator.pop(context);
                _showCreateCategoryDialog(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateCategoryDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final pathController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建分类'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '分类名称'),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pathController,
              decoration: const InputDecoration(
                labelText: '保存路径（可选）',
                hintText: '/path/to/save',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final actions = ref.read(qbittorrentActionsProvider(sourceId));
              await actions.createCategory(
                nameController.text,
                savePath: pathController.text.isNotEmpty ? pathController.text : null,
              );
              await actions.setCategory([torrent.hash], nameController.text);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showTagsDialog(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.read(qbTagsProvider(sourceId));
    final allTags = tagsAsync.valueOrNull ?? [];
    final currentTags = torrent.tags?.split(',').where((t) => t.isNotEmpty).toList() ?? [];

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('选择标签', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ...allTags.map(
                (tag) => CheckboxListTile(
                  title: Text(tag),
                  value: currentTags.contains(tag),
                  onChanged: (checked) {
                    final actions = ref.read(qbittorrentActionsProvider(sourceId));
                    if (checked == true) {
                      actions.addTags([torrent.hash], [tag]);
                      setState(() => currentTags.add(tag));
                    } else {
                      actions.removeTags([torrent.hash], [tag]);
                      setState(() => currentTags.remove(tag));
                    }
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('创建新标签'),
                onTap: () {
                  Navigator.pop(context);
                  _showCreateTagDialog(context, ref);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateTagDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建标签'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '标签名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final actions = ref.read(qbittorrentActionsProvider(sourceId));
              await actions.createTags([controller.text]);
              await actions.addTags([torrent.hash], [controller.text]);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, {required bool deleteFiles}) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          deleteFiles
              ? '确定要删除 "${torrent.name}" 及其文件吗？\n此操作不可恢复。'
              : '确定要删除 "${torrent.name}" 吗？\n文件将保留在磁盘上。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(qbittorrentActionsProvider(sourceId)).delete(
                [torrent.hash],
                deleteFiles: deleteFiles,
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 详情项
class _DetailItem extends StatelessWidget {
  const _DetailItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: context.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// 排序选项
class _SortOptionsSheet extends ConsumerWidget {
  const _SortOptionsSheet({required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(qbSortSettingsProvider(sourceId));

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('排序方式', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ...QBSortMode.values.map(
            (mode) => RadioListTile<QBSortMode>(
              title: Text(mode.label),
              value: mode,
              groupValue: settings.sortMode,
              onChanged: (value) {
                if (value != null) {
                  ref.read(qbSortSettingsProvider(sourceId).notifier).setSortMode(value);
                }
              },
            ),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('降序'),
            value: settings.reverse,
            onChanged: (_) {
              ref.read(qbSortSettingsProvider(sourceId).notifier).toggleReverse();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 速度限制设置对话框
class _SpeedLimitDialog extends ConsumerStatefulWidget {
  const _SpeedLimitDialog({required this.sourceId});

  final String sourceId;

  @override
  ConsumerState<_SpeedLimitDialog> createState() => _SpeedLimitDialogState();
}

class _SpeedLimitDialogState extends ConsumerState<_SpeedLimitDialog> {
  final _dlLimitController = TextEditingController();
  final _upLimitController = TextEditingController();
  final _altDlLimitController = TextEditingController();
  final _altUpLimitController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await ref.read(qbPreferencesProvider(widget.sourceId).future);
    if (prefs != null && mounted) {
      setState(() {
        _dlLimitController.text = prefs.dlLimit > 0 ? (prefs.dlLimit ~/ 1024).toString() : '';
        _upLimitController.text = prefs.upLimit > 0 ? (prefs.upLimit ~/ 1024).toString() : '';
        _altDlLimitController.text = prefs.altDlLimit > 0 ? (prefs.altDlLimit ~/ 1024).toString() : '';
        _altUpLimitController.text = prefs.altUpLimit > 0 ? (prefs.altUpLimit ~/ 1024).toString() : '';
      });
    }
  }

  @override
  void dispose() {
    _dlLimitController.dispose();
    _upLimitController.dispose();
    _altDlLimitController.dispose();
    _altUpLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('速度限制设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('全局限速', style: context.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dlLimitController,
                    decoration: const InputDecoration(
                      labelText: '下载 (KB/s)',
                      hintText: '0 = 无限制',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _upLimitController,
                    decoration: const InputDecoration(
                      labelText: '上传 (KB/s)',
                      hintText: '0 = 无限制',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('备用限速', style: context.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _altDlLimitController,
                    decoration: const InputDecoration(
                      labelText: '下载 (KB/s)',
                      hintText: '0 = 无限制',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _altUpLimitController,
                    decoration: const InputDecoration(
                      labelText: '上传 (KB/s)',
                      hintText: '0 = 无限制',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final actions = ref.read(qbittorrentActionsProvider(widget.sourceId));

    final dlLimit = (int.tryParse(_dlLimitController.text) ?? 0) * 1024;
    final upLimit = (int.tryParse(_upLimitController.text) ?? 0) * 1024;
    final altDlLimit = (int.tryParse(_altDlLimitController.text) ?? 0) * 1024;
    final altUpLimit = (int.tryParse(_altUpLimitController.text) ?? 0) * 1024;

    await actions.setGlobalSpeedLimits(dlLimit: dlLimit, upLimit: upLimit);
    await actions.setAlternativeSpeedLimits(dlLimit: altDlLimit, upLimit: altUpLimit);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('速度限制已保存')),
      );
    }
  }
}

/// 添加 Torrent 对话框
class _AddTorrentDialog extends ConsumerStatefulWidget {
  const _AddTorrentDialog({required this.sourceId});

  final String sourceId;

  @override
  ConsumerState<_AddTorrentDialog> createState() => _AddTorrentDialogState();
}

class _AddTorrentDialogState extends ConsumerState<_AddTorrentDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _paused = false;
  String? _selectedCategory;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(qbCategoriesProvider(widget.sourceId));
    final categories = categoriesAsync.valueOrNull?.keys.toList() ?? [];

    return AlertDialog(
      title: const Text('添加 Torrent'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'URL / Magnet 链接',
                hintText: 'magnet:?xt=urn:btih:...',
                helperText: '支持 Magnet 链接或 Torrent 文件 URL',
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.isEmpty) return '请输入链接';
                if (!value.startsWith('magnet:') &&
                    !value.startsWith('http://') &&
                    !value.startsWith('https://')) {
                  return '请输入有效的 Magnet 链接或 HTTP URL';
                }
                return null;
              },
            ),
            if (categories.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(labelText: '分类'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('无')),
                  ...categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                ],
                onChanged: (value) => setState(() => _selectedCategory = value),
              ),
            ],
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _paused,
              onChanged: (value) => setState(() => _paused = value ?? false),
              title: const Text('添加后暂停'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('添加'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(qbittorrentActionsProvider(widget.sourceId)).addTorrent(
            _controller.text.trim(),
            category: _selectedCategory,
            paused: _paused,
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已添加任务')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

// === 工具函数 ===

String _formatSpeed(int bytesPerSecond) {
  if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
  if (bytesPerSecond < 1024 * 1024) return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  if (bytesPerSecond < 1024 * 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes < 1024 * 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
}
