import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// 音乐进度条组件
/// 支持平滑拖动，显示缓冲进度，避免拖动过程中的闪烁和迟钝
class MusicProgressBar extends ConsumerStatefulWidget {
  const MusicProgressBar({
    required this.isDark,
    this.showTimeLabels = true,
    this.showBufferedProgress = true,
    this.trackHeight = 4.0,
    this.thumbRadius = 6.0,
    super.key,
  });

  final bool isDark;
  final bool showTimeLabels;
  final bool showBufferedProgress;
  final double trackHeight;
  final double thumbRadius;

  @override
  ConsumerState<MusicProgressBar> createState() => _MusicProgressBarState();
}

class _MusicProgressBarState extends ConsumerState<MusicProgressBar> {
  /// 是否正在拖动
  bool _isDragging = false;

  /// 拖动过程中的临时进度值
  double _dragValue = 0.0;

  @override
  Widget build(BuildContext context) {
    // 只监听需要的状态，避免不必要的重建
    final position = ref.watch(
      musicPlayerControllerProvider.select((state) => state.position),
    );
    final duration = ref.watch(
      musicPlayerControllerProvider.select((state) => state.duration),
    );
    final bufferedPosition = ref.watch(
      musicPlayerControllerProvider.select((state) => state.bufferedPosition),
    );
    final isBuffering = ref.watch(
      musicPlayerControllerProvider.select((state) => state.isBuffering),
    );

    // 计算进度
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    // 计算缓冲进度
    final bufferedProgress = duration.inMilliseconds > 0
        ? bufferedPosition.inMilliseconds / duration.inMilliseconds
        : 0.0;

    // 如果正在拖动，使用拖动值；否则使用实际进度
    final displayProgress = _isDragging ? _dragValue : progress.clamp(0.0, 1.0);

    // 计算显示的时间
    final displayPosition = _isDragging
        ? Duration(milliseconds: (_dragValue * duration.inMilliseconds).toInt())
        : position;

    // 判断拖动位置是否超出缓冲区
    final isDragBeyondBuffer =
        _isDragging && _dragValue > bufferedProgress + 0.01;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 使用自定义 SliderTheme 和 trackShape 来精确控制轨道渲染
          SizedBox(
            height: widget.thumbRadius * 2 + 16,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: widget.trackHeight,
                trackShape: _BufferedTrackShape(
                  bufferedProgress: widget.showBufferedProgress
                      ? bufferedProgress.clamp(0.0, 1.0)
                      : 0.0,
                  bufferedColor:
                      widget.isDark ? Colors.grey[600]! : Colors.grey[400]!,
                  inactiveColor:
                      widget.isDark ? Colors.grey[800]! : Colors.grey[300]!,
                ),
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: Colors.transparent,
                thumbColor: AppColors.primary,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: widget.thumbRadius,
                ),
                overlayShape: RoundSliderOverlayShape(
                  overlayRadius: widget.thumbRadius * 2 + 2,
                ),
                overlayColor: AppColors.primary.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: displayProgress.clamp(0.0, 1.0),
                onChangeStart: _onDragStart,
                onChanged: _onDragUpdate,
                onChangeEnd: _onDragEnd,
              ),
            ),
          ),
          if (widget.showTimeLabels)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatDuration(displayPosition),
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isDark
                              ? Colors.grey[500]
                              : Colors.grey[600],
                        ),
                      ),
                      // 显示缓冲状态提示
                      if (isBuffering || isDragBeyondBuffer)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                widget.isDark
                                    ? Colors.grey[500]!
                                    : Colors.grey[600]!,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          widget.isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _onDragStart(double value) {
    setState(() {
      _isDragging = true;
      _dragValue = value;
    });
  }

  void _onDragUpdate(double value) {
    setState(() {
      _dragValue = value;
    });
  }

  Future<void> _onDragEnd(double value) async {
    // 计算目标位置
    final duration = ref.read(musicPlayerControllerProvider).duration;
    final position = Duration(
      milliseconds: (value * duration.inMilliseconds).toInt(),
    );

    // 执行 seek - just_audio 的 LockCachingAudioSource 会自动处理超出缓冲区的情况
    // 播放器会自动进入 buffering 状态，下载所需数据后继续播放
    await ref.read(musicPlayerControllerProvider.notifier).seek(position);

    // seek 完成后才结束拖动状态
    if (mounted) {
      setState(() {
        _isDragging = false;
      });
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 自定义轨道形状，同时显示缓冲进度和播放进度
/// 解决使用两个 Slider 叠加时起始点和终点不对齐的问题
class _BufferedTrackShape extends RoundedRectSliderTrackShape {
  _BufferedTrackShape({
    required this.bufferedProgress,
    required this.bufferedColor,
    required this.inactiveColor,
  });

  final double bufferedProgress;
  final Color bufferedColor;
  final Color inactiveColor;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final canvas = context.canvas;
    final trackHeight = sliderTheme.trackHeight ?? 4.0;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width;
    final trackRight = trackLeft + trackWidth;
    final trackRadius = Radius.circular(trackHeight / 2);

    // 1. 绘制底层未播放轨道（灰色）
    final inactiveRect = RRect.fromLTRBR(
      trackLeft,
      trackTop,
      trackRight,
      trackTop + trackHeight,
      trackRadius,
    );
    final inactivePaint = Paint()..color = inactiveColor;
    canvas.drawRRect(inactiveRect, inactivePaint);

    // 2. 绘制缓冲进度（浅灰色）
    if (bufferedProgress > 0) {
      final bufferedRight = trackLeft + trackWidth * bufferedProgress;
      final bufferedRect = RRect.fromLTRBR(
        trackLeft,
        trackTop,
        bufferedRight,
        trackTop + trackHeight,
        trackRadius,
      );
      final bufferedPaint = Paint()..color = bufferedColor;
      canvas.drawRRect(bufferedRect, bufferedPaint);
    }

    // 3. 绘制已播放进度（主题色）- 使用 thumbCenter 确保与滑块对齐
    final activeRight = thumbCenter.dx;
    if (activeRight > trackLeft) {
      final activeRect = RRect.fromLTRBR(
        trackLeft,
        trackTop,
        activeRight,
        trackTop + trackHeight,
        trackRadius,
      );
      final activePaint = Paint()
        ..color = sliderTheme.activeTrackColor ?? AppColors.primary;
      canvas.drawRRect(activeRect, activePaint);
    }
  }
}

/// 紧凑型进度条（用于迷你播放器等）
class CompactProgressBar extends ConsumerWidget {
  const CompactProgressBar({
    this.height = 3.0,
    this.activeColor,
    this.inactiveColor,
    super.key,
  });

  final double height;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(
      musicPlayerControllerProvider.select((state) => state.progress),
    );

    return LinearProgressIndicator(
      value: progress.clamp(0.0, 1.0),
      minHeight: height,
      backgroundColor: inactiveColor ?? Colors.grey.withValues(alpha: 0.3),
      valueColor: AlwaysStoppedAnimation<Color>(
        activeColor ?? AppColors.primary,
      ),
    );
  }
}
