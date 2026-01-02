import 'dart:ui';

import 'package:my_nas/features/music/domain/entities/desktop_lyric_settings.dart';
import 'package:my_nas/features/music/domain/entities/lyric_line_data.dart';

export 'package:my_nas/features/music/domain/entities/lyric_line_data.dart';

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
  /// [progress] 当前行进度 (0.0-1.0)，用于卡拉OK效果
  Future<void> updateLyric({
    required LyricLineData? currentLine,
    LyricLineData? nextLine,
    required bool isPlaying,
    double progress = 0.0,
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
