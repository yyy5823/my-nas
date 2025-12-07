import 'package:flutter/material.dart';

/// 带有淡入滑动动画的列表项包装器
class AnimatedListItem extends StatefulWidget {
  const AnimatedListItem({
    required this.child,
    required this.index,
    this.duration = const Duration(milliseconds: 300),
    this.delay = const Duration(milliseconds: 50),
    this.slideOffset = 20.0,
    super.key,
  });

  final Widget child;
  final int index;
  final Duration duration;
  final Duration delay;
  final double slideOffset;

  @override
  State<AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, widget.slideOffset / 100),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    // 延迟启动动画，实现交错效果
    Future.delayed(widget.delay * widget.index.clamp(0, 10), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
}

/// 带有缩放淡入动画的网格项包装器
///
/// 性能优化：
/// - 当 [enableAnimation] 为 false 时，直接显示子组件，不创建动画控制器
/// - 当 [index] 超过 [maxAnimatedIndex] 时，自动禁用动画
/// - 默认只对前 20 个项目应用动画，避免大量照片时的性能问题
class AnimatedGridItem extends StatefulWidget {
  const AnimatedGridItem({
    required this.child,
    required this.index,
    this.duration = const Duration(milliseconds: 350),
    this.delay = const Duration(milliseconds: 30),
    this.enableAnimation = true,
    this.maxAnimatedIndex = 20,
    super.key,
  });

  final Widget child;
  final int index;
  final Duration duration;
  final Duration delay;

  /// 是否启用动画，设为 false 可完全禁用动画
  final bool enableAnimation;

  /// 最大应用动画的索引，超过此索引的项目不会有动画
  /// 默认为 20，即只有前 20 个项目有动画效果
  final int maxAnimatedIndex;

  @override
  State<AnimatedGridItem> createState() => _AnimatedGridItemState();
}

class _AnimatedGridItemState extends State<AnimatedGridItem>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _fadeAnimation;
  Animation<double>? _scaleAnimation;

  /// 是否应该显示动画
  bool get _shouldAnimate =>
      widget.enableAnimation && widget.index < widget.maxAnimatedIndex;

  @override
  void initState() {
    super.initState();
    if (_shouldAnimate) {
      _initAnimation();
    }
  }

  void _initAnimation() {
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller!, curve: Curves.easeOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(parent: _controller!, curve: Curves.easeOutBack),
    );

    // 延迟启动动画，实现交错效果
    // 使用 clamp 限制最大延迟，避免过长等待
    final clampedIndex = widget.index.clamp(0, 15);
    Future.delayed(widget.delay * clampedIndex, () {
      if (mounted && _controller != null) {
        _controller!.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 如果不需要动画，直接返回子组件
    if (!_shouldAnimate || _controller == null) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _fadeAnimation!,
      child: ScaleTransition(
        scale: _scaleAnimation!,
        child: widget.child,
      ),
    );
  }
}

/// 内容切换的平滑过渡组件
class AnimatedContentSwitcher extends StatelessWidget {
  const AnimatedContentSwitcher({
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    super.key,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      child: child,
    );
}
