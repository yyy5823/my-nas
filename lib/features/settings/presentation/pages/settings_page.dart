import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/connection/presentation/providers/connection_provider.dart';
import 'package:my_nas/shared/providers/theme_provider.dart';
import 'package:my_nas/shared/services/download_service.dart';
import 'package:my_nas/shared/widgets/download_manager_sheet.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: AppSpacing.paddingMd,
        children: [
          // 外观设置
          _buildSectionHeader(context, '外观'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.brightness_6),
                  title: const Text('主题模式'),
                  subtitle: Text(_getThemeModeText(themeMode)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showThemeModeDialog(context, ref, themeMode),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 下载设置
          _buildSectionHeader(context, '下载'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('下载管理'),
                  subtitle: const Text('查看和管理下载任务'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showDownloadManager(context),
                ),
                FutureBuilder<String>(
                  future: downloadService.downloadDirectory,
                  builder: (context, snapshot) => ListTile(
                    leading: const Icon(Icons.folder),
                    title: const Text('下载目录'),
                    subtitle: Text(
                      snapshot.data ?? '加载中...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 连接设置
          _buildSectionHeader(context, '连接'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('NAS 连接'),
                  subtitle: const Text('管理 NAS 连接'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showConnectionInfo(context, ref),
                ),
                ListTile(
                  leading: Icon(
                    Icons.logout,
                    color: context.colorScheme.error,
                  ),
                  title: Text(
                    '断开连接',
                    style: TextStyle(color: context.colorScheme.error),
                  ),
                  onTap: () => _showDisconnectDialog(context, ref),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 关于
          _buildSectionHeader(context, '关于'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('版本'),
                  subtitle: const Text('1.0.0'),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('开源许可'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'MyNAS',
                      applicationVersion: '1.0.0',
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          title,
          style: context.textTheme.titleSmall?.copyWith(
            color: context.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  String _getThemeModeText(ThemeMode mode) => switch (mode) {
        ThemeMode.system => '跟随系统',
        ThemeMode.light => '浅色模式',
        ThemeMode.dark => '深色模式',
      };

  void _showThemeModeDialog(
    BuildContext context,
    WidgetRef ref,
    ThemeMode currentMode,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              RadioListTile<ThemeMode>(
                title: Text(_getThemeModeText(mode)),
                value: mode,
                groupValue: currentMode,
                onChanged: (value) {
                  if (value != null) {
                    ref.read(themeModeProvider.notifier).setThemeMode(value);
                  }
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showConnectionInfo(BuildContext context, WidgetRef ref) {
    final adapter = ref.read(activeAdapterProvider);
    if (adapter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未连接到 NAS')),
      );
      return;
    }

    final connection = adapter.connection;
    if (connection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无连接信息')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('连接信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('地址', connection.host),
            _buildInfoRow('端口', connection.port.toString()),
            _buildInfoRow('用户', connection.username),
            _buildInfoRow('类型', adapter.info.name),
            _buildInfoRow('SSL', connection.useSsl ? '是' : '否'),
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

  Widget _buildInfoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 60,
              child: Text(
                '$label:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  void _showDisconnectDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('断开连接'),
        content: const Text('确定要断开与 NAS 的连接吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(connectionStateProvider.notifier).disconnect();
              Navigator.pop(context);
              // 导航到连接页面
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: FilledButton.styleFrom(
              backgroundColor: context.colorScheme.error,
            ),
            child: const Text('断开'),
          ),
        ],
      ),
    );
  }
}
