import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/aspect_ratio_selector.dart';
import 'package:my_nas/features/video/presentation/widgets/audio_track_selector.dart';
import 'package:my_nas/features/video/presentation/widgets/playback_settings_sheet.dart';
import 'package:my_nas/features/video/presentation/widgets/playlist_sheet.dart';
import 'package:my_nas/features/video/presentation/widgets/subtitle_selector.dart';

class VideoControls extends ConsumerWidget {
  const VideoControls({
    required this.video,
    required this.state,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSeekForward,
    required this.onSeekBackward,
    required this.onVolumeChange,
    required this.onSpeedChange,
    required this.onToggleFullscreen,
    required this.onBack,
    this.hasSubtitles = false,
    this.hasPlaylist = false,
    this.hasPrevious = false,
    this.hasNext = false,
    this.onPlayPrevious,
    this.onPlayNext,
    this.onShowBookmarks,
    this.onTogglePip,
    this.isPipSupported = false,
    super.key,
  });

  final VideoItem video;
  final VideoPlayerState state;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekForward;
  final VoidCallback onSeekBackward;
  final ValueChanged<double> onVolumeChange;
  final ValueChanged<double> onSpeedChange;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onBack;
  final bool hasSubtitles;
  final bool hasPlaylist;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback? onPlayPrevious;
  final VoidCallback? onPlayNext;
  final VoidCallback? onShowBookmarks;
  final VoidCallback? onTogglePip;
  final bool isPipSupported;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black54,
              Colors.transparent,
              Colors.transparent,
              Colors.black54,
            ],
            stops: [0.0, 0.2, 0.8, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏
              _buildTopBar(context, ref),

              // 中间区域
              const Spacer(),
              _buildCenterControls(context),
              const Spacer(),

              // 底部控制栏
              _buildBottomBar(context),
            ],
          ),
        ),
      );

  Widget _buildTopBar(BuildContext context, WidgetRef ref) {
    final subtitleEnabled = state.subtitleEnabled;

    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            Expanded(
              child: Text(
                video.name,
                style: context.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 字幕按钮：点击打开选择器
            GestureDetector(
              onTap: () => showSubtitleSelector(
                context,
                videoPath: video.path,
                title: video.name,
              ),
              child: Tooltip(
                message: '字幕设置',
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    hasSubtitles && subtitleEnabled
                        ? Icons.closed_caption
                        : Icons.closed_caption_off,
                    color: hasSubtitles ? Colors.white : Colors.white54,
                  ),
                ),
              ),
            ),
            // 更多选项
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                switch (value) {
                  case 'subtitle':
                    showSubtitleSelector(
                      context,
                      videoPath: video.path,
                      title: video.name,
                    );
                  case 'aspect':
                    showAspectRatioSelector(context);
                  case 'audio':
                    showAudioTrackSelector(context);
                  case 'bookmark':
                    onShowBookmarks?.call();
                  case 'settings':
                    showPlaybackSettingsSheet(context);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'subtitle',
                  child: Row(
                    children: [
                      Icon(
                        hasSubtitles ? Icons.closed_caption : Icons.closed_caption_off,
                      ),
                      const SizedBox(width: 12),
                      const Text('字幕'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'aspect',
                  child: Row(
                    children: [
                      Icon(Icons.aspect_ratio),
                      SizedBox(width: 12),
                      Text('画面比例'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'audio',
                  child: Row(
                    children: [
                      Icon(Icons.audiotrack),
                      SizedBox(width: 12),
                      Text('音轨'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'bookmark',
                  child: Row(
                    children: [
                      Icon(Icons.bookmark_rounded),
                      SizedBox(width: 12),
                      Text('书签'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings_rounded),
                      SizedBox(width: 12),
                      Text('播放设置'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
  }

  Widget _buildCenterControls(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 上一个（播放列表）
          if (hasPlaylist)
            IconButton(
              onPressed: hasPrevious ? onPlayPrevious : null,
              iconSize: 36,
              icon: Icon(
                Icons.skip_previous_rounded,
                color: hasPrevious ? Colors.white : Colors.white38,
              ),
            ),
          // 快退
          IconButton(
            onPressed: onSeekBackward,
            iconSize: 48,
            icon: const Icon(
              Icons.replay_10,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 24),
          // 播放/暂停
          IconButton(
            onPressed: onPlayPause,
            iconSize: 64,
            icon: Icon(
              state.isPlaying ? Icons.pause_circle : Icons.play_circle,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 24),
          // 快进
          IconButton(
            onPressed: onSeekForward,
            iconSize: 48,
            icon: const Icon(
              Icons.forward_10,
              color: Colors.white,
            ),
          ),
          // 下一个（播放列表）
          if (hasPlaylist)
            IconButton(
              onPressed: hasNext ? onPlayNext : null,
              iconSize: 36,
              icon: Icon(
                Icons.skip_next_rounded,
                color: hasNext ? Colors.white : Colors.white38,
              ),
            ),
        ],
      );

  Widget _buildBottomBar(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条
            Row(
              children: [
                Text(
                  state.positionText,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24,
                    ),
                    child: Slider(
                      value: state.progress.clamp(0.0, 1.0),
                      onChanged: (value) {
                        final position = Duration(
                          milliseconds:
                              (value * state.duration.inMilliseconds).toInt(),
                        );
                        onSeek(position);
                      },
                    ),
                  ),
                ),
                Text(
                  state.durationText,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),

            // 控制按钮
            Row(
              children: [
                // 音量
                _VolumeButton(
                  volume: state.volume,
                  onVolumeChange: onVolumeChange,
                ),
                const Spacer(),
                // 播放列表按钮
                if (hasPlaylist)
                  IconButton(
                    onPressed: () => showPlaylistSheet(context),
                    icon: const Icon(
                      Icons.playlist_play_rounded,
                      color: Colors.white,
                    ),
                    tooltip: '播放列表',
                  ),
                // 倍速
                _SpeedButton(
                  speed: state.speed,
                  onSpeedChange: onSpeedChange,
                ),
                const SizedBox(width: 8),
                // 画中画
                if (isPipSupported)
                  IconButton(
                    onPressed: onTogglePip,
                    icon: Icon(
                      state.isPictureInPicture
                          ? Icons.picture_in_picture_alt
                          : Icons.picture_in_picture,
                      color: Colors.white,
                    ),
                    tooltip: state.isPictureInPicture ? '退出画中画' : '画中画',
                  ),
                const SizedBox(width: 8),
                // 全屏
                IconButton(
                  onPressed: onToggleFullscreen,
                  icon: Icon(
                    state.isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _VolumeButton extends StatefulWidget {
  const _VolumeButton({
    required this.volume,
    required this.onVolumeChange,
  });

  final double volume;
  final ValueChanged<double> onVolumeChange;

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  bool _showSlider = false;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => setState(() => _showSlider = !_showSlider),
            icon: Icon(
              widget.volume == 0
                  ? Icons.volume_off
                  : widget.volume < 0.5
                      ? Icons.volume_down
                      : Icons.volume_up,
              color: Colors.white,
            ),
          ),
          if (_showSlider)
            SizedBox(
              width: 100,
              child: Slider(
                value: widget.volume,
                onChanged: widget.onVolumeChange,
                activeColor: Colors.white,
                inactiveColor: Colors.white30,
              ),
            ),
        ],
      );
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({
    required this.speed,
    required this.onSpeedChange,
  });

  final double speed;
  final ValueChanged<double> onSpeedChange;

  @override
  Widget build(BuildContext context) => PopupMenuButton<double>(
        onSelected: onSpeedChange,
        offset: const Offset(0, -200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white54),
            borderRadius: AppRadius.borderRadiusSm,
          ),
          child: Text(
            '${speed}x',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        itemBuilder: (context) => availableSpeeds
            .map(
              (s) => PopupMenuItem(
                value: s,
                child: Row(
                  children: [
                    if (s == speed) const Icon(Icons.check, size: 18),
                    if (s != speed) const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text('${s}x'),
                  ],
                ),
              ),
            )
            .toList(),
      );
}
