# iOS 26 Liquid Glass 实现记录

## 目标
在 iOS 26+ 设备上实现真正的 Liquid Glass (水滴玻璃) 效果。

## 环境
- 设备: iPhone (programApe)
- iOS 版本: 26.2
- Flutter Platform View: UiKitView

---

## 当前进度

### ✅ 已完成

#### 1. 底部导航栏 (Tab Bar)
- **实现方式**: 使用原生 `UITabBarController`
- **文件**: `ios/Runner/LiquidGlassView.swift`, `lib/shared/widgets/liquid_glass/liquid_glass_nav_bar.dart`
- **效果**: 透明背景 + 选中指示器玻璃药丸 + 长按拖动 + 变形动画

#### 2. UI 风格切换
- **文件**: `lib/shared/providers/ui_style_provider.dart`, `lib/shared/widgets/main_scaffold.dart`
- **功能**:
  - 用户可在 classic / liquidClear / liquidTinted 之间切换
  - iOS 26 选择 classic 时使用传统不透明导航栏
  - iOS 26 选择 glass 时使用原生 Liquid Glass 导航栏

#### 3. 首次安装默认设置
- **文件**: `lib/shared/providers/ui_style_provider.dart`
- **功能**:
  - 首次安装时检测 iOS 26+，自动默认为 `liquidClear`
  - 用户主动修改后记住选择（`ui_style_user_set` 标记）
  - 重新安装后才会重置

---

## 🔧 共通组件抽取计划

### 当前抽象情况分析

| 组件类型 | 共通封装 | 直接使用 | 问题 |
|----------|----------|----------|------|
| 底部弹窗 | `showAppBottomSheet` (2处) | `showModalBottomSheet` (45处) | 大部分未使用统一封装 |
| 对话框 | ❌ 无 | `showDialog`/`AlertDialog` (33处) | 没有统一封装 |
| 弹出菜单 | ❌ 无 | `PopupMenuButton` (22处) | 没有统一封装 |
| 顶部导航栏 | ✅ `GlassAppBar` | - | 需要添加原生支持 |
| 搜索栏 | ❌ 无 | `TextField`/`SearchBar` (31处) | 分散使用 |
| 分段控制器 | ❌ 无 | `SegmentedButton` (2处) | 使用量少 |

### 需要创建/改造的共通组件

#### 1. `showAppDialog` - 统一对话框 (高优先级)
- **当前**: 33 处直接使用 `showDialog`/`AlertDialog`
- **目标**:
  - 创建 `showAppDialog()` 共通方法
  - iOS 26+ 自动使用原生 `UIAlertController`
  - 其他平台使用 Flutter `AlertDialog` + 玻璃效果
- **文件**: `lib/shared/widgets/app_dialog.dart`
- **迁移工作**: 替换 33 处调用

```dart
// 目标 API
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  Widget? content,
  List<DialogAction<T>>? actions,
  bool useNative = true,  // iOS 26 自动使用原生
});
```

#### 2. 推广 `showAppBottomSheet` (高优先级)
- **当前**: 只有 2 处使用，45 处直接使用 `showModalBottomSheet`
- **目标**:
  - 添加 `useNative` 参数，iOS 26 使用 `UISheetPresentationController`
  - 迁移 45 处直接调用
- **迁移工作**: 替换 45 处调用

#### 3. `AppPopupMenu` - 统一弹出菜单 (中优先级)
- **当前**: 22 处使用 `PopupMenuButton`
- **目标**:
  - 创建 `AppPopupMenu` 组件
  - iOS 26+ 使用原生 `UIMenu` / `UIContextMenuInteraction`
- **文件**: `lib/shared/widgets/app_popup_menu.dart`

#### 4. `AppSearchBar` - 统一搜索栏 (中优先级)
- **当前**: 31 处分散使用 `TextField`/`SearchBar`
- **目标**:
  - 创建 `AppSearchBar` 组件
  - iOS 26+ 使用原生 `UISearchBar`
- **文件**: `lib/shared/widgets/app_search_bar.dart`

#### 5. 改造 `GlassAppBar` (中优先级)
- **当前**: 已有统一封装，使用 Flutter BackdropFilter
- **目标**:
  - 添加 `useNative` 参数
  - iOS 26+ 使用原生 `UINavigationBar`

#### 6. `AppSegmentedControl` - 统一分段控制器 (低优先级)
- **当前**: 只有 2 处使用
- **目标**:
  - 创建 `AppSegmentedControl` 组件
  - iOS 26+ 使用原生 `UISegmentedControl`
- **说明**: 使用量少，优先级低

### 迁移策略

1. **第一阶段**: 创建共通组件，保持向后兼容
   - 创建 `showAppDialog`
   - 扩展 `showAppBottomSheet` 支持原生
   - 创建 `AppPopupMenu`

2. **第二阶段**: 逐步迁移现有代码
   - 替换 `showDialog` → `showAppDialog`
   - 替换 `showModalBottomSheet` → `showAppBottomSheet`
   - 替换 `PopupMenuButton` → `AppPopupMenu`

3. **第三阶段**: 添加原生 iOS 26 支持
   - 实现原生 Platform Channel
   - 各组件添加 `useNative` 判断

### 预计工作量

| 组件 | 创建共通组件 | 迁移现有代码 | 添加原生支持 |
|------|-------------|-------------|-------------|
| 对话框 | 1天 | 2天 | 2天 |
| 底部弹窗 | 已有 | 3天 | 2天 |
| 弹出菜单 | 1天 | 2天 | 2天 |
| 搜索栏 | 1天 | 2天 | 1天 |
| 导航栏 | 已有 | - | 2天 |
| 分段控制 | 0.5天 | 0.5天 | 1天 |

---

## 📋 待适配任务

### 高优先级 (主要 UI 组件)

#### 1. 顶部导航栏 (App Bar / Navigation Bar)
- **当前实现**: `lib/shared/widgets/glass_app_bar.dart` - Flutter BackdropFilter
- **目标**: iOS 26 使用原生 `UINavigationBar` 自动获得 Liquid Glass
- **难点**:
  - Flutter 页面需要与原生 NavigationBar 协调
  - 需要处理标题、返回按钮、actions 的传递
- **参考**: iOS 26 原生 App 的导航栏效果

#### 2. 底部弹窗 (Bottom Sheet)
- **当前实现**: `lib/shared/widgets/app_bottom_sheet.dart` - Flutter DraggableScrollableSheet
- **目标**: iOS 26 使用原生 `UISheetPresentationController`
- **难点**:
  - 需要 Platform Channel 传递内容
  - 或使用 `UIHostingController` 嵌入 SwiftUI 视图
- **涉及文件**: 21 个 `*_sheet.dart` 文件

#### 3. 对话框 (Alert / Dialog)
- **当前实现**: Flutter `showDialog` / `AlertDialog`
- **目标**: iOS 26 使用原生 `UIAlertController`
- **难点**: 需要 Platform Channel 传递按钮和回调
- **涉及组件**: `auto_scrape_dialog.dart`, `quality_switch_dialog.dart`, `subtitle_download_dialog.dart` 等

### 中优先级 (次要组件)

#### 4. 桌面端侧边导航栏 (Sidebar)
- **当前实现**: `main_scaffold.dart` 中的 `_buildDesktopNav`
- **目标**: macOS 26 使用原生 `NSVisualEffectView` 或 SwiftUI `.glassEffect()`
- **说明**: 仅影响 macOS 平台

#### 5. 播放器工具栏 (Player Toolbar)
- **当前实现**: 各播放器页面的控制栏
- **目标**: 悬浮玻璃效果工具栏
- **涉及文件**: `video_player_page.dart`, `music_player_page.dart`

#### 6. 搜索栏 (Search Bar)
- **当前实现**: Flutter `TextField` / `SearchBar`
- **目标**: iOS 26 使用原生 `UISearchBar` 获得 Liquid Glass
- **说明**: 搜索栏在 iOS 26 有特殊的玻璃效果

#### 7. 分段控制器 (Segmented Control)
- **当前实现**: Flutter `ToggleButtons` / `SegmentedButton`
- **目标**: iOS 26 使用原生 `UISegmentedControl`
- **说明**: iOS 26 的 SegmentedControl 有独特的玻璃变形效果

### 低优先级 (可选组件)

#### 8. 内容卡片 (Card)
- **当前实现**: `lib/shared/widgets/glass_container.dart`
- **目标**: 可选的玻璃效果卡片
- **说明**: 不是所有卡片都需要玻璃效果，按需使用

#### 9. 上下文菜单 (Context Menu)
- **当前实现**: `lib/shared/widgets/context_menu_region.dart`
- **目标**: iOS 26 使用原生 `UIContextMenuInteraction`
- **说明**: 原生菜单自动获得 Liquid Glass

#### 10. 弹出菜单 (Popover)
- **当前实现**: Flutter `PopupMenuButton`
- **目标**: iOS 26 使用原生 `UIPopoverPresentationController`
- **说明**: 原生 Popover 自动获得 Liquid Glass

---

## 技术方案

### 方案 A: 原生 UIKit 组件 (推荐)
iOS 26 的系统 UI 组件自动获得 Liquid Glass 效果：
- `UITabBar` ✅ 已实现
- `UINavigationBar`
- `UISheetPresentationController`
- `UIAlertController`
- `UISearchBar`
- `UISegmentedControl`
- `UIContextMenuInteraction`

**优点**: 效果最正确，与系统一致
**缺点**: 需要 Platform Channel 通信

### 方案 B: SwiftUI + UIHostingController
使用 SwiftUI 的 `.glassEffect()` 修饰符：
```swift
SomeView()
    .glassEffect(.regular.interactive(), in: .capsule)
```

**优点**: 更灵活的自定义
**缺点**: 在 Flutter Platform View 中可能有渲染问题

### 方案 C: Flutter BackdropFilter (回退)
在不支持原生效果的情况下使用 Flutter 模糊：
```dart
ClipRRect(
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
    child: content,
  ),
)
```

**优点**: 跨平台一致
**缺点**: 无法实现 iOS 26 特有的交互效果

---

## ✅ 底部导航栏实现细节

### 关键发现
**iOS 26 的 UITabBar 自动获得 Liquid Glass 效果，无需任何自定义代码！**

### 正确实现
```swift
class LiquidGlassTabBarController: UITabBarController, UITabBarControllerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()

        // 透明背景
        view.backgroundColor = .clear
        view.isOpaque = false
        delegate = self

        // 配置外观
        let appearance = UITabBarAppearance()
        if #available(iOS 26.0, *) {
            appearance.configureWithTransparentBackground()
        }
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.isTranslucent = true

        // 创建 tab items
        rebuildTabs()
    }
}
```

### 系统自动处理的效果
- 选中指示器的玻璃"药丸"效果
- 长按拖动切换 tab
- 按压动画效果
- tab 之间的变形动画

---

## ❌ 之前的错误尝试

### 错误方法 1: SwiftUI .glassEffect() 直接应用
**结果**: 失败 - 在 Flutter Platform View 的 UIKit 环境中无法正确渲染

### 错误方法 2: UIGlassEffect() 默认初始化
**结果**: 毛玻璃效果，不是真正的透明玻璃

### 错误方法 3: UIGlassEffect(style: .clear)
**结果**: 仍然不透明，无法实现真正的 Liquid Glass 效果

### 错误方法 4: SwiftUI GlassEffectContainer + glassEffectID
**结果**: 导航栏完全不透明，选中效果不变动，无交互反馈

---

## 文件清单

### Swift (原生端)
- `ios/Runner/LiquidGlassView.swift` - 使用 UITabBarController 实现导航栏
- `ios/Runner/LiquidGlassChannel.swift` - Platform Channel 通信
- `ios/Runner/AppDelegate.swift` - 注册插件

### Dart (Flutter 端)
- `lib/shared/widgets/liquid_glass/liquid_glass_nav_bar.dart` - 导航栏组件
- `lib/shared/widgets/liquid_glass/liquid_glass_service.dart` - 平台服务
- `lib/shared/providers/ui_style_provider.dart` - UI 风格状态管理
- `lib/shared/widgets/main_scaffold.dart` - 主布局

### 现有玻璃效果组件 (Flutter 实现)
- `lib/shared/widgets/glass_app_bar.dart` - 玻璃 AppBar
- `lib/shared/widgets/glass_container.dart` - 玻璃容器
- `lib/shared/widgets/adaptive_glass_container.dart` - 自适应玻璃容器
- `lib/shared/widgets/app_bottom_sheet.dart` - 底部弹窗

---

## 调试日志

```bash
# 实时查看 Liquid Glass 日志
log stream --predicate 'subsystem == "com.apple.os_log"' | grep "LiquidGlass"
```

日志前缀：
- `🔮 LiquidGlassView:` - Platform View 相关
- `🔮 LiquidGlassTabBarController:` - TabBar 控制器相关
- `🔮 LiquidGlassPlugin:` - 插件注册相关

---

## 参考资料

- WWDC25: Meet the Liquid Glass design system
- WWDC25: Build with UIKit and Liquid Glass
- Apple Developer: UITabBarController
- Apple Developer: UISheetPresentationController
- `native_glass_navbar` Flutter 包

---

## 更新日志

### 2024-12-31
- ✅ 实现底部导航栏 Liquid Glass 效果
- ✅ 修复 UI 风格切换在 iOS 26 上失效的问题
- ✅ 添加首次安装默认风格检测
- ✅ 添加用户选择记忆功能
- 📋 整理待适配任务列表
