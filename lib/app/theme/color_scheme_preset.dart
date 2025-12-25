import 'package:flutter/material.dart';

/// 配色方案预设
/// 参考成熟软件设计：Infuse, Plex, Spotify, Netflix, Apple TV+, Disney+
class ColorSchemePreset {

  const ColorSchemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.iconName,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.secondary,
    required this.secondaryLight,
    required this.accent,
    required this.music,
    required this.video,
    required this.photo,
    required this.book,
    required this.download,
    required this.subscription,
    required this.ai,
    required this.control,
    required this.darkBackground,
    required this.darkSurface,
    required this.darkSurfaceVariant,
    required this.darkSurfaceElevated,
    required this.darkOutline,
  });

  /// 从 JSON 创建
  factory ColorSchemePreset.fromJson(Map<String, dynamic> json) => ColorSchemePreset(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      iconName: json['iconName'] as String,
      primary: Color(json['primary'] as int),
      primaryLight: Color(json['primaryLight'] as int),
      primaryDark: Color(json['primaryDark'] as int),
      secondary: Color(json['secondary'] as int),
      secondaryLight: Color(json['secondaryLight'] as int),
      accent: Color(json['accent'] as int),
      music: Color(json['music'] as int),
      video: Color(json['video'] as int),
      photo: Color(json['photo'] as int),
      book: Color(json['book'] as int),
      download: Color(json['download'] as int),
      subscription: Color(json['subscription'] as int),
      ai: Color(json['ai'] as int),
      control: Color(json['control'] as int),
      darkBackground: Color(json['darkBackground'] as int),
      darkSurface: Color(json['darkSurface'] as int),
      darkSurfaceVariant: Color(json['darkSurfaceVariant'] as int),
      darkSurfaceElevated: Color(json['darkSurfaceElevated'] as int),
      darkOutline: Color(json['darkOutline'] as int),
    );
  final String id;
  final String name;
  final String description;
  final String iconName; // 用于显示的图标

  // 主色调
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;

  // 次要色
  final Color secondary;
  final Color secondaryLight;

  // 强调色
  final Color accent;

  // 功能性颜色 - 用于区分不同类型内容
  final Color music; // 音乐
  final Color video; // 视频
  final Color photo; // 照片
  final Color book; // 图书
  final Color download; // 下载
  final Color subscription; // 订阅
  final Color ai; // AI 功能
  final Color control; // 控制设置

  // 深色模式背景 (RGB 相同值 = 纯灰色)
  final Color darkBackground;
  final Color darkSurface;
  final Color darkSurfaceVariant;
  final Color darkSurfaceElevated;
  final Color darkOutline;

  /// 转为 JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'iconName': iconName,
        'primary': primary.toARGB32(),
        'primaryLight': primaryLight.toARGB32(),
        'primaryDark': primaryDark.toARGB32(),
        'secondary': secondary.toARGB32(),
        'secondaryLight': secondaryLight.toARGB32(),
        'accent': accent.toARGB32(),
        'music': music.toARGB32(),
        'video': video.toARGB32(),
        'photo': photo.toARGB32(),
        'book': book.toARGB32(),
        'download': download.toARGB32(),
        'subscription': subscription.toARGB32(),
        'ai': ai.toARGB32(),
        'control': control.toARGB32(),
        'darkBackground': darkBackground.toARGB32(),
        'darkSurface': darkSurface.toARGB32(),
        'darkSurfaceVariant': darkSurfaceVariant.toARGB32(),
        'darkSurfaceElevated': darkSurfaceElevated.toARGB32(),
        'darkOutline': darkOutline.toARGB32(),
      };
}

/// 预设配色方案集合
abstract final class ColorSchemePresets {
  /// 1. Teal 青色 - 清新现代 (当前默认)
  /// 参考：Spotify 的清新感 + Apple 的简洁
  static const teal = ColorSchemePreset(
    id: 'teal',
    name: '青色',
    description: '清新现代，适合日常使用',
    iconName: 'spa',
    // 主色 - Teal
    primary: Color(0xFF14B8A6),
    primaryLight: Color(0xFF2DD4BF),
    primaryDark: Color(0xFF0D9488),
    // 次要色 - Cyan
    secondary: Color(0xFF06B6D4),
    secondaryLight: Color(0xFF22D3EE),
    // 强调色
    accent: Color(0xFF06B6D4),
    // 功能性颜色 - 保持多彩但协调
    music: Color(0xFF8B5CF6), // 紫色
    video: Color(0xFFEC4899), // 粉色
    photo: Color(0xFF10B981), // 绿色
    book: Color(0xFFF59E0B), // 琥珀色
    download: Color(0xFF3B82F6), // 蓝色
    subscription: Color(0xFF8B5CF6), // 紫色
    ai: Color(0xFF6366F1), // 靛蓝色
    control: Color(0xFF8B5CF6), // 紫色
    // 深色背景 - 中性灰
    darkBackground: Color(0xFF0D0D0D),
    darkSurface: Color(0xFF1A1A1A),
    darkSurfaceVariant: Color(0xFF242424),
    darkSurfaceElevated: Color(0xFF2C2C2C),
    darkOutline: Color(0xFF3D3D3D),
  );

  /// 2. Ocean 海洋蓝 - 专业稳重
  /// 参考：VS Code, Notion, Linear
  static const ocean = ColorSchemePreset(
    id: 'ocean',
    name: '海洋蓝',
    description: '专业稳重，适合长时间使用',
    iconName: 'waves',
    // 主色 - 海洋蓝
    primary: Color(0xFF0EA5E9),
    primaryLight: Color(0xFF38BDF8),
    primaryDark: Color(0xFF0284C7),
    // 次要色 - 天蓝
    secondary: Color(0xFF06B6D4),
    secondaryLight: Color(0xFF22D3EE),
    // 强调色
    accent: Color(0xFF38BDF8),
    // 功能性颜色 - 蓝色系为主
    music: Color(0xFF8B5CF6), // 紫色
    video: Color(0xFFF472B6), // 粉色
    photo: Color(0xFF34D399), // 绿色
    book: Color(0xFFFBBF24), // 黄色
    download: Color(0xFF60A5FA), // 浅蓝
    subscription: Color(0xFFA78BFA), // 淡紫
    ai: Color(0xFF818CF8), // 靛蓝色
    control: Color(0xFF60A5FA), // 浅蓝
    // 深色背景 - 微蓝灰（非常细微）
    darkBackground: Color(0xFF0C0C0E),
    darkSurface: Color(0xFF18181B),
    darkSurfaceVariant: Color(0xFF222226),
    darkSurfaceElevated: Color(0xFF2A2A2E),
    darkOutline: Color(0xFF3B3B40),
  );

  /// 3. Sunset 日落橙 - 温暖活力
  /// 参考：Plex, VLC, SoundCloud
  static const sunset = ColorSchemePreset(
    id: 'sunset',
    name: '日落橙',
    description: '温暖活力，适合娱乐内容',
    iconName: 'wb_sunny',
    // 主色 - 橙色
    primary: Color(0xFFF97316),
    primaryLight: Color(0xFFFB923C),
    primaryDark: Color(0xFFEA580C),
    // 次要色 - 琥珀
    secondary: Color(0xFFF59E0B),
    secondaryLight: Color(0xFFFBBF24),
    // 强调色
    accent: Color(0xFFFB923C),
    // 功能性颜色 - 暖色调
    music: Color(0xFFEC4899), // 粉色
    video: Color(0xFFF472B6), // 亮粉
    photo: Color(0xFF10B981), // 绿色
    book: Color(0xFF8B5CF6), // 紫色
    download: Color(0xFF06B6D4), // 青色
    subscription: Color(0xFFFBBF24), // 黄色
    ai: Color(0xFF6366F1), // 靛蓝
    control: Color(0xFFEC4899), // 粉色
    // 深色背景 - 微暖灰
    darkBackground: Color(0xFF0E0D0C),
    darkSurface: Color(0xFF1C1A18),
    darkSurfaceVariant: Color(0xFF262422),
    darkSurfaceElevated: Color(0xFF2E2C2A),
    darkOutline: Color(0xFF403D3A),
  );

  /// 4. Forest 森林绿 - 自然护眼
  /// 参考：Spotify, 微信读书
  static const forest = ColorSchemePreset(
    id: 'forest',
    name: '森林绿',
    description: '自然护眼，适合阅读和长时间使用',
    iconName: 'park',
    // 主色 - 祖母绿
    primary: Color(0xFF10B981),
    primaryLight: Color(0xFF34D399),
    primaryDark: Color(0xFF059669),
    // 次要色 - 青绿
    secondary: Color(0xFF14B8A6),
    secondaryLight: Color(0xFF2DD4BF),
    // 强调色
    accent: Color(0xFF34D399),
    // 功能性颜色 - 自然色系
    music: Color(0xFF8B5CF6), // 紫色
    video: Color(0xFFF472B6), // 粉色
    photo: Color(0xFF22C55E), // 亮绿
    book: Color(0xFFFBBF24), // 黄色
    download: Color(0xFF06B6D4), // 青色
    subscription: Color(0xFFA78BFA), // 淡紫
    ai: Color(0xFF60A5FA), // 蓝色
    control: Color(0xFF22C55E), // 亮绿
    // 深色背景 - 微绿灰
    darkBackground: Color(0xFF0C0E0D),
    darkSurface: Color(0xFF171C19),
    darkSurfaceVariant: Color(0xFF212623),
    darkSurfaceElevated: Color(0xFF292E2B),
    darkOutline: Color(0xFF3A403C),
  );

  /// 5. Rose 玫瑰粉 - 温柔优雅
  /// 参考：Apple Music, Dribbble
  static const rose = ColorSchemePreset(
    id: 'rose',
    name: '玫瑰粉',
    description: '温柔优雅，适合生活类内容',
    iconName: 'local_florist',
    // 主色 - 玫瑰粉
    primary: Color(0xFFF43F5E),
    primaryLight: Color(0xFFFB7185),
    primaryDark: Color(0xFFE11D48),
    // 次要色 - 珊瑚
    secondary: Color(0xFFF472B6),
    secondaryLight: Color(0xFFF9A8D4),
    // 强调色
    accent: Color(0xFFFB7185),
    // 功能性颜色 - 柔和色调
    music: Color(0xFFA78BFA), // 淡紫
    video: Color(0xFFFB7185), // 亮粉
    photo: Color(0xFF34D399), // 绿色
    book: Color(0xFFFBBF24), // 黄色
    download: Color(0xFF60A5FA), // 蓝色
    subscription: Color(0xFFF472B6), // 粉色
    ai: Color(0xFF818CF8), // 靛蓝
    control: Color(0xFFA78BFA), // 淡紫
    // 深色背景 - 微粉灰
    darkBackground: Color(0xFF0E0C0D),
    darkSurface: Color(0xFF1C181A),
    darkSurfaceVariant: Color(0xFF262224),
    darkSurfaceElevated: Color(0xFF2E2A2C),
    darkOutline: Color(0xFF403B3D),
  );

  /// 6. Midnight 午夜黑 - 纯粹深邃
  /// 参考：Netflix, Apple TV+, AMOLED
  static const midnight = ColorSchemePreset(
    id: 'midnight',
    name: '午夜黑',
    description: '纯粹深邃，适合 OLED 屏幕和夜间使用',
    iconName: 'dark_mode',
    // 主色 - 纯白作为强调（极简风格）
    primary: Color(0xFFE5E5E5),
    primaryLight: Color(0xFFFFFFFF),
    primaryDark: Color(0xFFCCCCCC),
    // 次要色 - 浅灰
    secondary: Color(0xFF9CA3AF),
    secondaryLight: Color(0xFFD1D5DB),
    // 强调色 - 红色点缀（Netflix 风格）
    accent: Color(0xFFE50914),
    // 功能性颜色 - 彩色点缀在黑色背景上
    music: Color(0xFF8B5CF6), // 紫色
    video: Color(0xFFE50914), // Netflix 红
    photo: Color(0xFF22C55E), // 绿色
    book: Color(0xFFF59E0B), // 琥珀
    download: Color(0xFF3B82F6), // 蓝色
    subscription: Color(0xFFE50914), // 红色
    ai: Color(0xFF60A5FA), // 蓝色
    control: Color(0xFF9CA3AF), // 灰色
    // 深色背景 - 纯黑 AMOLED
    darkBackground: Color(0xFF000000),
    darkSurface: Color(0xFF0A0A0A),
    darkSurfaceVariant: Color(0xFF141414),
    darkSurfaceElevated: Color(0xFF1A1A1A),
    darkOutline: Color(0xFF2A2A2A),
  );

  /// 7. Lavender 薰衣草 - 柔和舒适
  /// 参考：Discord, Figma
  static const lavender = ColorSchemePreset(
    id: 'lavender',
    name: '薰衣草',
    description: '柔和舒适，减少视觉疲劳',
    iconName: 'auto_awesome',
    // 主色 - 薰衣草紫
    primary: Color(0xFF8B5CF6),
    primaryLight: Color(0xFFA78BFA),
    primaryDark: Color(0xFF7C3AED),
    // 次要色 - 靛蓝
    secondary: Color(0xFF6366F1),
    secondaryLight: Color(0xFF818CF8),
    // 强调色
    accent: Color(0xFFA78BFA),
    // 功能性颜色 - 梦幻色调
    music: Color(0xFFA78BFA), // 淡紫
    video: Color(0xFFF472B6), // 粉色
    photo: Color(0xFF34D399), // 绿色
    book: Color(0xFFFBBF24), // 黄色
    download: Color(0xFF60A5FA), // 蓝色
    subscription: Color(0xFFC084FC), // 亮紫
    ai: Color(0xFF818CF8), // 靛蓝
    control: Color(0xFF6366F1), // 靛蓝
    // 深色背景 - 微紫灰
    darkBackground: Color(0xFF0D0C0E),
    darkSurface: Color(0xFF1A181C),
    darkSurfaceVariant: Color(0xFF242228),
    darkSurfaceElevated: Color(0xFF2C2A30),
    darkOutline: Color(0xFF3D3A42),
  );

  /// 8. Monokai 经典 - 程序员最爱
  /// 参考：Sublime Text Monokai 主题
  static const monokai = ColorSchemePreset(
    id: 'monokai',
    name: '经典',
    description: '经典配色，程序员最爱',
    iconName: 'code',
    // 主色 - Monokai 黄
    primary: Color(0xFFA6E22E),
    primaryLight: Color(0xFFB8F339),
    primaryDark: Color(0xFF8CC721),
    // 次要色 - Monokai 粉
    secondary: Color(0xFFF92672),
    secondaryLight: Color(0xFFFF5A92),
    // 强调色 - Monokai 青
    accent: Color(0xFF66D9EF),
    // 功能性颜色 - Monokai 调色板
    music: Color(0xFFAE81FF), // Monokai 紫
    video: Color(0xFFF92672), // Monokai 粉
    photo: Color(0xFFA6E22E), // Monokai 绿
    book: Color(0xFFE6DB74), // Monokai 黄
    download: Color(0xFF66D9EF), // Monokai 青
    subscription: Color(0xFFFD971F), // Monokai 橙
    ai: Color(0xFFAE81FF), // Monokai 紫
    control: Color(0xFF66D9EF), // Monokai 青
    // 深色背景 - Monokai 背景
    darkBackground: Color(0xFF1E1E1E),
    darkSurface: Color(0xFF272822),
    darkSurfaceVariant: Color(0xFF333328),
    darkSurfaceElevated: Color(0xFF3E3D32),
    darkOutline: Color(0xFF49483E),
  );

  /// 所有预设列表
  static const List<ColorSchemePreset> all = [
    teal,
    ocean,
    sunset,
    forest,
    rose,
    midnight,
    lavender,
    monokai,
  ];

  /// 根据 ID 获取预设
  static ColorSchemePreset? getById(String id) {
    try {
      return all.firstWhere((preset) => preset.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 默认预设
  static const ColorSchemePreset defaultPreset = teal;
}
