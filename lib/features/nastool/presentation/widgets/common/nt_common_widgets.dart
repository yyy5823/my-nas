import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

// ============================================================
// NASTool 颜色工具类 - 使用全局 AppColors
// ============================================================

class NtColors {
  // 语义颜色 - 直接映射到 AppColors
  static Color get primary => AppColors.primary;
  static Color get primaryLight => AppColors.primaryLight;
  static Color get success => AppColors.success;
  static Color get successLight => AppColors.successLight;
  static Color get warning => AppColors.warning;
  static Color get warningLight => AppColors.warningLight;
  static Color get error => AppColors.error;
  static Color get errorLight => AppColors.errorLight;
  static Color get info => AppColors.info;
  static Color get infoLight => AppColors.infoLight;

  // 动态颜色 - 根据深浅模式返回
  static Color background(bool isDark) => isDark ? AppColors.darkBackground : AppColors.lightBackground;
  static Color surface(bool isDark) => isDark ? AppColors.darkSurface : AppColors.lightSurface;
  static Color surfaceVariant(bool isDark) => isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant;
  static Color onSurface(bool isDark) => isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;
  static Color onSurfaceVariant(bool isDark) => isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant;
  static Color divider(bool isDark) => isDark ? AppColors.darkOutline : AppColors.lightOutline;
}

// ============================================================
// 通用按钮
// ============================================================

class NtIconButton extends StatelessWidget {
  const NtIconButton({
    super.key,
    required this.icon,
    required this.isDark,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 40,
  });

  final IconData icon;
  final bool isDark;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: 20, color: color ?? (isDark ? Colors.white70 : Colors.black54)),
            ),
          ),
        ),
      );
}

class NtButton extends StatelessWidget {
  const NtButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.isOutlined = false,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool isOutlined;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final btnColor = color ?? NtColors.primary;

    if (isOutlined) {
      return OutlinedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : (icon != null ? Icon(icon, size: 18) : const SizedBox.shrink()),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: btnColor,
          side: BorderSide(color: btnColor),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : (icon != null ? Icon(icon, size: 18) : const SizedBox.shrink()),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: btnColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}

// ============================================================
// 卡片组件
// ============================================================

class NtCard extends StatelessWidget {
  const NtCard({
    super.key,
    required this.isDark,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
  });

  final bool isDark;
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        decoration: BoxDecoration(
          color: NtColors.surface(isDark),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
              child: child,
            ),
          ),
        ),
      );
}

class NtStatCard extends StatelessWidget {
  const NtStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
    required this.isDark,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final List<Color> gradient;
  final bool isDark;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => NtCard(
        isDark: isDark,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: gradient[0].withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              value,
              style: context.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: NtColors.onSurface(isDark),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: NtColors.onSurfaceVariant(isDark),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: context.textTheme.labelSmall?.copyWith(color: NtColors.onSurfaceVariant(isDark)),
              ),
            ],
          ],
        ),
      );
}

// ============================================================
// 列表项组件
// ============================================================

class NtListTile extends StatelessWidget {
  const NtListTile({
    super.key,
    required this.isDark,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final bool isDark;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: leading,
        title: Text(
          title,
          style: context.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: NtColors.onSurface(isDark),
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: context.textTheme.bodySmall?.copyWith(color: NtColors.onSurfaceVariant(isDark)),
              )
            : null,
        trailing: trailing,
      );
}

// ============================================================
// 空状态组件
// ============================================================

class NtEmptyState extends StatelessWidget {
  const NtEmptyState({
    super.key,
    required this.icon,
    required this.message,
    required this.isDark,
    this.action,
    this.actionLabel,
  });

  final IconData icon;
  final String message;
  final bool isDark;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 80, color: isDark ? Colors.white12 : Colors.black12),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: context.textTheme.titleMedium?.copyWith(
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: AppSpacing.lg),
              NtButton(label: actionLabel!, onPressed: action, icon: Icons.add_rounded),
            ],
          ],
        ),
      );
}

// ============================================================
// 加载状态组件
// ============================================================

class NtLoading extends StatelessWidget {
  const NtLoading({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(message!),
            ],
          ],
        ),
      );
}

// ============================================================
// 错误状态组件
// ============================================================

class NtError extends StatelessWidget {
  const NtError({
    super.key,
    required this.message,
    required this.isDark,
    this.onRetry,
  });

  final String message;
  final bool isDark;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: NtColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: context.textTheme.bodyMedium?.copyWith(color: NtColors.onSurfaceVariant(isDark)),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              NtButton(label: '重试', onPressed: onRetry, icon: Icons.refresh_rounded),
            ],
          ],
        ),
      );
}

// ============================================================
// 进度条组件
// ============================================================

class NtProgressBar extends StatelessWidget {
  const NtProgressBar({
    super.key,
    this.progress,
    required this.isDark,
    this.color,
    this.height = 6,
    this.showLabel = false,
  });

  final double? progress;
  final bool isDark;
  final Color? color;
  final double height;
  final bool showLabel;

  double get _progress => (progress ?? 0).clamp(0, 1);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showLabel)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${(_progress * 100).toStringAsFixed(1)}%',
                style: context.textTheme.labelSmall?.copyWith(
                  color: color ?? NtColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(height / 2),
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation(color ?? NtColors.primary),
              minHeight: height,
            ),
          ),
        ],
      );
}

// ============================================================
// 标签组件
// ============================================================

class NtChip extends StatelessWidget {
  const NtChip({
    super.key,
    required this.label,
    this.color,
    this.icon,
  });

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (color ?? NtColors.primary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color ?? NtColors.primary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: color ?? NtColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

// ============================================================
// 海报卡片组件
// ============================================================

class NtPosterCard extends StatelessWidget {
  const NtPosterCard({
    super.key,
    required this.isDark,
    required this.title,
    this.posterUrl,
    this.subtitle,
    this.chips = const [],
    this.progress,
    this.onTap,
  });

  final bool isDark;
  final String title;
  final String? posterUrl;
  final String? subtitle;
  final List<Widget> chips;
  final double? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: NtColors.surface(isDark),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (posterUrl != null)
                      CachedNetworkImage(
                        imageUrl: posterUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => ColoredBox(
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                          child: const Icon(Icons.image, size: 40, color: Colors.white24),
                        ),
                        errorWidget: (_, _, _) => ColoredBox(
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                          child: const Icon(Icons.broken_image, size: 40, color: Colors.white24),
                        ),
                      )
                    else
                      ColoredBox(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                        child: const Icon(Icons.movie_rounded, size: 40, color: Colors.white24),
                      ),
                    if (chips.isNotEmpty)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Wrap(spacing: 4, runSpacing: 4, children: chips),
                      ),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 4,
                          color: Colors.black38,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: progress!.clamp(0, 1),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [NtColors.success, NtColors.successLight]),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: NtColors.onSurface(isDark),
                          height: 1.2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const Spacer(),
                        Text(
                          subtitle!,
                          style: context.textTheme.labelSmall?.copyWith(color: NtColors.onSurfaceVariant(isDark)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

// ============================================================
// Section 标题组件
// ============================================================

class NtSectionHeader extends StatelessWidget {
  const NtSectionHeader({
    super.key,
    required this.title,
    required this.isDark,
    this.count,
    this.action,
    this.actionLabel,
  });

  final String title;
  final bool isDark;
  final int? count;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(
            title,
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: NtColors.onSurface(isDark),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: context.textTheme.labelSmall?.copyWith(
                  color: NtColors.onSurfaceVariant(isDark),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (action != null)
            TextButton(
              onPressed: action,
              child: Text(actionLabel ?? '查看全部'),
            ),
        ],
      );
}

// ============================================================
// 搜索框组件
// ============================================================

class NtSearchBar extends StatelessWidget {
  const NtSearchBar({
    super.key,
    required this.controller,
    required this.isDark,
    this.hintText,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool isDark;
  final String? hintText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: NtColors.surface(isDark),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 10,
            ),
          ],
        ),
        child: TextField(
          controller: controller,
          style: TextStyle(color: NtColors.onSurface(isDark)),
          decoration: InputDecoration(
            hintText: hintText ?? '搜索...',
            hintStyle: TextStyle(color: NtColors.onSurfaceVariant(isDark)),
            prefixIcon: Icon(Icons.search_rounded, color: NtColors.onSurfaceVariant(isDark)),
            suffixIcon: IconButton(
              icon: Icon(Icons.arrow_forward_rounded, color: NtColors.onSurfaceVariant(isDark)),
              onPressed: () => onSubmitted?.call(controller.text),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            filled: true,
            fillColor: Colors.transparent,
          ),
          onSubmitted: onSubmitted,
          onChanged: onChanged,
        ),
      );
}

// ============================================================
// 格式化工具
// ============================================================

class NtFormatter {
  static String number(int number) {
    if (number >= 100000000) return '${(number / 100000000).toStringAsFixed(1)}亿';
    if (number >= 10000) return '${(number / 10000).toStringAsFixed(1)}万';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}k';
    return number.toString();
  }

  static String bytes(int? bytes) {
    if (bytes == null) return '-';
    if (bytes >= 1099511627776) return '${(bytes / 1099511627776).toStringAsFixed(2)} TB';
    if (bytes >= 1073741824) return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(2)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '$bytes B';
  }

  static String date(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}周前';
    return '${date.month}/${date.day}';
  }

  static String duration(int? seconds) {
    if (seconds == null) return '-';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}
