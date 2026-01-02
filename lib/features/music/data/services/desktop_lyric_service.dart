import 'dart:ui';

import 'package:my_nas/features/music/domain/entities/desktop_lyric_settings.dart';

/// 歌词行数据
class LyricLineData {
  const LyricLineData({
    required this.text,
    this.translation,
    required this.startTime,
    this.endTime,
  });

  /// 原文歌词
  final String text;

  /// 翻译歌词（可选）
  final String? translation;

  /// 开始时间
  final Duration startTime;

  /// 结束时间（下一行开始时间）
  final Duration? endTime;

  bool get hasTranslation => translation != null && translation!.isNotEmpty;
}

/// 桌面歌词服务抽象接口
abstract class DesktopLyricService {
  /// 当前平台是否支持桌面歌词
  bool get isSupported;

  /// 歌词窗口是否可见
  bool get isVisible;

  /// 初始化服务
  Future<void> init(DesktopLyricSettings settings);

  /// 显示歌词窗口
  Future<void> show();

  /// 隐藏歌词窗口
  Future<void> hide();

  /// 切换显示状态
  Future<void> toggle();

  /// 更新歌词内容
  Future<void> updateLyric({
    required LyricLineData? currentLine,
    LyricLineData? nextLine,
    required bool isPlaying,
  });

  /// 更新播放状态（暂停/播放）
  Future<void> updatePlayingState(bool isPlaying);

  /// 更新窗口位置
  Future<void> setPosition(Offset position);

  /// 获取当前窗口位置
  Future<Offset?> getPosition();

  /// 更新设置
  Future<void> updateSettings(DesktopLyricSettings settings);

  /// 释放资源
  Future<void> dispose();
}
