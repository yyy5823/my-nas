import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/services/error_report/error_report_settings.dart';
import 'package:my_nas/core/services/error_report/error_report_settings_service.dart';

/// 日志上报设置页面
/// @author cq
/// @date 2025-12-28
class ErrorReportSettingsPage extends StatefulWidget {
  const ErrorReportSettingsPage({super.key});

  @override
  State<ErrorReportSettingsPage> createState() => _ErrorReportSettingsPageState();
}

class _ErrorReportSettingsPageState extends State<ErrorReportSettingsPage> {
  late ErrorReportSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = ErrorReportSettingsService.instance.settings;
  }

  Future<void> _updateSettings(ErrorReportSettings newSettings) async {
    setState(() {
      _settings = newSettings;
    });
    await ErrorReportSettingsService.instance.updateSettings(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkSurface : null,
        title: Text(
          '日志上报设置',
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? AppColors.darkOnSurface : null,
        ),
      ),
      body: ListView(
        padding: AppSpacing.paddingMd,
        children: [
          // 说明文字
          _buildInfoCard(context, isDark),
          const SizedBox(height: AppSpacing.lg),

          // 总开关
          _buildSectionHeader(context, '总开关', Icons.power_settings_new_rounded, isDark),
          const SizedBox(height: AppSpacing.sm),
          _buildSettingsCard(
            context,
            isDark,
            children: [
              _buildSwitchTile(
                context,
                isDark,
                icon: Icons.cloud_upload_rounded,
                iconColor: _settings.enabled ? AppColors.success : AppColors.error,
                title: '启用日志上报',
                subtitle: _settings.enabled ? '已开启，将上报错误日志' : '已关闭，不会上报任何数据',
                value: _settings.enabled,
                onChanged: (value) => _updateSettings(_settings.copyWith(enabled: value)),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // 字段开关（只有在总开关开启时才显示）
          if (_settings.enabled) ...[
            // 快捷操作
            _buildSectionHeader(context, '快捷操作', Icons.flash_on_rounded, isDark),
            const SizedBox(height: AppSpacing.sm),
            _buildSettingsCard(
              context,
              isDark,
              children: [
                _buildActionTile(
                  context,
                  isDark,
                  icon: Icons.check_circle_rounded,
                  iconColor: AppColors.success,
                  title: '全部开启',
                  subtitle: '开启所有字段的上报',
                  onTap: () async {
                    await ErrorReportSettingsService.instance.enableAllFields();
                    setState(() {
                      _settings = ErrorReportSettingsService.instance.settings;
                    });
                  },
                ),
                _buildDivider(isDark),
                _buildActionTile(
                  context,
                  isDark,
                  icon: Icons.cancel_rounded,
                  iconColor: AppColors.error,
                  title: '全部关闭',
                  subtitle: '关闭所有可选字段的上报',
                  onTap: () async {
                    await ErrorReportSettingsService.instance.disableAllFields();
                    setState(() {
                      _settings = ErrorReportSettingsService.instance.settings;
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // 设备信息
            _buildSectionHeader(context, '设备信息', Icons.phone_android_rounded, isDark),
            const SizedBox(height: AppSpacing.sm),
            _buildSettingsCard(
              context,
              isDark,
              children: [
                _buildSwitchTile(
                  context,
                  isDark,
                  icon: Icons.fingerprint_rounded,
                  iconColor: AppColors.primary,
                  title: '设备ID',
                  subtitle: '唯一标识设备的匿名ID',
                  value: _settings.includeDeviceId,
                  onChanged: (value) => _updateSettings(_settings.copyWith(includeDeviceId: value)),
                ),
                _buildDivider(isDark),
                _buildSwitchTile(
                  context,
                  isDark,
                  icon: Icons.phone_iphone_rounded,
                  iconColor: AppColors.accent,
                  title: '设备型号',
                  subtitle: '如 iPhone 15, Pixel 8',
                  value: _settings.includeDeviceModel,
                  onChanged: (value) => _updateSettings(_settings.copyWith(includeDeviceModel: value)),
                ),
                _buildDivider(isDark),
                _buildSwitchTile(
                  context,
                  isDark,
                  icon: Icons.business_rounded,
                  iconColor: AppColors.fileVideo,
                  title: '设备品牌',
                  subtitle: '如 Apple, Google, Samsung',
                  value: _settings.includeDeviceBrand,
                  onChanged: (value) => _updateSettings(_settings.copyWith(includeDeviceBrand: value)),
                ),
                _buildDivider(isDark),
                _buildSwitchTile(
                  context,
                  isDark,
                  icon: Icons.settings_rounded,
                  iconColor: AppColors.info,
                  title: '操作系统',
                  subtitle: '系统名称和版本号',
                  value: _settings.includeOsInfo,
                  onChanged: (value) => _updateSettings(_settings.copyWith(includeOsInfo: value)),
                ),
                _buildDivider(isDark),
                _buildSwitchTile(
                  context,
                  isDark,
                  icon: Icons.aspect_ratio_rounded,
                  iconColor: AppColors.tertiary,
                  title: '屏幕分辨率',
                  subtitle: '设备屏幕的分辨率',
                  value: _settings.includeScreenResolution,
                  onChanged: (value) => _updateSettings(_settings.copyWith(includeScreenResolution: value)),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // 应用信息
            _buildSectionHeader(context, '应用信息', Icons.apps_rounded, isDark),
            const SizedBox(height: AppSpacing.sm),
            _buildSettingsCard(
              context,
              isDark,
              children: [
                _buildSwitchTile(
                  context,
                  isDark,
                  icon: Icons.info_rounded,
                  iconColor: AppColors.secondary,
                  title: '应用版本',
                  subtitle: '当前应用的版本号',
                  value: _settings.includeAppVersion,
                  onChanged: (value) => _updateSettings(_settings.copyWith(includeAppVersion: value)),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // 用户信息
            _buildSectionHeader(context, '用户信息', Icons.person_rounded, isDark),
            const SizedBox(height: AppSpacing.sm),
            _buildSettingsCard(
              context,
              isDark,
              children: [
                _buildSwitchTile(
                  context,
                  isDark,
                  icon: Icons.account_circle_rounded,
                  iconColor: AppColors.fileAudio,
                  title: '用户信息',
                  subtitle: '用户ID和用户名',
                  value: _settings.includeUserId,
                  onChanged: (value) => _updateSettings(_settings.copyWith(includeUserId: value)),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // 上下文信息
            _buildSectionHeader(context, '上下文信息', Icons.location_on_rounded, isDark),
            const SizedBox(height: AppSpacing.sm),
            _buildSettingsCard(
              context,
              isDark,
              children: [
                _buildSwitchTile(
                  context,
                  isDark,
                  icon: Icons.wifi_rounded,
                  iconColor: AppColors.success,
                  title: '网络类型',
                  subtitle: 'WiFi、移动数据等',
                  value: _settings.includeNetworkType,
                  onChanged: (value) => _updateSettings(_settings.copyWith(includeNetworkType: value)),
                ),
                _buildDivider(isDark),
                _buildSwitchTile(
                  context,
                  isDark,
                  icon: Icons.route_rounded,
                  iconColor: AppColors.warning,
                  title: '页面路由',
                  subtitle: '错误发生时所在的页面',
                  value: _settings.includePageRoute,
                  onChanged: (value) => _updateSettings(_settings.copyWith(includePageRoute: value)),
                ),
                _buildDivider(isDark),
                _buildSwitchTile(
                  context,
                  isDark,
                  icon: Icons.touch_app_rounded,
                  iconColor: AppColors.fileImage,
                  title: '操作名称',
                  subtitle: '触发错误的操作',
                  value: _settings.includeAction,
                  onChanged: (value) => _updateSettings(_settings.copyWith(includeAction: value)),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // 错误详情
            _buildSectionHeader(context, '错误详情', Icons.bug_report_rounded, isDark),
            const SizedBox(height: AppSpacing.sm),
            _buildSettingsCard(
              context,
              isDark,
              children: [
                _buildSwitchTile(
                  context,
                  isDark,
                  icon: Icons.code_rounded,
                  iconColor: AppColors.error,
                  title: '堆栈跟踪',
                  subtitle: '错误的代码调用栈',
                  value: _settings.includeStackTrace,
                  onChanged: (value) => _updateSettings(_settings.copyWith(includeStackTrace: value)),
                ),
                _buildDivider(isDark),
                _buildSwitchTile(
                  context,
                  isDark,
                  icon: Icons.data_object_rounded,
                  iconColor: AppColors.fileFolder,
                  title: '额外数据',
                  subtitle: '错误相关的附加信息',
                  value: _settings.includeExtraData,
                  onChanged: (value) => _updateSettings(_settings.copyWith(includeExtraData: value)),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // 重置按钮
            _buildResetButton(context, isDark),
          ],

          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, bool isDark) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.info.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.info,
                size: 24,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '日志上报帮助我们改进应用',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: AppColors.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '上报的数据仅用于分析和修复问题，不会用于其他用途。您可以随时关闭或选择要上报的信息。',
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
  }) =>
      DecoratedBox(
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

  Widget _buildSwitchTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
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
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
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
                Switch.adaptive(
                  value: value,
                  onChanged: onChanged,
                  activeTrackColor: AppColors.primary,
                  activeThumbColor: Colors.white,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildActionTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) =>
      Material(
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
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
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

  Widget _buildResetButton(BuildContext context, bool isDark) => Center(
        child: TextButton.icon(
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: isDark ? AppColors.darkSurface : null,
                title: Text(
                  '重置设置',
                  style: TextStyle(
                    color: isDark ? AppColors.darkOnSurface : null,
                  ),
                ),
                content: Text(
                  '确定要将所有设置恢复为默认值吗？',
                  style: TextStyle(
                    color: isDark ? AppColors.darkOnSurfaceVariant : null,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                      '重置',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            );

            if ((confirmed ?? false) && context.mounted) {
              await ErrorReportSettingsService.instance.resetToDefaults();
              setState(() {
                _settings = ErrorReportSettingsService.instance.settings;
              });
            }
          },
          icon: Icon(
            Icons.restore_rounded,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            size: 18,
          ),
          label: Text(
            '恢复默认设置',
            style: TextStyle(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ),
      );
}
