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
/// 使用 Flutter Shader 实现真实的书页翻转效果
/// 支持仿真翻页和覆盖翻页两种模式
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
    this.backgroundColor = Colors.white,
    this.nextPageBuilder,
    this.prevPageBuilder,
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

  /// 下一页内容构建器（用于预渲染下一页）
  final Widget Function()? nextPageBuilder;

  /// 上一页内容构建器（用于预渲染上一页）
  final Widget Function()? prevPageBuilder;

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
  ui.Image? _currentPageImage;

  /// 捕获的目标页面图像（下一页或上一页）
  ui.Image? _targetPageImage;

  /// 用于捕获当前页面的 GlobalKey
  final GlobalKey _currentPageKey = GlobalKey();

  /// 用于捕获目标页面的 GlobalKey
  final GlobalKey _targetPageKey = GlobalKey();

  /// 是否正在捕获
  bool _isCapturing = false;

  /// Shader 是否加载完成
  bool _shaderLoaded = false;

  /// Shader 程序
  ui.FragmentProgram? _shaderProgram;

  // 点击检测
  Offset? _tapDownPosition;
  DateTime? _tapDownTime;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    )
      ..addListener(_onAnimationUpdate)
      ..addStatusListener(_onAnimationStatus);

    // 预加载 shader
    if (widget.mode == PageFlipMode.simulation) {
      _loadShader();
    }
  }

  Future<void> _loadShader() async {
    try {
      _shaderProgram = await ui.FragmentProgram.fromAsset('shaders/page_curl.frag');
      if (mounted) {
        setState(() => _shaderLoaded = true);
      }
    } on Exception catch (e) {
      logger.w('PageFlipEffect: 加载 shader 失败 - $e');
      // 如果 shader 加载失败，回退到覆盖翻页模式
    }
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
    _currentPageImage?.dispose();
    _currentPageImage = null;
    _targetPageImage?.dispose();
    _targetPageImage = null;
    _controller.reset();
    if (mounted) setState(() {});
  }

  /// 捕获指定 key 对应的页面
  Future<ui.Image?> _captureWidget(GlobalKey key) async {
    if (_isCapturing) return null;
    _isCapturing = true;

    try {
      await Future<void>.delayed(const Duration(milliseconds: 16));

      if (!mounted) return null;

      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject == null || renderObject is! RenderRepaintBoundary) {
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
      _currentPageImage = await _captureWidget(_currentPageKey);
      if (_currentPageImage == null) {
        _direction = null;
        return;
      }

      // 捕获目标页面
      _targetPageImage = await _captureWidget(_targetPageKey);
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
    _currentPageImage?.dispose();
    _targetPageImage?.dispose();
    super.dispose();
  }

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
            // 目标页面（预渲染，用于捕获）
            if (_direction != null)
              Positioned.fill(
                child: Offstage(
                  offstage: true,
                  child: RepaintBoundary(
                    key: _targetPageKey,
                    child: _direction == FlipDirection.forward
                        ? (widget.nextPageBuilder?.call() ?? widget.child)
                        : (widget.prevPageBuilder?.call() ?? widget.child),
                  ),
                ),
              ),

            // 当前页面
            RepaintBoundary(
              key: _currentPageKey,
              child: widget.child,
            ),

            // 翻页动画层
            if (_direction != null && _currentPageImage != null)
              Positioned.fill(
                child: _buildFlipEffect(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlipEffect() {
    if (widget.mode == PageFlipMode.simulation && _shaderLoaded && _shaderProgram != null) {
      return _buildShaderSimulationEffect();
    }
    return _buildCoverEffect();
  }

  /// 使用 Shader 的仿真翻页效果
  Widget _buildShaderSimulationEffect() => CustomPaint(
    painter: _ShaderPageCurlPainter(
      shaderProgram: _shaderProgram!,
      currentPage: _currentPageImage!,
      nextPage: _targetPageImage ?? _currentPageImage!,
      progress: _dragProgress,
      direction: _direction == FlipDirection.forward ? 1.0 : -1.0,
      dragStartY: _dragStartY,
      backgroundColor: widget.backgroundColor,
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
        // 背景（目标页面）
        if (_targetPageImage != null)
          Positioned.fill(
            child: RawImage(
              image: _targetPageImage,
              fit: BoxFit.cover,
            ),
          )
        else
          ColoredBox(
            color: widget.backgroundColor,
            child: const SizedBox.expand(),
          ),

        // 滑动的当前页面
        Transform.translate(
          offset: Offset(slideOffset, 0),
          child: Stack(
            children: [
              Positioned.fill(
                child: RawImage(
                  image: _currentPageImage,
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

/// Shader 翻页绘制器
class _ShaderPageCurlPainter extends CustomPainter {
  _ShaderPageCurlPainter({
    required this.shaderProgram,
    required this.currentPage,
    required this.nextPage,
    required this.progress,
    required this.direction,
    required this.dragStartY,
    required this.backgroundColor,
  });

  final ui.FragmentProgram shaderProgram;
  final ui.Image currentPage;
  final ui.Image nextPage;
  final double progress;
  final double direction;
  final double dragStartY;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) {
      // 无进度时直接绘制当前页
      canvas.drawImageRect(
        currentPage,
        Rect.fromLTWH(0, 0, currentPage.width.toDouble(), currentPage.height.toDouble()),
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint(),
      );
      return;
    }

    final shader = shaderProgram.fragmentShader()
      // 设置 uniform 变量
      ..setFloat(0, size.width)   // resolution.x
      ..setFloat(1, size.height)  // resolution.y
      ..setFloat(2, progress)      // progress
      ..setFloat(3, direction)     // direction
      ..setFloat(4, dragStartY)    // dragStartY
      // Color 的 .r, .g, .b, .a 属性已经是 0.0-1.0 范围
      ..setFloat(5, backgroundColor.r) // backgroundColor.r
      ..setFloat(6, backgroundColor.g) // backgroundColor.g
      ..setFloat(7, backgroundColor.b) // backgroundColor.b
      ..setFloat(8, backgroundColor.a) // backgroundColor.a
      ..setImageSampler(0, currentPage) // currentPage
      ..setImageSampler(1, nextPage);   // nextPage

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_ShaderPageCurlPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      direction != oldDelegate.direction ||
      currentPage != oldDelegate.currentPage ||
      nextPage != oldDelegate.nextPage ||
      dragStartY != oldDelegate.dragStartY;
}
