# iOS 26 Liquid Glass 实现记录

## 目标
在 iOS 26+ 设备上实现真正的 Liquid Glass (水滴玻璃) 效果，用于底部导航栏。

## 环境
- 设备: iPhone (programApe)
- iOS 版本: 26.2
- Flutter Platform View: UiKitView

---

## ⚠️ 关键发现：Clear vs Regular 样式

**这是最重要的发现！**

iOS 26 的 `UIGlassEffect` 有两种样式：

| 样式 | 效果 | 透明度 | 适用场景 |
|------|------|--------|----------|
| `.regular` | **毛玻璃** (frosted blur) | 较低 | 一般 UI、需要可读性 |
| `.clear` | **真正的透明玻璃** (凸透镜、折射) | 极高 | 动态界面、媒体背景 |

**之前的问题**：使用了默认的 `UIGlassEffect()` 或 `.regular`，这是毛玻璃效果！

**正确实现**：
```swift
// ❌ 错误 - 毛玻璃效果
let glassEffect = UIGlassEffect()  // 默认是 .regular

// ✅ 正确 - 真正的透明玻璃效果
let glassEffect = UIGlassEffect(style: .clear)
```

---

## 尝试记录

### 方法 1: SwiftUI .glassEffect() 直接应用

**代码示例:**
```swift
var body: some View {
    HStack {
        // nav items
    }
    .glassEffect(.regular.interactive(), in: .capsule)
}
```

**结果:** ❌ 失败

**现象:** 只显示普通的磨砂效果，没有玻璃质感

**原因分析:**
- Flutter Platform View 使用 UIKit 的 `UIView` 作为容器
- SwiftUI 视图通过 `UIHostingController` 嵌入
- `.glassEffect()` 可能需要特定的 SwiftUI 渲染上下文才能正确工作
- 在 Flutter Platform View 的 UIKit 环境中，SwiftUI 的玻璃效果可能无法正确渲染

---

### 方法 2: SwiftUI GlassEffectContainer 包装

**代码示例:**
```swift
var body: some View {
    GlassEffectContainer {
        HStack {
            // nav items with .glassEffect()
        }
    }
}
```

**结果:** ❌ 失败

**现象:** 与方法 1 相同，只有普通磨砂效果

**原因分析:**
- 同上，Flutter Platform View 的 UIKit 环境可能不支持 SwiftUI 的玻璃效果
- WWDC25 视频表明 UIKit 应用应该使用 `UIGlassEffect`

---

### 方法 3: UIKit UIGlassEffect() 默认初始化

**代码示例:**
```swift
@available(iOS 26.0, *)
private func setupNavBarWithGlassEffect() {
    let glassEffect = UIGlassEffect()  // 默认样式
    glassEffect.isInteractive = true

    let effectView = UIVisualEffectView(effect: nil)
    effectView.layer.cornerRadius = 30

    UIView.animate(withDuration: 0.3) {
        effectView.effect = glassEffect
    }
}
```

**结果:** ⚠️ 部分成功 - 但效果不对！

**现象:** 显示的是**毛玻璃效果**，不是真正的透明玻璃

**原因:** `UIGlassEffect()` 默认使用 `.regular` 样式，这是毛玻璃！

---

### 方法 4: UIKit UIGlassEffect(style: .clear)

**代码示例:**
```swift
let glassEffect = UIGlassEffect(style: .clear)
let effectView = UIVisualEffectView(effect: glassEffect)
```

**结果:** ❌ 失败

**问题:** 整个导航栏仍然不透明，不是真正的 iOS 26 效果

**原因分析:** 我对 iOS 26 TabBar 的理解完全错误！

---

### 方法 5: SwiftUI GlassEffectContainer + 每个 item 独立玻璃效果 ✅ 当前方案

**关键发现（来自 iOS 26 音乐 App 截图分析）：**

真正的 iOS 26 Liquid Glass 导航栏特点：
1. **整个导航栏背景是完全透明的**（不是一个大玻璃块！）
2. **只有选中的 tab 有玻璃效果**（一个独立的玻璃"药丸"）
3. **未选中的 tab 只有图标和文字，没有背景**
4. **玻璃块可以在 tab 之间变形移动**（使用 `glassEffectID`）
5. **选中的玻璃块可以长按拖动切换 tab**

**代码示例:**
```swift
@available(iOS 26.0, *)
struct LiquidGlassNavBarView: View {
    let items: [LiquidGlassNavItem]
    let selectedIndex: Int
    let onTap: (Int) -> Void

    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    navButton(for: item)
                }
            }
        }
    }

    @ViewBuilder
    private func navButton(for item: LiquidGlassNavItem) -> some View {
        let isSelected = item.id == selectedIndex

        Button { onTap(item.id) } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? item.selectedIcon : item.icon)
                Text(item.label)
            }
        }
        .buttonStyle(.plain)
        // 关键: 只有选中的 item 有玻璃效果，其他用 .identity
        .glassEffect(
            isSelected ? .regular.interactive() : .identity,
            in: .capsule
        )
        // 关键: 相同的 ID 让玻璃块变形移动
        .glassEffectID("navSelection", in: namespace)
    }
}
```

**结果:** 待验证

**改进点:**
1. 使用 SwiftUI `GlassEffectContainer` 获得变形支持
2. 只对选中的 item 应用 `.glassEffect(.regular.interactive())`
3. 对未选中的 item 使用 `.glassEffect(.identity)` (无效果)
4. 使用相同的 `glassEffectID` 让玻璃块在 items 之间变形移动

---

## 已解决的问题

### 问题 1: 构建错误 - UICornerConfiguration
- 错误: `Type 'UICornerConfiguration' has no member 'fixed'`
- 解决: 改用 `effectView.layer.cornerRadius`，后续改为 `.capsule()`

### 问题 2: SF Symbol 图标消失
- 错误: `music.note.list.fill` 不存在，导致选中时图标消失
- 解决: 添加 `selectedIcon` 字段，显式映射每个图标的选中/未选中版本

### 问题 3: 导航点击无响应
- 原因: `createNavButton` 创建的 container 视图缺少尺寸约束
- 解决:
  1. 将 stack 约束改为边缘约束
  2. 禁用子视图的 `isUserInteractionEnabled`

### 问题 4: 显示毛玻璃而非透明玻璃
- 原因: 使用了默认的 `UIGlassEffect()` (`.regular` 样式)
- 解决: 使用 `UIGlassEffect(style: .clear)`

---

## 关键技术发现

### 1. iOS 26 TabBar 设计理念 (最重要!)

**之前的错误理解：** 整个导航栏是一个玻璃块

**正确理解（来自 iOS 26 音乐 App 分析）：**
- 整个导航栏背景是**完全透明的**
- **只有选中的 tab** 有一个独立的玻璃"药丸"背景
- 未选中的 tab 只有图标和文字，无背景
- 玻璃块使用 `glassEffectID` 在 tab 之间**变形移动**

### 2. UIGlassEffect 样式差异

| 属性 | `.regular` | `.clear` | `.identity` |
|------|-----------|----------|-------------|
| 模糊 | 标准毛玻璃 | 最小模糊 | 无 |
| 透明度 | 较低 | 极高 | 完全透明 |
| 适用场景 | 选中状态 | 媒体背景 | 未选中状态 |

### 3. GlassEffectContainer 和 glassEffectID

- `GlassEffectContainer` - 包装多个玻璃元素，启用变形动画
- `glassEffectID` - 给多个元素相同的 ID，让玻璃块在它们之间变形移动
- 选中 → `.glassEffect(.regular.interactive())`
- 未选中 → `.glassEffect(.identity)`

### 4. Flutter Platform View 与 SwiftUI
- Flutter 的 `UiKitView` 使用 UIKit 作为底层
- SwiftUI 视图通过 `UIHostingController` 嵌入到 UIKit 容器
- SwiftUI 的某些视觉效果（如 `.glassEffect()`）可能在这种混合环境中无法正确工作

### 2. WWDC25 官方指导
- SwiftUI 应用: 使用 `.glassEffect()` 修饰符
- UIKit 应用: 使用 `UIGlassEffect` + `UIVisualEffectView`
- 由于 Flutter Platform View 本质是 UIKit，应该使用 UIKit API

### 3. UIStackView 子视图尺寸
- `UIStackView` 使用 `distribution = .fillEqually` 时
- 子视图需要有 intrinsic content size 或显式约束
- 如果子视图没有尺寸，可能导致尺寸为零

### 4. 手势响应层级
- UIKit 的手势响应遵循视图层级
- 子视图的 `isUserInteractionEnabled = true` 可能拦截父视图的手势
- 需要禁用不需要交互的子视图的 `isUserInteractionEnabled`

---

## 当前状态

### 已解决
- [x] Xcode 项目配置（Swift 文件编译）
- [x] SF Symbol 图标映射（选中/未选中）
- [x] 构建错误（UICornerConfiguration）
- [x] 导航按钮点击区域（约束和交互设置）

### 待验证
- [ ] UIGlassEffect 是否正确渲染 Liquid Glass 效果
- [ ] 导航点击是否正常切换 tab
- [ ] 触觉反馈是否正常

---

## 文件清单

### Swift (原生端)
- `ios/Runner/LiquidGlassView.swift` - UIKit 实现的 Liquid Glass 视图
- `ios/Runner/AppDelegate.swift` - 注册 LiquidGlassPlugin

### Dart (Flutter 端)
- `lib/shared/widgets/liquid_glass/liquid_glass_nav_bar.dart` - Flutter 组件
- `lib/shared/widgets/liquid_glass/liquid_glass_service.dart` - 平台服务

---

## 调试日志标识

所有 Liquid Glass 相关日志使用 `🔮 LiquidGlassView:` 前缀，可通过以下命令过滤：

```bash
# 实时查看日志
log stream --predicate 'subsystem == "com.apple.os_log"' | grep "LiquidGlassView"

# 或使用 Console.app 搜索 "LiquidGlassView"
```

---

## 参考资料

- WWDC25: Meet the Liquid Glass design system
- WWDC25: Build with UIKit and Liquid Glass
- Apple Developer: UIGlassEffect
- Apple Developer: UIGlassContainerEffect
