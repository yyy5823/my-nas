import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/music/data/services/lyric_service.dart';
import 'package:my_nas/features/music/presentation/providers/lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// Spotify 风格的歌词视图
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

class _LyricViewState extends ConsumerState<LyricView> {
  final ScrollController _scrollController = ScrollController();
  int _lastLineIndex = -1;
  bool _userScrolling = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLine(int index, int totalLines) {
    if (!_scrollController.hasClients || _userScrolling) return;
    if (index < 0 || index >= totalLines) return;

    // 计算目标位置，使当前行居中
    final itemHeight = widget.showFullScreen ? 60.0 : 50.0;
    final viewportHeight = _scrollController.position.viewportDimension;
    final targetOffset = (index * itemHeight) - (viewportHeight / 2) + (itemHeight / 2);

    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyricState = ref.watch(currentLyricProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (lyricState.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: AppColors.primary.withValues(alpha: 0.5),
              strokeWidth: 2,
            ),
            const SizedBox(height: 16),
            Text(
              '正在加载歌词...',
              style: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (lyricState.lyricData.isEmpty) {
      return _buildNoLyric(isDark);
    }

    final lyrics = lyricState.lyricData;
    final currentIndex = lyrics.getCurrentLineIndex(playerState.position);

    // 自动滚动到当前行
    if (currentIndex != _lastLineIndex && currentIndex >= 0) {
      _lastLineIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLine(currentIndex, lyrics.lines.length);
      });
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification) {
            _userScrolling = true;
          } else if (notification is ScrollEndNotification) {
            // 延迟恢复自动滚动
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                setState(() => _userScrolling = false);
              }
            });
          }
          return false;
        },
        child: ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(
            vertical: widget.showFullScreen ? 200 : 100,
            horizontal: 24,
          ),
          itemCount: lyrics.lines.length,
          itemBuilder: (context, index) {
            final line = lyrics.lines[index];
            final isCurrent = index == currentIndex;
            final isPast = index < currentIndex;

            return _LyricLineWidget(
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
    );
  }

  Widget _buildNoLyric(bool isDark) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_note_rounded,
            size: 64,
            color: isDark ? Colors.grey[700] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '暂无歌词',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '尽情享受音乐吧',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[600] : Colors.grey[500],
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
  });

  final LyricLine line;
  final bool isCurrent;
  final bool isPast;
  final bool isDark;
  final bool showFullScreen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          vertical: showFullScreen ? 12 : 8,
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            fontSize: isCurrent
                ? (showFullScreen ? 24 : 20)
                : (showFullScreen ? 18 : 16),
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            color: isCurrent
                ? (isDark ? Colors.white : Colors.black87)
                : isPast
                    ? (isDark ? Colors.grey[600] : Colors.grey[500])
                    : (isDark ? Colors.grey[500] : Colors.grey[400]),
            height: 1.5,
          ),
          textAlign: TextAlign.center,
          child: Text(line.text),
        ),
      ),
    );
}

/// 紧凑型歌词显示（用于播放页底部）
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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            currentLine?.text ?? '',
            key: ValueKey(currentLine?.time.inMilliseconds ?? 0),
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
