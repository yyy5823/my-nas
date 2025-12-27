import 'package:flutter/material.dart';

/// 视频播放器控件专用颜色
/// 视频播放器界面需要在深色视频背景上显示白色控件
/// 因此使用固定的白色系颜色，不随应用主题变化
abstract final class VideoPlayerColors {
  // ============ 主要颜色 ============

  /// 主要控件颜色（图标、文字、进度条等）
  static const Color primary = Colors.white;

  /// 次要颜色（提示文字、副标题等）
  static const Color secondary = Color(0xB3FFFFFF); // Colors.white70

  /// 禁用状态颜色
  static const Color disabled = Color(0x61FFFFFF); // Colors.white38

  // ============ 进度条颜色 ============

  /// 进度条活动轨道颜色
  static const Color sliderActive = Colors.white;

  /// 进度条非活动轨道颜色
  static const Color sliderInactive = Color(0x4DFFFFFF); // Colors.white30

  /// 进度条滑块颜色
  static const Color sliderThumb = Colors.white;

  /// 进度条覆盖层颜色
  static const Color sliderOverlay = Color(0x3DFFFFFF); // Colors.white24

  // ============ 背景颜色 ============

  /// 渐变遮罩颜色（顶部和底部）
  static const Color gradientMask = Color(0x8A000000); // Colors.black54

  /// 透明色
  static const Color transparent = Colors.transparent;

  /// 面板背景色
  static const Color panelBackground = Color(0xF2212121); // Colors.grey[900] with opacity

  /// 深色背景
  static const Color darkBackground = Color(0xFF212121); // Colors.grey[900]

  /// PopupMenu 背景色
  static const Color popupBackground = Color(0xDE000000); // Colors.black87

  // ============ 边框颜色 ============

  /// 边框颜色
  static const Color border = Color(0x8AFFFFFF); // Colors.white54

  /// 分隔线颜色
  static const Color divider = Color(0x1FFFFFFF); // Colors.white12

  // ============ 状态颜色 ============

  /// 错误颜色
  static const Color error = Colors.red;

  /// 加载指示器颜色
  static const Color loading = Colors.white;

  // ============ 投屏状态颜色 ============

  /// 投屏指示器背景
  static const Color castIndicatorBg = Color(0x1AFFFFFF); // Colors.white.withOpacity(0.1)

  // ============ 渐变定义 ============

  /// 控件渐变背景（顶部和底部遮罩）
  static const LinearGradient controlsGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      gradientMask,
      transparent,
      transparent,
      gradientMask,
    ],
    stops: [0.0, 0.2, 0.8, 1.0],
  );

  // ============ Slider 主题配置 ============

  /// 获取统一的 Slider 主题数据
  static SliderThemeData getSliderTheme(BuildContext context) =>
      SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: sliderActive,
        inactiveTrackColor: sliderInactive,
        thumbColor: sliderThumb,
        overlayColor: sliderOverlay,
      );

  // ============ 通用样式 ============

  /// 时间文字样式
  static const TextStyle timeTextStyle = TextStyle(
    color: primary,
    fontSize: 12,
  );

  /// 标题文字样式
  static const TextStyle titleTextStyle = TextStyle(
    color: primary,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  /// 副标题文字样式
  static const TextStyle subtitleTextStyle = TextStyle(
    color: secondary,
    fontSize: 12,
  );

  /// 按钮边框样式
  static const BorderSide buttonBorder = BorderSide(color: border);
}
