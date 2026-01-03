# iOS 26 Liquid Glass 适配指南

> 创建时间: 2026-01-03
> 参考来源:
> - [Apple Newsroom - Liquid Glass Design](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
> - [Grow on iOS 26 - Liquid Glass Adaptation](https://fatbobman.com/en/posts/grow-on-ios26)
> - [Designing Custom UI with Liquid Glass](https://www.donnywals.com/designing-custom-ui-with-liquid-glass-on-ios-26/)
> - [MacRumors iOS 26 Guide](https://www.macrumors.com/guide/ios-26-liquid-glass/)

## 1. iOS 26 Liquid Glass 设计原则

### 1.1 核心理念

Liquid Glass 是 iOS 26 的核心设计语言，具有以下特点：

- **半透明材质**: 导航栏、工具栏、标签栏使用半透明玻璃效果
- **悬浮层级**: 导航元素悬浮于内容之上，创建独特的层次感
- **动态模糊**: 玻璃效果会动态反射和折射周围环境
- **分组按钮**: 工具栏按钮自动分组，共享玻璃背景

### 1.2 设计规范

| 元素 | iOS 26 规范 |
|------|------------|
| 导航栏 | 悬浮于内容上方，无边框，圆角玻璃背景 |
| 返回按钮 | 独立玻璃胶囊，带有 chevron.left 图标 |
| 工具栏按钮 | 分组在胶囊形玻璃容器内，按钮间使用间距（非分割线）|
| 弹出菜单 | 圆角矩形，无箭头尖角，玻璃背景 |
| 标签栏 | 悬浮圆角，滚动时收缩 |

### 1.3 禁止事项

- **不要**将玻璃效果应用于内容（列表、表格、媒体）
- **不要**叠加多层玻璃
- **不要**在玻璃层上设置不透明背景
- **不要**使用传统的导航栏边框和阴影

## 2. 当前应用架构

### 2.1 已完成适配

| 组件 | 文件 | 状态 |
|------|------|------|
| GlassButtonGroup | `adaptive_glass_app_bar.dart` | ✅ 完成 |
| GlassGroupIconButton | `adaptive_glass_app_bar.dart` | ✅ 完成 |
| GlassGroupPopupMenuButton | `adaptive_glass_app_bar.dart` | ✅ 完成 |
| showGlassPopupMenu | `adaptive_glass_app_bar.dart` | ✅ 完成 |
| AdaptiveGlassAppBar | `adaptive_glass_app_bar.dart` | ✅ 完成 |
| AdaptiveGlassHeader | `adaptive_glass_app_bar.dart` | ✅ 完成 |
| LiquidGlassPageLayout | `adaptive_glass_app_bar.dart` | ✅ 完成 |
| GlassSearchBar | `adaptive_glass_app_bar.dart` | ✅ 完成 |
| NativeTabBarController | `ios/Runner/` | ✅ 完成 |
| GlassPopupMenu (iOS) | `ios/Runner/GlassPopupMenu.swift` | ✅ 完成 |

### 2.2 需要新建的组件

| 组件 | 用途 | 优先级 |
|------|------|--------|
| GlassBackButton | 详情页左上角玻璃返回按钮 | P0 |
| GlassNavigationBar | 子页面的玻璃导航栏 | P0 |
| GlassFloatingBackButton | 悬浮玻璃返回按钮（适用于有背景图的页面）| P0 |

## 3. 需要适配的页面清单

### 3.1 视频模块 (P0 - 高优先级)

#### 详情页类

| 页面 | 文件 | 当前状态 | 需要改动 |
|------|------|----------|----------|
| 电影/剧集详情 | `video_detail_page.dart` | DecoratedBox 圆形按钮 | 改为 GlassFloatingBackButton |
| TMDB 预览页 | `tmdb_preview_page.dart` | 标准 AppBar | 改为玻璃导航栏 |

#### 查看全部类

| 页面 | 文件 | 当前状态 | 需要改动 |
|------|------|----------|----------|
| 每日推荐全部 | `video_list_page.dart:_CategoryFullPage` | 标准 AppBar | 改为玻璃导航栏 |
| 剧集全部 | `video_list_page.dart:_TvShowsFullPage` | 标准 AppBar | 改为玻璃导航栏 |
| 电影全部 | `video_list_page.dart:_MoviesPaginatedPage` | 标准 AppBar | 改为玻璃导航栏 |
| 电影系列全部 | `video_list_page.dart:_MovieCollectionsFullPage` | 标准 AppBar | 改为玻璃导航栏 |
| 电影系列详情 | `video_list_page.dart:_MovieCollectionPage` | 标准 AppBar | 改为玻璃导航栏 |
| 类型/地区筛选 | `video_list_page.dart:_FilteredVideosPaginatedPage` | 标准 AppBar | 改为玻璃导航栏 |

#### 设置类

| 页面 | 文件 | 当前状态 | 需要改动 |
|------|------|----------|----------|
| 刮削源设置 | `scraper_sources_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| 刮削表单 | `scraper_form_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| 手动刮削 | `manual_scraper_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| 剧集刮削 | `season_scraper_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| 播放器设置 | `video_player_settings_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| 重复视频 | `video_duplicates_page.dart` | 标准 AppBar | 改为玻璃导航栏 |

### 3.2 音乐模块 (P0 - 高优先级)

#### 详情页类

| 页面 | 文件 | 当前状态 | 需要改动 |
|------|------|----------|----------|
| 歌单详情 | `playlist_detail_page.dart` | 标准 Scaffold | 改为玻璃布局 + GlassFloatingBackButton |

#### 查看全部类

| 页面 | 文件 | 当前状态 | 需要改动 |
|------|------|----------|----------|
| 全部歌曲 | `music_list_page.dart:AllSongsPage` | 标准 AppBar | 改为玻璃导航栏 |
| 分类详情 | `music_list_page.dart:CategoryDetailPage` | 标准 AppBar | 改为玻璃导航栏 |
| 音乐分类页 | `music_list_page.dart:_MusicCategoryPage` | 标准 AppBar | 改为玻璃导航栏 |

#### 设置类

| 页面 | 文件 | 当前状态 | 需要改动 |
|------|------|----------|----------|
| 刮削源设置 | `music_scraper_sources_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| 刮削表单 | `music_scraper_form_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| 手动刮削 | `manual_music_scraper_page.dart` | 标准 AppBar | 改为玻璃导航栏 |

### 3.3 相册模块 (P1 - 中优先级)

| 页面 | 文件 | 当前状态 | 需要改动 |
|------|------|----------|----------|
| 重复照片 | `photo_duplicates_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| 人物照片 | `photo_people_page.dart` | 标准 AppBar | 改为玻璃导航栏 |

### 3.4 阅读模块 (P1 - 中优先级)

| 页面 | 文件 | 当前状态 | 需要改动 |
|------|------|----------|----------|
| 笔记编辑 | `note_editor_page.dart` | 标准 AppBar | 改为玻璃导航栏 |

### 3.5 设置/我的模块 (P1 - 中优先级)

| 页面 | 文件 | 当前状态 | 需要改动 |
|------|------|----------|----------|
| 我的页面 | `mine_page.dart` | 自定义布局 | 检查并适配 |
| 错误上报设置 | `error_report_settings_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| 连接源管理 | `sources_page.dart` | 自定义布局 | 检查并适配 |
| 源表单 | `source_form_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| 源类型选择 | `source_type_selection_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| 媒体库设置 | `media_library_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| 服务源页面 | `service_sources_page.dart` | 标准 AppBar | 改为玻璃导航栏 |

### 3.6 下载/传输模块 (P2 - 低优先级)

| 页面 | 文件 | 当前状态 | 需要改动 |
|------|------|----------|----------|
| 下载页面 | `download_page.dart` | 自定义布局 | 检查并适配 |
| 传输管理 | `transfer_manager_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| Aria2 详情 | `aria2_detail_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| qBittorrent 详情 | `qbittorrent_detail_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| Transmission 详情 | `transmission_detail_page.dart` | 标准 AppBar | 改为玻璃导航栏 |
| PT 站点详情 | `pt_site_detail_page.dart` | 标准 AppBar | 改为玻璃导航栏 |

### 3.7 文件浏览模块 (P2 - 低优先级)

| 页面 | 文件 | 当前状态 | 需要改动 |
|------|------|----------|----------|
| 文件浏览器 | `file_browser_page.dart` | 标准 AppBar | 改为玻璃导航栏 |

## 4. 实现方案

### 4.1 GlassFloatingBackButton 组件

用于有背景图片的详情页（如电影详情、歌单详情），按钮悬浮在内容左上角。

```dart
/// 玻璃悬浮返回按钮
///
/// 用于有背景图的详情页，按钮悬浮于内容左上角
/// iOS 26 风格：圆形玻璃背景 + chevron.left 图标
class GlassFloatingBackButton extends ConsumerWidget {
  const GlassFloatingBackButton({
    this.onPressed,
    this.onLongPress,
    this.tooltip = '返回',
    super.key,
  });

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safeTop = MediaQuery.of(context).padding.top;

    // 经典模式 - 使用半透明黑色背景
    if (!uiStyle.isGlass) {
      return Positioned(
        top: safeTop + 8,
        left: 8,
        child: _buildClassicButton(context),
      );
    }

    // 玻璃模式 - 使用 GlassButtonGroup
    return Positioned(
      top: safeTop + 8,
      left: 16,
      child: GlassButtonGroup(
        children: [
          GlassGroupIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onPressed: onPressed ?? () => Navigator.of(context).pop(),
            tooltip: tooltip,
            size: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildClassicButton(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: onPressed ?? () => Navigator.of(context).pop(),
          tooltip: tooltip,
        ),
      ),
    );
  }
}
```

### 4.2 GlassNavigationBar 组件

用于子页面的玻璃导航栏（如"查看全部"页面、设置页面）。

```dart
/// 玻璃导航栏
///
/// 用于子页面的导航栏，包含返回按钮、标题、可选的操作按钮
/// iOS 26 风格：悬浮玻璃背景，按钮使用 GlassButtonGroup
class GlassNavigationBar extends ConsumerWidget {
  const GlassNavigationBar({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onBack,
    this.showBackButton = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onBack;
  final bool showBackButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safeTop = MediaQuery.of(context).padding.top;

    if (!uiStyle.isGlass) {
      return _buildClassicNavigationBar(context, isDark, safeTop);
    }

    return _buildGlassNavigationBar(context, isDark, safeTop);
  }

  Widget _buildGlassNavigationBar(BuildContext context, bool isDark, double safeTop) {
    return AdaptiveGlassHeader(
      height: kToolbarHeight,
      child: Row(
        children: [
          if (showBackButton) ...[
            const SizedBox(width: 8),
            GlassButtonGroup(
              children: [
                GlassGroupIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onPressed: onBack ?? () => Navigator.of(context).pop(),
                  tooltip: '返回',
                  size: 18,
                ),
              ],
            ),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildClassicNavigationBar(BuildContext context, bool isDark, double safeTop) {
    return Container(
      padding: EdgeInsets.only(top: safeTop),
      color: isDark ? AppColors.darkSurface : Colors.white,
      child: SizedBox(
        height: kToolbarHeight,
        child: Row(
          children: [
            if (showBackButton)
              IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_rounded,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: onBack ?? () => Navigator.of(context).pop(),
              ),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
```

### 4.3 页面适配模式

#### 模式 A: 详情页（有背景图）

```dart
// 视频详情、歌单详情等有大背景图的页面
Scaffold(
  body: Stack(
    children: [
      // 主内容（包含背景图）
      CustomScrollView(
        slivers: [
          // Hero 区域（背景图）
          SliverToBoxAdapter(child: _buildHeroSection()),
          // 其他内容
          ...
        ],
      ),
      // 悬浮返回按钮
      GlassFloatingBackButton(
        onLongPress: () => Navigator.popUntil(context, (r) => r.isFirst),
      ),
      // 悬浮操作按钮（可选）
      Positioned(
        top: safeTop + 8,
        right: 16,
        child: GlassButtonGroup(children: [...]),
      ),
    ],
  ),
);
```

#### 模式 B: 列表页（查看全部）

```dart
// 电影全部、歌曲全部等列表页
Scaffold(
  body: Column(
    children: [
      // 玻璃导航栏
      GlassNavigationBar(
        title: '全部电影',
        subtitle: '共 100 部',
        trailing: GlassButtonGroup(
          children: [
            GlassGroupIconButton(icon: Icons.filter_list, ...),
            GlassGroupIconButton(icon: Icons.sort, ...),
          ],
        ),
      ),
      // 内容列表
      Expanded(
        child: GridView.builder(...),
      ),
    ],
  ),
);
```

#### 模式 C: 设置页（表单）

```dart
// 刮削设置、源表单等设置页
Scaffold(
  body: Column(
    children: [
      // 玻璃导航栏
      GlassNavigationBar(
        title: '刮削源设置',
        trailing: TextButton(onPressed: _save, child: Text('保存')),
      ),
      // 设置表单
      Expanded(
        child: ListView(
          children: [
            _buildSection('基本设置', [...]),
            _buildSection('高级选项', [...]),
          ],
        ),
      ),
    ],
  ),
);
```

## 5. iOS 原生实现（可选增强）

如果需要更原生的体验，可以为返回按钮创建 iOS 原生实现：

### 5.1 GlassBackButtonView.swift

```swift
import Flutter
import UIKit

class GlassBackButtonPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = GlassBackButtonViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "com.kkape.mynas/glass_back_button")
    }
}

class GlassBackButtonViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return GlassBackButtonView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args as? [String: Any] ?? [:],
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

class GlassBackButtonView: NSObject, FlutterPlatformView {
    private var container: UIView
    private var channel: FlutterMethodChannel

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: [String: Any],
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        container = UIView(frame: frame)
        channel = FlutterMethodChannel(
            name: "com.kkape.mynas/glass_back_button_\(viewId)",
            binaryMessenger: messenger
        )
        super.init()

        setupButton(isDark: args["isDark"] as? Bool ?? false)
    }

    func view() -> UIView {
        return container
    }

    private func setupButton(isDark: Bool) {
        // iOS 26+ 使用 UIGlassEffect
        if #available(iOS 26.0, *) {
            let button = UIButton(type: .system)
            button.setImage(
                UIImage(systemName: "chevron.left"),
                for: .normal
            )
            button.tintColor = isDark ? .white : .black

            // 应用 Liquid Glass 效果
            button.glassEffect = .regular

            button.addTarget(self, action: #selector(onTap), for: .touchUpInside)

            container.addSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 44),
                button.heightAnchor.constraint(equalToConstant: 44),
            ])
        } else {
            // iOS < 26 使用 UIVisualEffectView
            let blurEffect = UIBlurEffect(style: isDark ? .systemMaterialDark : .systemMaterial)
            let blurView = UIVisualEffectView(effect: blurEffect)
            blurView.layer.cornerRadius = 22
            blurView.clipsToBounds = true

            let button = UIButton(type: .system)
            button.setImage(
                UIImage(systemName: "chevron.left"),
                for: .normal
            )
            button.tintColor = isDark ? .white : .black
            button.addTarget(self, action: #selector(onTap), for: .touchUpInside)

            container.addSubview(blurView)
            blurView.contentView.addSubview(button)

            // Layout constraints...
        }
    }

    @objc private func onTap() {
        channel.invokeMethod("onTap", arguments: nil)
    }
}
```

## 6. 迁移检查清单

### 6.1 每个页面适配步骤

- [ ] 确定页面类型（详情页/列表页/设置页）
- [ ] 选择对应的适配模式（A/B/C）
- [ ] 替换 AppBar/SliverAppBar 为玻璃组件
- [ ] 添加 uiStyleProvider 依赖
- [ ] 测试经典模式回退
- [ ] 测试玻璃模式效果
- [ ] 验证深色/浅色模式

### 6.2 测试要点

- [ ] iOS 26 真机测试 Liquid Glass 效果
- [ ] iOS 15-25 测试模糊效果回退
- [ ] Android/桌面平台测试 Flutter 实现
- [ ] 经典模式测试（用户设置为经典风格时）
- [ ] 无障碍功能测试（对比度、触控区域）

## 7. 进度跟踪

| 阶段 | 状态 | 预计完成 |
|------|------|----------|
| 创建基础组件 | 待开始 | - |
| 视频模块适配 | 待开始 | - |
| 音乐模块适配 | 待开始 | - |
| 相册模块适配 | 待开始 | - |
| 阅读模块适配 | 待开始 | - |
| 设置模块适配 | 待开始 | - |
| 其他模块适配 | 待开始 | - |
| 全面测试 | 待开始 | - |

---

## 附录 A: SF Symbol 映射表

| Flutter Icon | SF Symbol |
|--------------|-----------|
| Icons.arrow_back_ios_new_rounded | chevron.left |
| Icons.arrow_back_rounded | arrow.left |
| Icons.close_rounded | xmark |
| Icons.search_rounded | magnifyingglass |
| Icons.more_vert_rounded | ellipsis |
| Icons.filter_list_rounded | line.3.horizontal.decrease.circle |
| Icons.sort_rounded | arrow.up.arrow.down |
| Icons.settings_rounded | gearshape |
| Icons.check_rounded | checkmark |
| Icons.add_rounded | plus |

## 附录 B: 颜色参考

| 用途 | 浅色模式 | 深色模式 |
|------|----------|----------|
| 玻璃背景 | black.withOpacity(0.06) | white.withOpacity(0.12) |
| 玻璃边框 | black.withOpacity(0.08) | white.withOpacity(0.15) |
| 禁用图标 | black26 | white38 |
| 普通图标 | black87 | white |
