import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 翻页效果模式
enum PageFlipMode {
  /// 仿真翻页（3D 翻转效果）
  simulation,

  /// 覆盖翻页
  cover,
}

/// 翻页方向
enum FlipDirection {
  /// 向左翻（下一页）
  forward,

  /// 向右翻（上一页）
  backward,
}

/// 页面翻转效果 Widget
///
/// 使用 Flutter Transform 实现 3D 翻页效果
/// 支持仿真翻页和覆盖翻页两种模式
class PageFlipEffect extends StatefulWidget {
  const PageFlipEffect({
    required this.child,
    required this.onNextPage,
    required this.onPrevPage,
    this.mode = PageFlipMode.simulation,
    this.enabled = true,
    this.animationDuration = const Duration(milliseconds: 400),
    this.dragThreshold = 0.25,
    this.onTap,
    super.key,
  });

  /// 当前页面内容
  final Widget child;

  /// 下一页回调
  final Future<void> Function() onNextPage;

  /// 上一页回调
  final Future<void> Function() onPrevPage;

  /// 翻页模式
  final PageFlipMode mode;

  /// 是否启用翻页效果
  final bool enabled;

  /// 动画时长
  final Duration animationDuration;

  /// 拖动阈值（超过此比例触发翻页）
  final double dragThreshold;

  /// 点击事件回调（用于处理点击翻页区域）
  final void Function(TapUpDetails details)? onTap;

  @override
  State<PageFlipEffect> createState() => _PageFlipEffectState();
}

class _PageFlipEffectState extends State<PageFlipEffect>
    with SingleTickerProviderStateMixin {
  /// 动画控制器
  late AnimationController _controller;

  /// 翻页进度 (0.0 - 1.0)
  double _flipProgress = 0.0;

  /// 翻页方向
  FlipDirection? _direction;

  /// 是否正在动画中
  bool _isAnimating = false;

  /// 拖动起始位置
  Offset? _dragStart;

  /// 捕获的当前页面图像
  ui.Image? _capturedImage;

  /// 用于捕获的 GlobalKey
  final GlobalKey _captureKey = GlobalKey();

  /// 是否正在捕获
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    )
      ..addListener(_onAnimationUpdate)
      ..addStatusListener(_onAnimationStatus);
  }

  void _onAnimationUpdate() {
    if (!mounted) return;
    setState(() {
      if (_direction == FlipDirection.forward) {
        _flipProgress = _controller.value;
      } else {
        _flipProgress = 1.0 - _controller.value;
      }
    });
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _onFlipComplete();
    } else if (status == AnimationStatus.dismissed) {
      _onFlipCancelled();
    }
  }

  Future<void> _onFlipComplete() async {
    final direction = _direction;
    if (direction == null) return;

    _isAnimating = false;

    // 执行翻页
    if (direction == FlipDirection.forward) {
      await widget.onNextPage();
    } else {
      await widget.onPrevPage();
    }

    _reset();
  }

  void _onFlipCancelled() {
    _isAnimating = false;
    _reset();
  }

  void _reset() {
    _direction = null;
    _flipProgress = 0.0;
    _dragStart = null;
    _capturedImage?.dispose();
    _capturedImage = null;
    _controller.reset();
    if (mounted) setState(() {});
  }

  /// 捕获当前页面
  Future<ui.Image?> _capturePage() async {
    if (_isCapturing) return null;
    _isCapturing = true;

    try {
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      // 使用较低的像素比以提高性能
      final image = await boundary.toImage(pixelRatio: 1.0);
      return image;
    } on Exception catch (e) {
      logger.w('PageFlipEffect: 捕获页面失败 - $e');
      return null;
    } finally {
      _isCapturing = false;
    }
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enabled || _isAnimating) return;
    _dragStart = details.localPosition;
  }

  Future<void> _onDragUpdate(DragUpdateDetails details) async {
    if (!widget.enabled || _isAnimating || _dragStart == null) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final dragDelta = details.localPosition.dx - _dragStart!.dx;
    final dragRatio = dragDelta.abs() / screenWidth;

    // 确定翻页方向
    if (_direction == null && dragRatio > 0.03) {
      _direction = dragDelta < 0
          ? FlipDirection.forward
          : FlipDirection.backward;

      // 开始拖动时捕获页面
      _capturedImage = await _capturePage();
      if (_capturedImage == null) {
        _direction = null;
        return;
      }
    }

    if (_direction != null && mounted) {
      setState(() {
        if (_direction == FlipDirection.forward) {
          _flipProgress = dragRatio.clamp(0.0, 1.0);
        } else {
          _flipProgress = (1.0 - dragRatio).clamp(0.0, 1.0);
        }
      });
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled || _direction == null) {
      _reset();
      return;
    }

    final shouldComplete = _direction == FlipDirection.forward
        ? _flipProgress > widget.dragThreshold
        : _flipProgress < (1.0 - widget.dragThreshold);

    _isAnimating = true;

    if (shouldComplete) {
      // 完成翻页
      _controller.value = _direction == FlipDirection.forward
          ? _flipProgress
          : 1.0 - _flipProgress;
      _controller.forward();
      HapticFeedback.lightImpact();
    } else {
      // 取消翻页
      _controller.value = _direction == FlipDirection.forward
          ? _flipProgress
          : 1.0 - _flipProgress;
      _controller.reverse();
    }
  }

  void _onDragCancel() {
    if (_direction != null && !_isAnimating) {
      _isAnimating = true;
      _controller.value = _direction == FlipDirection.forward
          ? _flipProgress
          : 1.0 - _flipProgress;
      _controller.reverse();
    } else {
      _reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _capturedImage?.dispose();
    super.dispose();
  }

  // 点击检测相关变量
  Offset? _tapDownPosition;
  DateTime? _tapDownTime;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return GestureDetector(
        onTapUp: widget.onTap,
        child: widget.child,
      );
    }

    // 使用 Listener 检测点击，避免与拖动手势竞争
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _tapDownPosition = event.localPosition;
        _tapDownTime = DateTime.now();
      },
      onPointerUp: (event) {
        // 如果正在拖动翻页，不处理点击
        if (_direction != null || _isAnimating) {
          _tapDownPosition = null;
          _tapDownTime = null;
          return;
        }

        if (_tapDownPosition != null && _tapDownTime != null) {
          final distance = (event.localPosition - _tapDownPosition!).distance;
          final duration = DateTime.now().difference(_tapDownTime!);

          // 快速点击且移动距离小，视为点击
          if (distance < 20 && duration.inMilliseconds < 300) {
            widget.onTap?.call(TapUpDetails(
              kind: event.kind,
              localPosition: event.localPosition,
              globalPosition: event.position,
            ));
          }
        }
        _tapDownPosition = null;
        _tapDownTime = null;
      },
      onPointerCancel: (event) {
        _tapDownPosition = null;
        _tapDownTime = null;
      },
      child: GestureDetector(
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _onDragCancel,
        child: Stack(
          children: [
            // 原始内容（用于捕获）
            RepaintBoundary(
              key: _captureKey,
              child: widget.child,
            ),

            // 翻页动画层
            if (_direction != null && _capturedImage != null)
              Positioned.fill(
                child: widget.mode == PageFlipMode.simulation
                    ? _buildSimulationEffect()
                    : _buildCoverEffect(),
              ),
          ],
        ),
      ),
    );
  }

  /// 仿真翻页效果（书页折叠）
  /// 页面跟随手指移动，模拟真实翻书效果
  Widget _buildSimulationEffect() {
    final screenWidth = MediaQuery.of(context).size.width;
    final progress = _direction == FlipDirection.forward
        ? _flipProgress
        : 1.0 - _flipProgress;

    // 页面边缘位置 - 跟随手指
    final pageEdgeX = _direction == FlipDirection.forward
        ? screenWidth * (1.0 - progress)
        : screenWidth * progress;

    // 翻页角度 - 从 0 到 90 度
    final angle = progress * math.pi * 0.5;

    // 阴影强度
    final shadowOpacity = (0.5 * progress).clamp(0.0, 0.5);

    return Stack(
      children: [
        // 背景 - 白色下一页
        Container(color: Colors.white),

        // 翻起的页面 - 使用 ClipRect 裁剪
        if (progress > 0)
          Positioned(
            left: _direction == FlipDirection.forward ? 0 : pageEdgeX,
            right: _direction == FlipDirection.forward
                ? screenWidth - pageEdgeX
                : 0,
            top: 0,
            bottom: 0,
            child: Transform(
              alignment: _direction == FlipDirection.forward
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(_direction == FlipDirection.forward ? angle : -angle),
              child: Stack(
                children: [
                  // 页面内容
                  Positioned.fill(
                    child: ClipRect(
                      child: Align(
                        alignment: _direction == FlipDirection.forward
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        widthFactor: 1.0 - progress,
                        child: SizedBox(
                          width: screenWidth,
                          child: RawImage(
                            image: _capturedImage,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 页面暗角
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: _direction == FlipDirection.forward
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          end: _direction == FlipDirection.forward
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          colors: [
                            Colors.black.withValues(alpha: shadowOpacity * 0.4),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 页面折叠处的阴影
        if (progress > 0.02)
          Positioned(
            left: _direction == FlipDirection.forward ? pageEdgeX - 20 : null,
            right: _direction == FlipDirection.backward ? pageEdgeX - 20 : null,
            top: 0,
            bottom: 0,
            width: 25,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.15 * progress),
                    Colors.black.withValues(alpha: 0.08 * progress),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.3, 0.7, 1.0],
                ),
              ),
            ),
          ),

        // 翻起页面的背面（模拟纸张背面）
        if (progress > 0.1)
          Positioned(
            left: _direction == FlipDirection.forward ? pageEdgeX : null,
            right: _direction == FlipDirection.backward ? pageEdgeX : null,
            top: 0,
            bottom: 0,
            width: math.min(progress * screenWidth * 0.15, 30),
            child: Transform(
              alignment: _direction == FlipDirection.forward
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(
                  _direction == FlipDirection.forward
                      ? math.pi - angle
                      : -(math.pi - angle),
                ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1 * progress),
                      blurRadius: 3,
                      offset: Offset(
                        _direction == FlipDirection.forward ? -2 : 2,
                        0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 覆盖翻页效果
  Widget _buildCoverEffect() {
    final progress = _direction == FlipDirection.forward
        ? _flipProgress
        : 1.0 - _flipProgress;

    final screenWidth = MediaQuery.of(context).size.width;
    final offset = _direction == FlipDirection.forward
        ? -screenWidth * progress
        : screenWidth * (1 - progress);

    return Stack(
      children: [
        // 背景 - 纯白色模拟下一页
        Container(color: Colors.white),

        // 滑动的页面
        Transform.translate(
          offset: Offset(offset, 0),
          child: Stack(
            children: [
              // 页面图像
              Positioned.fill(
                child: RawImage(
                  image: _capturedImage,
                  fit: BoxFit.cover,
                ),
              ),

              // 边缘阴影
              Positioned(
                right: _direction == FlipDirection.forward ? 0 : null,
                left: _direction == FlipDirection.backward ? 0 : null,
                top: 0,
                bottom: 0,
                width: 30,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: _direction == FlipDirection.forward
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      end: _direction == FlipDirection.forward
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.2 * progress),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
