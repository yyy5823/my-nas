import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

/// 书籍翻页加载动画
/// 模拟一本书不断翻动的效果
class BookFlipLoading extends StatefulWidget {
  const BookFlipLoading({
    super.key,
    this.message,
    this.size = 80,
    this.backgroundColor,
    this.textColor,
    this.bookColor,
    this.pageColor,
  });

  final String? message;
  final double size;

  /// 自定义背景色
  final Color? backgroundColor;

  /// 自定义文字颜色
  final Color? textColor;

  /// 书籍封面颜色
  final Color? bookColor;

  /// 书页颜色
  final Color? pageColor;

  @override
  State<BookFlipLoading> createState() => _BookFlipLoadingState();
}

class _BookFlipLoadingState extends State<BookFlipLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
            builder: (context, child) => CustomPaint(
              size: Size(widget.size, widget.size * 0.8),
              painter: _BookFlipPainter(
                progress: _controller.value,
                bookColor: widget.bookColor ?? AppColors.primary,
                pageColor: widget.pageColor ??
                    (isDark ? const Color(0xFFF5F1E8) : Colors.white),
                shadowColor: isDark
                    ? Colors.black.withValues(alpha: 0.4)
                    : Colors.black.withValues(alpha: 0.2),
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

/// 书籍翻页绘制器
class _BookFlipPainter extends CustomPainter {
  _BookFlipPainter({
    required this.progress,
    required this.bookColor,
    required this.pageColor,
    required this.shadowColor,
  });

  final double progress;
  final Color bookColor;
  final Color pageColor;
  final Color shadowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final bookWidth = size.width * 0.8;
    final bookHeight = size.height;
    final bookLeft = (size.width - bookWidth) / 2;
    final bookTop = 0.0;

    // 书脊位置（中心）
    final spineX = bookLeft + bookWidth / 2;

    // 绘制书籍阴影
    final shadowRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        bookLeft + 4,
        bookTop + 4,
        bookWidth,
        bookHeight,
      ),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      shadowRect,
      Paint()
        ..color = shadowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // 绘制左侧书页（固定的底层页面）
    _drawLeftPages(canvas, bookLeft, bookTop, bookWidth / 2 - 2, bookHeight);

    // 绘制右侧书页（固定的底层页面）
    _drawRightPages(
        canvas, spineX + 2, bookTop, bookWidth / 2 - 2, bookHeight);

    // 绘制翻动的书页
    _drawFlippingPage(canvas, spineX, bookTop, bookWidth / 2, bookHeight);

    // 绘制书脊
    _drawSpine(canvas, spineX, bookTop, bookHeight);

    // 绘制封面边缘
    _drawBookEdges(canvas, bookLeft, bookTop, bookWidth, bookHeight);
  }

  /// 绘制左侧页面堆叠效果
  void _drawLeftPages(
      Canvas canvas, double left, double top, double width, double height) {
    final pagePaint = Paint()..style = PaintingStyle.fill;

    // 多层页面
    for (var i = 3; i >= 0; i--) {
      final offset = i * 1.5;
      final pageRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left + offset, top + 2, width - offset, height - 4),
        topLeft: const Radius.circular(2),
        bottomLeft: const Radius.circular(2),
      );

      // 页面颜色逐渐变深
      final shade = 1.0 - i * 0.05;
      pagePaint.color = Color.lerp(pageColor, Colors.grey.shade300, 1 - shade)!;

      canvas.drawRRect(pageRect, pagePaint);
    }

    // 绘制页面线条
    final linePaint = Paint()
      ..color = Colors.grey.shade300.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;

    for (var i = 0; i < 6; i++) {
      final y = top + 12 + i * 8.0;
      if (y < top + height - 10) {
        canvas.drawLine(
          Offset(left + 8, y),
          Offset(left + width - 8, y),
          linePaint,
        );
      }
    }
  }

  /// 绘制右侧页面堆叠效果
  void _drawRightPages(
      Canvas canvas, double left, double top, double width, double height) {
    final pagePaint = Paint()..style = PaintingStyle.fill;

    // 多层页面
    for (var i = 3; i >= 0; i--) {
      final offset = i * 1.5;
      final pageRect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top + 2, width - offset, height - 4),
        topRight: const Radius.circular(2),
        bottomRight: const Radius.circular(2),
      );

      final shade = 1.0 - i * 0.05;
      pagePaint.color = Color.lerp(pageColor, Colors.grey.shade300, 1 - shade)!;

      canvas.drawRRect(pageRect, pagePaint);
    }

    // 绘制页面线条
    final linePaint = Paint()
      ..color = Colors.grey.shade300.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;

    for (var i = 0; i < 6; i++) {
      final y = top + 12 + i * 8.0;
      if (y < top + height - 10) {
        canvas.drawLine(
          Offset(left + 8, y),
          Offset(left + width - 8, y),
          linePaint,
        );
      }
    }
  }

  /// 绘制翻动的书页
  void _drawFlippingPage(
      Canvas canvas, double spineX, double top, double pageWidth, double height) {
    // 使用正弦函数创建更自然的翻页动画
    // progress: 0 -> 0.5: 从右向左翻
    // progress: 0.5 -> 1: 从左向右翻回（准备下一页）
    final double flipProgress;
    final bool isFlippingLeft;

    if (progress < 0.5) {
      flipProgress = progress * 2; // 0 -> 1
      isFlippingLeft = true;
    } else {
      flipProgress = (progress - 0.5) * 2; // 0 -> 1
      isFlippingLeft = false;
    }

    // 使用缓动函数使动画更自然
    final easedProgress = _easeInOutCubic(flipProgress);

    // 计算翻页角度 (0 到 π)
    final angle = isFlippingLeft
        ? easedProgress * math.pi
        : math.pi - easedProgress * math.pi;

    // 绘制翻动页面
    canvas
      ..save()
      // 设置透视变换的中心点为书脊
      ..translate(spineX, top + height / 2);

    // 添加简单的3D透视效果
    final perspective = Matrix4.identity()
      ..setEntry(3, 2, 0.001) // 透视深度
      ..rotateY(angle - math.pi / 2); // 绕Y轴旋转

    canvas
      ..transform(perspective.storage)
      ..translate(0, -height / 2);

    // 根据角度决定绘制页面的哪一面
    final showFront = angle < math.pi / 2;

    if (showFront) {
      // 正面（右侧页）
      _drawPageContent(
        canvas,
        Rect.fromLTWH(0, 2, pageWidth - 4, height - 4),
        isRightPage: true,
      );
    } else {
      // 背面（左侧页），需要镜像
      canvas.scale(-1, 1);
      _drawPageContent(
        canvas,
        Rect.fromLTWH(0, 2, pageWidth - 4, height - 4),
        isRightPage: false,
      );
    }

    canvas.restore();

    // 绘制阴影效果
    _drawPageShadow(canvas, spineX, top, pageWidth, height, easedProgress,
        isFlippingLeft);
  }

  /// 缓动函数
  double _easeInOutCubic(double t) {
    if (t < 0.5) {
      return 4 * t * t * t;
    } else {
      return 1 - math.pow(-2 * t + 2, 3) / 2;
    }
  }

  /// 绘制页面内容
  void _drawPageContent(Canvas canvas, Rect rect, {required bool isRightPage}) {
    // 页面背景
    final pageRRect = RRect.fromRectAndCorners(
      rect,
      topRight: isRightPage ? const Radius.circular(2) : Radius.zero,
      bottomRight: isRightPage ? const Radius.circular(2) : Radius.zero,
      topLeft: !isRightPage ? const Radius.circular(2) : Radius.zero,
      bottomLeft: !isRightPage ? const Radius.circular(2) : Radius.zero,
    );

    // 绘制页面和边框
    canvas
      ..drawRRect(
        pageRRect,
        Paint()..color = pageColor,
      )
      ..drawRRect(
        pageRRect,
        Paint()
          ..color = Colors.grey.shade400
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );

    // 绘制内容线条
    final linePaint = Paint()
      ..color = Colors.grey.shade300.withValues(alpha: 0.7)
      ..strokeWidth = 0.5;

    final lineStart = isRightPage ? rect.left + 6 : rect.left + 6;
    final lineEnd = isRightPage ? rect.right - 6 : rect.right - 6;

    for (var i = 0; i < 5; i++) {
      final y = rect.top + 10 + i * 8.0;
      if (y < rect.bottom - 10) {
        // 随机长度的线条模拟文字
        final length = 0.5 + (i % 3) * 0.2;
        canvas.drawLine(
          Offset(lineStart, y),
          Offset(lineStart + (lineEnd - lineStart) * length, y),
          linePaint,
        );
      }
    }
  }

  /// 绘制翻页阴影
  void _drawPageShadow(Canvas canvas, double spineX, double top,
      double pageWidth, double height, double progress, bool isFlippingLeft) {
    // 计算阴影强度（在翻页中间最强）
    final shadowIntensity = math.sin(progress * math.pi) * 0.3;

    if (shadowIntensity > 0.01) {
      final shadowWidth = pageWidth * 0.3;

      if (isFlippingLeft) {
        // 在右侧页面上的阴影
        final shadowRect = Rect.fromLTWH(
          spineX,
          top,
          shadowWidth * (1 - progress),
          height,
        );
        final shadowGradient = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            shadowColor.withValues(alpha: shadowIntensity),
            shadowColor.withValues(alpha: 0),
          ],
        );
        canvas.drawRect(
          shadowRect,
          Paint()..shader = shadowGradient.createShader(shadowRect),
        );
      } else {
        // 在左侧页面上的阴影
        final shadowRect = Rect.fromLTWH(
          spineX - shadowWidth * progress,
          top,
          shadowWidth * progress,
          height,
        );
        final shadowGradient = LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            shadowColor.withValues(alpha: shadowIntensity),
            shadowColor.withValues(alpha: 0),
          ],
        );
        canvas.drawRect(
          shadowRect,
          Paint()..shader = shadowGradient.createShader(shadowRect),
        );
      }
    }
  }

  /// 绘制书脊
  void _drawSpine(
      Canvas canvas, double spineX, double top, double height) {
    // 书脊宽度
    const spineWidth = 6.0;

    // 书脊渐变
    final spineRect = Rect.fromLTWH(
      spineX - spineWidth / 2,
      top,
      spineWidth,
      height,
    );

    final spineGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        bookColor.withValues(alpha: 0.8),
        bookColor,
        bookColor.withValues(alpha: 0.9),
      ],
      stops: const [0, 0.5, 1],
    );

    canvas
      ..drawRect(
        spineRect,
        Paint()..shader = spineGradient.createShader(spineRect),
      )
      // 书脊高光
      ..drawLine(
        Offset(spineX - 1, top + 2),
        Offset(spineX - 1, top + height - 2),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.3)
          ..strokeWidth = 1,
      );
  }

  /// 绘制书籍边缘（封面效果）
  void _drawBookEdges(
      Canvas canvas, double left, double top, double width, double height) {
    final edgePaint = Paint()
      ..color = bookColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // 左侧封面边缘
    final leftEdge = RRect.fromRectAndCorners(
      Rect.fromLTWH(left, top, width / 2 - 3, height),
      topLeft: const Radius.circular(4),
      bottomLeft: const Radius.circular(4),
    );
    canvas.drawRRect(leftEdge, edgePaint);

    // 右侧封面边缘
    final rightEdge = RRect.fromRectAndCorners(
      Rect.fromLTWH(left + width / 2 + 3, top, width / 2 - 3, height),
      topRight: const Radius.circular(4),
      bottomRight: const Radius.circular(4),
    );
    canvas.drawRRect(rightEdge, edgePaint);

    // 顶部和底部边缘
    edgePaint.strokeWidth = 2;
    canvas
      ..drawLine(
        Offset(left + 4, top),
        Offset(left + width / 2 - 4, top),
        edgePaint,
      )
      ..drawLine(
        Offset(left + width / 2 + 4, top),
        Offset(left + width - 4, top),
        edgePaint,
      )
      ..drawLine(
        Offset(left + 4, top + height),
        Offset(left + width / 2 - 4, top + height),
        edgePaint,
      )
      ..drawLine(
        Offset(left + width / 2 + 4, top + height),
        Offset(left + width - 4, top + height),
        edgePaint,
      );
  }

  @override
  bool shouldRepaint(_BookFlipPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      bookColor != oldDelegate.bookColor ||
      pageColor != oldDelegate.pageColor;
}
