import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/presentation/providers/cast_provider.dart';
import 'package:my_nas/features/video/presentation/theme/video_player_colors.dart';
import 'package:my_nas/features/video/presentation/widgets/cast/cast_device_sheet.dart';

/// 投屏按钮
class CastButton extends ConsumerWidget {
  const CastButton({
    super.key,
    this.size = 24,
    this.color,
    this.onCastStarted,
    this.onCastStopped,
  });

  /// 图标大小
  final double size;

  /// 图标颜色
  final Color? color;

  /// 投屏开始回调
  final VoidCallback? onCastStarted;

  /// 投屏结束回调
  final VoidCallback? onCastStopped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCasting = ref.watch(isCastingProvider);
    final isDiscovering = ref.watch(isDiscoveringDevicesProvider);

    return IconButton(
      onPressed: () => _handleTap(context, ref, isCasting),
      icon: _buildIcon(isCasting, isDiscovering),
      tooltip: isCasting ? '停止投屏' : '投屏',
    );
  }

  Widget _buildIcon(bool isCasting, bool isDiscovering) {
    if (isDiscovering) {
      return SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: color ?? VideoPlayerColors.primary,
        ),
      );
    }

    return Icon(
      isCasting ? Icons.cast_connected : Icons.cast,
      size: size,
      color: color ?? VideoPlayerColors.primary,
    );
  }

  void _handleTap(BuildContext context, WidgetRef ref, bool isCasting) {
    if (isCasting) {
      _showCastControlSheet(context, ref);
    } else {
      _showDeviceSheet(context, ref);
    }
  }

  void _showDeviceSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VideoPlayerColors.transparent,
      builder: (context) => CastDeviceSheet(
        onDeviceSelected: (device) {
          Navigator.pop(context);
          onCastStarted?.call();
        },
      ),
    );
  }

  void _showCastControlSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: VideoPlayerColors.transparent,
      builder: (context) => _CastControlSheet(
        onStop: () {
          Navigator.pop(context);
          ref.read(castProvider.notifier).stop();
          onCastStopped?.call();
        },
      ),
    );
  }
}

/// 投屏按钮 - 带轮廓样式
class CastButtonOutlined extends ConsumerWidget {
  const CastButtonOutlined({
    super.key,
    this.onCastStarted,
    this.onCastStopped,
  });

  final VoidCallback? onCastStarted;
  final VoidCallback? onCastStopped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCasting = ref.watch(isCastingProvider);
    final isDiscovering = ref.watch(isDiscoveringDevicesProvider);

    return OutlinedButton.icon(
      onPressed: () => _handleTap(context, ref, isCasting),
      icon: _buildIcon(isCasting, isDiscovering),
      label: Text(isCasting ? '投屏中' : '投屏'),
      style: OutlinedButton.styleFrom(
        foregroundColor: VideoPlayerColors.primary,
        side: VideoPlayerColors.buttonBorder,
      ),
    );
  }

  Widget _buildIcon(bool isCasting, bool isDiscovering) {
    if (isDiscovering) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: VideoPlayerColors.primary,
        ),
      );
    }

    return Icon(
      isCasting ? Icons.cast_connected : Icons.cast,
      size: 18,
    );
  }

  void _handleTap(BuildContext context, WidgetRef ref, bool isCasting) {
    if (isCasting) {
      _showCastControlSheet(context, ref);
    } else {
      _showDeviceSheet(context, ref);
    }
  }

  void _showDeviceSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VideoPlayerColors.transparent,
      builder: (context) => CastDeviceSheet(
        onDeviceSelected: (device) {
          Navigator.pop(context);
          onCastStarted?.call();
        },
      ),
    );
  }

  void _showCastControlSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: VideoPlayerColors.transparent,
      builder: (context) => _CastControlSheet(
        onStop: () {
          Navigator.pop(context);
          ref.read(castProvider.notifier).stop();
          onCastStopped?.call();
        },
      ),
    );
  }
}

/// 简单的投屏控制面板
class _CastControlSheet extends ConsumerWidget {
  const _CastControlSheet({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final castState = ref.watch(castProvider);
    final session = castState.session;

    return Container(
      decoration: const BoxDecoration(
        color: VideoPlayerColors.darkBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽指示条
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: VideoPlayerColors.disabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // 设备信息
            Row(
              children: [
                const Icon(
                  Icons.cast_connected,
                  color: VideoPlayerColors.primary,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '正在投屏到',
                        style: VideoPlayerColors.subtitleTextStyle,
                      ),
                      Text(
                        session?.device.name ?? '未知设备',
                        style: const TextStyle(
                          color: VideoPlayerColors.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 视频标题
            if (session != null)
              Text(
                session.videoTitle,
                style: VideoPlayerColors.titleTextStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 20),

            // 播放控制
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => ref.read(castProvider.notifier).togglePlayPause(),
                  iconSize: 64,
                  icon: Icon(
                    (session?.isPlaying ?? false) ? Icons.pause_circle : Icons.play_circle,
                    color: VideoPlayerColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 进度条
            if (session != null && session.duration > Duration.zero) ...[
              Row(
                children: [
                  Text(
                    _formatDuration(session.position),
                    style: VideoPlayerColors.timeTextStyle,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: VideoPlayerColors.getSliderTheme(context),
                      child: Slider(
                        value: session.progress.clamp(0.0, 1.0),
                        onChanged: (value) {
                          final position = Duration(
                            milliseconds: (value * session.duration.inMilliseconds).round(),
                          );
                          ref.read(castProvider.notifier).seek(position);
                        },
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(session.duration),
                    style: VideoPlayerColors.timeTextStyle,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // 停止投屏按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop),
                label: const Text('停止投屏'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VideoPlayerColors.primary,
                  side: VideoPlayerColors.buttonBorder,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
