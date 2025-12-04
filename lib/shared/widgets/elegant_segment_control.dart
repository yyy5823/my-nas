import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';

/// 优雅的分段控制器项目
class SegmentItem {
  const SegmentItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

/// 优雅的分段控制器
class ElegantSegmentControl extends StatefulWidget {
  const ElegantSegmentControl({
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.backgroundColor,
    this.selectedColor,
    this.unselectedColor,
    this.indicatorColor,
    super.key,
  });

  final List<SegmentItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Color? backgroundColor;
  final Color? selectedColor;
  final Color? unselectedColor;
  final Color? indicatorColor;

  @override
  State<ElegantSegmentControl> createState() => _ElegantSegmentControlState();
}

class _ElegantSegmentControlState extends State<ElegantSegmentControl>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.selectedIndex;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: widget.selectedIndex.toDouble(),
      end: widget.selectedIndex.toDouble(),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void didUpdateWidget(ElegantSegmentControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _previousIndex = oldWidget.selectedIndex;
      _slideAnimation = Tween<double>(
        begin: _previousIndex.toDouble(),
        end: widget.selectedIndex.toDouble(),
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ));
      _animationController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColor = widget.backgroundColor ??
        (isDark ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5) : Colors.grey[200]!);
    final selectedColor = widget.selectedColor ??
        (isDark ? AppColors.darkOnSurface : Colors.black87);
    final unselectedColor = widget.unselectedColor ??
        (isDark ? AppColors.darkOnSurfaceVariant : Colors.grey[600]!);
    final indicatorColor = widget.indicatorColor ??
        (isDark ? AppColors.darkSurface : Colors.white);

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / widget.items.length;

          return Stack(
            children: [
              // 滑动指示器
              AnimatedBuilder(
                animation: _slideAnimation,
                builder: (context, child) => Positioned(
                    left: _slideAnimation.value * itemWidth,
                    top: 0,
                    bottom: 0,
                    width: itemWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: indicatorColor,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
              ),
              // 分段项目
              Row(
                children: List.generate(widget.items.length, (index) {
                  final item = widget.items[index];
                  final isSelected = index == widget.selectedIndex;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => widget.onChanged(index),
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: isSelected ? selectedColor : unselectedColor,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 14,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              item.icon,
                              size: 18,
                              color: isSelected ? selectedColor : unselectedColor,
                            ),
                            const SizedBox(width: 6),
                            Text(item.label),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 带有发光效果的分段控制器（更现代的风格）
class GlowingSegmentControl extends StatefulWidget {
  const GlowingSegmentControl({
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.accentColor,
    super.key,
  });

  final List<SegmentItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Color? accentColor;

  @override
  State<GlowingSegmentControl> createState() => _GlowingSegmentControlState();
}

class _GlowingSegmentControlState extends State<GlowingSegmentControl>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: widget.selectedIndex.toDouble(),
      end: widget.selectedIndex.toDouble(),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));
  }

  @override
  void didUpdateWidget(GlowingSegmentControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _animation = Tween<double>(
        begin: _animation.value,
        end: widget.selectedIndex.toDouble(),
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = widget.accentColor ?? AppColors.primary;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / widget.items.length;

          return Stack(
            children: [
              // 发光指示器
              AnimatedBuilder(
                animation: _animation,
                builder: (context, child) => Positioned(
                    left: _animation.value * itemWidth + 4,
                    top: 4,
                    bottom: 4,
                    width: itemWidth - 8,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accentColor.withValues(alpha: 0.8),
                            accentColor,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
              ),
              // 分段项目
              Row(
                children: List.generate(widget.items.length, (index) {
                  final item = widget.items[index];
                  final isSelected = index == widget.selectedIndex;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => widget.onChanged(index),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.grey[400] : Colors.grey[600]),
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 14,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item.icon,
                                size: 18,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? Colors.grey[400] : Colors.grey[600]),
                              ),
                              const SizedBox(width: 6),
                              Text(item.label),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 极简风格的 Chip 选择器
class ChipSegmentControl extends StatelessWidget {
  const ChipSegmentControl({
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.spacing = 8,
    super.key,
  });

  final List<SegmentItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isSelected = index == selectedIndex;

          return Padding(
            padding: EdgeInsets.only(right: index < items.length - 1 ? spacing : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onChanged(index),
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? Colors.grey[850] : Colors.grey[200]),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                        width: isSelected ? 0 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          size: 16,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.grey[400] : Colors.grey[600]),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.grey[400] : Colors.grey[600]),
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
