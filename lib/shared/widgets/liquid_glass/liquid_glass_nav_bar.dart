import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/shared/widgets/liquid_glass/liquid_glass_service.dart';

/// 导航项配置
class LiquidGlassNavItem {
  const LiquidGlassNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.sfSymbol,
  });

  /// Flutter 图标
  final IconData icon;

  /// 选中状态图标
  final IconData selectedIcon;

  /// 标签文本
  final String label;

  /// SF Symbol 名称 (用于原生视图)
  final String? sfSymbol;

  Map<String, dynamic> toMap() => {
        'icon': _iconToSFSymbol(icon),
        'selectedIcon': _iconToSFSymbol(selectedIcon),
        'label': label,
      };

  /// 将 Material Icon 映射到 SF Symbol
  static String _iconToSFSymbol(IconData icon) {
    // 使用 codePoint 进行匹配，避免 const map 的限制
    final codePoint = icon.codePoint;

    // 常用图标映射 (使用 codePoint)
    // 注意：outlined 和 rounded 版本映射到不同的 SF Symbol
    final iconMap = <int, String>{
      // 影视
      Icons.movie_filter_outlined.codePoint: 'film',
      Icons.movie_filter_rounded.codePoint: 'film.fill',
      // 曲库
      Icons.library_music_outlined.codePoint: 'music.note.list',
      Icons.library_music_rounded.codePoint: 'music.note.list',  // 没有 .fill 变体
      // 相册
      Icons.photo_album_outlined.codePoint: 'photo.on.rectangle',
      Icons.photo_album_rounded.codePoint: 'photo.on.rectangle.fill',
      // 阅读
      Icons.menu_book_outlined.codePoint: 'book',
      Icons.menu_book_rounded.codePoint: 'book.fill',
      // 我的
      Icons.account_circle_outlined.codePoint: 'person.circle',
      Icons.account_circle_rounded.codePoint: 'person.circle.fill',
      // 其他常用图标
      Icons.home_outlined.codePoint: 'house',
      Icons.home_rounded.codePoint: 'house.fill',
      Icons.settings_outlined.codePoint: 'gearshape',
      Icons.settings_rounded.codePoint: 'gearshape.fill',
      Icons.search_outlined.codePoint: 'magnifyingglass',
      Icons.search_rounded.codePoint: 'magnifyingglass',
    };

    return iconMap[codePoint] ?? 'circle';
  }
}

/// iOS 26 Liquid Glass 悬浮底部导航栏
///
/// 在 iOS 26+ 使用原生 SwiftUI .glassEffect() 实现真正的 Liquid Glass 效果
/// 在其他平台回退到 Flutter 的 BackdropFilter 实现
///
/// 特点：
/// - 悬浮设计，与底部边缘有间距
/// - 胶囊形外观
/// - iOS 26+ 支持交互动画（按压、弹跳、闪光）
/// - iOS 26+ 支持形态变换动画
class LiquidGlassNavBar extends StatefulWidget {
  const LiquidGlassNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    this.forceNative = false,
    this.forceFallback = false,
    super.key,
  });

  /// 导航项列表
  final List<LiquidGlassNavItem> items;

  /// 当前选中索引
  final int selectedIndex;

  /// 点击回调
  final ValueChanged<int> onTap;

  /// 强制使用原生视图（即使不支持 Liquid Glass）
  final bool forceNative;

  /// 强制使用 Flutter 回退（即使支持 Liquid Glass）
  final bool forceFallback;

  @override
  State<LiquidGlassNavBar> createState() => _LiquidGlassNavBarState();
}

class _LiquidGlassNavBarState extends State<LiquidGlassNavBar> {
  static const _viewType = 'com.kkape.mynas/liquid_glass_view';

  MethodChannel? _viewChannel;

  bool get _shouldUseNative {
    if (widget.forceFallback) return false;
    if (kIsWeb) return false;
    if (!Platform.isIOS) return false;
    if (widget.forceNative) return true;

    // 使用原生视图（无论是否支持 Liquid Glass，原生都有更好的回退）
    return true;
  }

  @override
  void didUpdateWidget(LiquidGlassNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 如果选中索引变化，通知原生视图
    if (oldWidget.selectedIndex != widget.selectedIndex && _viewChannel != null) {
      _viewChannel!.invokeMethod('updateSelectedIndex', widget.selectedIndex);
    }
  }

  void _onPlatformViewCreated(int viewId) {
    final channelName = 'com.kkape.mynas/liquid_glass_view_$viewId';
    _viewChannel = MethodChannel(channelName);

    _viewChannel!.setMethodCallHandler((call) async {
      if (call.method == 'onNavTap') {
        final index = call.arguments as int;
        if (index != widget.selectedIndex) {
          // 触觉反馈
          await LiquidGlassService.instance.hapticFeedback(HapticType.selection);
          widget.onTap(index);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_shouldUseNative) {
      return _buildNativeNavBar(isDark);
    }

    return _buildFallbackNavBar(context, isDark);
  }

  Widget _buildNativeNavBar(bool isDark) {
    final creationParams = <String, dynamic>{
      'viewType': 'navBar',
      'isDark': isDark,
      'selectedIndex': widget.selectedIndex,
      'items': widget.items.map((e) => e.toMap()).toList(),
      'cornerRadius': 30.0,
      'isInteractive': true,
    };

    return SizedBox(
      height: 70,
      child: UiKitView(
        viewType: _viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
    );
  }

  Widget _buildFallbackNavBar(BuildContext context, bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(35),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SizedBox(
        height: 70,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(35),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(35),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.1),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(widget.items.length, (index) {
                  final item = widget.items[index];
                  final isSelected = index == widget.selectedIndex;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (index != widget.selectedIndex) {
                          HapticFeedback.selectionClick();
                          widget.onTap(index);
                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primary.withValues(alpha: isDark ? 0.25 : 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isSelected ? item.selectedIcon : item.icon,
                              color: isSelected
                                  ? colorScheme.primary
                                  : isDark
                                      ? Colors.white70
                                      : Colors.black54,
                              size: 22,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                color: isSelected
                                    ? colorScheme.primary
                                    : isDark
                                        ? Colors.white70
                                        : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 悬浮导航栏容器
///
/// 将导航栏定位在屏幕底部，并提供悬浮效果
class LiquidGlassNavBarScaffold extends StatelessWidget {
  const LiquidGlassNavBarScaffold({
    required this.body,
    required this.navBar,
    this.bottomPadding = 16.0,
    this.horizontalPadding = 16.0,
    super.key,
  });

  /// 页面主体内容
  final Widget body;

  /// 导航栏
  final LiquidGlassNavBar navBar;

  /// 底部间距
  final double bottomPadding;

  /// 水平间距
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;

    return Stack(
      children: [
        // 主体内容（需要为导航栏留出空间）
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: 70 + bottomPadding + bottomSafeArea,
            ),
            child: body,
          ),
        ),

        // 悬浮导航栏
        Positioned(
          left: horizontalPadding,
          right: horizontalPadding,
          bottom: bottomPadding + bottomSafeArea,
          child: navBar,
        ),
      ],
    );
  }
}
