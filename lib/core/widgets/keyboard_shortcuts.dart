import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 键盘快捷键处理器组件
///
/// 包装子组件并处理键盘事件，支持各种媒体播放页面的快捷键操作。
/// 使用 [KeyboardListener] 监听键盘事件，避免与其他焦点组件冲突。
class KeyboardShortcuts extends StatelessWidget {
  const KeyboardShortcuts({
    required this.child,
    required this.shortcuts,
    this.autofocus = true,
    super.key,
  });

  /// 子组件
  final Widget child;

  /// 快捷键映射
  final Map<ShortcutKey, VoidCallback> shortcuts;

  /// 是否自动获取焦点
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: autofocus,
        onKeyEvent: (node, event) {
          // 只处理按下事件
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          final key = ShortcutKey.fromKeyEvent(event);
          if (key != null && shortcuts.containsKey(key)) {
            shortcuts[key]!();
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: child,
      );
}

/// 快捷键定义
class ShortcutKey {
  const ShortcutKey(
    this.key, {
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  /// 从键盘事件创建快捷键
  static ShortcutKey? fromKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    // 忽略单独的修饰键
    if (_isModifierKey(key)) return null;

    return ShortcutKey(
      key,
      ctrl: HardwareKeyboard.instance.isControlPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      meta: HardwareKeyboard.instance.isMetaPressed,
    );
  }

  static bool _isModifierKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShortcutKey &&
          key == other.key &&
          ctrl == other.ctrl &&
          shift == other.shift &&
          alt == other.alt &&
          meta == other.meta;

  @override
  int get hashCode => Object.hash(key, ctrl, shift, alt, meta);

  @override
  String toString() {
    final parts = <String>[];
    if (ctrl) parts.add('Ctrl');
    if (shift) parts.add('Shift');
    if (alt) parts.add('Alt');
    if (meta) parts.add('Meta');
    parts.add(key.keyLabel);
    return parts.join('+');
  }
}

/// 常用快捷键定义
class CommonShortcuts {
  CommonShortcuts._();

  // === 播放控制 ===
  /// 播放/暂停 (Space)
  static const playPause = ShortcutKey(LogicalKeyboardKey.space);

  /// 播放/暂停 (K - YouTube风格)
  static const playPauseK = ShortcutKey(LogicalKeyboardKey.keyK);

  // === 导航 ===
  /// 上一个 (左箭头)
  static const previous = ShortcutKey(LogicalKeyboardKey.arrowLeft);

  /// 下一个 (右箭头)
  static const next = ShortcutKey(LogicalKeyboardKey.arrowRight);

  /// 上一个 (Page Up)
  static const previousPage = ShortcutKey(LogicalKeyboardKey.pageUp);

  /// 下一个 (Page Down)
  static const nextPage = ShortcutKey(LogicalKeyboardKey.pageDown);

  /// 第一个/首页 (Home)
  static const first = ShortcutKey(LogicalKeyboardKey.home);

  /// 最后一个/尾页 (End)
  static const last = ShortcutKey(LogicalKeyboardKey.end);

  // === 视频快进快退 ===
  /// 快退5秒 (J - YouTube风格)
  static const seekBackward = ShortcutKey(LogicalKeyboardKey.keyJ);

  /// 快进5秒 (L - YouTube风格)
  static const seekForward = ShortcutKey(LogicalKeyboardKey.keyL);

  /// 快退10秒 (Shift+左箭头)
  static const seekBackwardLong =
      ShortcutKey(LogicalKeyboardKey.arrowLeft, shift: true);

  /// 快进10秒 (Shift+右箭头)
  static const seekForwardLong =
      ShortcutKey(LogicalKeyboardKey.arrowRight, shift: true);

  // === 音量 ===
  /// 增加音量 (上箭头)
  static const volumeUp = ShortcutKey(LogicalKeyboardKey.arrowUp);

  /// 减少音量 (下箭头)
  static const volumeDown = ShortcutKey(LogicalKeyboardKey.arrowDown);

  /// 静音切换 (M)
  static const mute = ShortcutKey(LogicalKeyboardKey.keyM);

  // === 全屏 ===
  /// 全屏切换 (F)
  static const fullscreen = ShortcutKey(LogicalKeyboardKey.keyF);

  /// 全屏切换 (F11 - Windows风格)
  static const fullscreenF11 = ShortcutKey(LogicalKeyboardKey.f11);

  // === 缩放 ===
  /// 放大 (=或+)
  static const zoomIn = ShortcutKey(LogicalKeyboardKey.equal);

  /// 放大 (Ctrl+=)
  static const zoomInCtrl = ShortcutKey(LogicalKeyboardKey.equal, ctrl: true);

  /// 缩小 (-)
  static const zoomOut = ShortcutKey(LogicalKeyboardKey.minus);

  /// 缩小 (Ctrl+-)
  static const zoomOutCtrl = ShortcutKey(LogicalKeyboardKey.minus, ctrl: true);

  /// 重置缩放 (0)
  static const zoomReset = ShortcutKey(LogicalKeyboardKey.digit0);

  /// 重置缩放 (Ctrl+0)
  static const zoomResetCtrl = ShortcutKey(LogicalKeyboardKey.digit0, ctrl: true);

  // === 退出 ===
  /// 退出/返回 (Escape)
  static const escape = ShortcutKey(LogicalKeyboardKey.escape);

  /// 返回 (Backspace)
  static const back = ShortcutKey(LogicalKeyboardKey.backspace);

  // === 其他 ===
  /// 显示/隐藏控制栏 (C)
  static const toggleControls = ShortcutKey(LogicalKeyboardKey.keyC);

  /// 帮助 (?)
  static const help = ShortcutKey(LogicalKeyboardKey.slash, shift: true);

  /// 循环模式 (R)
  static const repeatMode = ShortcutKey(LogicalKeyboardKey.keyR);

  /// 随机播放 (S)
  static const shuffle = ShortcutKey(LogicalKeyboardKey.keyS);

  /// 收藏 (F或L)
  static const favorite = ShortcutKey(LogicalKeyboardKey.keyL);

  /// 信息 (I)
  static const info = ShortcutKey(LogicalKeyboardKey.keyI);

  /// 设置 (,)
  static const settings = ShortcutKey(LogicalKeyboardKey.comma);

  /// 字幕切换 (C) - 用于视频
  static const subtitles = ShortcutKey(LogicalKeyboardKey.keyC);

  // === 滚动 ===
  /// 向上滚动 (上箭头)
  static const scrollUp = ShortcutKey(LogicalKeyboardKey.arrowUp);

  /// 向下滚动 (下箭头)
  static const scrollDown = ShortcutKey(LogicalKeyboardKey.arrowDown);

  // === 播放速度 ===
  /// 减慢速度 ([)
  static const speedDown = ShortcutKey(LogicalKeyboardKey.bracketLeft);

  /// 加快速度 (])
  static const speedUp = ShortcutKey(LogicalKeyboardKey.bracketRight);

  /// 正常速度 (Backslash \)
  static const speedNormal = ShortcutKey(LogicalKeyboardKey.backslash);

  // === 数字键跳转 ===
  /// 跳转到 0% (0)
  static const jumpTo0 = ShortcutKey(LogicalKeyboardKey.digit0);

  /// 跳转到 10% (1)
  static const jumpTo10 = ShortcutKey(LogicalKeyboardKey.digit1);

  /// 跳转到 20% (2)
  static const jumpTo20 = ShortcutKey(LogicalKeyboardKey.digit2);

  /// 跳转到 30% (3)
  static const jumpTo30 = ShortcutKey(LogicalKeyboardKey.digit3);

  /// 跳转到 40% (4)
  static const jumpTo40 = ShortcutKey(LogicalKeyboardKey.digit4);

  /// 跳转到 50% (5)
  static const jumpTo50 = ShortcutKey(LogicalKeyboardKey.digit5);

  /// 跳转到 60% (6)
  static const jumpTo60 = ShortcutKey(LogicalKeyboardKey.digit6);

  /// 跳转到 70% (7)
  static const jumpTo70 = ShortcutKey(LogicalKeyboardKey.digit7);

  /// 跳转到 80% (8)
  static const jumpTo80 = ShortcutKey(LogicalKeyboardKey.digit8);

  /// 跳转到 90% (9)
  static const jumpTo90 = ShortcutKey(LogicalKeyboardKey.digit9);
}

/// 快捷键帮助对话框
class KeyboardShortcutsHelpDialog extends StatelessWidget {
  const KeyboardShortcutsHelpDialog({
    required this.title,
    required this.shortcuts,
    super.key,
  });

  final String title;
  final List<({String key, String description})> shortcuts;

  static void show(
    BuildContext context, {
    required String title,
    required List<({String key, String description})> shortcuts,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => KeyboardShortcutsHelpDialog(
        title: title,
        shortcuts: shortcuts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.keyboard),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: shortcuts
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            child: Text(
                              s.key,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: Text(s.description)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );
}
