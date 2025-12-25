import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/color_scheme_preset.dart';
import 'package:my_nas/shared/providers/theme_provider.dart';

/// 功能性颜色扩展
/// 用于在组件中获取当前配色方案的功能性颜色
extension FunctionalColorsExtension on WidgetRef {
  /// 获取当前配色方案
  ColorSchemePreset get colorPreset => watch(colorSchemePresetProvider);

  /// 音乐类型颜色
  Color get musicColor => colorPreset.music;

  /// 视频类型颜色
  Color get videoColor => colorPreset.video;

  /// 照片类型颜色
  Color get photoColor => colorPreset.photo;

  /// 图书类型颜色
  Color get bookColor => colorPreset.book;

  /// 下载颜色
  Color get downloadColor => colorPreset.download;

  /// 订阅颜色
  Color get subscriptionColor => colorPreset.subscription;

  /// AI 功能颜色
  Color get aiColor => colorPreset.ai;

  /// 控制设置颜色
  Color get controlColor => colorPreset.control;
}

/// 功能性颜色工具类
/// 用于在没有 WidgetRef 的地方获取功能性颜色
class FunctionalColors {
  final ColorSchemePreset preset;

  const FunctionalColors(this.preset);

  /// 音乐类型颜色
  Color get music => preset.music;

  /// 视频类型颜色
  Color get video => preset.video;

  /// 照片类型颜色
  Color get photo => preset.photo;

  /// 图书类型颜色
  Color get book => preset.book;

  /// 下载颜色
  Color get download => preset.download;

  /// 订阅颜色
  Color get subscription => preset.subscription;

  /// AI 功能颜色
  Color get ai => preset.ai;

  /// 控制设置颜色
  Color get control => preset.control;

  /// 根据媒体类型获取颜色
  Color forMediaType(String type) => switch (type.toLowerCase()) {
        'music' || 'audio' => music,
        'video' || 'movie' || 'tv' => video,
        'photo' || 'image' => photo,
        'book' || 'ebook' => book,
        _ => preset.primary,
      };

  /// 根据文件类型获取颜色（保持与 AppColors 一致）
  static Color forFileType(String extension) => switch (extension.toLowerCase()) {
        'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'bmp' || 'heic' => const Color(0xFF10B981),
        'mp4' || 'mkv' || 'avi' || 'mov' || 'wmv' || 'flv' => const Color(0xFFEC4899),
        'mp3' || 'flac' || 'wav' || 'aac' || 'm4a' || 'ogg' => const Color(0xFF8B5CF6),
        'pdf' || 'doc' || 'docx' || 'txt' || 'md' => const Color(0xFF3B82F6),
        'zip' || 'rar' || '7z' || 'tar' || 'gz' => const Color(0xFFF59E0B),
        'js' || 'ts' || 'dart' || 'py' || 'java' || 'cpp' || 'c' || 'h' => const Color(0xFF06B6D4),
        _ => const Color(0xFF64748B),
      };
}
