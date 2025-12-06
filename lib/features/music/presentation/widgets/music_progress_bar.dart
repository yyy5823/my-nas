import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// 音乐进度条组件
/// 支持平滑拖动，避免拖动过程中的闪烁和迟钝
class MusicProgressBar extends ConsumerStatefulWidget {
  const MusicProgressBar({
    required this.isDark,
    this.showTimeLabels = true,
    this.trackHeight = 4.0,
    this.thumbRadius = 6.0,
    super.key,
  });

  final bool isDark;
  final bool showTimeLabels;
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

    // 计算进度
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    // 如果正在拖动，使用拖动值；否则使用实际进度
    final displayProgress = _isDragging ? _dragValue : progress.clamp(0.0, 1.0);

    // 计算显示的时间
    final displayPosition = _isDragging
        ? Duration(milliseconds: (_dragValue * duration.inMilliseconds).toInt())
        : position;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: widget.trackHeight,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor:
                  widget.isDark ? Colors.grey[800] : Colors.grey[300],
              thumbColor: AppColors.primary,
              thumbShape:
                  RoundSliderThumbShape(enabledThumbRadius: widget.thumbRadius),
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
          if (widget.showTimeLabels)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(displayPosition),
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          widget.isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
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

  void _onDragEnd(double value) {
    // 计算目标位置
    final duration = ref.read(musicPlayerControllerProvider).duration;
    final position = Duration(
      milliseconds: (value * duration.inMilliseconds).toInt(),
    );

    // 执行 seek
    ref.read(musicPlayerControllerProvider.notifier).seek(position);

    setState(() {
      _isDragging = false;
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
