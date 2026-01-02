import 'package:flutter/material.dart';
import 'package:my_nas/features/music/domain/entities/desktop_lyric_settings.dart';

/// 桌面歌词内容组件
class DesktopLyricContent extends StatelessWidget {
  const DesktopLyricContent({
    super.key,
    this.currentLyric,
    this.currentTranslation,
    this.nextLyric,
    this.nextTranslation,
    required this.isPlaying,
    required this.isHovering,
    required this.settings,
    this.onClose,
    this.onLockToggle,
  });

  /// 当前歌词行
  final String? currentLyric;

  /// 当前歌词翻译
  final String? currentTranslation;

  /// 下一行歌词
  final String? nextLyric;

  /// 下一行歌词翻译
  final String? nextTranslation;

  /// 是否正在播放
  final bool isPlaying;

  /// 鼠标是否悬停
  final bool isHovering;

  /// 歌词设置
  final DesktopLyricSettings settings;

  /// 关闭回调
  final VoidCallback? onClose;

  /// 锁定切换回调
  final VoidCallback? onLockToggle;

  @override
  Widget build(BuildContext context) {
    final hasLyric = currentLyric != null && currentLyric!.isNotEmpty;
    final hasTranslation = settings.showTranslation &&
        currentTranslation != null &&
        currentTranslation!.isNotEmpty;
    final hasNextLine = settings.showNextLine &&
        nextLyric != null &&
        nextLyric!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: settings.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          // 歌词内容
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 当前歌词
                  if (hasLyric) ...[
                    _LyricLine(
                      text: currentLyric!,
                      fontSize: settings.fontSize,
                      color: settings.textColor,
                      isPlaying: isPlaying,
                    ),
                    // 翻译歌词
                    if (hasTranslation)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _LyricLine(
                          text: currentTranslation!,
                          fontSize: settings.fontSize * 0.7,
                          color: settings.textColor.withValues(alpha: 0.7),
                          isPlaying: isPlaying,
                        ),
                      ),
                  ] else ...[
                    // 无歌词时的占位
                    _LyricLine(
                      text: isPlaying ? '♪ ♪ ♪' : '暂无歌词',
                      fontSize: settings.fontSize * 0.8,
                      color: settings.textColor.withValues(alpha: 0.5),
                      isPlaying: false,
                    ),
                  ],
                  // 下一行歌词预览
                  if (hasNextLine)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _LyricLine(
                        text: nextLyric!,
                        fontSize: settings.fontSize * 0.6,
                        color: settings.textColor.withValues(alpha: 0.4),
                        isPlaying: false,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 控制按钮（悬停时显示）
          if (isHovering)
            Positioned(
              top: 4,
              right: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 锁定按钮
                  _ControlButton(
                    icon: settings.lockPosition ? Icons.lock : Icons.lock_open,
                    tooltip: settings.lockPosition ? '解锁位置' : '锁定位置',
                    onTap: onLockToggle,
                  ),
                  const SizedBox(width: 4),
                  // 关闭按钮
                  _ControlButton(
                    icon: Icons.close,
                    tooltip: '关闭',
                    onTap: onClose,
                  ),
                ],
              ),
            ),
          // 拖动指示器（悬停时显示）
          if (isHovering && !settings.lockPosition)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 歌词行组件
class _LyricLine extends StatelessWidget {
  const _LyricLine({
    required this.text,
    required this.fontSize,
    required this.color,
    required this.isPlaying,
  });

  final String text;
  final double fontSize;
  final Color color;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 200),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: color,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 控制按钮组件
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              icon,
              size: 16,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}
