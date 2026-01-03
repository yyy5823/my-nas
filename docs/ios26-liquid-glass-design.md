# iOS 26 Liquid Glass 设计规范

> 基于 Apple WWDC 2025 发布的 Liquid Glass 设计系统，本文档详细说明需要修改的交互和样式。

## 参考资料

- [Apple 官方公告](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
- [WWDC25: Build a UIKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/284/)
- [iOS 26 Liquid Glass Comprehensive Reference](https://medium.com/@madebyluddy/overview-37b3685227aa)
- [What's New in UIKit 26](https://sebvidal.com/blog/whats-new-in-uikit-26/)
- [Exploring tab bars on iOS 26](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/)

---

## 一、核心设计原则

### 1.1 Liquid Glass 的本质

Liquid Glass 是一种**悬浮于内容之上的导航层**，具有以下特性：

- **半透明**：与背景内容融合，自动适应深色/浅色模式
- **动态折射**：反射和折射周围内容
- **悬浮设计**：工具栏、标签栏、弹出框不再固定于屏幕边缘
- **自动分组**：按钮自动组合成玻璃胶囊

### 1.2 适用范围

✅ **适用于导航层**：
- 导航栏和工具栏
- 标签栏和底部附件
- 悬浮操作按钮 (FAB)
- 弹出框、菜单、Sheet

❌ **禁止用于内容层**：
- 列表、表格
- 媒体内容
- 卡片背景

---

## 二、顶栏 (Navigation Bar) 设计变更

### 2.1 当前问题

| 问题 | 描述 |
|------|------|
| 固定区域 | 顶栏是一个固定高度的实色/模糊背景区域 |
| 非悬浮按钮 | 按钮嵌入在顶栏背景中，不是独立悬浮 |
| 拥挤布局 | 多个按钮挤在一起，没有合适的间距 |
| 缺少分组 | 按钮没有按功能自动分组成独立的玻璃胶囊 |

### 2.2 iOS 26 正确行为

#### 2.2.1 悬浮导航元素

在 iOS 26 中，导航栏**不再是固定的背景区域**：

```
❌ 错误：固定背景顶栏
┌──────────────────────────────────────┐
│ [背景色/模糊背景]                      │
│  标题         [按钮1] [按钮2] [按钮3] │
└──────────────────────────────────────┘

✅ 正确：悬浮元素
                    ┌─────────────────┐
   标题              │ 🔍  ⚙️  │  ⋮  │  ← 独立悬浮的玻璃胶囊
                    └─────────────────┘
     ↑ 大标题随内容滚动
```

#### 2.2.2 自动分组规则

系统自动将 bar button items 分组：

| 类型 | 分组行为 |
|------|----------|
| **图标按钮** | 相邻的图标按钮共享同一个玻璃背景 |
| **文字按钮** | 通常独立，不与图标按钮共享背景 |
| **"完成"/"关闭"按钮** | 始终独立，单独的玻璃背景 |
| **突出样式按钮** | 独立的玻璃背景 |

```swift
// 示例：4个图标按钮共享背景，"选择"和"完成"独立
┌────────┐  ┌─────────────────────┐  ┌────────┐
│  选择  │  │ 📷  📁  ⭐️  📤 │  │  完成  │
└────────┘  └─────────────────────┘  └────────┘
```

#### 2.2.3 UIKit 控制分组

```swift
// 让按钮不共享背景（独立胶囊）
barButtonItem.sharesBackground = false

// 完全隐藏玻璃背景（自定义设计）
barButtonItem.hidesSharedBackground = true

// 创建零宽度分隔符（分开按钮组）
let separator = UIBarButtonItem.fixedSpace(0)
```

#### 2.2.4 按钮间距

按钮之间应该有合适的间距，不要拥挤：

```
❌ 错误：按钮拥挤
┌────────────┐
│🔍⚙️⋮│
└────────────┘

✅ 正确：合适间距
┌──────────────────┐
│  🔍    ⚙️    ⋮  │
└──────────────────┘
```

---

## 三、滚动行为

### 3.1 大标题 (Large Title) 变化

```
初始状态：大标题在内容区顶部
┌────────────────────────┐
│     悬浮工具栏按钮      │ ← 悬浮在内容之上
├────────────────────────┤
│                        │
│  大标题文字             │ ← 在内容滚动区域内
│                        │
│  内容...               │
└────────────────────────┘

滚动后：大标题变为行内标题
┌────────────────────────┐
│  标题    [工具栏按钮]   │ ← 标题移入导航区域
├────────────────────────┤
│  内容...               │
└────────────────────────┘
```

### 3.2 标签栏最小化

当用户向下滚动时，标签栏会收缩为更紧凑的形式：

```swift
// SwiftUI
TabView { ... }
    .tabBarMinimizeBehavior(.onScrollDown)

// 行为选项
.automatic  // 系统自动决定
.onScrollDown  // 向下滚动时最小化
.never  // 永不最小化
```

### 3.3 滚动边缘效果 (Scroll Edge Effect)

iOS 26 在屏幕顶部和底部引入了渐进式模糊效果：

- 当内容滚动到导航栏下方时，自动应用边缘模糊
- 增强悬浮元素的可见性
- 可通过 API 控制启用/禁用

```swift
// 控制边缘效果
// 使用 ToolbarItem(placement: .bottomBar) → 激活效果
// 使用 .safeAreaInset(edge: .bottom) → 禁用效果
```

---

## 四、UIGlassEffect 实现

### 4.1 基本用法

```swift
// 创建玻璃效果
let glassEffect = UIGlassEffect(style: .regular)
glassEffect.tintColor = .systemBlue  // 可选着色
glassEffect.isInteractive = true     // 启用交互动画

// 应用到视图
let glassView = UIVisualEffectView(effect: glassEffect)

// 使用动画设置效果（materialize 动画）
UIView.animate(withDuration: 0.3) {
    glassView.effect = glassEffect
}
```

### 4.2 样式选项

| 样式 | 用途 |
|------|------|
| `.regular` | 默认样式，适用于大多数 UI（中等透明度） |
| `.clear` | 高透明度，适用于媒体丰富的背景 |

### 4.3 交互效果

当 `isInteractive = true` 时：
- 按压时缩放和弹跳动画
- 闪烁效果
- 触摸点照明效果扩散到附近的玻璃元素

### 4.4 形状自定义

```swift
// 默认是胶囊形状
// 自定义圆角
glassView.cornerConfiguration = .corners(radius: .fixed(26))

// 容器同心圆角（自动适应父视图）
glassView.cornerConfiguration = .corners(radius: .containerConcentric())
```

---

## 五、GlassEffectContainer（多按钮组合）

### 5.1 SwiftUI 实现

```swift
GlassEffectContainer(spacing: 30) {
    HStack(spacing: 20) {
        Image(systemName: "pencil")
            .glassEffect(.regular.interactive())
        Image(systemName: "eraser")
            .glassEffect(.regular.interactive())
    }
}
```

- `spacing` 参数控制形变距离
- 在该距离内的元素会在过渡时视觉融合

### 5.2 工具栏间距

```swift
// 使用 ToolbarSpacer 控制按钮间距
ToolbarItem(placement: .navigationBarTrailing) {
    HStack {
        Button(...) { }
        ToolbarSpacer()  // 新 API
        Button(...) { }
    }
}
```

---

## 六、需要修改的代码

### 6.1 AdaptiveGlassHeader 重构

**当前问题**：
- 固定高度的背景区域
- 按钮嵌入在背景中

**修改方向**：
1. 移除固定背景区域
2. 大标题放在内容滚动区域内
3. 工具栏按钮使用悬浮玻璃胶囊
4. 按钮组自动分组

### 6.2 GlassButtonGroup 重构

**当前问题**：
- 按钮拥挤，间距不足
- 不符合 iOS 26 自动分组规则

**修改方向**：
1. 增加按钮间距（建议 36pt 按钮配 8-12pt 间距）
2. 实现分隔线样式匹配系统设计
3. 确保交互反馈正确

### 6.3 滚动集成

**需要实现**：
1. 大标题随内容滚动
2. 滚动时导航栏状态变化
3. 边缘模糊效果

---

## 七、各页面修改清单

### 7.1 视频页 (VideoPage)

| 元素 | 当前状态 | 目标状态 |
|------|----------|----------|
| 问候语 | 在固定顶栏内 | 作为大标题在内容区顶部，随内容滚动 |
| 类型切换按钮 | 嵌入顶栏 | 悬浮玻璃胶囊，右上角 |
| 搜索按钮 | 嵌入顶栏 | 悬浮玻璃胶囊 |
| 筛选按钮 | 嵌入顶栏 | 与搜索按钮共享玻璃背景 |

### 7.2 音乐页 (MusicPage)

同上模式

### 7.3 相册页 (PhotoPage)

同上模式

### 7.4 阅读页 (ReadingPage)

同上模式

---

## 八、实现优先级

1. **P0 - 立即修改**
   - 移除固定顶栏背景
   - 大标题移入内容区域
   - 悬浮按钮正确分组和间距

2. **P1 - 短期优化**
   - 滚动时大标题变化
   - 边缘模糊效果

3. **P2 - 后续迭代**
   - 标签栏最小化行为
   - 更复杂的过渡动画

---

## 九、技术实现方案

### 9.1 架构变更

```
当前：
┌──────────────────────────────────┐
│ AdaptiveGlassHeader (固定区域)   │
├──────────────────────────────────┤
│ 内容区域 (PageView)              │
└──────────────────────────────────┘

目标：
┌──────────────────────────────────┐
│           悬浮按钮组              │ ← 绝对定位，悬浮于内容之上
├──────────────────────────────────┤
│ 大标题 (随内容滚动)               │
│ 内容区域                         │
└──────────────────────────────────┘
```

### 9.2 Flutter 实现方案

由于 Flutter 不直接支持 iOS 26 的导航栏行为，需要：

1. **移除 AdaptiveGlassHeader 固定区域**
2. **使用 Stack 布局**：
   - 底层：带有大标题的滚动内容
   - 顶层：悬浮的玻璃按钮组（使用 Positioned）
3. **原生 Platform View**：悬浮按钮使用原生 UIGlassEffect
4. **滚动监听**：监听滚动位置，触发大标题状态变化

```dart
Stack(
  children: [
    // 底层：可滚动内容（包含大标题）
    CustomScrollView(
      slivers: [
        // 大标题区域
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: safeAreaTop + 60), // 为悬浮按钮留空间
            child: LargeTitle('问候语'),
          ),
        ),
        // 内容
        SliverList(...),
      ],
    ),
    // 顶层：悬浮按钮组
    Positioned(
      top: safeAreaTop + 8,
      right: 16,
      child: NativeGlassButtonGroup(...),
    ),
  ],
)
```

---

## 十、验收标准

- [ ] 顶栏没有固定背景区域
- [ ] 大标题在内容区域顶部，随内容滚动
- [ ] 工具栏按钮悬浮于内容之上
- [ ] 按钮组有合适的间距，不拥挤
- [ ] 按钮组使用原生 UIGlassEffect（iOS 26+）
- [ ] 按钮有正确的交互反馈（缩放、弹跳）
- [ ] 深色/浅色模式自动适应
