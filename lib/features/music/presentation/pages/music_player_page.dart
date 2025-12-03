import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/lyric_view.dart';
import 'package:my_nas/features/music/presentation/widgets/music_queue_sheet.dart';
import 'package:my_nas/features/music/presentation/widgets/music_settings_sheet.dart';

class MusicPlayerPage extends ConsumerStatefulWidget {
  const MusicPlayerPage({super.key});

  @override
  ConsumerState<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends ConsumerState<MusicPlayerPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  bool _showLyrics = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _toggleLyricView() {
    setState(() => _showLyrics = !_showLyrics);
  }

  @override
  Widget build(BuildContext context) {
    final currentMusic = ref.watch(currentMusicProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 控制封面旋转动画
    if (playerState.isPlaying) {
      _rotationController.repeat();
    } else {
      _rotationController.stop();
    }

    if (currentMusic == null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : null,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('正在播放'),
        ),
        body: const Center(
          child: Text('未选择音乐'),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[100],
      appBar: _buildAppBar(context, ref, currentMusic, isDark),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [
                    AppColors.primary.withValues(alpha: 0.15),
                    AppColors.darkBackground,
                    AppColors.darkBackground,
                  ]
                : [
                    AppColors.primary.withValues(alpha: 0.1),
                    Colors.white,
                    Colors.grey[100]!,
                  ],
          ),
        ),
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _showLyrics
                ? _buildLyricMode(context, ref, currentMusic, playerState, isDark)
                : _buildCoverMode(context, ref, currentMusic, playerState, isDark),
          ),
        ),
      ),
    );
  }

  /// 封面模式
  Widget _buildCoverMode(
    BuildContext context,
    WidgetRef ref,
    MusicItem currentMusic,
    MusicPlayerState playerState,
    bool isDark,
  ) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 700; // 紧凑模式（小屏幕或桌面端窗口较小）

    return Column(
      key: const ValueKey('cover_mode'),
      children: [
        // 可滚动的封面区域
        Expanded(
          flex: isCompact ? 5 : 6,
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: isCompact ? 8 : 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 封面（点击切换到歌词）
                GestureDetector(
                  onTap: _toggleLyricView,
                  child: _buildCover(context, currentMusic, playerState, isDark),
                ),
                SizedBox(height: isCompact ? 12 : 20),
                // 歌曲信息
                _buildTrackInfo(context, currentMusic, isDark),
                const SizedBox(height: 4),
                // 紧凑歌词显示
                CompactLyricView(onTap: _toggleLyricView),
              ],
            ),
          ),
        ),
        // 固定的控制区域
        Container(
          padding: EdgeInsets.fromLTRB(16, isCompact ? 8 : 12, 16, isCompact ? 8 : 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                (isDark ? AppColors.darkBackground : Colors.grey[100]!)
                    .withValues(alpha: 0.8),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条
              _buildProgressBar(context, ref, playerState, isDark),
              SizedBox(height: isCompact ? 12 : 20),
              // 控制按钮
              _buildControlButtons(context, ref, playerState, isDark),
              SizedBox(height: isCompact ? 8 : 12),
              // 额外控制
              _buildExtraControls(context, playerState, isDark),
            ],
          ),
        ),
      ],
    );
  }

  /// 歌词模式
  Widget _buildLyricMode(
    BuildContext context,
    WidgetRef ref,
    MusicItem currentMusic,
    MusicPlayerState playerState,
    bool isDark,
  ) {
    return Column(
      key: const ValueKey('lyric_mode'),
      children: [
        // 歌词视图
        Expanded(
          child: LyricView(
            onTap: _toggleLyricView,
            showFullScreen: true,
          ),
        ),
        // 底部控制区域
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                (isDark ? AppColors.darkBackground : Colors.grey[100]!)
                    .withValues(alpha: 0.9),
                isDark ? AppColors.darkBackground : Colors.grey[100]!,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 迷你封面和歌曲信息
              Row(
                children: [
                  // 迷你封面
                  GestureDetector(
                    onTap: _toggleLyricView,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: isDark ? Colors.grey[800] : Colors.grey[300],
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: currentMusic.coverUrl != null
                          ? Image.network(
                              currentMusic.coverUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildMiniCoverPlaceholder(isDark),
                            )
                          : _buildMiniCoverPlaceholder(isDark),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 歌曲信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentMusic.displayTitle,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentMusic.displayArtist,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 进度条
              _buildProgressBar(context, ref, playerState, isDark),
              const SizedBox(height: 16),
              // 控制按钮
              _buildControlButtons(context, ref, playerState, isDark),
              const SizedBox(height: 8),
              // 音量控制（歌词模式下）
              _buildLyricModeVolumeControl(playerState, isDark),
            ],
          ),
        ),
      ],
    );
  }

  /// 歌词模式下的音量控制条
  Widget _buildLyricModeVolumeControl(MusicPlayerState state, bool isDark) {
    return Consumer(
      builder: (context, ref, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.volume_down_rounded,
              size: 20,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: AppColors.primary.withValues(alpha: 0.8),
                  inactiveTrackColor: isDark ? Colors.grey[800] : Colors.grey[300],
                  thumbColor: AppColors.primary,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  value: state.volume,
                  onChanged: (value) {
                    ref.read(musicPlayerControllerProvider.notifier).setVolume(value);
                  },
                ),
              ),
            ),
            Icon(
              Icons.volume_up_rounded,
              size: 20,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ],
        );
      },
    );
  }

  Widget _buildMiniCoverPlaceholder(bool isDark) {
    return Container(
      color: isDark ? Colors.grey[800] : Colors.grey[300],
      child: Icon(
        Icons.music_note_rounded,
        size: 28,
        color: isDark ? Colors.grey[600] : Colors.grey[400],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    MusicItem currentMusic,
    bool isDark,
  ) {
    final isFavoriteAsync = ref.watch(isMusicFavoriteProvider(currentMusic.path));

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 32,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      title: Column(
        children: [
          Text(
            '正在播放',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          Text(
            currentMusic.folderName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        // 收藏按钮
        isFavoriteAsync.when(
          data: (isFavorite) => IconButton(
            onPressed: () async {
              final result = await ref
                  .read(musicFavoritesProvider.notifier)
                  .toggleFavorite(currentMusic);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result ? '已添加到收藏' : '已取消收藏'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            icon: Icon(
              isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isFavorite ? Colors.red[400] : (isDark ? Colors.white : Colors.black87),
            ),
            tooltip: isFavorite ? '取消收藏' : '收藏',
          ),
          loading: () => const SizedBox(
            width: 48,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, __) => IconButton(
            onPressed: null,
            icon: Icon(
              Icons.favorite_border_rounded,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
          ),
        ),
        // 更多选项
        IconButton(
          onPressed: () => showMusicSettingsSheet(context),
          icon: Icon(
            Icons.more_vert_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          tooltip: '更多选项',
        ),
      ],
    );
  }

  Widget _buildCover(
    BuildContext context,
    MusicItem currentMusic,
    MusicPlayerState playerState,
    bool isDark,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    // 桌面端限制封面最大尺寸，移动端使用屏幕宽度的70%
    final maxSize = screenHeight * 0.35; // 最大为屏幕高度的35%
    final size = (screenWidth * 0.7).clamp(150.0, maxSize);

    return Center(
      child: AnimatedBuilder(
        animation: _rotationController,
        builder: (context, child) {
          return Transform.rotate(
            angle: playerState.isPlaying ? _rotationController.value * 2 * math.pi : 0,
            child: child,
          );
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? Colors.grey[850] : Colors.grey[300],
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 40,
                spreadRadius: 5,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 外圈
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.8),
                      AppColors.secondary.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
              // 内圈（封面）
              Container(
                width: size * 0.9,
                height: size * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppColors.darkSurface : Colors.white,
                ),
                clipBehavior: Clip.antiAlias,
                child: currentMusic.coverUrl != null
                    ? Image.network(
                        currentMusic.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildCoverPlaceholder(size * 0.9, isDark),
                      )
                    : _buildCoverPlaceholder(size * 0.9, isDark),
              ),
              // 中心圆点
              Container(
                width: size * 0.15,
                height: size * 0.15,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppColors.darkBackground : Colors.grey[100],
                  border: Border.all(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    width: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder(double size, bool isDark) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [Colors.grey[800]!, Colors.grey[900]!]
              : [Colors.grey[200]!, Colors.grey[300]!],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.4,
        color: isDark ? Colors.grey[600] : Colors.grey[400],
      ),
    );
  }

  Widget _buildTrackInfo(BuildContext context, MusicItem currentMusic, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            currentMusic.displayTitle,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            currentMusic.displayArtist,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(
    BuildContext context,
    WidgetRef ref,
    MusicPlayerState state,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: isDark ? Colors.grey[800] : Colors.grey[300],
              thumbColor: AppColors.primary,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              overlayColor: AppColors.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: state.progress.clamp(0.0, 1.0),
              onChanged: (value) {
                final position = Duration(
                  milliseconds: (value * state.duration.inMilliseconds).toInt(),
                );
                ref.read(musicPlayerControllerProvider.notifier).seek(position);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  state.positionText,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
                Text(
                  state.durationText,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons(
    BuildContext context,
    WidgetRef ref,
    MusicPlayerState state,
    bool isDark,
  ) {
    final notifier = ref.read(musicPlayerControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 随机/循环模式
          IconButton(
            onPressed: notifier.togglePlayMode,
            iconSize: 28,
            icon: Icon(
              _getPlayModeIcon(state.playMode),
              color: state.playMode != PlayMode.loop
                  ? AppColors.primary
                  : (isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
            tooltip: _getPlayModeTooltip(state.playMode),
          ),
          // 上一曲
          IconButton(
            onPressed: notifier.playPrevious,
            iconSize: 44,
            icon: Icon(
              Icons.skip_previous_rounded,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          // 播放/暂停
          GestureDetector(
            onTap: notifier.playOrPause,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.secondary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: state.isBuffering
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : Icon(
                      state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 40,
                      color: Colors.white,
                    ),
            ),
          ),
          // 下一曲
          IconButton(
            onPressed: notifier.playNext,
            iconSize: 44,
            icon: Icon(
              Icons.skip_next_rounded,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          // 播放列表
          IconButton(
            onPressed: () => showMusicQueueSheet(context),
            iconSize: 28,
            icon: Icon(
              Icons.queue_music_rounded,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            tooltip: '播放队列',
          ),
        ],
      ),
    );
  }

  Widget _buildExtraControls(
    BuildContext context,
    MusicPlayerState state,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 音量控制
          _VolumeButton(
            volume: state.volume,
            isDark: isDark,
          ),
          // 歌词按钮
          IconButton(
            onPressed: _toggleLyricView,
            icon: Icon(
              Icons.lyrics_rounded,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            tooltip: '歌词',
          ),
          // 定时关闭
          IconButton(
            onPressed: () => _showSleepTimer(context),
            icon: Icon(
              Icons.timer_outlined,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            tooltip: '定时关闭',
          ),
        ],
      ),
    );
  }

  IconData _getPlayModeIcon(PlayMode mode) => switch (mode) {
        PlayMode.loop => Icons.repeat_rounded,
        PlayMode.repeatOne => Icons.repeat_one_rounded,
        PlayMode.shuffle => Icons.shuffle_rounded,
      };

  String _getPlayModeTooltip(PlayMode mode) => switch (mode) {
        PlayMode.loop => '列表循环',
        PlayMode.repeatOne => '单曲循环',
        PlayMode.shuffle => '随机播放',
      };

  void _showSleepTimer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '定时关闭',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            ...[15, 30, 45, 60, 90].map((minutes) {
              return ListTile(
                title: Text(
                  '$minutes 分钟后',
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                ),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('将在 $minutes 分钟后停止播放'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              );
            }),
            ListTile(
              title: Text(
                '播放完当前歌曲后',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _VolumeButton extends ConsumerStatefulWidget {
  const _VolumeButton({
    required this.volume,
    required this.isDark,
  });

  final double volume;
  final bool isDark;

  @override
  ConsumerState<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends ConsumerState<_VolumeButton> {
  bool _showSlider = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => setState(() => _showSlider = !_showSlider),
          icon: Icon(
            widget.volume == 0
                ? Icons.volume_off_rounded
                : widget.volume < 0.5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
            color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          tooltip: '音量',
        ),
        if (_showSlider)
          SizedBox(
            width: 100,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: widget.isDark ? Colors.grey[800] : Colors.grey[300],
                thumbColor: AppColors.primary,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: widget.volume,
                onChanged: (value) {
                  ref.read(musicPlayerControllerProvider.notifier).setVolume(value);
                },
              ),
            ),
          ),
      ],
    );
  }
}
