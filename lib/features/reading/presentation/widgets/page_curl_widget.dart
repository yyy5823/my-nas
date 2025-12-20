import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 翻页方向
enum PageCurlDirection {
  left,  // 向左翻（下一页）
  right, // 向右翻（上一页）
}

/// 页面卷曲翻页 Widget
///
/// 使用 Fragment Shader 实现仿真翻页效果
/// 通过预渲染页面图像来避免实时截图的性能问题
class PageCurlWidget extends StatefulWidget {
  const PageCurlWidget({
    required this.child,
    required this.onNextPage,
    required this.onPrevPage,
    this.enabled = true,
    this.curlRadius = 0.08,
    this.shadowIntensity = 0.4,
    this.animationDuration = const Duration(milliseconds: 350),
    this.dragThreshold = 0.3,
    super.key,
  });

  /// 当前页面内容
  final Widget child;

  /// 下一页回调
  final Future<void> Function() onNextPage;

  /// 上一页回调
  final Future<void> Function() onPrevPage;

  /// 是否启用仿真翻页
  final bool enabled;

  /// 卷曲半径（相对于页面宽度的比例）
  final double curlRadius;

  /// 阴影强度
  final double shadowIntensity;

  /// 动画时长
  final Duration animationDuration;

  /// 拖动阈值（超过此比例触发翻页）
  final double dragThreshold;

  @override
  State<PageCurlWidget> createState() => _PageCurlWidgetState();
}

class _PageCurlWidgetState extends State<PageCurlWidget>
    with SingleTickerProviderStateMixin {
  /// Shader 程序
  ui.FragmentProgram? _shaderProgram;
  ui.FragmentShader? _shader;

  /// 动画控制器
  late AnimationController _animationController;
  late Animation<double> _curlAnimation;

  /// 当前卷曲位置 (0.0 - 1.0)
  double _curlPosition = 0.0;

  /// 翻页方向
  PageCurlDirection? _curlDirection;

  /// 是否正在翻页动画中
  bool _isAnimating = false;

  /// 拖动起始位置
  Offset? _dragStartPosition;

  /// 预渲染的当前页面图像
  ui.Image? _currentPageImage;

  /// 预渲染的下一页图像（占位白色）
  ui.Image? _nextPageImage;

  /// 用于捕获页面图像的 GlobalKey
  final GlobalKey _captureKey = GlobalKey();

  /// 是否已加载 shader
  bool _shaderLoaded = false;

  @override
  void initState() {
    super.initState();
    _initAnimationController();
    _loadShader();
    _createPlaceholderImage();
  }

  void _initAnimationController() {
    _animationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    _curlAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );

    _animationController..addListener(() {
      if (mounted) {
        setState(() {
          if (_curlDirection == PageCurlDirection.left) {
            _curlPosition = _curlAnimation.value;
          } else {
            _curlPosition = 1.0 - _curlAnimation.value;
          }
        });
      }
    })

    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onAnimationComplete();
      }
    });
  }

  Future<void> _loadShader() async {
    try {
      _shaderProgram = await ui.FragmentProgram.fromAsset('shaders/page_curl.frag');
      _shader = _shaderProgram!.fragmentShader();
      if (mounted) {
        setState(() {
          _shaderLoaded = true;
        });
      }
      logger.d('PageCurlWidget: Shader 加载成功');
    } on Exception catch (e, st) {
      logger.e('PageCurlWidget: Shader 加载失败', e, st);
      // Shader 加载失败时禁用效果，使用普通翻页
    }
  }

  /// 创建占位图像（白色/透明）
  Future<void> _createPlaceholderImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
    ..drawRect(
      const Rect.fromLTWH(0, 0, 100, 100),
      Paint()..color = Colors.white,
    );
    final picture = recorder.endRecording();
    _nextPageImage = await picture.toImage(100, 100);
  }

  /// 捕获当前页面为图像
  Future<ui.Image?> _captureCurrentPage() async {
    try {
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 1.5);
      return image;
    } on Exception catch (e) {
      logger.w('PageCurlWidget: 捕获页面失败 - $e');
      return null;
    }
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enabled || _isAnimating || !_shaderLoaded) return;
    _dragStartPosition = details.localPosition;
  }

  Future<void> _onDragUpdate(DragUpdateDetails details) async {
    if (!widget.enabled || _isAnimating || _dragStartPosition == null) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final dragDelta = details.localPosition.dx - _dragStartPosition!.dx;
    final dragRatio = dragDelta.abs() / screenWidth;

    // 确定翻页方向
    if (_curlDirection == null && dragRatio > 0.02) {
      _curlDirection = dragDelta < 0
          ? PageCurlDirection.left
          : PageCurlDirection.right;

      // 开始拖动时捕获当前页面
      _currentPageImage = await _captureCurrentPage();
      if (_currentPageImage == null) {
        _curlDirection = null;
        return;
      }
    }

    if (_curlDirection != null) {
      setState(() {
        if (_curlDirection == PageCurlDirection.left) {
          _curlPosition = (dragRatio).clamp(0.0, 1.0);
        } else {
          _curlPosition = (1.0 - dragRatio).clamp(0.0, 1.0);
        }
      });
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled || _curlDirection == null) {
      _resetDrag();
      return;
    }

    final shouldComplete = _curlDirection == PageCurlDirection.left
        ? _curlPosition > widget.dragThreshold
        : _curlPosition < (1.0 - widget.dragThreshold);

    if (shouldComplete) {
      _completePageTurn();
    } else {
      _cancelPageTurn();
    }
  }

  void _onDragCancel() {
    if (_curlDirection != null) {
      _cancelPageTurn();
    } else {
      _resetDrag();
    }
  }

  void _completePageTurn() {
    _isAnimating = true;
    _animationController.value = _curlDirection == PageCurlDirection.left
        ? _curlPosition
        : 1.0 - _curlPosition;
    _animationController.forward();

    // 触发触觉反馈
    HapticFeedback.lightImpact();
  }

  void _cancelPageTurn() {
    _isAnimating = true;
    if (_curlDirection == PageCurlDirection.left) {
      _animationController.value = _curlPosition;
      _animationController.reverse();
    } else {
      _animationController.value = 1.0 - _curlPosition;
      _animationController.reverse();
    }
  }

  Future<void> _onAnimationComplete() async {
    final direction = _curlDirection;
    final wasCompleting = _animationController.status == AnimationStatus.completed;

    if (wasCompleting && direction != null) {
      // 执行翻页
      if (direction == PageCurlDirection.left) {
        await widget.onNextPage();
      } else {
        await widget.onPrevPage();
      }
    }

    _resetDrag();
  }

  void _resetDrag() {
    _dragStartPosition = null;
    _curlDirection = null;
    _isAnimating = false;
    _curlPosition = 0.0;
    _currentPageImage?.dispose();
    _currentPageImage = null;
    _animationController.reset();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _animationController.dispose();
    _currentPageImage?.dispose();
    _nextPageImage?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 如果未启用或 shader 未加载，直接显示内容
    if (!widget.enabled || !_shaderLoaded) {
      return widget.child;
    }

    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      child: Stack(
        children: [
          // 使用 RepaintBoundary 包裹以便捕获
          RepaintBoundary(
            key: _captureKey,
            child: widget.child,
          ),

          // 翻页动画层（仅在翻页时显示）
          if (_curlDirection != null && _currentPageImage != null)
            Positioned.fill(
              child: CustomPaint(
                painter: _PageCurlPainter(
                  shader: _shader!,
                  currentImage: _currentPageImage!,
                  nextImage: _nextPageImage,
                  curlPosition: _curlPosition,
                  curlRadius: widget.curlRadius,
                  shadowIntensity: widget.shadowIntensity,
                  direction: _curlDirection!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 页面卷曲绘制器
class _PageCurlPainter extends CustomPainter {
  _PageCurlPainter({
    required this.shader,
    required this.currentImage,
    this.nextImage,
    required this.curlPosition,
    required this.curlRadius,
    required this.shadowIntensity,
    required this.direction,
  });

  final ui.FragmentShader shader;
  final ui.Image currentImage;
  final ui.Image? nextImage;
  final double curlPosition;
  final double curlRadius;
  final double shadowIntensity;
  final PageCurlDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    // 配置 shader uniforms
    shader..setFloat(0, size.width)   // uResolution.x
    ..setFloat(1, size.height)  // uResolution.y
    ..setFloat(2, curlPosition) // uCurlPosition
    ..setFloat(3, curlRadius)   // uCurlRadius
    ..setFloat(4, shadowIntensity) // uShadowIntensity
    ..setImageSampler(0, currentImage); // uTexture

    if (nextImage != null) {
      shader.setImageSampler(1, nextImage!); // uNextTexture
    }

    // 绘制 shader
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_PageCurlPainter oldDelegate) =>
      curlPosition != oldDelegate.curlPosition ||
      currentImage != oldDelegate.currentImage ||
      direction != oldDelegate.direction;
}
