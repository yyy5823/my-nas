import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/downloader/presentation/pages/downloader_list_page.dart';
import 'package:my_nas/features/media_management/presentation/pages/media_management_list_page.dart';
import 'package:my_nas/features/media_tracking/presentation/pages/media_tracking_list_page.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/presentation/pages/music_scraper_sources_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_scraper_provider.dart';
import 'package:my_nas/features/pt_sites/presentation/pages/pt_sites_list_page.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/service_sources_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/presentation/pages/scraper_sources_page.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart';
import 'package:my_nas/shared/providers/download_provider.dart';
import 'package:my_nas/shared/providers/language_preference_provider.dart';
import 'package:my_nas/shared/providers/theme_provider.dart';
import 'package:my_nas/shared/services/download_service.dart';
import 'package:my_nas/shared/widgets/download_manager_sheet.dart';
import 'package:my_nas/shared/widgets/update_dialog.dart';
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
      body: Column(
        children: [
          // 固定的顶部头像区域
          _buildHeader(context, isDark, connectedCount, connections.length),
          // 可滚动的设置列表
          Expanded(
            child: ListView(
              padding: AppSpacing.paddingMd,
              children: [
                // 连接设置
                _buildSectionHeader(context, '连接', Icons.lan_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  children: [
                    _buildSourcesTile(context, ref, isDark),
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
                    _VideoScraperSourcesTile(isDark: isDark),
                    _buildDivider(isDark),
                    _SubtitleSourcesTile(isDark: isDark),
                    _buildDivider(isDark),
                    _LanguagePreferenceTile(isDark: isDark),
                    _buildDivider(isDark),
                    _MediaTrackingTile(isDark: isDark),
                    _buildDivider(isDark),
                    _MediaManagementTile(isDark: isDark),
                    _buildDivider(isDark),
                    _DownloaderTile(isDark: isDark),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // 音乐设置
                _buildSectionHeader(context, '音乐', Icons.music_note_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  children: [
                    _MusicScraperSourcesTile(isDark: isDark),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // 站点
                _buildSectionHeader(context, '站点', Icons.rss_feed_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  children: [
                    _PTSitesTile(isDark: isDark),
                  ],
                ),

                const SizedBox(height: AppSpacing.lg),

                // 传输
                _buildSectionHeader(context, '传输', Icons.swap_vert_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _TransferCard(isDark: isDark),

                const SizedBox(height: AppSpacing.lg),

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

                // 关于
                _buildSectionHeader(context, '关于', Icons.info_outline_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  children: [
                    _VersionTile(isDark: isDark),
                    _buildDivider(isDark),
                    CheckUpdateTile(isDark: isDark),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxxl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, int connectedCount, int totalCount) => Container(
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
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/logo.png',
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
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

  Widget _buildSourcesTile(BuildContext context, WidgetRef ref, bool isDark) {
    // 只统计存储类源的连接状态
    final storageSources = ref.watch(storageSourcesProvider);
    final connections = ref.watch(activeConnectionsProvider);
    final storageConnections = storageSources
        .map((s) => connections[s.id])
        .where((c) => c != null)
        .toList();
    final connectedCount = storageConnections
        .where((c) => c?.status == SourceStatus.connected)
        .length;
    final totalCount = storageSources.length;

    final statusColor = connectedCount == 0
        ? AppColors.warning
        : connectedCount == totalCount
            ? Colors.green
            : AppColors.accent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
        ),
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
                  Icons.storage_rounded,
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
                      '连接源',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理 NAS、WebDAV、SMB 等连接',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 连接状态徽章
              if (totalCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$connectedCount/$totalCount',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                )
              else
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
          child: DecoratedBox(
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
  Widget build(BuildContext context) => Padding(
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

/// 视频刮削源入口组件
class _VideoScraperSourcesTile extends ConsumerWidget {
  const _VideoScraperSourcesTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(scraperSourcesProvider);

    return sourcesAsync.when(
      data: (sources) {
        final enabledCount = sources.where((s) => s.isEnabled).length;
        // 使用所有可用刮削源类型数量作为总数
        final totalCount = ScraperType.values.length;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ScraperSourcesPage()),
            ),
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
                      Icons.video_library_rounded,
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
                          '刮削源',
                          style: context.textTheme.bodyLarge?.copyWith(
                            color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '管理 TMDB、豆瓣等视频刮削源',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (enabledCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$enabledCount/$totalCount',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                      ),
                    )
                  else
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
      },
      loading: () => _buildLoadingTile(context),
      error: (_, _) => _buildLoadingTile(context),
    );
  }

  Widget _buildLoadingTile(BuildContext context) => Padding(
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
                Icons.video_library_rounded,
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
                    '刮削源',
                    style: context.textTheme.bodyLarge?.copyWith(
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '加载中...',
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

/// 字幕源入口组件
class _SubtitleSourcesTile extends ConsumerWidget {
  const _SubtitleSourcesTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitleSources = ref.watch(subtitleSourcesProvider);
    final count = subtitleSources.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const ServiceSourcesPage(
              title: '字幕源',
              category: SourceCategory.subtitleSites,
              emptyIcon: Icons.subtitles_rounded,
              emptyTitle: '暂无字幕源',
              emptySubtitle: '添加 OpenSubtitles 等字幕源来下载字幕',
            ),
          ),
        ),
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
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.subtitles_rounded,
                  color: Colors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '字幕源',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理 OpenSubtitles 等字幕下载源',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                )
              else
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
}

/// 音乐刮削源入口组件
class _MusicScraperSourcesTile extends ConsumerWidget {
  const _MusicScraperSourcesTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(musicScraperSourcesProvider);
    final enabledCount = state.sources.where((s) => s.isEnabled).length;
    // 使用所有可用刮削源类型数量作为总数
    final totalCount = MusicScraperType.values.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const MusicScraperSourcesPage()),
        ),
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
                  color: AppColors.fileAudio.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.library_music_rounded,
                  color: AppColors.fileAudio,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '刮削源',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理 MusicBrainz、网易云等音乐刮削源',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabledCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$enabledCount/$totalCount',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                )
              else
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
}

/// 传输卡片组件 - 下载和同步合并在一个卡片中
class _TransferCard extends ConsumerWidget {
  const _TransferCard({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(downloadTasksProvider);

    return tasksAsync.when(
      data: (tasks) => _buildContent(context, tasks),
      loading: () => _buildContent(context, []),
      error: (_, _) => _buildContent(context, []),
    );
  }

  Widget _buildContent(BuildContext context, List<DownloadTask> tasks) {
    final downloading = tasks
        .where((t) =>
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.pending ||
            t.status == DownloadStatus.paused)
        .toList();
    final completed = tasks.where((t) => t.status == DownloadStatus.completed).toList();
    final hasActiveTasks = downloading.isNotEmpty;

    return DecoratedBox(
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
          children: [
            // 下载项
            _buildTransferItem(
              context,
              icon: Icons.download_rounded,
              label: '下载',
              count: downloading.length,
              subtitle: hasActiveTasks
                  ? '${downloading.length} 个任务进行中'
                  : completed.isEmpty
                      ? '暂无下载任务'
                      : '${completed.length} 个已完成',
              color: AppColors.primary,
              isActive: hasActiveTasks,
            ),
            // 分隔线
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Divider(
                height: 1,
                color: isDark
                    ? AppColors.darkOutline.withValues(alpha: 0.2)
                    : AppColors.lightOutline.withValues(alpha: 0.3),
              ),
            ),
            // 同步项
            _buildTransferItem(
              context,
              icon: Icons.sync_rounded,
              label: '同步',
              count: 0,
              subtitle: '暂无同步任务',
              color: AppColors.accent,
              isActive: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int count,
    required String subtitle,
    required Color color,
    required bool isActive,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showDownloadManager(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                // 图标
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: isActive ? 0.15 : 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        color: isActive ? color : color,
                        size: 20,
                      ),
                    ),
                    if (count > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            count > 99 ? '99+' : count.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                // 标题和副标题
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: context.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (isActive) ...[
                            SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              subtitle,
                              style: context.textTheme.bodySmall?.copyWith(
                                color: isActive
                                    ? color
                                    : (isDark
                                        ? AppColors.darkOnSurfaceVariant
                                        : AppColors.lightOnSurfaceVariant),
                                fontWeight: isActive ? FontWeight.w500 : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 右侧箭头
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

/// 媒体追踪入口组件
class _MediaTrackingTile extends ConsumerWidget {
  const _MediaTrackingTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingSources = ref.watch(mediaTrackingSourcesProvider);
    final count = trackingSources.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const MediaTrackingListPage()),
        ),
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
                  color: Colors.purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.track_changes_rounded,
                  color: Colors.purple,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '媒体追踪',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理 Trakt 等媒体追踪工具',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.purple,
                    ),
                  ),
                )
              else
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
}

/// 媒体管理入口组件
class _MediaManagementTile extends ConsumerWidget {
  const _MediaManagementTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managementSources = ref.watch(mediaManagementSourcesProvider);
    final count = managementSources.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const MediaManagementListPage()),
        ),
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
                  color: Colors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.construction_rounded,
                  color: Colors.teal,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '媒体管理',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理 NASTool、MoviePilot 等工具',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal,
                    ),
                  ),
                )
              else
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
}

/// 下载器入口组件
class _DownloaderTile extends ConsumerWidget {
  const _DownloaderTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaderSources = ref.watch(downloadToolSourcesProvider);
    final count = downloaderSources.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const DownloaderListPage()),
        ),
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
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.download_for_offline_rounded,
                  color: Colors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '下载器',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理 qBittorrent、Transmission 等下载工具',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                )
              else
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
}

/// PT 站点入口组件
class _PTSitesTile extends ConsumerWidget {
  const _PTSitesTile({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ptSitesSources = ref.watch(ptSitesSourcesProvider);
    final count = ptSitesSources.length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const PTSitesListPage()),
        ),
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
                  color: Colors.indigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.rss_feed_rounded,
                  color: Colors.indigo,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PT 站点',
                      style: context.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '管理馒头等 PT 站点连接',
                      style: context.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.indigo,
                    ),
                  ),
                )
              else
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
    final metadata = preference.getPreferredLanguage(LanguageType.metadata);
    final audio = preference.getPreferredLanguage(LanguageType.audio);
    final subtitle = preference.getPreferredLanguage(LanguageType.subtitle);

    final isAllAuto = metadata == LanguageOption.auto &&
        audio == LanguageOption.auto &&
        subtitle == LanguageOption.auto;

    if (isAllAuto) {
      return '全部自动';
    }

    final parts = <String>[];
    if (metadata != LanguageOption.auto) {
      parts.add('元数据: ${metadata.displayName}');
    }
    if (audio != LanguageOption.auto) {
      parts.add('音频: ${audio.displayName}');
    }
    if (subtitle != LanguageOption.auto) {
      parts.add('字幕: ${subtitle.displayName}');
    }

    return parts.isEmpty ? '全部自动' : parts.join(' | ');
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
class _LanguageSettingsSheet extends ConsumerWidget {
  const _LanguageSettingsSheet({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(languagePreferenceProvider);

    return ClipRRect(
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
                    '语言偏好设置',
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Text(
                    '设置影片元数据、音频和字幕的默认显示语言',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // 元数据语言
                _buildLanguageDropdown(
                  context,
                  ref,
                  type: LanguageType.metadata,
                  title: '元数据语言',
                  subtitle: '影片标题、简介、演员信息',
                  icon: Icons.description_rounded,
                  iconColor: AppColors.primary,
                  currentValue: preference.getPreferredLanguage(LanguageType.metadata),
                  availableLanguages: LanguageOption.metadataLanguages,
                ),

                const SizedBox(height: AppSpacing.sm),

                // 音频语言
                _buildLanguageDropdown(
                  context,
                  ref,
                  type: LanguageType.audio,
                  title: '音频语言',
                  subtitle: '默认播放的音轨语言',
                  icon: Icons.audiotrack_rounded,
                  iconColor: AppColors.accent,
                  currentValue: preference.getPreferredLanguage(LanguageType.audio),
                  availableLanguages: LanguageOption.audioSubtitleLanguages,
                ),

                const SizedBox(height: AppSpacing.sm),

                // 字幕语言
                _buildLanguageDropdown(
                  context,
                  ref,
                  type: LanguageType.subtitle,
                  title: '字幕语言',
                  subtitle: '默认显示的字幕语言',
                  icon: Icons.subtitles_rounded,
                  iconColor: AppColors.fileVideo,
                  currentValue: preference.getPreferredLanguage(LanguageType.subtitle),
                  availableLanguages: LanguageOption.audioSubtitleLanguages,
                ),

                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageDropdown(
    BuildContext context,
    WidgetRef ref, {
    required LanguageType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required LanguageOption currentValue,
    required List<LanguageOption> availableLanguages,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : AppColors.lightOutline.withValues(alpha: 0.3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // 图标
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                // 标题和副标题
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // 下拉选择
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurface.withValues(alpha: 0.5)
                        : AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkOutline.withValues(alpha: 0.3)
                          : AppColors.lightOutline.withValues(alpha: 0.5),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<LanguageOption>(
                      value: currentValue,
                      isDense: true,
                      menuMaxHeight: 300, // 限制下拉菜单最大高度
                      icon: Icon(
                        Icons.expand_more_rounded,
                        size: 18,
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      dropdownColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                      borderRadius: BorderRadius.circular(12),
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                      items: availableLanguages.map((lang) => DropdownMenuItem(
                        value: lang,
                        child: Text(lang.displayName),
                      )).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          ref.read(languagePreferenceProvider.notifier)
                              .setLanguages(type, [value]);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
