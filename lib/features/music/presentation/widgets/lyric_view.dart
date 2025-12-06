import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/music/data/services/lyric_service.dart';
import 'package:my_nas/features/music/presentation/providers/lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// Spotify 风格的歌词视图 - 现代化设计
/// 参考主流音乐APP的歌词展示方式：
/// - 当前歌词始终居中显示
/// - 平滑滚动动画
/// - 支持手动滚动后暂停自动滚动
class LyricView extends ConsumerStatefulWidget {
  const LyricView({
    super.key,
    this.onTap,
    this.showFullScreen = false,
  });

  /// 点击歌词回调
  final VoidCallback? onTap;

  /// 是否全屏模式
  final bool showFullScreen;

  @override
  ConsumerState<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends ConsumerState<LyricView>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();

  int _lastLineIndex = -1;
  bool _userScrolling = false;
  bool _isAnimating = false;
  DateTime? _lastUserScrollTime;

  late AnimationController _pulseController;

  // 每行歌词的 GlobalKey，用于精确计算位置
  final Map<int, GlobalKey> _lineKeys = {};

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// 获取指定行的 key
  GlobalKey _getKeyForLine(int index) =>
      _lineKeys.putIfAbsent(index, GlobalKey.new);

  /// 滚动到指定行，使其居中显示
  void _scrollToLine(int index, int totalLines) {
    if (!_scrollController.hasClients) return;
    if (index < 0 || index >= totalLines) return;
    if (_isAnimating) return;

    // 检查是否在用户滚动的冷却期内
    if (_userScrolling) return;
    if (_lastUserScrollTime != null) {
      final elapsed = DateTime.now().difference(_lastUserScrollTime!);
      if (elapsed.inSeconds < 3) return;
    }

    // 计算估算的行高（包含 padding）
    // 全屏模式: fontSize 26/18 + padding 14*2 = 约 56px
    // 非全屏: fontSize 20/16 + padding 10*2 = 约 44px
    final estimatedLineHeight = widget.showFullScreen ? 56.0 : 44.0;

    // 列表使用 verticalPadding = screenHeight * 0.4 作为顶部/底部 padding
    // 这样第一行会从屏幕 40% 处开始，我们需要考虑这个偏移
    // 目标：让当前行显示在视口中央
    //
    // 内容结构：[顶部padding 40%][歌词内容][底部padding 40%]
    // 第 index 行在列表中的位置 = index * lineHeight
    // 我们希望这一行居中，即它距离视口顶部 = viewportHeight / 2 - lineHeight / 2
    // 所以 scrollOffset = index * lineHeight - (viewportHeight / 2 - lineHeight / 2)
    // 但由于有顶部 padding，实际滚动位置需要考虑这个 padding
    final targetOffset = index * estimatedLineHeight;

    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _isAnimating = true;
    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    ).then((_) {
      if (mounted) {
        _isAnimating = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lyricState = ref.watch(currentLyricProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (lyricState.isLoading) {
      return _buildLoadingState(isDark);
    }

    if (lyricState.lyricData.isEmpty) {
      return _buildNoLyric(isDark);
    }

    final lyrics = lyricState.lyricData;
    final currentIndex = lyrics.getCurrentLineIndex(playerState.position);

    // 自动滚动到当前行 - 只要索引变化就滚动
    if (currentIndex >= 0 && currentIndex != _lastLineIndex) {
      _lastLineIndex = currentIndex;
      // 使用 SchedulerBinding 确保在布局完成后滚动
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToLine(currentIndex, lyrics.lines.length);
        }
      });
    }

    // 计算视口高度用于 padding
    final screenHeight = MediaQuery.of(context).size.height;
    final verticalPadding = screenHeight * 0.4; // 40% 的空白用于居中效果

    return GestureDetector(
      onTap: widget.onTap,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is UserScrollNotification) {
            // 用户开始手动滚动
            _userScrolling = true;
            _lastUserScrollTime = DateTime.now();
          } else if (notification is ScrollEndNotification) {
            // 滚动结束后，延迟恢复自动滚动
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() {
                  _userScrolling = false;
                });
              }
            });
          }
          return false;
        },
        child: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: const [0.0, 0.15, 0.85, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            key: _listKey,
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              vertical: verticalPadding,
              horizontal: widget.showFullScreen ? 32 : 24,
            ),
            itemCount: lyrics.lines.length,
            itemBuilder: (context, index) {
              final line = lyrics.lines[index];
              final isCurrent = index == currentIndex;
              final isPast = index < currentIndex;

              return _LyricLineWidget(
                key: _getKeyForLine(index),
                line: line,
                isCurrent: isCurrent,
                isPast: isPast,
                isDark: isDark,
                showFullScreen: widget.showFullScreen,
                onTap: () {
                  // 点击歌词跳转到对应位置
                  ref.read(musicPlayerControllerProvider.notifier).seek(line.time);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 脉冲动画
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(
                  alpha: 0.1 + (_pulseController.value * 0.1),
                ),
              ),
              child: Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(
                      alpha: 0.2 + (_pulseController.value * 0.1),
                    ),
                  ),
                  child: Icon(
                    Icons.lyrics_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '正在加载歌词...',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.black45,
            ),
          ),
        ],
      ),
    );

  Widget _buildNoLyric(bool isDark) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 装饰性音符
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withValues(alpha: 0.15),
                  AppColors.secondary.withValues(alpha: 0.1),
                ],
              ),
            ),
            child: Icon(
              Icons.music_note_rounded,
              size: 48,
              color: AppColors.primary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '暂无歌词',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '尽情享受音乐吧',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
}

class _LyricLineWidget extends StatelessWidget {
  const _LyricLineWidget({
    required this.line,
    required this.isCurrent,
    required this.isPast,
    required this.isDark,
    required this.showFullScreen,
    required this.onTap,
    super.key,
  });

  final LyricLine line;
  final bool isCurrent;
  final bool isPast;
  final bool isDark;
  final bool showFullScreen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 根据状态确定颜色和大小
    Color textColor;
    double fontSize;
    FontWeight fontWeight;

    if (isCurrent) {
      textColor = isDark ? Colors.white : Colors.black87;
      fontSize = showFullScreen ? 26 : 20;
      fontWeight = FontWeight.bold;
    } else if (isPast) {
      textColor = isDark
          ? Colors.white.withValues(alpha: 0.35)
          : Colors.black.withValues(alpha: 0.3);
      fontSize = showFullScreen ? 18 : 16;
      fontWeight = FontWeight.normal;
    } else {
      textColor = isDark
          ? Colors.white.withValues(alpha: 0.5)
          : Colors.black.withValues(alpha: 0.4);
      fontSize = showFullScreen ? 18 : 16;
      fontWeight = FontWeight.normal;
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          vertical: showFullScreen ? 14 : 10,
        ),
        child: Row(
          children: [
            // 当前行指示器
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isCurrent ? 4 : 0,
              height: showFullScreen ? 28 : 22,
              margin: EdgeInsets.only(right: isCurrent ? 12 : 0),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
            // 歌词文本
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: fontWeight,
                  color: textColor,
                  height: 1.4,
                ),
                child: Text(
                  line.text,
                  textAlign: TextAlign.left,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 紧凑型歌词显示（用于播放页底部）- 现代化设计
class CompactLyricView extends ConsumerWidget {
  const CompactLyricView({
    super.key,
    this.onTap,
  });

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricState = ref.watch(currentLyricProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (lyricState.lyricData.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentLine = lyricState.lyricData.getCurrentLine(playerState.position);
    final nextLineIndex = lyricState.lyricData.getCurrentLineIndex(playerState.position) + 1;
    final nextLine = nextLineIndex < lyricState.lyricData.lines.length
        ? lyricState.lyricData.lines[nextLineIndex]
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 当前歌词
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  )),
                  child: child,
                ),
              ),
              child: Text(
                currentLine?.text ?? '',
                key: ValueKey(currentLine?.time.inMilliseconds ?? 0),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 下一句歌词预览
            if (nextLine != null) ...[
              const SizedBox(height: 6),
              Text(
                nextLine.text,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.black.withValues(alpha: 0.35),
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 迷你歌词显示（用于迷你播放器等小空间）
class MiniLyricView extends ConsumerWidget {
  const MiniLyricView({
    super.key,
    this.style,
  });

  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricState = ref.watch(currentLyricProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (lyricState.lyricData.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentLine = lyricState.lyricData.getCurrentLine(playerState.position);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Text(
        currentLine?.text ?? '',
        key: ValueKey(currentLine?.time.inMilliseconds ?? 0),
        style: style ??
            TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.black45,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
