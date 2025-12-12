import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/shared/providers/language_preference_provider.dart';
import 'package:my_nas/shared/providers/theme_provider.dart';
import 'package:my_nas/shared/services/download_service.dart';
import 'package:my_nas/shared/widgets/download_manager_sheet.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: CustomScrollView(
        slivers: [
          // 自定义 AppBar
          SliverAppBar(
            expandedHeight: 80,
            pinned: true,
            backgroundColor: isDark ? AppColors.darkSurface : null,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                '设置',
                style: TextStyle(
                  color: isDark ? AppColors.darkOnSurface : null,
                  fontWeight: FontWeight.bold,
                ),
              ),
              titlePadding: const EdgeInsets.only(left: 16, bottom: 12),
            ),
          ),
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

                const SizedBox(height: AppSpacing.xl),

                // 下载设置
                _buildSectionHeader(context, '下载', Icons.download_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  children: [
                    _buildSettingsTile(
                      context,
                      isDark,
                      icon: Icons.download_rounded,
                      iconColor: AppColors.accent,
                      title: '下载管理',
                      subtitle: '查看和管理下载任务',
                      onTap: () => showDownloadManager(context),
                    ),
                    _buildDivider(isDark),
                    FutureBuilder<String>(
                      future: downloadService.downloadDirectory,
                      builder: (context, snapshot) => _buildSettingsTile(
                        context,
                        isDark,
                        icon: Icons.folder_rounded,
                        iconColor: AppColors.fileFolder,
                        title: '下载目录',
                        subtitle: snapshot.data ?? '加载中...',
                        showChevron: false,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.xl),

                // 视频设置
                _buildSectionHeader(context, '视频', Icons.movie_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  children: [
                    _TmdbApiKeyTile(isDark: isDark),
                    _buildDivider(isDark),
                    _LanguagePreferenceTile(isDark: isDark),
                  ],
                ),

                const SizedBox(height: AppSpacing.xl),

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

                const SizedBox(height: AppSpacing.xl),

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

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, bool isDark) => Row(
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

  Widget _buildSettingsCard(
    BuildContext context,
    bool isDark, {
    required List<Widget> children,
  }) => DecoratedBox(
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
  }) => Material(
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

  Widget _buildDivider(bool isDark) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Divider(
        height: 1,
        color: isDark
            ? AppColors.darkOutline.withValues(alpha: 0.2)
            : AppColors.lightOutline.withValues(alpha: 0.3),
      ),
    );

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
      builder: (context) => _buildBottomSheet(
        context,
        isDark,
        title: '选择主题',
        children: [
          for (final mode in ThemeMode.values)
            _buildOptionTile(
              context,
              isDark,
              icon: switch (mode) {
                ThemeMode.system => Icons.brightness_auto_rounded,
                ThemeMode.light => Icons.light_mode_rounded,
                ThemeMode.dark => Icons.dark_mode_rounded,
              },
              title: _getThemeModeText(mode),
              isSelected: currentMode == mode,
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(mode);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet(
    BuildContext context,
    bool isDark, {
    required String title,
    required List<Widget> children,
  }) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurface.withValues(alpha: 0.95)
                : AppColors.lightSurface.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: isDark ? AppColors.glassStroke : AppColors.lightOutline.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖动指示器
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
                    title,
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                ),
                ...children,
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );

  Widget _buildOptionTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
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
                  title,
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
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
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
      ),
    );
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
  Widget build(BuildContext context) => Material(
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

/// TMDB API Key 设置项
class _TmdbApiKeyTile extends StatefulWidget {
  const _TmdbApiKeyTile({required this.isDark});

  final bool isDark;

  @override
  State<_TmdbApiKeyTile> createState() => _TmdbApiKeyTileState();
}

class _TmdbApiKeyTileState extends State<_TmdbApiKeyTile> {
  final _tmdbService = TmdbService();
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
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                // 打开 TMDB 网站
              },
              child: Text(
                '前往 themoviedb.org 申请免费 API Key',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.primary,
                  decoration: TextDecoration.underline,
                ),
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
  Widget build(BuildContext context) => Material(
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

/// 语言偏好设置组件
class _LanguagePreferenceTile extends ConsumerWidget {
  const _LanguagePreferenceTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(languagePreferenceProvider);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showLanguageSettingsSheet(context, ref),
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
                  color: AppColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.language_rounded,
                  color: AppColors.info,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '语言偏好',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getPreferenceSummary(preference),
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
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

  String _getPreferenceSummary(LanguagePreference preference) {
    final isAllAuto = preference.audioLanguages.length == 1 &&
        preference.audioLanguages.first == LanguageOption.auto &&
        preference.subtitleLanguages.length == 1 &&
        preference.subtitleLanguages.first == LanguageOption.auto &&
        preference.metadataLanguages.length == 1 &&
        preference.metadataLanguages.first == LanguageOption.auto;

    if (isAllAuto) {
      return '全部自动';
    }

    final parts = <String>[];
    if (preference.metadataLanguages.first != LanguageOption.auto) {
      parts.add('元数据: ${_formatLanguageList(preference.metadataLanguages)}');
    }
    if (preference.audioLanguages.first != LanguageOption.auto) {
      parts.add('音频: ${_formatLanguageList(preference.audioLanguages)}');
    }
    if (preference.subtitleLanguages.first != LanguageOption.auto) {
      parts.add('字幕: ${_formatLanguageList(preference.subtitleLanguages)}');
    }

    return parts.isEmpty ? '全部自动' : parts.join(' | ');
  }

  String _formatLanguageList(List<LanguageOption> languages) {
    if (languages.length == 1) {
      return languages.first.displayName;
    }
    return languages.map((e) => e.displayName).take(2).join(' > ') +
        (languages.length > 2 ? '...' : '');
  }

  void _showLanguageSettingsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _LanguageSettingsSheet(isDark: isDark),
    );
  }
}

/// 语言设置底部弹窗
class _LanguageSettingsSheet extends ConsumerStatefulWidget {
  const _LanguageSettingsSheet({required this.isDark});

  final bool isDark;

  @override
  ConsumerState<_LanguageSettingsSheet> createState() => _LanguageSettingsSheetState();
}

class _LanguageSettingsSheetState extends ConsumerState<_LanguageSettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(languagePreferenceProvider);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.isDark
                ? AppColors.darkSurface.withValues(alpha: 0.95)
                : AppColors.lightSurface.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: widget.isDark ? AppColors.glassStroke : AppColors.lightOutline.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖动指示器
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                          : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      '语言偏好设置',
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: widget.isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Text(
                      '设置音频、字幕和元数据的语言优先级，可添加多个语言并拖拽调整顺序。',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: widget.isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // 元数据语言
                  _buildLanguagePriorityList(
                    context,
                    type: LanguageType.metadata,
                    title: '元数据语言',
                    subtitle: '影片标题、简介、演员信息',
                    icon: Icons.description_rounded,
                    iconColor: AppColors.primary,
                    languages: preference.metadataLanguages,
                    availableLanguages: LanguageOption.metadataLanguages,
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // 音频语言
                  _buildLanguagePriorityList(
                    context,
                    type: LanguageType.audio,
                    title: '音频语言',
                    subtitle: '默认播放的音轨语言',
                    icon: Icons.audiotrack_rounded,
                    iconColor: AppColors.accent,
                    languages: preference.audioLanguages,
                    availableLanguages: LanguageOption.audioSubtitleLanguages,
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // 字幕语言
                  _buildLanguagePriorityList(
                    context,
                    type: LanguageType.subtitle,
                    title: '字幕语言',
                    subtitle: '默认显示的字幕语言',
                    icon: Icons.subtitles_rounded,
                    iconColor: AppColors.fileVideo,
                    languages: preference.subtitleLanguages,
                    availableLanguages: LanguageOption.audioSubtitleLanguages,
                  ),

                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguagePriorityList(
    BuildContext context, {
    required LanguageType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required List<LanguageOption> languages,
    required List<LanguageOption> availableLanguages,
  }) {
    // 获取可添加的语言（排除已选的）
    final addableLanguages = availableLanguages
        .where((lang) => !languages.contains(lang))
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.isDark
              ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
              : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : AppColors.lightOutline.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 18),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: widget.isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: widget.isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 分割线
            Divider(
              height: 1,
              color: widget.isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : AppColors.lightOutline.withValues(alpha: 0.3),
            ),

            // 已选语言列表（可拖拽排序）
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: languages.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) {
                  newIndex -= 1;
                }
                ref.read(languagePreferenceProvider.notifier)
                    .reorderLanguages(type, oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final lang = languages[index];
                final canRemove = languages.length > 1;

                return Material(
                  key: ValueKey('${type.name}_${lang.code}'),
                  color: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        // 优先级序号
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: iconColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),

                        // 语言名称
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lang.displayName,
                                style: context.textTheme.bodyMedium?.copyWith(
                                  color: widget.isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (lang.nativeName != lang.displayName)
                                Text(
                                  lang.nativeName,
                                  style: context.textTheme.bodySmall?.copyWith(
                                    color: widget.isDark
                                        ? AppColors.darkOnSurfaceVariant
                                        : AppColors.lightOnSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // 删除按钮
                        if (canRemove)
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: widget.isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : AppColors.lightOnSurfaceVariant,
                            ),
                            onPressed: () {
                              ref.read(languagePreferenceProvider.notifier)
                                  .removeLanguage(type, lang);
                            },
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),

                        // 拖拽手柄
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.drag_handle_rounded,
                              size: 20,
                              color: widget.isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // 添加语言按钮
            if (addableLanguages.isNotEmpty)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showAddLanguageSheet(context, type, addableLanguages),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '添加语言',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAddLanguageSheet(
    BuildContext context,
    LanguageType type,
    List<LanguageOption> availableLanguages,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? AppColors.darkSurface.withValues(alpha: 0.95)
                  : AppColors.lightSurface.withValues(alpha: 0.98),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖动指示器
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                        : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    '添加语言',
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: widget.isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: availableLanguages.length,
                    itemBuilder: (context, index) {
                      final option = availableLanguages[index];

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            ref.read(languagePreferenceProvider.notifier)
                                .addLanguage(type, option);
                            Navigator.pop(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        option.displayName,
                                        style: context.textTheme.bodyLarge?.copyWith(
                                          color: widget.isDark
                                              ? AppColors.darkOnSurface
                                              : AppColors.lightOnSurface,
                                        ),
                                      ),
                                      if (option.nativeName != option.displayName) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          option.nativeName,
                                          style: context.textTheme.bodySmall?.copyWith(
                                            color: widget.isDark
                                                ? AppColors.darkOnSurfaceVariant
                                                : AppColors.lightOnSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.add_rounded,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
