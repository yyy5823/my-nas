# iOS 26 Liquid Glass 实现指南（官方规范对齐版）

> 目标：所有玻璃效果与交互 100% 使用 iOS 26 系统 SDK，避免自绘伪效果。本文聚焦导航栏/工具栏按钮组、搜索、弹出菜单（更多）、顶部安全区适配。

## 1. 设计与布局原则
- **悬浮层级**：导航/工具栏、搜索、弹出菜单都是悬浮胶囊，离开内容层，且不与背景产生缝隙。
- **安全区起点**：所有悬浮元素从 `safeAreaInsets.top` 下方开始，避免被状态栏（时间/Wi‑Fi/电量）遮挡。
- **触控分组**：右上角按钮组合在一个胶囊内（系统玻璃背景），不使用分隔线，使用 8pt 间距。
- **原生模糊**：iOS 26+ 使用 `UIGlassEffect` / `.glassEffect`，不叠加手动半透明色块；<26 回退 `UIBlurEffect`.
- **动态交互**：系统提供的弹出菜单、搜索面板、编辑菜单，禁止自绘；始终走系统 API 以获得惯性/手势/动效。

## 2. 系统 API 清单（必须使用）
- **玻璃背景**：`UIGlassEffect()` + `UIVisualEffectView(effect:)`，或 SwiftUI `.glassEffect(.regular.interactive())`。  
  - 使用 `.isInteractive = true`，cornerRadius 由容器决定（胶囊 22pt/圆形 20pt）。
- **分组按钮**：`UIStackView` + `UIButton`，放入同一 `UIVisualEffectView`，spacing=8，contentEdgeInsets=10/6。  
  - SF Symbol 配置：`UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)`.
- **弹出菜单（更多）**：
  - ✅ **iOS 14+**：使用 `UIButton.menu` + `showsMenuAsPrimaryAction = true`（点击即弹出）
  - ✅ **iOS 13**：使用 `UIContextMenuInteraction` + `UIMenu`（需长按触发）
  - ✅ **iOS < 13**：回退自定义玻璃菜单（`LegacyGlassMenuViewController`）
- **搜索**：
  - ✅ **默认模式**：`UIGlassEffect` + `UITextField` 自定义胶囊搜索栏
  - ✅ **原生模式**：`UISearchBar`（通过 `useNativeSearchBar: true` 启用）
  - 两种模式均支持 iOS 26 Liquid Glass 自动适配
- **弹出菜单锚点**：使用按钮中心作为 sourcePoint；确保 anchorView 位于 safe area 内。

## 3. 布局规范（关键尺寸）
- 顶部按钮组胶囊：高度 44pt，左右内边距 10pt，按钮尺寸 36‑40pt，间距 8pt，圆角 22pt。
- 独立圆形按钮：直径 40pt，圆角 20pt。
- 搜索栏：高度 44pt，胶囊圆角=高度/2；左侧系统放大镜，右侧清除按钮使用 `xmark.circle.fill`。  
- 悬浮位置：`top = safeAreaInsets.top + 8`（按钮组）；搜索栏在键盘上方：`bottom = keyboardHeight + 16`。
- 弹出菜单：最小宽度 200pt，cornerRadius 14pt，系统控制阴影/高亮。

## 4. 集成流程（Flutter 宿主示例）

### 4.1 搜索栏
**默认模式（推荐）**  
使用 `UiKitView` 托管 `GlassSearchBarPlatformView`：
```dart
UiKitView(
  viewType: 'com.kkape.mynas/glass_search_bar',
  creationParams: {
    'isDark': isDark,
    'placeholder': '搜索',
    'autofocus': true,
    'height': 44.0,
  },
)
```

**原生 UISearchBar 模式**  
```dart
UiKitView(
  viewType: 'com.kkape.mynas/glass_search_bar',
  creationParams: {
    'useNativeSearchBar': true,  // 启用完全原生 UISearchBar
    'isDark': isDark,
    'placeholder': '搜索',
  },
)
```

### 4.2 右上角按钮组
保留 Flutter 层布局，iOS 端使用 `UIVisualEffectView(UIGlassEffect)` + `UIStackView` 承载按钮。

### 4.3 更多菜单
调用 MethodChannel 显示原生菜单：
```dart
final result = await methodChannel.invokeMethod('showMenu', {
  'x': position.dx,
  'y': position.dy,
  'isDark': isDark,
  'items': [
    {'title': '刷新', 'icon': 'arrow.clockwise', 'value': 'refresh'},
    {'title': '设置', 'icon': 'gearshape', 'value': 'settings'},
    {'title': '删除', 'icon': 'trash', 'value': 'delete', 'isDestructive': true},
  ],
});
```

### 4.4 状态栏遮挡问题
所有悬浮控件位置计算必须加 `safeAreaInsets.top`；不要用屏幕绝对坐标。

## 5. 交互规则
- **更多菜单**：iOS 14+ 点击即弹出；系统自动处理高亮/动画；点击外部自动关闭。
- **搜索**：点击搜索按钮 -> 搜索栏获取焦点，键盘弹出；点击空白区域或关闭按钮收起并清空。  
  - 清除按钮使用系统 `xmark.circle.fill` 图标，保持一致性。
- **悬浮按钮组**：触控热区 >=44pt；按钮组整体可命中透明区域。

## 6. 回退策略
| iOS 版本 | 弹出菜单 | 搜索栏 | 玻璃效果 |
|---------|---------|-------|---------|
| **26+** | `UIButton.menu` (点击弹出) | `UIGlassEffect` + TextField/SearchBar | Liquid Glass |
| **14-25** | `UIButton.menu` (点击弹出) | `UIBlurEffect` + TextField/SearchBar | 模糊毛玻璃 |
| **13** | `UIContextMenuInteraction` (长按) | `UIBlurEffect` + TextField | 模糊毛玻璃 |
| **< 13** | `LegacyGlassMenuViewController` | `UIBlurEffect` + TextField | 模糊毛玻璃 |

macOS 26：对应使用 `NSGlassEffectView` + `NSPopover`；Flutter 平台视图同理。

## 7. 已完成实现 ✅
- [x] `GlassPopupMenu.swift`: 使用原生 `UIButton.menu` API (iOS 14+)
- [x] `GlassSearchBar.swift`: 双模式支持（默认玻璃/原生 UISearchBar）
- [x] 系统自动应用 Liquid Glass 材质
- [x] 完整的版本回退策略

## 8. 验证清单
- [ ] iOS 26 真机：导航按钮组/搜索/更多均显示系统玻璃，菜单有系统高亮，搜索清除按钮为系统圆形。  
- [ ] 小屏幕：搜索栏不超出屏幕，关闭按钮圆形；点击空白处可关闭。  
- [ ] 状态栏：任何时刻搜索/菜单不被时间/Wi‑Fi 覆盖。  
- [ ] 回退：iOS 15 设备仍能显示毛玻璃回退，功能可用。
