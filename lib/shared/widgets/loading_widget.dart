import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

class LoadingWidget extends StatefulWidget {
  const LoadingWidget({
    super.key,
    this.message,
    this.size = 48,
    this.backgroundColor,
    this.textColor,
  });

  final String? message;
  final double size;

  /// 自定义背景色（用于加载指示器内部圆圈）
  final Color? backgroundColor;

  /// 自定义文字颜色
  final Color? textColor;

  @override
  State<LoadingWidget> createState() => _LoadingWidgetState();
}

class _LoadingWidgetState extends State<LoadingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 使用自定义背景色或默认背景色
    final bgColor = widget.backgroundColor ??
        (isDark ? AppColors.darkBackground : AppColors.lightBackground);

    // 使用自定义文字颜色或默认颜色
    final txtColor = widget.textColor ??
        (isDark
            ? AppColors.darkOnSurfaceVariant
            : context.colorScheme.onSurfaceVariant);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    endAngle: 3.14 * 2,
                    transform: GradientRotation(_controller.value * 3.14 * 2),
                    colors: [
                      AppColors.primary.withValues(alpha: 0),
                      AppColors.primary,
                      AppColors.secondary,
                      AppColors.accent,
                      AppColors.primary.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                  ),
                ),
                child: Center(
                  child: Container(
                    width: widget.size - 8,
                    height: widget.size - 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: bgColor,
                    ),
                    child: Center(
                      child: Container(
                        width: widget.size * 0.4,
                        height: widget.size * 0.4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.primaryGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ),
          if (widget.message != null) ...[
            const SizedBox(height: 20),
            Text(
              widget.message!,
              style: context.textTheme.bodyMedium?.copyWith(color: txtColor),
            ),
          ],
        ],
      ),
    );
  }
}
