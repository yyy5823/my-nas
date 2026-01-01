import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';

/// 显示应用统一风格的底部弹窗
///
/// [context] 上下文
/// [builder] 构建内容
/// [title] 标题（可选）
/// [titleWidget] 自定义标题组件（可选，优先级高于 title）
/// [useScrollable] 是否使用可拖拽滚动（默认 true，适用于内容较多的情况）
/// [initialChildSize] 初始高度比例（0.0 - 1.0）
/// [minChildSize] 最小高度比例
/// [maxChildSize] 最大高度比例
/// [useSafeArea] 是否使用安全区域（默认 true）
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController? scrollController) builder,
  String? title,
  Widget? titleWidget,
  bool useScrollable = true,
  double initialChildSize = 0.5,
  double minChildSize = 0.25,
  double maxChildSize = 0.9,
  bool useSafeArea = true,
  bool enableDrag = true,
}) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: useSafeArea,
    backgroundColor: Colors.transparent,
    enableDrag: enableDrag,
    builder: (context) => useScrollable
        ? _ScrollableBottomSheet(
            title: title,
            titleWidget: titleWidget,
            initialChildSize: initialChildSize,
            minChildSize: minChildSize,
            maxChildSize: maxChildSize,
            builder: builder,
          )
        : _FixedBottomSheet(
            title: title,
            titleWidget: titleWidget,
            builder: builder,
          ),
  );

/// 可滚动的底部弹窗（使用 DraggableScrollableSheet）
class _ScrollableBottomSheet extends ConsumerWidget {
  const _ScrollableBottomSheet({
    required this.builder,
    this.title,
    this.titleWidget,
    this.initialChildSize = 0.5,
    this.minChildSize = 0.25,
    this.maxChildSize = 0.9,
  });

  final Widget Function(BuildContext context, ScrollController? scrollController) builder;
  final String? title;
  final Widget? titleWidget;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);

    return DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      expand: false,
      builder: (context, scrollController) => _buildContainer(
        context,
        isDark,
        glassStyle,
        child: Column(
          children: [
            _buildDragHandle(isDark),
            if (titleWidget != null || title != null)
              _buildHeader(context, isDark),
            Expanded(
              child: builder(context, scrollController),
            ),
            // 底部安全区域（包含原生 Tab Bar 高度）
            SizedBox(height: _getBottomPadding(context, uiStyle)),
          ],
        ),
      ),
    );
  }

  Widget _buildContainer(
    BuildContext context,
    bool isDark,
    GlassStyle glassStyle, {
    required Widget child,
  }) {
    final borderRadius = const BorderRadius.vertical(top: Radius.circular(24));
    
    // 计算背景色 - 底部弹窗使用稍高的不透明度
    final bgColor = glassStyle.needsBlur
        ? (isDark
            ? AppColors.darkSurface.withValues(
                alpha: (glassStyle.backgroundOpacity + 0.15).clamp(0.0, 1.0),
              )
            : AppColors.lightSurface.withValues(
                alpha: (glassStyle.backgroundOpacity + 0.1).clamp(0.0, 1.0),
              ))
        : (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    final decoration = BoxDecoration(
      color: bgColor,
      borderRadius: borderRadius,
      border: Border(
        top: BorderSide(
          color: isDark
              ? AppColors.glassStroke
              : AppColors.lightOutline.withValues(alpha: 0.2),
        ),
      ),
    );

    Widget content = DecoratedBox(
      decoration: decoration,
      child: child,
    );

    if (glassStyle.needsBlur) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: glassStyle.blurFilter!,
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildDragHandle(bool isDark) => Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
            : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );

  Widget _buildHeader(BuildContext context, bool isDark) {
    if (titleWidget != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: titleWidget,
      );
    }

    if (title != null && title!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title!,
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

}

/// 计算底部弹窗的底部间距
///
/// 在 iOS 玻璃风格下需要额外添加原生 Tab Bar 的高度，
/// 因为原生 UITabBar 悬浮在 Flutter 内容之上。
double _getBottomPadding(BuildContext context, UIStyle uiStyle) {
  final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
  // 确保至少有一点底部间距
  var padding = bottomPadding > 0 ? bottomPadding : AppSpacing.md;

  // iOS 玻璃风格下需要额外添加原生 Tab Bar 的高度
  // 因为原生 UITabBar 悬浮在 Flutter 内容之上
  if (!kIsWeb && Platform.isIOS && uiStyle.isGlass) {
    // UITabBar 标准高度约 49pt
    padding += 49;
  }

  return padding;
}

/// 固定高度的底部弹窗（内容较少时使用）
class _FixedBottomSheet extends ConsumerWidget {
  const _FixedBottomSheet({
    required this.builder,
    this.title,
    this.titleWidget,
  });

  final Widget Function(BuildContext context, ScrollController? scrollController) builder;
  final String? title;
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);
    final bottomPadding = _getBottomPadding(context, uiStyle);
    final borderRadius = const BorderRadius.vertical(top: Radius.circular(24));

    // 计算背景色
    final bgColor = glassStyle.needsBlur
        ? (isDark
            ? AppColors.darkSurface.withValues(
                alpha: (glassStyle.backgroundOpacity + 0.15).clamp(0.0, 1.0),
              )
            : AppColors.lightSurface.withValues(
                alpha: (glassStyle.backgroundOpacity + 0.1).clamp(0.0, 1.0),
              ))
        : (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    final decoration = BoxDecoration(
      color: bgColor,
      borderRadius: borderRadius,
      border: Border(
        top: BorderSide(
          color: isDark
              ? AppColors.glassStroke
              : AppColors.lightOutline.withValues(alpha: 0.2),
        ),
      ),
    );

    Widget content = DecoratedBox(
      decoration: decoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动指示器
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                  : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          if (titleWidget != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: titleWidget,
            )
          else if (title != null && title!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                title!,
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
            ),
          // 内容（使用 SingleChildScrollView 确保内容可以滚动）
          Flexible(
            child: SingleChildScrollView(
              child: builder(context, null),
            ),
          ),
          // 底部安全区域（包含原生 Tab Bar 高度）
          SizedBox(height: bottomPadding),
        ],
      ),
    );

    if (glassStyle.needsBlur) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: glassStyle.blurFilter!,
          child: content,
        ),
      );
    }

    return content;
  }
}

/// 显示简单的选项菜单底部弹窗
Future<T?> showOptionsBottomSheet<T>({
  required BuildContext context,
  required List<OptionItem<T>> options, String? title,
}) => showAppBottomSheet<T>(
    context: context,
    title: title,
    useScrollable: false,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          _OptionTile<T>(option: option),
      ],
    ),
  );

/// 选项项
class OptionItem<T> {
  const OptionItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.value,
    this.onTap,
    this.isSelected = false,
    this.isDestructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final T? value;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool isDestructive;
}

class _OptionTile<T> extends StatelessWidget {
  const _OptionTile({required this.option});

  final OptionItem<T> option;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveColor = option.isDestructive
        ? AppColors.error
        : (option.iconColor ??
            (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface));

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          option.icon,
          color: effectiveColor,
          size: 20,
        ),
      ),
      title: Text(
        option.title,
        style: TextStyle(
          color: option.isDestructive ? AppColors.error : null,
          fontWeight: option.isSelected ? FontWeight.w600 : null,
        ),
      ),
      subtitle: option.subtitle != null ? Text(option.subtitle!) : null,
      trailing: option.isSelected
          ? Icon(Icons.check_rounded, color: AppColors.primary)
          : null,
      onTap: () {
        if (option.value != null) {
          Navigator.pop(context, option.value);
        } else {
          option.onTap?.call();
        }
      },
    );
  }
}
