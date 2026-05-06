import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/music/data/services/lyric_service.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// 渲染单行**激活态**字级歌词。每个 syllable 是独立 widget，外层用
/// [Wrap] 自动换行；每帧由 60Hz [Ticker] 驱动一个 [ValueNotifier]，
/// 各 syllable 通过 [AnimatedBuilder] 监听只触发自身重绘，不触发 Wrap
/// 重新布局（Transform.scale 仅影响绘制层，不影响 layout）。
///
/// 字级动效细节（与 primuse `KaraokeLineView.swift` 保持一致）：
/// - **字内 mask 扫光**：每个 syllable 由两层 [Text] 叠加 — 底层 inactive 色，
///   顶层 active 色 + [LinearGradient] mask，mask 的「可见区」随 progress 从
///   左扫到右。单字内部能看到「左半亮右半暗」的过渡边一路扫过。
/// - **字级 bounce**：当前唱的字 scale 1.0 → 1.05 → 1.0 走 sin 曲线，像被
///   节奏「点」起来一下。anchor=bottomCenter 让字向上抬，不影响行高。
/// - **lookahead 提前唤醒 100ms**：字真正唱出来那一刻，扫光已基本到位 +
///   bounce 在最高点，跟人耳节奏感对齐。
/// - **easeOut 曲线**：前快后慢，跟唱字的能量曲线吻合。
class KaraokeLineWidget extends ConsumerStatefulWidget {
  const KaraokeLineWidget({
    required this.line,
    required this.fontSize,
    required this.fontWeight,
    required this.activeColor,
    required this.inactiveColor,
    super.key,
    this.textAlign = TextAlign.center,
  });

  final LyricLine line;
  final double fontSize;
  final FontWeight fontWeight;
  final Color activeColor;
  final Color inactiveColor;
  final TextAlign textAlign;

  /// 提前进入过渡的时间 — 让字真正唱出来时已亮 80-90%
  static const Duration lookahead = Duration(milliseconds: 100);

  /// 字内过渡跨度的下限 — 短字 (e.g. "啊" 30ms) 会瞬切，强行至少 180ms
  static const Duration minTransition = Duration(milliseconds: 180);

  /// scale bounce 的峰值幅度 (1.0 → 1 + bumpAmount → 1.0)
  static const double bumpAmount = 0.05;

  /// mask 扫光的边缘宽度 (0..1 progress 单位)；越大边缘越柔
  static const double maskEdgeWidth = 0.12;

  @override
  ConsumerState<KaraokeLineWidget> createState() => _KaraokeLineWidgetState();
}

class _KaraokeLineWidgetState extends ConsumerState<KaraokeLineWidget>
    with SingleTickerProviderStateMixin {
  /// 外推后的当前播放位置（秒），由 ticker 每帧更新
  final ValueNotifier<double> _timeSec = ValueNotifier<double>(0);

  /// 上次从播放器收到的已知位置 + 时间戳
  Duration _lastReportedPosition = Duration.zero;
  DateTime _lastReportedAt = DateTime.now();
  bool _isPlaying = false;

  late final Ticker _ticker = createTicker(_onTick)..start();

  @override
  void dispose() {
    _ticker.dispose();
    _timeSec.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    if (_isPlaying) {
      final elapsed = DateTime.now().difference(_lastReportedAt);
      _timeSec.value =
          (_lastReportedPosition + elapsed).inMicroseconds / 1e6;
    }
  }

  void _syncFromPlayer(MusicPlayerState s) {
    final newPlaying = s.isPlaying;
    final newPos = s.position;
    if (newPlaying != _isPlaying ||
        (newPos - _lastReportedPosition).abs().inMilliseconds > 50) {
      _lastReportedPosition = newPos;
      _lastReportedAt = DateTime.now();
      _isPlaying = newPlaying;
      if (!_isPlaying) {
        _timeSec.value = newPos.inMicroseconds / 1e6;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听播放器状态以更新外推基准
    ref.listen<MusicPlayerState>(musicPlayerControllerProvider,
        (prev, next) => _syncFromPlayer(next));
    // 首次构建同步一次
    _syncFromPlayer(ref.read(musicPlayerControllerProvider));

    final syllables = widget.line.syllables;
    if (syllables == null || syllables.isEmpty) {
      // 兜底：行级歌词
      return Text(
        widget.line.text,
        style: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: widget.fontWeight,
          color: widget.inactiveColor,
          height: 1.4,
        ),
        textAlign: widget.textAlign,
      );
    }

    return Wrap(
      alignment: _wrapAlignment,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final syl in syllables)
          _KaraokeSyllable(
            syllable: syl,
            timeNotifier: _timeSec,
            fontSize: widget.fontSize,
            fontWeight: widget.fontWeight,
            activeColor: widget.activeColor,
            inactiveColor: widget.inactiveColor,
          ),
      ],
    );
  }

  WrapAlignment get _wrapAlignment {
    switch (widget.textAlign) {
      case TextAlign.center:
        return WrapAlignment.center;
      case TextAlign.right:
      case TextAlign.end:
        return WrapAlignment.end;
      case TextAlign.left:
      case TextAlign.start:
      default:
        return WrapAlignment.start;
    }
  }
}

/// 单个 syllable：双层 Text + 扫光 mask + scale bounce
class _KaraokeSyllable extends StatelessWidget {
  const _KaraokeSyllable({
    required this.syllable,
    required this.timeNotifier,
    required this.fontSize,
    required this.fontWeight,
    required this.activeColor,
    required this.inactiveColor,
  });

  final LyricSyllable syllable;
  final ValueListenable<double> timeNotifier;
  final double fontSize;
  final FontWeight fontWeight;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: timeNotifier,
        builder: (context, _) {
          final progress = _computeProgress(timeNotifier.value);
          final scale =
              1.0 + KaraokeLineWidget.bumpAmount * _bellCurve(progress);
          final baseStyle = TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            height: 1.4,
          );
          return Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 底层：inactive 色，总是显示
                Text(
                  syllable.text,
                  style: baseStyle.copyWith(color: inactiveColor),
                ),
                // 顶层：active 色，用 mask 露出 progress 部分
                ShaderMask(
                  shaderCallback: (bounds) => _sweepGradient(progress)
                      .createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  child: Text(
                    syllable.text,
                    style: baseStyle.copyWith(color: activeColor),
                  ),
                ),
              ],
            ),
          );
        },
      );

  /// 扫光 mask：LinearGradient 左到右，progress 位置左侧实色、右侧透明，
  /// 中间 maskEdgeWidth 渐变成柔边。
  LinearGradient _sweepGradient(double progress) {
    const half = KaraokeLineWidget.maskEdgeWidth / 2;
    final leftEnd = math.max(0.0, progress - half);
    final rightStart = math.min(1.0, progress + half);
    // stops 必须严格单调
    final l = math.min(leftEnd, rightStart);
    final r = math.max(leftEnd, rightStart);
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: const [
        Colors.black,
        Colors.black,
        Colors.transparent,
        Colors.transparent,
      ],
      stops: [0, l, r, 1],
    );
  }

  /// 字级 progress 0..1：时间 / 过渡跨度，easeOut。
  double _computeProgress(double nowSec) {
    final start = syllable.start.inMicroseconds / 1e6;
    final rawEnd = syllable.end.inMicroseconds / 1e6;
    final dur = math.max(
      rawEnd - start,
      KaraokeLineWidget.minTransition.inMicroseconds / 1e6,
    );
    final lookaheadSec =
        KaraokeLineWidget.lookahead.inMicroseconds / 1e6;
    final transitionStart = start - lookaheadSec;
    final transitionEnd = start + dur;
    if (nowSec <= transitionStart) return 0;
    if (nowSec >= transitionEnd) return 1;
    final raw = (nowSec - transitionStart) / (transitionEnd - transitionStart);
    return _easeOut(raw);
  }

  double _easeOut(double t) {
    final c = t.clamp(0.0, 1.0);
    return 1 - (1 - c) * (1 - c);
  }

  /// 0..1..0 钟形曲线（sin），让 scale bump 在 progress=0.5 处达峰、两端为 0
  double _bellCurve(double progress) {
    final c = progress.clamp(0.0, 1.0);
    return math.sin(c * math.pi);
  }
}
