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

/// 页面卷曲绘制器
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

    // 计算卷曲参数
    final curlProgress = progress.clamp(0.0, 1.0);

    // 页面翻起的位置（从右边开始）
    final foldX = isForward
        ? screenWidth * (1.0 - curlProgress)
        : screenWidth * curlProgress;

    // 根据起始位置计算卷曲角度
    final curlAngle = switch (origin) {
      FlipOrigin.top => -math.pi / 8 * curlProgress,
      FlipOrigin.bottom => math.pi / 8 * curlProgress,
      FlipOrigin.middle => 0.0,
    };

    // 绘制背景（下一页 - 白色）
    canvas.drawRect(
      Rect.fromLTWH(0, 0, screenWidth, screenHeight),
      Paint()..color = Colors.white,
    );

    // 保存画布状态
    canvas.save();

    // 绘制未翻起的部分（左侧仍然显示的当前页）
    if (isForward && foldX > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, foldX, screenHeight));

      // 绘制原始页面内容
      final srcRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dstRect = Rect.fromLTWH(0, 0, screenWidth, screenHeight);
      canvas.drawImageRect(image, srcRect, dstRect, Paint());

      canvas.restore();
    } else if (!isForward && foldX < screenWidth) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(foldX, 0, screenWidth - foldX, screenHeight));

      final srcRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dstRect = Rect.fromLTWH(0, 0, screenWidth, screenHeight);
      canvas.drawImageRect(image, srcRect, dstRect, Paint());

      canvas.restore();
    }

    // 绘制折叠阴影（投射到下层页面）
    final shadowWidth = 25.0 * curlProgress;
    if (shadowWidth > 0) {
      final shadowRect = isForward
          ? Rect.fromLTWH(foldX - shadowWidth, 0, shadowWidth, screenHeight)
          : Rect.fromLTWH(foldX, 0, shadowWidth, screenHeight);

      final shadowGradient = ui.Gradient.linear(
        isForward ? Offset(foldX - shadowWidth, 0) : Offset(foldX, 0),
        isForward ? Offset(foldX, 0) : Offset(foldX + shadowWidth, 0),
        [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.3 * curlProgress),
        ],
      );

      canvas.drawRect(
        shadowRect,
        Paint()..shader = shadowGradient,
      );
    }

    // 绘制翻起的页面（右侧部分）
    canvas.save();

    // 计算翻起页面的变换
    final flipWidth = isForward
        ? screenWidth - foldX
        : foldX;

    if (flipWidth > 0) {
      // 应用 3D 变换
      canvas.save();

      // 移动到折叠线位置，并根据起始位置调整中心点
      final centerY = switch (origin) {
        FlipOrigin.top => screenHeight * 0.2,
        FlipOrigin.bottom => screenHeight * 0.8,
        FlipOrigin.middle => screenHeight / 2,
      };

      canvas.translate(foldX, centerY);

      // 应用透视旋转（包括角落翻页的倾斜角度）
      final angle = curlProgress * math.pi * 0.6;
      final perspective = Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateZ(curlAngle) // 从角落翻页的倾斜效果
        ..rotateY(isForward ? angle : -angle);

      canvas.translate(0, -centerY);

      // 绘制翻起的页面
      canvas.transform(perspective.storage);

      // 绘制页面内容（翻起部分）
      final srcRect = Rect.fromLTWH(
        isForward ? image.width * (1 - curlProgress) : 0,
        0,
        image.width * curlProgress,
        image.height.toDouble(),
      );

      final pageDstRect = Rect.fromLTWH(
        0,
        0,
        flipWidth,
        screenHeight,
      );

      // 页面正面
      if (angle < math.pi / 2) {
        canvas.drawImageRect(
          image,
          srcRect,
          pageDstRect,
          Paint(),
        );

        // 正面阴影（越翻越暗）
        final frontShadow = Paint()
          ..color = Colors.black.withValues(alpha: 0.3 * curlProgress);
        canvas.drawRect(pageDstRect, frontShadow);
      }

      canvas.restore();

      // 绘制页面背面（镜像效果）
      if (curlProgress > 0.1) {
        canvas.save();

        // 背面位置
        final backWidth = math.min(flipWidth * 0.3, 60.0);
        final backRect = isForward
            ? Rect.fromLTWH(foldX, 0, backWidth, screenHeight)
            : Rect.fromLTWH(foldX - backWidth, 0, backWidth, screenHeight);

        canvas.clipRect(backRect);

        // 背面颜色（纸张背面略暗）
        canvas.drawRect(
          backRect,
          Paint()..color = const Color(0xFFF5F5F0),
        );

        // 背面文字效果（镜像）
        canvas.save();
        if (isForward) {
          canvas.translate(foldX + backWidth, 0);
          canvas.scale(-1, 1);
        } else {
          canvas.translate(foldX, 0);
          canvas.scale(-1, 1);
        }

        // 绘制镜像的页面内容（模糊效果表示背面透过来的文字）
        final backSrcRect = Rect.fromLTWH(
          isForward ? image.width * (1 - curlProgress * 0.3) : 0,
          0,
          image.width * 0.3,
          image.height.toDouble(),
        );

        final backDstRect = Rect.fromLTWH(
          0,
          0,
          backWidth,
          screenHeight,
        );

        canvas.drawImageRect(
          image,
          backSrcRect,
          backDstRect,
          Paint()..color = Colors.white.withValues(alpha: 0.3),
        );

        canvas.restore();

        // 背面阴影
        final backShadowGradient = ui.Gradient.linear(
          isForward ? Offset(foldX, 0) : Offset(foldX - backWidth, 0),
          isForward ? Offset(foldX + backWidth, 0) : Offset(foldX, 0),
          [
            Colors.black.withValues(alpha: 0.15 * curlProgress),
            Colors.transparent,
          ],
        );

        canvas.drawRect(
          backRect,
          Paint()..shader = backShadowGradient,
        );

        canvas.restore();
      }
    }

    canvas.restore();

    // 恢复画布状态
    canvas.restore();

    // 绘制页面边缘高光（卷曲处）
    if (curlProgress > 0.05) {
      final highlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.5 * curlProgress)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      final highlightX = isForward ? foldX : foldX;
      canvas.drawLine(
        Offset(highlightX, 0),
        Offset(highlightX, screenHeight),
        highlightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_PageCurlPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      direction != oldDelegate.direction ||
      origin != oldDelegate.origin ||
      image != oldDelegate.image;
}
