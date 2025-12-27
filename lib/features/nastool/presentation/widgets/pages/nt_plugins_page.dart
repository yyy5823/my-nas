import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/common/nt_common_widgets.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

class NtPluginsPage extends ConsumerStatefulWidget {
  const NtPluginsPage({super.key, required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  ConsumerState<NtPluginsPage> createState() => _NtPluginsPageState();
}

class _NtPluginsPageState extends ConsumerState<NtPluginsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
            tabs: const [
              Tab(text: '已安装', icon: Icon(Icons.extension_rounded, size: 20)),
              Tab(text: '插件商店', icon: Icon(Icons.store_rounded, size: 20)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _InstalledPluginsTab(sourceId: widget.sourceId, isDark: widget.isDark),
              _PluginStoreTab(sourceId: widget.sourceId, isDark: widget.isDark),
            ],
          ),
        ),
      ],
    );
}

class _InstalledPluginsTab extends ConsumerWidget {
  const _InstalledPluginsTab({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pluginsAsync = ref.watch(nastoolPluginsProvider(sourceId));

    return pluginsAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(
        message: '加载失败: $e',
        isDark: isDark,
        onRetry: () => ref.invalidate(nastoolPluginsProvider(sourceId)),
      ),
      data: (plugins) {
        if (plugins.isEmpty) {
          return NtEmptyState(
            icon: Icons.extension_off_rounded,
            message: '暂无已安装插件\n前往插件商店安装',
            isDark: isDark,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolPluginsProvider(sourceId)),
          child: GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 350,
              childAspectRatio: 2.2,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
            ),
            itemCount: plugins.length,
            itemBuilder: (context, index) => _PluginCard(
              plugin: plugins[index],
              isDark: isDark,
              isInstalled: true,
              onUninstall: () => _confirmUninstall(context, plugins[index], ref),
            ),
          ),
        );
      },
    );
  }

  void _confirmUninstall(BuildContext context, NtPlugin plugin, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('卸载插件'),
        content: Text('确定要卸载插件「${plugin.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(nastoolActionsProvider(sourceId)).uninstallPlugin(plugin.id);
              ref.invalidate(nastoolPluginsProvider(sourceId));
              context.showSuccessToast('插件已卸载');
            },
            child: Text('卸载', style: TextStyle(color: NtColors.error)),
          ),
        ],
      ),
    );
  }
}

class _PluginStoreTab extends ConsumerWidget {
  const _PluginStoreTab({required this.sourceId, required this.isDark});
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appsAsync = ref.watch(nastoolPluginAppsProvider(sourceId));

    return appsAsync.when(
      loading: () => const NtLoading(),
      error: (e, _) => NtError(
        message: '加载失败: $e',
        isDark: isDark,
        onRetry: () => ref.invalidate(nastoolPluginAppsProvider(sourceId)),
      ),
      data: (apps) {
        if (apps.isEmpty) {
          return NtEmptyState(icon: Icons.store_rounded, message: '插件商店暂无可用插件', isDark: isDark);
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(nastoolPluginAppsProvider(sourceId)),
          child: GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 350,
              childAspectRatio: 2.2,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
            ),
            itemCount: apps.length,
            itemBuilder: (context, index) => _PluginAppCard(
              app: apps[index],
              isDark: isDark,
              onInstall: () => _installPlugin(context, apps[index], ref),
            ),
          ),
        );
      },
    );
  }

  void _installPlugin(BuildContext context, NtPluginApp app, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('安装插件'),
        content: Text('确定要安装插件「${app.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(nastoolActionsProvider(sourceId)).installPlugin(app.id);
              ref.invalidate(nastoolPluginsProvider(sourceId));
              context.showInfoToast('插件安装中...');
            },
            child: const Text('安装'),
          ),
        ],
      ),
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard({
    required this.plugin,
    required this.isDark,
    required this.isInstalled,
    this.onUninstall,
  });

  final NtPlugin plugin;
  final bool isDark;
  final bool isInstalled;
  final VoidCallback? onUninstall;

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [NtColors.primary, NtColors.primaryLight]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.extension_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    plugin.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: NtColors.onSurface(isDark),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plugin.description ?? '',
                    style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isInstalled)
              NtIconButton(
                icon: Icons.delete_rounded,
                isDark: isDark,
                onPressed: onUninstall ?? () {},
                tooltip: '卸载',
                color: NtColors.error,
              ),
          ],
        ),
      );
}

class _PluginAppCard extends StatelessWidget {
  const _PluginAppCard({required this.app, required this.isDark, this.onInstall});
  final NtPluginApp app;
  final bool isDark;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: NtColors.surfaceVariant(isDark),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.extension_rounded, color: NtColors.onSurfaceVariant(isDark), size: 24),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    app.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: NtColors.onSurface(isDark),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    app.description ?? '',
                    style: TextStyle(color: NtColors.onSurfaceVariant(isDark), fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            NtIconButton(
              icon: Icons.download_rounded,
              isDark: isDark,
              onPressed: onInstall ?? () {},
              tooltip: '安装',
              color: NtColors.success,
            ),
          ],
        ),
      );
}
