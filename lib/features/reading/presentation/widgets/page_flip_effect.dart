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

/// 翻页起始位置
enum FlipOrigin {
  /// 从上方开始（右上角）
  top,

  /// 从中间开始
  middle,

  /// 从下方开始（右下角）
  bottom,
}

/// 页面翻转效果 Widget
///
/// 使用 Flutter Transform 实现 3D 翻页效果
/// 支持仿真翻页和覆盖翻页两种模式
/// 支持从上、中、下三个位置开始翻页
class PageFlipEffect extends StatefulWidget {
  const PageFlipEffect({
    required this.child,
    required this.onNextPage,
    required this.onPrevPage,
    this.mode = PageFlipMode.simulation,
    this.enabled = true,
    this.animationDuration = const Duration(milliseconds: 350),
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

  /// 翻页起始位置
  FlipOrigin _flipOrigin = FlipOrigin.middle;

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

      // 使用较高的像素比以获得清晰的图像
      final pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final image = await boundary.toImage(pixelRatio: math.min(pixelRatio, 2.0));
      return image;
    } on Exception catch (e) {
      logger.w('PageFlipEffect: 捕获页面失败 - $e');
      return null;
    } finally {
      _isCapturing = false;
    }
  }

  /// 根据Y坐标判断翻页起始位置
  FlipOrigin _determineFlipOrigin(double y, double height) {
    final ratio = y / height;
    if (ratio < 0.33) {
      return FlipOrigin.top;
    } else if (ratio > 0.67) {
      return FlipOrigin.bottom;
    } else {
      return FlipOrigin.middle;
    }
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enabled || _isAnimating) return;
    _dragStart = details.localPosition;

    // 判断翻页起始位置
    final height = MediaQuery.of(context).size.height;
    _flipOrigin = _determineFlipOrigin(details.localPosition.dy, height);
  }

  Future<void> _onDragUpdate(DragUpdateDetails details) async {
    if (!widget.enabled || _isAnimating || _dragStart == null) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final dragDelta = details.localPosition.dx - _dragStart!.dx;
    final dragRatio = dragDelta.abs() / screenWidth;

    // 确定翻页方向
    if (_direction == null && dragRatio > 0.02) {
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
      // 取消翻页 - 手指往回移动
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

  /// 仿真翻页效果（书页卷曲）
  Widget _buildSimulationEffect() {
    final size = MediaQuery.of(context).size;
    final screenWidth = size.width;
    final screenHeight = size.height;

    final progress = _direction == FlipDirection.forward
        ? _flipProgress
        : 1.0 - _flipProgress;

    return CustomPaint(
      painter: _PageCurlPainter(
        image: _capturedImage!,
        progress: progress,
        direction: _direction!,
        origin: _flipOrigin,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
      ),
      size: size,
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

/// 页面卷曲绘制器 - 实现真正的角落翻页效果
class _PageCurlPainter extends CustomPainter {
  _PageCurlPainter({
    required this.image,
    required this.progress,
    required this.direction,
    required this.origin,
    required this.screenWidth,
    required this.screenHeight,
  });

  final ui.Image image;
  final double progress;
  final FlipDirection direction;
  final FlipOrigin origin;
  final double screenWidth;
  final double screenHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final isForward = direction == FlipDirection.forward;
    final curlProgress = progress.clamp(0.0, 1.0);

    // 绘制背景（下一页 - 白色）
    canvas.drawRect(
      Rect.fromLTWH(0, 0, screenWidth, screenHeight),
      Paint()..color = Colors.white,
    );

    // 计算折叠线的角度和位置
    // 从角落翻页时，折叠线是倾斜的
    final foldAngle = switch (origin) {
      FlipOrigin.top => math.pi / 6 * curlProgress, // 从右上角，折叠线向左下倾斜
      FlipOrigin.bottom => -math.pi / 6 * curlProgress, // 从右下角，折叠线向左上倾斜
      FlipOrigin.middle => 0.0, // 中间翻页，折叠线垂直
    };

    // 折叠线的基准 X 位置
    final baseFoldX = isForward
        ? screenWidth * (1.0 - curlProgress)
        : screenWidth * curlProgress;

    // 根据角度计算折叠线的上下端点
    final foldOffset = math.tan(foldAngle) * screenHeight / 2;
    final foldTopX = baseFoldX + (origin == FlipOrigin.top ? foldOffset : -foldOffset);
    final foldBottomX = baseFoldX + (origin == FlipOrigin.top ? -foldOffset : foldOffset);

    // 对于中间翻页，折叠线是垂直的
    final actualFoldTopX = origin == FlipOrigin.middle ? baseFoldX : foldTopX;
    final actualFoldBottomX = origin == FlipOrigin.middle ? baseFoldX : foldBottomX;

    // 创建未翻起部分的裁剪路径
    final unflippedPath = Path();
    if (isForward) {
      unflippedPath.moveTo(0, 0);
      unflippedPath.lineTo(actualFoldTopX.clamp(0, screenWidth), 0);
      unflippedPath.lineTo(actualFoldBottomX.clamp(0, screenWidth), screenHeight);
      unflippedPath.lineTo(0, screenHeight);
      unflippedPath.close();
    } else {
      unflippedPath.moveTo(screenWidth, 0);
      unflippedPath.lineTo(actualFoldTopX.clamp(0, screenWidth), 0);
      unflippedPath.lineTo(actualFoldBottomX.clamp(0, screenWidth), screenHeight);
      unflippedPath.lineTo(screenWidth, screenHeight);
      unflippedPath.close();
    }

    // 绘制未翻起的部分
    canvas.save();
    canvas.clipPath(unflippedPath);
    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, screenWidth, screenHeight);
    canvas.drawImageRect(image, srcRect, dstRect, Paint());
    canvas.restore();

    // 绘制折叠线阴影
    if (curlProgress > 0.02) {
      _drawFoldShadow(canvas, actualFoldTopX, actualFoldBottomX, curlProgress, isForward);
    }

    // 绘制翻起的页面
    _drawFlippedPage(canvas, actualFoldTopX, actualFoldBottomX, curlProgress, isForward);

    // 绘制页面背面
    if (curlProgress > 0.05) {
      _drawPageBack(canvas, actualFoldTopX, actualFoldBottomX, curlProgress, isForward);
    }

    // 绘制折叠线高光
    if (curlProgress > 0.02) {
      _drawFoldHighlight(canvas, actualFoldTopX, actualFoldBottomX, curlProgress);
    }
  }

  /// 绘制折叠阴影
  void _drawFoldShadow(Canvas canvas, double foldTopX, double foldBottomX,
      double curlProgress, bool isForward) {
    final shadowWidth = 20.0 * curlProgress;

    final shadowPath = Path();
    if (isForward) {
      shadowPath.moveTo(foldTopX - shadowWidth, 0);
      shadowPath.lineTo(foldTopX, 0);
      shadowPath.lineTo(foldBottomX, screenHeight);
      shadowPath.lineTo(foldBottomX - shadowWidth, screenHeight);
      shadowPath.close();
    } else {
      shadowPath.moveTo(foldTopX, 0);
      shadowPath.lineTo(foldTopX + shadowWidth, 0);
      shadowPath.lineTo(foldBottomX + shadowWidth, screenHeight);
      shadowPath.lineTo(foldBottomX, screenHeight);
      shadowPath.close();
    }

    canvas.save();
    canvas.clipPath(shadowPath);

    final shadowGradient = ui.Gradient.linear(
      Offset(isForward ? foldTopX - shadowWidth : foldTopX, 0),
      Offset(isForward ? foldTopX : foldTopX + shadowWidth, 0),
      [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.35 * curlProgress),
      ],
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, screenWidth, screenHeight),
      Paint()..shader = shadowGradient,
    );
    canvas.restore();
  }

  /// 绘制翻起的页面
  void _drawFlippedPage(Canvas canvas, double foldTopX, double foldBottomX,
      double curlProgress, bool isForward) {
    // 翻起页面的路径
    final flippedPath = Path();
    if (isForward) {
      flippedPath.moveTo(foldTopX, 0);
      flippedPath.lineTo(screenWidth, 0);
      flippedPath.lineTo(screenWidth, screenHeight);
      flippedPath.lineTo(foldBottomX, screenHeight);
      flippedPath.close();
    } else {
      flippedPath.moveTo(0, 0);
      flippedPath.lineTo(foldTopX, 0);
      flippedPath.lineTo(foldBottomX, screenHeight);
      flippedPath.lineTo(0, screenHeight);
      flippedPath.close();
    }

    canvas.save();
    canvas.clipPath(flippedPath);

    // 计算折叠线中点
    final foldCenterX = (foldTopX + foldBottomX) / 2;
    final foldCenterY = screenHeight / 2;

    // 计算折叠线角度
    final lineAngle = math.atan2(foldBottomX - foldTopX, screenHeight);

    // 移动到折叠线中心
    canvas.translate(foldCenterX, foldCenterY);

    // 先旋转到折叠线方向
    canvas.rotate(-lineAngle);

    // 应用 3D 翻转
    final flipAngle = curlProgress * math.pi * 0.55;
    final perspective = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateY(isForward ? flipAngle : -flipAngle);
    canvas.transform(perspective.storage);

    // 旋转回来
    canvas.rotate(lineAngle);

    // 移动回原点
    canvas.translate(-foldCenterX, -foldCenterY);

    // 绘制页面
    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, screenWidth, screenHeight);
    canvas.drawImageRect(image, srcRect, dstRect, Paint());

    // 添加阴影效果
    canvas.drawRect(
      dstRect,
      Paint()..color = Colors.black.withValues(alpha: 0.25 * curlProgress),
    );

    canvas.restore();
  }

  /// 绘制页面背面
  void _drawPageBack(Canvas canvas, double foldTopX, double foldBottomX,
      double curlProgress, bool isForward) {
    // 背面宽度
    final backWidth = 40.0 * curlProgress;

    // 计算背面区域
    final backPath = Path();
    if (isForward) {
      backPath.moveTo(foldTopX, 0);
      backPath.lineTo(foldTopX + backWidth, 0);
      backPath.lineTo(foldBottomX + backWidth, screenHeight);
      backPath.lineTo(foldBottomX, screenHeight);
      backPath.close();
    } else {
      backPath.moveTo(foldTopX - backWidth, 0);
      backPath.lineTo(foldTopX, 0);
      backPath.lineTo(foldBottomX, screenHeight);
      backPath.lineTo(foldBottomX - backWidth, screenHeight);
      backPath.close();
    }

    canvas.save();
    canvas.clipPath(backPath);

    // 绘制背面颜色
    canvas.drawRect(
      Rect.fromLTWH(0, 0, screenWidth, screenHeight),
      Paint()..color = const Color(0xFFF0EDE8),
    );

    // 绘制镜像的页面内容（透过来的文字效果）
    canvas.save();
    final mirrorCenterX = (foldTopX + foldBottomX) / 2;
    canvas.translate(mirrorCenterX, 0);
    canvas.scale(-1, 1);
    canvas.translate(-mirrorCenterX, 0);

    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, screenWidth, screenHeight);
    canvas.drawImageRect(
      image,
      srcRect,
      dstRect,
      Paint()..color = Colors.white.withValues(alpha: 0.15),
    );
    canvas.restore();

    // 背面渐变阴影
    final backGradient = ui.Gradient.linear(
      Offset(isForward ? foldTopX : foldTopX - backWidth, 0),
      Offset(isForward ? foldTopX + backWidth : foldTopX, 0),
      [
        Colors.black.withValues(alpha: 0.12 * curlProgress),
        Colors.transparent,
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, screenWidth, screenHeight),
      Paint()..shader = backGradient,
    );

    canvas.restore();
  }

  /// 绘制折叠线高光
  void _drawFoldHighlight(Canvas canvas, double foldTopX, double foldBottomX,
      double curlProgress) {
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6 * curlProgress)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(foldTopX, 0),
      Offset(foldBottomX, screenHeight),
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(_PageCurlPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      direction != oldDelegate.direction ||
      origin != oldDelegate.origin ||
      image != oldDelegate.image;
}
