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
    // 延迟连接以避免在 build 中修改 provider
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
    final connection =
        ref.watch(qbittorrentConnectionProvider(widget.source.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          // 顶部栏
          _buildHeader(context, isDark, connection),
          // 主体内容
          Expanded(
            child: _buildBody(context, isDark, connection),
          ),
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
    final transferInfo =
        ref.watch(qbTransferInfoAutoRefreshProvider(widget.source.id));

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
                  // 更多操作菜单
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: isDark ? AppColors.darkOnSurface : null,
                    ),
                    onSelected: (value) => _handleMenuAction(value),
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
    if (connection == null ||
        connection.status == QBConnectionStatus.connecting) {
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
            Text(
              '连接失败',
              style: context.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                connection.errorMessage ?? '未知错误',
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: Colors.red,
                ),
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

    // 已连接，显示 Torrent 列表
    return _TorrentList(
      sourceId: widget.source.id,
      isDark: isDark,
    );
  }

  void _handleMenuAction(String action) {
    final actions = ref.read(qbittorrentActionsProvider(widget.source.id));

    switch (action) {
      case 'pause_all':
        actions.pauseAll();
      case 'resume_all':
        actions.resumeAll();
      case 'refresh':
        ref.invalidate(qbittorrentAutoRefreshProvider(widget.source.id));
        ref.invalidate(qbTransferInfoAutoRefreshProvider(widget.source.id));
    }
  }

  void _showAddTorrentDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _AddTorrentDialog(
        sourceId: widget.source.id,
      ),
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
  });

  final IconData icon;
  final String label;
  final int speed;
  final int total;
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
                  '$label: ${_formatSize(total)}',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
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
  const _TorrentList({
    required this.sourceId,
    required this.isDark,
  });

  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final torrents = ref.watch(qbittorrentAutoRefreshProvider(sourceId));

    if (torrents.isEmpty) {
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
              child: const Icon(
                Icons.download_done,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '暂无下载任务',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '点击右下角按钮添加任务',
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

    // 分类 Torrent
    final downloading = torrents.where((t) => t.isDownloading).toList();
    final seeding = torrents.where((t) => t.isUploading && t.isCompleted).toList();
    final paused = torrents.where((t) => t.isPaused).toList();
    final completed = torrents
        .where((t) => t.isCompleted && !t.isUploading && !t.isPaused)
        .toList();
    final errored = torrents.where((t) => t.hasError).toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(qbittorrentAutoRefreshProvider(sourceId));
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (downloading.isNotEmpty) ...[
            _buildSectionHeader(context, '下载中', Icons.downloading, downloading.length, isDark),
            const SizedBox(height: AppSpacing.sm),
            ...downloading.map((t) => _TorrentTile(
                  torrent: t,
                  sourceId: sourceId,
                  isDark: isDark,
                )),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (seeding.isNotEmpty) ...[
            _buildSectionHeader(context, '做种中', Icons.upload, seeding.length, isDark),
            const SizedBox(height: AppSpacing.sm),
            ...seeding.map((t) => _TorrentTile(
                  torrent: t,
                  sourceId: sourceId,
                  isDark: isDark,
                )),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (paused.isNotEmpty) ...[
            _buildSectionHeader(context, '已暂停', Icons.pause_circle, paused.length, isDark),
            const SizedBox(height: AppSpacing.sm),
            ...paused.map((t) => _TorrentTile(
                  torrent: t,
                  sourceId: sourceId,
                  isDark: isDark,
                )),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (completed.isNotEmpty) ...[
            _buildSectionHeader(context, '已完成', Icons.check_circle, completed.length, isDark),
            const SizedBox(height: AppSpacing.sm),
            ...completed.map((t) => _TorrentTile(
                  torrent: t,
                  sourceId: sourceId,
                  isDark: isDark,
                )),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (errored.isNotEmpty) ...[
            _buildSectionHeader(context, '出错', Icons.error, errored.length, isDark),
            const SizedBox(height: AppSpacing.sm),
            ...errored.map((t) => _TorrentTile(
                  torrent: t,
                  sourceId: sourceId,
                  isDark: isDark,
                )),
          ],
          // 底部安全区域
          SizedBox(height: MediaQuery.of(context).padding.bottom + 80),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
    int count,
    bool isDark,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: context.textTheme.titleSmall?.copyWith(
            color: isDark
                ? AppColors.darkOnSurfaceVariant
                : AppColors.lightOnSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count.toString(),
            style: context.textTheme.labelSmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
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
                        Text(
                          _formatSize(torrent.size),
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 快捷操作按钮
                  _buildQuickAction(context, ref),
                ],
              ),
              // 进度条（仅下载中显示）
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
                    // 速度
                    if (torrent.dlSpeed > 0 || torrent.upSpeed > 0)
                      Row(
                        children: [
                          if (torrent.dlSpeed > 0) ...[
                            Icon(
                              Icons.arrow_downward,
                              size: 12,
                              color: AppColors.success,
                            ),
                            Text(
                              _formatSpeed(torrent.dlSpeed),
                              style: context.textTheme.labelSmall?.copyWith(
                                color: AppColors.success,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (torrent.upSpeed > 0) ...[
                            Icon(
                              Icons.arrow_upward,
                              size: 12,
                              color: AppColors.primary,
                            ),
                            Text(
                              _formatSpeed(torrent.upSpeed),
                              style: context.textTheme.labelSmall?.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ],
                      )
                    else
                      const SizedBox.shrink(),
                    // 进度
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
                    Icon(
                      Icons.arrow_upward,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatSpeed(torrent.upSpeed),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.sync,
                      size: 14,
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '分享率: ${torrent.ratio?.toStringAsFixed(2) ?? '-'}',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
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
    if (torrent.hasError) {
      return (AppColors.error, Icons.error);
    }
    if (torrent.isPaused) {
      return (AppColors.warning, Icons.pause_circle);
    }
    if (torrent.isDownloading) {
      return (AppColors.success, Icons.downloading);
    }
    if (torrent.isUploading) {
      return (AppColors.primary, Icons.upload);
    }
    if (torrent.isCompleted) {
      return (AppColors.success, Icons.check_circle);
    }
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
    // 简单显示详情信息
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
            // 拖动指示器
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
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _DetailItem(label: '大小', value: _formatSize(torrent.size)),
            _DetailItem(
              label: '进度',
              value: '${(torrent.progress * 100).toStringAsFixed(1)}%',
            ),
            _DetailItem(label: '状态', value: torrent.state),
            if (torrent.dlSpeed > 0)
              _DetailItem(label: '下载速度', value: _formatSpeed(torrent.dlSpeed)),
            if (torrent.upSpeed > 0)
              _DetailItem(label: '上传速度', value: _formatSpeed(torrent.upSpeed)),
            if (torrent.ratio != null)
              _DetailItem(
                label: '分享率',
                value: torrent.ratio!.toStringAsFixed(2),
              ),
            if (torrent.numSeeds != null)
              _DetailItem(label: '种子数', value: torrent.numSeeds.toString()),
            if (torrent.numLeechers != null)
              _DetailItem(label: '下载者', value: torrent.numLeechers.toString()),
            if (torrent.category != null && torrent.category!.isNotEmpty)
              _DetailItem(label: '分类', value: torrent.category!),
            if (torrent.savePath != null)
              _DetailItem(label: '保存路径', value: torrent.savePath!),
            if (torrent.addedOn != null)
              _DetailItem(
                label: '添加时间',
                value: DateTime.fromMillisecondsSinceEpoch(
                  torrent.addedOn! * 1000,
                ).toString().substring(0, 19),
              ),
            const SizedBox(height: 16),
            // 操作按钮
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
    final actions = ref.read(qbittorrentActionsProvider(sourceId));

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
              leading: Icon(
                torrent.isPaused ? Icons.play_arrow : Icons.pause,
              ),
              title: Text(torrent.isPaused ? '继续' : '暂停'),
              onTap: () {
                Navigator.pop(context);
                if (torrent.isPaused) {
                  actions.resume([torrent.hash]);
                } else {
                  actions.pause([torrent.hash]);
                }
              },
            ),
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

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref, {
    required bool deleteFiles,
  }) {
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
              ref
                  .read(qbittorrentActionsProvider(sourceId))
                  .delete([torrent.hash], deleteFiles: deleteFiles);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 详情项
class _DetailItem extends StatelessWidget {
  const _DetailItem({
    required this.label,
    required this.value,
  });

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
          Expanded(
            child: Text(
              value,
              style: context.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                if (value == null || value.isEmpty) {
                  return '请输入链接';
                }
                if (!value.startsWith('magnet:') &&
                    !value.startsWith('http://') &&
                    !value.startsWith('https://')) {
                  return '请输入有效的 Magnet 链接或 HTTP URL';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _paused,
              onChanged: (value) {
                setState(() {
                  _paused = value ?? false;
                });
              },
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

    setState(() {
      _isLoading = true;
    });

    try {
      await ref.read(qbittorrentActionsProvider(widget.sourceId)).addTorrent(
            _controller.text.trim(),
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
          SnackBar(
            content: Text('添加失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

// === 工具函数 ===

String _formatSpeed(int bytesPerSecond) {
  if (bytesPerSecond < 1024) {
    return '$bytesPerSecond B/s';
  } else if (bytesPerSecond < 1024 * 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  } else if (bytesPerSecond < 1024 * 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  } else {
    return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  } else if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  } else if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  } else if (bytes < 1024 * 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  } else {
    return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
  }
}
