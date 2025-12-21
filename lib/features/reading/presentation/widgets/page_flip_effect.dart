import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 翻页效果模式
enum PageFlipMode {
  /// 仿真翻页（书页卷曲效果）
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
/// 使用纯 Flutter 实现书页翻转效果
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
    this.backgroundColor = Colors.white,
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

  /// 点击事件回调
  final void Function(TapUpDetails details)? onTap;

  /// 背景颜色
  final Color backgroundColor;

  @override
  State<PageFlipEffect> createState() => _PageFlipEffectState();
}

class _PageFlipEffectState extends State<PageFlipEffect>
    with SingleTickerProviderStateMixin {
  /// 动画控制器
  late AnimationController _controller;

  /// 翻页方向
  FlipDirection? _direction;

  /// 是否正在动画中
  bool _isAnimating = false;

  /// 拖动起始位置
  Offset? _dragStart;

  /// 当前拖动进度 (0.0 - 1.0)
  double _dragProgress = 0.0;

  /// 拖动起始Y位置比例 (0=顶部, 1=底部)
  double _dragStartY = 0.5;

  /// 动画开始时的进度
  double _animationStartProgress = 0.0;

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

    final t = Curves.easeOutCubic.transform(_controller.value);

    if (_direction == FlipDirection.forward) {
      // 向左翻：从起始进度动画到 1.0
      _dragProgress = _animationStartProgress + (1.0 - _animationStartProgress) * t;
    } else {
      // 向右翻/取消：从起始进度动画回 0.0
      _dragProgress = _animationStartProgress * (1.0 - t);
    }

    setState(() {});
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _onFlipComplete();
    }
  }

  Future<void> _onFlipComplete() async {
    final direction = _direction;
    final progress = _dragProgress;

    _isAnimating = false;

    // 只有当进度接近 1.0 时才触发翻页
    if (progress > 0.9) {
      if (direction == FlipDirection.forward) {
        await widget.onNextPage();
      } else {
        await widget.onPrevPage();
      }
    }

    _reset();
  }

  void _reset() {
    _direction = null;
    _dragStart = null;
    _dragProgress = 0.0;
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
      await Future<void>.delayed(const Duration(milliseconds: 16));

      if (!mounted) return null;

      final renderObject = _captureKey.currentContext?.findRenderObject();
      if (renderObject == null || renderObject is! RenderRepaintBoundary) {
        logger.w('PageFlipEffect: RenderRepaintBoundary 未找到');
        return null;
      }

      final boundary = renderObject;

      if (boundary.debugNeedsPaint) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted) return null;
      }

      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: pixelRatio.clamp(1.0, 2.0));
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

    final size = MediaQuery.of(context).size;
    _dragStart = details.localPosition;
    _dragStartY = (details.localPosition.dy / size.height).clamp(0.0, 1.0);
  }

  Future<void> _onDragUpdate(DragUpdateDetails details) async {
    if (!widget.enabled || _isAnimating || _dragStart == null) return;

    final size = MediaQuery.of(context).size;
    final dragDelta = details.localPosition.dx - _dragStart!.dx;
    final dragRatio = dragDelta.abs() / size.width;

    // 确定翻页方向
    if (_direction == null && dragRatio > 0.02) {
      _direction = dragDelta < 0 ? FlipDirection.forward : FlipDirection.backward;

      // 开始拖动时捕获页面
      _capturedImage = await _capturePage();
      if (_capturedImage == null) {
        _direction = null;
        return;
      }
    }

    if (_direction != null && mounted) {
      setState(() {
        _dragProgress = dragRatio.clamp(0.0, 1.0);
      });
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled || _direction == null) {
      _reset();
      return;
    }

    final shouldComplete = _dragProgress > widget.dragThreshold;

    _isAnimating = true;
    _animationStartProgress = _dragProgress;

    if (shouldComplete) {
      // 完成翻页
      if (_direction == FlipDirection.backward) {
        // 向右翻（上一页）需要反转方向完成动画
        _direction = FlipDirection.forward;
      }
      _controller.forward(from: 0);
      HapticFeedback.lightImpact();
    } else {
      // 取消翻页
      if (_direction == FlipDirection.forward) {
        _direction = FlipDirection.backward;
      }
      _controller.forward(from: 0);
    }
  }

  void _onDragCancel() {
    if (_direction != null && !_isAnimating) {
      _isAnimating = true;
      _animationStartProgress = _dragProgress;
      _direction = FlipDirection.backward;
      _controller.forward(from: 0);
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

  // 点击检测
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

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _tapDownPosition = event.localPosition;
        _tapDownTime = DateTime.now();
      },
      onPointerUp: (event) {
        if (_direction != null || _isAnimating) {
          _tapDownPosition = null;
          _tapDownTime = null;
          return;
        }

        if (_tapDownPosition != null && _tapDownTime != null) {
          final distance = (event.localPosition - _tapDownPosition!).distance;
          final duration = DateTime.now().difference(_tapDownTime!);

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
            // 原始内容
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

  /// 仿真翻页效果
  Widget _buildSimulationEffect() => CustomPaint(
    painter: _SimulationPagePainter(
      image: _capturedImage!,
      progress: _dragProgress,
      dragStartY: _dragStartY,
      backgroundColor: widget.backgroundColor,
      isForward: _direction == FlipDirection.forward,
    ),
    size: Size.infinite,
  );

  /// 覆盖翻页效果
  Widget _buildCoverEffect() {
    final size = MediaQuery.of(context).size;

    // 计算页面偏移
    final slideOffset = _direction == FlipDirection.forward
        ? size.width * (1.0 - _dragProgress)
        : -size.width * _dragProgress;

    return Stack(
      children: [
        // 背景
        ColoredBox(
          color: widget.backgroundColor,
          child: const SizedBox.expand(),
        ),

        // 滑动的页面
        Transform.translate(
          offset: Offset(slideOffset, 0),
          child: Stack(
            children: [
              Positioned.fill(
                child: RawImage(
                  image: _capturedImage,
                  fit: BoxFit.cover,
                ),
              ),
              // 边缘阴影
              Positioned(
                left: _direction == FlipDirection.forward ? null : 0,
                right: _direction == FlipDirection.forward ? 0 : null,
                top: 0,
                bottom: 0,
                width: 30,
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
                        Colors.black.withValues(alpha: 0.15 * _dragProgress),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 页面边缘的阴影（在背景上）
        if (_dragProgress > 0)
          Positioned(
            left: _direction == FlipDirection.forward
                ? size.width * (1.0 - _dragProgress) - 20
                : null,
            right: _direction == FlipDirection.backward
                ? size.width * (1.0 - _dragProgress) - 20
                : null,
            top: 0,
            bottom: 0,
            width: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.1 * _dragProgress),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 仿真翻页绘制器
class _SimulationPagePainter extends CustomPainter {
  _SimulationPagePainter({
    required this.image,
    required this.progress,
    required this.dragStartY,
    required this.backgroundColor,
    required this.isForward,
  });

  final ui.Image image;
  final double progress;
  final double dragStartY;
  final Color backgroundColor;
  final bool isForward;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final imageRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final destRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // 计算翻页的关键点
    // 翻页线从右侧向左移动，同时有一定的角度
    final foldX = size.width * (1.0 - progress);

    // 根据拖动起始位置计算角度
    // 如果从顶部开始拖动，底部移动更多；反之亦然
    final angleIntensity = 0.15; // 角度强度
    final topOffset = dragStartY * angleIntensity * size.width * progress;
    final bottomOffset = (1.0 - dragStartY) * angleIntensity * size.width * progress;

    final foldTopX = foldX + topOffset;
    final foldBottomX = foldX - bottomOffset;

    // 绘制背景
    canvas.drawRect(destRect, Paint()..color = backgroundColor);

    // 1. 绘制未翻起的部分（左侧）
    final leftPath = Path()
      ..moveTo(0, 0)
      ..lineTo(foldTopX, 0)
      ..lineTo(foldBottomX, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas
      ..save()
      ..clipPath(leftPath)
      ..drawImageRect(image, imageRect, destRect, Paint())
      ..restore();

    // 2. 绘制翻起页面的背面
    if (progress > 0.01) {
      _drawPageBack(canvas, size, foldTopX, foldBottomX, imageRect, destRect);
    }

    // 3. 绘制阴影
    _drawShadows(canvas, size, foldTopX, foldBottomX);
  }

  void _drawPageBack(
    Canvas canvas,
    Size size,
    double foldTopX,
    double foldBottomX,
    Rect imageRect,
    Rect destRect,
  ) {
    // 计算翻起部分的路径
    // 翻起的页面是从折线到右边缘的镜像

    final backPath = Path()
      ..moveTo(foldTopX, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(foldBottomX, size.height)
      ..close();

    canvas
      ..save()
      ..clipPath(backPath);

    // 计算镜像变换
    // 以折线为轴进行镜像
    final foldCenterX = (foldTopX + foldBottomX) / 2;
    final foldAngle = math.atan2(foldTopX - foldBottomX, size.height);

    // 创建变换矩阵实现镜像效果
    // ignore: deprecated_member_use
    final matrix = Matrix4.identity()
      // ignore: deprecated_member_use
      ..translate(foldCenterX, size.height / 2)
      ..rotateZ(-foldAngle)
      // ignore: deprecated_member_use
      ..scale(-1.0, 1.0)  // 水平镜像
      ..rotateZ(foldAngle)
      // ignore: deprecated_member_use
      ..translate(-foldCenterX, -size.height / 2);

    canvas
      ..transform(matrix.storage)
      ..drawImageRect(image, imageRect, destRect, Paint())
      ..restore();

    // 绘制页面背面的覆盖层（模拟纸张背面）
    // 纸张背面颜色（略暗的米色）
    final backColor = Color.lerp(
      backgroundColor,
      const Color(0xFFE8E4DC),
      0.5,
    )!.withValues(alpha: 0.85);

    // 添加渐变效果模拟光照
    final gradient = ui.Gradient.linear(
      Offset(foldTopX, 0),
      Offset(size.width, size.height / 2),
      [
        Colors.black.withValues(alpha: 0.1),
        Colors.transparent,
        Colors.white.withValues(alpha: 0.05),
      ],
      [0.0, 0.5, 1.0],
    );

    canvas
      ..save()
      ..clipPath(backPath)
      ..drawRect(destRect, Paint()..color = backColor)
      ..drawRect(destRect, Paint()..shader = gradient)
      ..restore();
  }

  void _drawShadows(
    Canvas canvas,
    Size size,
    double foldTopX,
    double foldBottomX,
  ) {
    // 折痕阴影
    final shadowWidth = 25.0 * progress.clamp(0.0, 1.0);

    // 左侧阴影（在未翻起部分上）
    final leftShadowPath = Path()
      ..moveTo(foldTopX - shadowWidth, 0)
      ..lineTo(foldTopX, 0)
      ..lineTo(foldBottomX, size.height)
      ..lineTo(foldBottomX - shadowWidth, size.height)
      ..close();

    final leftShadowGradient = ui.Gradient.linear(
      Offset(foldTopX - shadowWidth, size.height / 2),
      Offset(foldTopX, size.height / 2),
      [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.15 * progress),
      ],
    );

    canvas.drawPath(leftShadowPath, Paint()..shader = leftShadowGradient);

    // 翻起部分的内阴影
    final innerShadowPath = Path()
      ..moveTo(foldTopX, 0)
      ..lineTo(foldTopX + shadowWidth * 0.5, 0)
      ..lineTo(foldBottomX + shadowWidth * 0.5, size.height)
      ..lineTo(foldBottomX, size.height)
      ..close();

    final innerShadowGradient = ui.Gradient.linear(
      Offset(foldTopX, size.height / 2),
      Offset(foldTopX + shadowWidth * 0.5, size.height / 2),
      [
        Colors.black.withValues(alpha: 0.2 * progress),
        Colors.transparent,
      ],
    );

    canvas.drawPath(innerShadowPath, Paint()..shader = innerShadowGradient);
  }

  @override
  bool shouldRepaint(_SimulationPagePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      image != oldDelegate.image ||
      dragStartY != oldDelegate.dragStartY;
}
