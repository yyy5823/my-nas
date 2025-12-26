import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/common/nt_common_widgets.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';

class NtSettingsPage extends ConsumerStatefulWidget {
  const NtSettingsPage({super.key, required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  ConsumerState<NtSettingsPage> createState() => _NtSettingsPageState();
}

class _NtSettingsPageState extends ConsumerState<NtSettingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
      children: [
        ColoredBox(
          color: NtColors.surface(widget.isDark),
          child: TabBar(
            controller: _tabController,
            labelColor: NtColors.primary,
            unselectedLabelColor: NtColors.onSurfaceVariant(widget.isDark),
            indicatorColor: NtColors.primary,
            isScrollable: true,
            tabs: const [
              Tab(text: '系统', icon: Icon(Icons.settings_rounded, size: 20)),
              Tab(text: '服务', icon: Icon(Icons.miscellaneous_services_rounded, size: 20)),
              Tab(text: '系统进程', icon: Icon(Icons.memory_rounded, size: 20)),
              Tab(text: '日志', icon: Icon(Icons.article_rounded, size: 20)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _SystemInfoTab(sourceId: widget.sourceId, isDark: widget.isDark),
              _ServicesTab(sourceId: widget.sourceId, isDark: widget.isDark),
              _ProcessesTab(sourceId: widget.sourceId, isDark: widget.isDark),
              _LogsTab(sourceId: widget.sourceId, isDark: widget.isDark),
            ],
          ),
        ),
      ],
    );
}

class _SystemInfoTab extends ConsumerWidget {
  const _SystemInfoTab({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(nastoolSystemInfoProvider(sourceId));

    return infoAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(
        message: '加载失败: $e',
        isDark: isDark,
        onRetry: () => ref.invalidate(nastoolSystemInfoProvider(sourceId)),
      ),
      data: (info) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolSystemInfoProvider(sourceId)),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _buildSection(context, '版本信息', [
                _InfoRow(label: 'NASTool 版本', value: info.version ?? '-'),
                _InfoRow(label: '更新通道', value: info.updateChannel ?? '-'),
                _InfoRow(label: '最新版本', value: info.latestVersion ?? '-'),
              ]),
              const SizedBox(height: AppSpacing.md),
              _buildSection(context, '系统资源', [
                _ResourceRow(
                  icon: Icons.memory_rounded,
                  label: '内存使用',
                  value: '${info.memoryUsedPercent?.toStringAsFixed(1) ?? 0}%',
                  progress: (info.memoryUsedPercent ?? 0) / 100,
                  color: _getResourceColor(info.memoryUsedPercent ?? 0),
                ),
                const SizedBox(height: AppSpacing.md),
                _ResourceRow(
                  icon: Icons.developer_board_rounded,
                  label: 'CPU 使用',
                  value: '${info.cpuUsedPercent?.toStringAsFixed(1) ?? 0}%',
                  progress: (info.cpuUsedPercent ?? 0) / 100,
                  color: _getResourceColor(info.cpuUsedPercent ?? 0),
                ),
              ]),
              const SizedBox(height: AppSpacing.md),
              _buildSection(context, '存储空间', [
                if (info.totalSpace != null && info.freeSpace != null)
                  _StorageRow(
                    total: info.totalSpace!,
                    free: info.freeSpace!,
                    isDark: isDark,
                  ),
              ]),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: NtButton(
                      label: '重启服务',
                      icon: Icons.refresh_rounded,
                      isOutlined: true,
                      onPressed: () => _restartService(context, ref),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: NtButton(
                      label: '检查更新',
                      icon: Icons.system_update_rounded,
                      onPressed: () => _checkUpdate(context, ref),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) => NtCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: NtColors.onSurface(isDark),
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          ...children,
        ],
      ),
    );

  Color _getResourceColor(double percent) {
    if (percent >= 90) return NtColors.error;
    if (percent >= 70) return NtColors.warning;
    return NtColors.success;
  }

  void _restartService(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重启服务'),
        content: const Text('确定要重启 NASTool 服务吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(nastoolActionsProvider(sourceId)).restartService();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('服务重启中...')));
            },
            child: Text('重启', style: TextStyle(color: NtColors.warning)),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdate(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在检查更新...')));
    try {
      final hasUpdate = await ref.read(nastoolActionsProvider(sourceId)).checkUpdate();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hasUpdate ? '发现新版本可用' : '已是最新版本')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('检查更新失败: $e')));
      }
    }
  }
}

class _ServicesTab extends ConsumerWidget {
  const _ServicesTab({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(nastoolServicesProvider(sourceId));

    return servicesAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(
        message: '加载失败: $e',
        isDark: isDark,
        onRetry: () => ref.invalidate(nastoolServicesProvider(sourceId)),
      ),
      data: (services) {
        if (services.isEmpty) {
          return NtEmptyState(icon: Icons.miscellaneous_services_rounded, message: '暂无服务信息', isDark: isDark);
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolServicesProvider(sourceId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: services.length,
            itemBuilder: (context, index) => _ServiceCard(service: services[index], isDark: isDark),
          ),
        );
      },
    );
  }
}

class _ProcessesTab extends ConsumerWidget {
  const _ProcessesTab({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final processesAsync = ref.watch(nastoolProcessesProvider(sourceId));

    return processesAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(
        message: '加载失败: $e',
        isDark: isDark,
        onRetry: () => ref.invalidate(nastoolProcessesProvider(sourceId)),
      ),
      data: (processes) {
        if (processes.isEmpty) {
          return NtEmptyState(icon: Icons.memory_rounded, message: '暂无进程信息', isDark: isDark);
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolProcessesProvider(sourceId)),
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: processes.length,
            itemBuilder: (context, index) => _ProcessCard(process: processes[index], isDark: isDark),
          ),
        );
      },
    );
  }
}

class _LogsTab extends ConsumerStatefulWidget {
  const _LogsTab({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  ConsumerState<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends ConsumerState<_LogsTab> {
  String _logLevel = 'INFO';
  List<NtLogEntry>? _logs;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final logs = await ref.read(nastoolActionsProvider(widget.sourceId)).getLogs(level: _logLevel);
      setState(() {
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Text('日志级别:', style: TextStyle(color: NtColors.onSurfaceVariant(widget.isDark))),
              const SizedBox(width: AppSpacing.md),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'DEBUG', label: Text('Debug')),
                  ButtonSegment(value: 'INFO', label: Text('Info')),
                  ButtonSegment(value: 'WARNING', label: Text('Warning')),
                  ButtonSegment(value: 'ERROR', label: Text('Error')),
                ],
                selected: {_logLevel},
                onSelectionChanged: (selected) {
                  setState(() => _logLevel = selected.first);
                  _loadLogs();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildContent(),
        ),
      ],
    );

  Widget _buildContent() {
    if (_isLoading) {
      return const NtLoading();
    }

    if (_error != null) {
      return NtError(message: '加载失败: $_error', isDark: widget.isDark, onRetry: _loadLogs);
    }

    if (_logs == null || _logs!.isEmpty) {
      return NtEmptyState(icon: Icons.article_rounded, message: '暂无日志', isDark: widget.isDark);
    }

    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: _logs!.length,
        itemBuilder: (context, index) => _LogTile(log: _logs![index], isDark: widget.isDark),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ],
        ),
      );
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: color.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 48,
            child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          ),
        ],
      );
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({required this.total, required this.free, required this.isDark});
  final int total;
  final int free;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final used = total - free;
    final percent = total > 0 ? used / total : 0.0;
    final color = percent >= 0.9
        ? NtColors.error
        : percent >= 0.7
            ? NtColors.warning
            : NtColors.success;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('已用 ${NtFormatter.bytes(used)}', style: const TextStyle(fontSize: 12)),
            Text('总共 ${NtFormatter.bytes(total)}', style: const TextStyle(fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent,
            backgroundColor: color.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '剩余 ${NtFormatter.bytes(free)} (${((1 - percent) * 100).toStringAsFixed(1)}%)',
          style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 11),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.isDark});
  final NtService service;
  final bool isDark;

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _getStatusColor(service.status).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_getStatusIcon(service.status), color: _getStatusColor(service.status)),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: NtColors.onSurface(isDark),
                        ),
                  ),
                  if (service.description != null)
                    Text(
                      service.description!,
                      style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 12),
                    ),
                ],
              ),
            ),
            NtChip(
              label: _getStatusLabel(service.status),
              color: _getStatusColor(service.status),
            ),
          ],
        ),
      );

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'running':
      case 'active':
        return NtColors.success;
      case 'stopped':
      case 'inactive':
        return NtColors.error;
      case 'warning':
        return NtColors.warning;
      default:
        return NtColors.info;
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status?.toLowerCase()) {
      case 'running':
      case 'active':
        return Icons.check_circle_rounded;
      case 'stopped':
      case 'inactive':
        return Icons.cancel_rounded;
      case 'warning':
        return Icons.warning_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status?.toLowerCase()) {
      case 'running':
      case 'active':
        return '运行中';
      case 'stopped':
      case 'inactive':
        return '已停止';
      case 'warning':
        return '警告';
      default:
        return status ?? '未知';
    }
  }
}

class _ProcessCard extends StatelessWidget {
  const _ProcessCard({required this.process, required this.isDark});
  final NtProcess process;
  final bool isDark;

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: NtColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${process.pid}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: NtColors.info),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    process.name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: NtColors.onSurface(isDark),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('CPU: ${process.cpu?.toStringAsFixed(1) ?? 0}%', style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 12),
                      Text('内存: ${process.memory?.toStringAsFixed(1) ?? 0}%', style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log, required this.isDark});
  final NtLogEntry log;
  final bool isDark;

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getLevelColor(log.level).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                log.level,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _getLevelColor(log.level)),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.message,
                    style: TextStyle(fontSize: 11, color: NtColors.onSurface(isDark)),
                  ),
                  Text(
                    log.time,
                    style: TextStyle(fontSize: 9, color: NtColors.onSurfaceVariant(isDark)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Color _getLevelColor(String level) {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return NtColors.error;
      case 'WARNING':
        return NtColors.warning;
      case 'INFO':
        return NtColors.info;
      case 'DEBUG':
        return NtColors.onSurfaceVariant(isDark);
      default:
        return NtColors.info;
    }
  }
}
