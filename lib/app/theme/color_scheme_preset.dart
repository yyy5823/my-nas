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

  /// 9. Spotify 绿 - 音乐氛围
  /// 参考：Spotify 官方配色
  static const spotify = ColorSchemePreset(
    id: 'spotify',
    name: 'Spotify 绿',
    description: '音乐氛围，充满活力',
    iconName: 'music_note',
    // 主色 - Spotify 绿
    primary: Color(0xFF1DB954),
    primaryLight: Color(0xFF1ED760),
    primaryDark: Color(0xFF169C46),
    // 次要色
    secondary: Color(0xFF1DB954),
    secondaryLight: Color(0xFF57D983),
    // 强调色
    accent: Color(0xFF1ED760),
    // 功能性颜色
    music: Color(0xFF1DB954), // Spotify 绿
    video: Color(0xFFE91E63), // 粉色
    photo: Color(0xFF4CAF50), // 绿色
    book: Color(0xFFFF9800), // 橙色
    download: Color(0xFF2196F3), // 蓝色
    subscription: Color(0xFF1DB954), // Spotify 绿
    ai: Color(0xFF9C27B0), // 紫色
    control: Color(0xFF1DB954), // Spotify 绿
    // 深色背景 - Spotify 黑
    darkBackground: Color(0xFF121212),
    darkSurface: Color(0xFF181818),
    darkSurfaceVariant: Color(0xFF282828),
    darkSurfaceElevated: Color(0xFF333333),
    darkOutline: Color(0xFF404040),
  );

  /// 10. Twitter 蓝 - 社交清新
  /// 参考：Twitter/X 官方配色
  static const twitter = ColorSchemePreset(
    id: 'twitter',
    name: 'Twitter 蓝',
    description: '社交清新，简洁大方',
    iconName: 'chat_bubble',
    // 主色 - Twitter 蓝
    primary: Color(0xFF1DA1F2),
    primaryLight: Color(0xFF4DB5F5),
    primaryDark: Color(0xFF1A8CD8),
    // 次要色
    secondary: Color(0xFF1DA1F2),
    secondaryLight: Color(0xFF71C9F8),
    // 强调色
    accent: Color(0xFF1DA1F2),
    // 功能性颜色
    music: Color(0xFF9B59B6), // 紫色
    video: Color(0xFFE74C3C), // 红色
    photo: Color(0xFF2ECC71), // 绿色
    book: Color(0xFFF39C12), // 橙色
    download: Color(0xFF1DA1F2), // Twitter 蓝
    subscription: Color(0xFF1DA1F2), // Twitter 蓝
    ai: Color(0xFF8E44AD), // 深紫
    control: Color(0xFF1DA1F2), // Twitter 蓝
    // 深色背景 - Twitter 暗黑
    darkBackground: Color(0xFF15202B),
    darkSurface: Color(0xFF192734),
    darkSurfaceVariant: Color(0xFF22303C),
    darkSurfaceElevated: Color(0xFF2C3E50),
    darkOutline: Color(0xFF38444D),
  );

  /// 11. Dracula 暗夜 - 吸血鬼主题
  /// 参考：Dracula Theme 官方配色
  static const dracula = ColorSchemePreset(
    id: 'dracula',
    name: 'Dracula 暗夜',
    description: '暗夜风格，护眼舒适',
    iconName: 'nights_stay',
    // 主色 - Dracula 紫
    primary: Color(0xFFBD93F9),
    primaryLight: Color(0xFFCAA9FA),
    primaryDark: Color(0xFFAB7DF8),
    // 次要色 - Dracula 粉
    secondary: Color(0xFFFF79C6),
    secondaryLight: Color(0xFFFF92D0),
    // 强调色 - Dracula 青
    accent: Color(0xFF8BE9FD),
    // 功能性颜色 - Dracula 调色板
    music: Color(0xFFBD93F9), // 紫色
    video: Color(0xFFFF79C6), // 粉色
    photo: Color(0xFF50FA7B), // 绿色
    book: Color(0xFFF1FA8C), // 黄色
    download: Color(0xFF8BE9FD), // 青色
    subscription: Color(0xFFFFB86C), // 橙色
    ai: Color(0xFFBD93F9), // 紫色
    control: Color(0xFF8BE9FD), // 青色
    // 深色背景 - Dracula 背景
    darkBackground: Color(0xFF282A36),
    darkSurface: Color(0xFF2D303E),
    darkSurfaceVariant: Color(0xFF343746),
    darkSurfaceElevated: Color(0xFF3D4052),
    darkOutline: Color(0xFF44475A),
  );

  /// 12. Nord 极光 - 北欧极简
  /// 参考：Nord Theme 官方配色
  static const nord = ColorSchemePreset(
    id: 'nord',
    name: 'Nord 极光',
    description: '北欧极简，冷静优雅',
    iconName: 'ac_unit',
    // 主色 - Nord 蓝
    primary: Color(0xFF88C0D0),
    primaryLight: Color(0xFF8FBCBB),
    primaryDark: Color(0xFF81A1C1),
    // 次要色 - Nord 青
    secondary: Color(0xFF5E81AC),
    secondaryLight: Color(0xFF81A1C1),
    // 强调色
    accent: Color(0xFF88C0D0),
    // 功能性颜色 - Nord 调色板
    music: Color(0xFFB48EAD), // Nord 紫
    video: Color(0xFFBF616A), // Nord 红
    photo: Color(0xFFA3BE8C), // Nord 绿
    book: Color(0xFFEBCB8B), // Nord 黄
    download: Color(0xFF88C0D0), // Nord 青
    subscription: Color(0xFFD08770), // Nord 橙
    ai: Color(0xFFB48EAD), // Nord 紫
    control: Color(0xFF5E81AC), // Nord 蓝
    // 深色背景 - Nord Polar Night
    darkBackground: Color(0xFF2E3440),
    darkSurface: Color(0xFF3B4252),
    darkSurfaceVariant: Color(0xFF434C5E),
    darkSurfaceElevated: Color(0xFF4C566A),
    darkOutline: Color(0xFF5A657A),
  );

  /// 13. Solarized 阳光 - 经典护眼
  /// 参考：Solarized 官方配色（Dark 模式）
  static const solarized = ColorSchemePreset(
    id: 'solarized',
    name: 'Solarized 阳光',
    description: '经典护眼，科技感十足',
    iconName: 'wb_twilight',
    // 主色 - Solarized 青
    primary: Color(0xFF2AA198),
    primaryLight: Color(0xFF35C4BA),
    primaryDark: Color(0xFF268BD2),
    // 次要色 - Solarized 蓝
    secondary: Color(0xFF268BD2),
    secondaryLight: Color(0xFF4DA3E0),
    // 强调色
    accent: Color(0xFF2AA198),
    // 功能性颜色 - Solarized 调色板
    music: Color(0xFF6C71C4), // Solarized 紫
    video: Color(0xFFD33682), // Solarized 品红
    photo: Color(0xFF859900), // Solarized 绿
    book: Color(0xFFB58900), // Solarized 黄
    download: Color(0xFF268BD2), // Solarized 蓝
    subscription: Color(0xFFCB4B16), // Solarized 橙
    ai: Color(0xFF6C71C4), // Solarized 紫
    control: Color(0xFF2AA198), // Solarized 青
    // 深色背景 - Solarized Dark
    darkBackground: Color(0xFF002B36),
    darkSurface: Color(0xFF073642),
    darkSurfaceVariant: Color(0xFF0A4050),
    darkSurfaceElevated: Color(0xFF0D4A5C),
    darkOutline: Color(0xFF586E75),
  );

  /// 14. Material 动感 - Material You
  /// 参考：Google Material You 设计语言
  static const materialYou = ColorSchemePreset(
    id: 'material_you',
    name: 'Material 动感',
    description: 'Material You 设计，现代动感',
    iconName: 'palette',
    // 主色 - Material You 紫蓝
    primary: Color(0xFF6750A4),
    primaryLight: Color(0xFF7F67BE),
    primaryDark: Color(0xFF4F378B),
    // 次要色 - Material You 青
    secondary: Color(0xFF625B71),
    secondaryLight: Color(0xFF7D7584),
    // 强调色 - Material You 粉
    accent: Color(0xFFD0BCFF),
    // 功能性颜色 - Material You 调色板
    music: Color(0xFF6750A4), // 紫色
    video: Color(0xFFB3261E), // 红色
    photo: Color(0xFF146C2E), // 绿色
    book: Color(0xFFFFB300), // 琥珀
    download: Color(0xFF0061A4), // 蓝色
    subscription: Color(0xFF6750A4), // 紫色
    ai: Color(0xFF7F67BE), // 亮紫
    control: Color(0xFF625B71), // 灰紫
    // 深色背景 - Material You Dark
    darkBackground: Color(0xFF1C1B1F),
    darkSurface: Color(0xFF2B2930),
    darkSurfaceVariant: Color(0xFF49454F),
    darkSurfaceElevated: Color(0xFF36343B),
    darkOutline: Color(0xFF938F99),
  );

  /// 15. Cyberpunk 赛博 - 赛博朋克
  /// 参考：Cyberpunk 2077, 赛博朋克美学
  static const cyberpunk = ColorSchemePreset(
    id: 'cyberpunk',
    name: 'Cyberpunk 赛博',
    description: '赛博朋克，未来科技感',
    iconName: 'blur_on',
    // 主色 - 霓虹粉
    primary: Color(0xFFFF2A6D),
    primaryLight: Color(0xFFFF5588),
    primaryDark: Color(0xFFD91656),
    // 次要色 - 霓虹青
    secondary: Color(0xFF05D9E8),
    secondaryLight: Color(0xFF36E8F5),
    // 强调色 - 霓虹黄
    accent: Color(0xFFFCE700),
    // 功能性颜色 - 霓虹调色板
    music: Color(0xFFFF2A6D), // 霓虹粉
    video: Color(0xFFFF2A6D), // 霓虹粉
    photo: Color(0xFF05D9E8), // 霓虹青
    book: Color(0xFFFCE700), // 霓虹黄
    download: Color(0xFF05D9E8), // 霓虹青
    subscription: Color(0xFFFF2A6D), // 霓虹粉
    ai: Color(0xFFD300C5), // 霓虹紫
    control: Color(0xFF05D9E8), // 霓虹青
    // 深色背景 - 深紫黑
    darkBackground: Color(0xFF0D0221),
    darkSurface: Color(0xFF150734),
    darkSurfaceVariant: Color(0xFF1F0C47),
    darkSurfaceElevated: Color(0xFF2A1158),
    darkOutline: Color(0xFF3D1F6D),
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
    spotify,
    twitter,
    dracula,
    nord,
    solarized,
    materialYou,
    cyberpunk,
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
