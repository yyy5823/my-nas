import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/file_browser/presentation/pages/file_browser_page.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/shared/providers/theme_provider.dart';
import 'package:my_nas/shared/widgets/download_manager_sheet.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MinePage extends ConsumerWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connections = ref.watch(activeConnectionsProvider);
    final connectedCount = connections.values
        .where((c) => c.status == SourceStatus.connected)
        .length;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: CustomScrollView(
        slivers: [
          // 顶部头像区域
          SliverToBoxAdapter(
            child: _buildHeader(context, isDark, connectedCount, connections.length),
          ),
          // 快捷功能
          SliverToBoxAdapter(
            child: _buildQuickActions(context, isDark),
          ),
          // 设置列表
          SliverPadding(
            padding: AppSpacing.paddingMd,
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 外观设置
                _buildSectionHeader(context, '外观', Icons.palette_outlined, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  children: [
                    _buildSettingsTile(
                      context,
                      isDark,
                      icon: Icons.brightness_6_rounded,
                      iconColor: AppColors.primary,
                      title: '主题模式',
                      subtitle: _getThemeModeText(themeMode),
                      onTap: () => _showThemeModeDialog(context, ref, themeMode, isDark),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // 连接设置
                _buildSectionHeader(context, '连接', Icons.lan_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  children: [
                    _buildSettingsTile(
                      context,
                      isDark,
                      icon: Icons.storage_rounded,
                      iconColor: AppColors.info,
                      title: '连接源',
                      subtitle: '管理 NAS、WebDAV、SMB 等连接',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
                      ),
                    ),
                    _buildDivider(isDark),
                    _buildSettingsTile(
                      context,
                      isDark,
                      icon: Icons.folder_special_rounded,
                      iconColor: AppColors.accent,
                      title: '媒体库',
                      subtitle: '配置视频、音乐、漫画等目录',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => const MediaLibraryPage()),
                      ),
                    ),
                    _buildDivider(isDark),
                    _buildConnectionStatusTile(context, ref, isDark),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // 视频设置
                _buildSectionHeader(context, '视频', Icons.movie_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  children: [
                    _TmdbApiKeyTile(isDark: isDark),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // 关于
                _buildSectionHeader(context, '关于', Icons.info_outline_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  children: [
                    _VersionTile(isDark: isDark),
                    _buildDivider(isDark),
                    _LicenseTile(isDark: isDark),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxxl),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, int connectedCount, int totalCount) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, context.padding.top + 20, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [AppColors.darkSurface, AppColors.darkBackground]
              : [AppColors.primary.withValues(alpha: 0.1), Colors.white],
        ),
      ),
      child: Row(
        children: [
          // 头像
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.cloud_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MyNAS',
                  style: context.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : null,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: connectedCount > 0 ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      connectedCount > 0
                          ? '$connectedCount / $totalCount 已连接'
                          : '未连接',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: _QuickActionCard(
              icon: Icons.folder_rounded,
              label: '文件管理',
              color: AppColors.fileFolder,
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const FileBrowserPage()),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickActionCard(
              icon: Icons.download_rounded,
              label: '下载管理',
              color: AppColors.primary,
              isDark: isDark,
              onTap: () => showDownloadManager(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _QuickActionCard(
              icon: Icons.storage_rounded,
              label: '连接源',
              color: AppColors.info,
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, bool isDark) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: context.textTheme.titleSmall?.copyWith(
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard(
    BuildContext context,
    bool isDark, {
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
            : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : AppColors.lightOutline.withValues(alpha: 0.3),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: children,
        ),
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Color? titleColor,
    bool showChevron = true,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: titleColor ??
                            (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (showChevron && onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Divider(
        height: 1,
        color: isDark
            ? AppColors.darkOutline.withValues(alpha: 0.2)
            : AppColors.lightOutline.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _buildConnectionStatusTile(BuildContext context, WidgetRef ref, bool isDark) {
    final connections = ref.watch(activeConnectionsProvider);
    final connectedCount = connections.values
        .where((c) => c.status == SourceStatus.connected)
        .length;
    final totalCount = connections.length;

    final statusText = totalCount == 0
        ? '未配置连接源'
        : '$connectedCount / $totalCount 已连接';
    final statusColor = connectedCount == 0
        ? AppColors.warning
        : connectedCount == totalCount
            ? Colors.green
            : AppColors.accent;

    return _buildSettingsTile(
      context,
      isDark,
      icon: connectedCount > 0 ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
      iconColor: statusColor,
      title: '连接状态',
      subtitle: statusText,
      showChevron: false,
    );
  }

  String _getThemeModeText(ThemeMode mode) => switch (mode) {
        ThemeMode.system => '跟随系统',
        ThemeMode.light => '浅色模式',
        ThemeMode.dark => '深色模式',
      };

  void _showThemeModeDialog(
    BuildContext context,
    WidgetRef ref,
    ThemeMode currentMode,
    bool isDark,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface.withValues(alpha: 0.95)
                  : AppColors.lightSurface.withValues(alpha: 0.98),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                          : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      '选择主题',
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                  ),
                  for (final mode in ThemeMode.values)
                    _buildThemeOption(context, ref, mode, currentMode, isDark),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context,
    WidgetRef ref,
    ThemeMode mode,
    ThemeMode currentMode,
    bool isDark,
  ) {
    final isSelected = mode == currentMode;
    final icon = switch (mode) {
      ThemeMode.system => Icons.brightness_auto_rounded,
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(themeModeProvider.notifier).setThemeMode(mode);
          Navigator.pop(context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant)
                          .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  _getThemeModeText(mode),
                  style: context.textTheme.bodyLarge?.copyWith(
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryGradient,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 快捷功能卡片
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : AppColors.lightOutline.withValues(alpha: 0.3),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 版本号组件
class _VersionTile extends StatefulWidget {
  const _VersionTile({required this.isDark});

  final bool isDark;

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  String _version = '加载中...';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = packageInfo.version;
        _buildNumber = packageInfo.buildNumber;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.info_rounded,
              color: AppColors.secondary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '版本',
                  style: context.textTheme.bodyLarge?.copyWith(
                    color: widget.isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _buildNumber.isNotEmpty ? '$_version ($_buildNumber)' : _version,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: widget.isDark
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

/// 开源许可组件
class _LicenseTile extends StatefulWidget {
  const _LicenseTile({required this.isDark});

  final bool isDark;

  @override
  State<_LicenseTile> createState() => _LicenseTileState();
}

class _LicenseTileState extends State<_LicenseTile> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = packageInfo.version;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          showLicensePage(
            context: context,
            applicationName: 'MyNAS',
            applicationVersion: _version.isNotEmpty ? _version : null,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.tertiary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.description_rounded,
                  color: AppColors.tertiary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  '开源许可',
                  style: context.textTheme.bodyLarge?.copyWith(
                    color: widget.isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: widget.isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// TMDB API Key 设置项
class _TmdbApiKeyTile extends StatefulWidget {
  const _TmdbApiKeyTile({required this.isDark});

  final bool isDark;

  @override
  State<_TmdbApiKeyTile> createState() => _TmdbApiKeyTileState();
}

class _TmdbApiKeyTileState extends State<_TmdbApiKeyTile> {
  final _tmdbService = TmdbService.instance;
  bool _hasApiKey = false;

  @override
  void initState() {
    super.initState();
    _loadApiKeyStatus();
  }

  Future<void> _loadApiKeyStatus() async {
    final box = await Hive.openBox<String>('settings');
    final apiKey = box.get('tmdb_api_key', defaultValue: '');
    if (apiKey != null && apiKey.isNotEmpty) {
      _tmdbService.setApiKey(apiKey);
    }
    setState(() => _hasApiKey = _tmdbService.hasApiKey);
  }

  Future<void> _showApiKeyDialog() async {
    final controller = TextEditingController();
    final box = await Hive.openBox<String>('settings');
    controller.text = box.get('tmdb_api_key', defaultValue: '') ?? '';

    if (!mounted) return;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'TMDB API Key',
          style: TextStyle(
            color: widget.isDark ? AppColors.darkOnSurface : Colors.black87,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '配置 TMDB API Key 后，可以自动获取电影和电视剧的海报、评分、简介等信息。',
              style: TextStyle(
                fontSize: 14,
                color: widget.isDark ? AppColors.darkOnSurfaceVariant : Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: '请输入 TMDB API Key',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: widget.isDark
                    ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                    : Colors.grey[100],
              ),
              style: TextStyle(
                color: widget.isDark ? AppColors.darkOnSurface : Colors.black87,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
          if (_hasApiKey)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text(
                '清除',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result != null) {
      await box.put('tmdb_api_key', result);
      if (result.isNotEmpty) {
        _tmdbService.setApiKey(result);
      } else {
        _tmdbService.setApiKey('');
      }
      setState(() => _hasApiKey = result.isNotEmpty);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.isEmpty ? 'API Key 已清除' : 'API Key 已保存'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showApiKeyDialog,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.fileVideo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.api_rounded,
                  color: AppColors.fileVideo,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TMDB API Key',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: widget.isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _hasApiKey ? '已配置' : '未配置 (无法获取影片信息)',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: _hasApiKey
                            ? Colors.green
                            : (widget.isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              if (_hasApiKey)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 14, color: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        '已启用',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: widget.isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
