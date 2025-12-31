# Liquid Glass 导航栏重构问题总结

## 背景

iOS 26 引入了 Liquid Glass 设计语言，需要在应用中实现悬浮底部导航栏效果。

## 标准尺寸参数（实测）

| 参数 | 标准值 | 说明 |
|------|--------|------|
| 高度 | 80pt (~1cm) | 导航栏整体高度 |
| 底部间距 | 12pt (~0.3cm) | 距离屏幕底部，不叠加 safeArea |
| 水平边距 | 4pt | 左右边距，使宽度约 6.1cm |
| 圆角 | 40pt | 高度的一半，形成胶囊形 |
| 透明度 | 最高 | iOS 26 使用系统 Liquid Glass，iOS < 26 使用 systemUltraThinMaterial |

## 实现方案对比

### 方案 A: UITabBarController（提交 2046886）- 推荐

```swift
class LiquidGlassPlatformView: NSObject, FlutterPlatformView {
    private let tabBarController: LiquidGlassTabBarController

    func view() -> UIView {
        return tabBarController.view
    }
}
```

**优点：**
- iOS 26 的 UITabBar 自动获得 Liquid Glass 样式
- 无需手动处理圆角、裁剪、玻璃效果
- 系统自动处理选中状态的"药丸"效果
- 支持长按拖动切换、平滑动画、按压交互

**缺点：**
- 依赖 iOS 26+ 的系统行为

### 方案 B: 自定义 ContainerView + UITabBar（提交 e176b5e）- 有问题

```swift
class LiquidGlassPlatformView: NSObject, FlutterPlatformView {
    private let containerView: SafeAreaIgnoringContainerView
    private let tabBar: FullHeightTabBar
    private var backgroundEffectView: UIVisualEffectView?
}
```

**问题：**
1. 手动管理多层视图结构，容易出现层叠问题
2. 初始 frame 可能为 (0,0,0,0)，导致 cornerRadius 为 0
3. 需要手动同步多个视图的圆角半径
4. 出现"外层椭圆"问题 - 多余的可见边界层

## 错误修改记录

### 问题 1: 初始 frame 为零

**现象：** 原生视图创建时 frame=(0,0,0,0)，导致导航栏不可见

**错误的修复方向：**
1. 移除 `containerView.clipsToBounds = true`
2. 移除 `containerView.layer.cornerRadius`
3. 添加 `autoresizingMask` 但移除了关键的裁剪属性

**为什么没有生效：**
- 原始设计中，`containerView` 负责统一裁剪所有子视图
- 移除裁剪属性后，暴露了 Flutter 平台视图的包装层，产生"外层椭圆"
- 只在 `backgroundEffectView` 上设置圆角，而 `containerView` 没有裁剪，导致层级混乱

### 问题 2: 多余的外层椭圆

**现象：** 导航栏外侧出现比内容更宽的椭圆形背景

**根本原因：**
- 方案 B 的结构是：`containerView > backgroundEffectView + tabBar`
- 当 `containerView.clipsToBounds = false` 时，子视图的渲染不受约束
- Flutter 的 `UiKitView` 创建的包装视图可能有默认背景
- 多层视图各自设置圆角，但没有统一的裁剪边界

**教训：**
1. 不要在不理解原始设计意图的情况下移除关键属性
2. `clipsToBounds` 和 `cornerRadius` 是配合使用的，移除一个会破坏视觉效果
3. 层叠视图结构需要明确的裁剪边界

## 正确的修复方法

### 针对 frame 为零的问题

如果必须使用方案 B，正确的修复是在 `layoutSubviews` 中更新圆角，但保持原有结构：

```swift
class SafeAreaIgnoringContainerView: UIView {
    var onLayoutUpdate: ((CGFloat) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.height > 0 {
            let cornerRadius = bounds.height / 2
            // 保持 containerView 的裁剪功能
            if layer.cornerRadius != cornerRadius {
                layer.cornerRadius = cornerRadius
                onLayoutUpdate?(cornerRadius)
            }
        }
    }
}
```

关键点：
- **保持** `clipsToBounds = true`
- **保持** `cornerRadius` 设置在 `containerView` 上
- 只添加动态更新机制，不改变原有结构

### 推荐方案

优先使用方案 A（UITabBarController），因为：
1. 利用系统提供的 Liquid Glass 效果
2. 无需手动管理视图层级
3. 自动适配 iOS 版本

## 关键原则

1. **理解再修改**：修改代码前先理解原始设计意图
2. **最小化改动**：只修改必要的部分，避免连锁反应
3. **保持结构完整**：不要移除看似无用但实际关键的属性
4. **回溯定位**：出现新问题时，先定位是哪次修改引入的，而不是继续叠加修复
5. **版本对比**：使用 git diff 对比正常版本和问题版本，找出具体差异

## 透明度配置研究

### iOS 26+ Liquid Glass 自动效果

根据 Apple 官方文档和 WWDC25 内容：

1. **系统自动适配**：iOS 26 的 `UITabBarController` 会自动获得 Liquid Glass 效果
2. **避免干扰**：不要添加自定义背景，否则会干扰系统效果
   - 不要设置 `tabBar.backgroundImage = UIImage()`
   - 不要设置 `tabBar.shadowImage = UIImage()`
   - 只需 `configureWithTransparentBackground()` 即可

正确的 iOS 26+ 配置：
```swift
if #available(iOS 26.0, *) {
    tabBar.isTranslucent = true
    let appearance = UITabBarAppearance()
    appearance.configureWithTransparentBackground()
    tabBar.standardAppearance = appearance
    tabBar.scrollEdgeAppearance = appearance
    // 不要设置其他任何背景属性！
}
```

### iOS < 26 回退方案

使用 `systemUltraThinMaterial`，这是 iOS 提供的最透明的模糊效果：

```swift
appearance.backgroundEffect = UIBlurEffect(style: isDark
    ? .systemUltraThinMaterialDark
    : .systemUltraThinMaterialLight)
```

### 透明度层级（从最透明到最不透明）

| UIBlurEffect.Style | 透明度 |
|-------------------|--------|
| systemUltraThinMaterial | 最高 |
| systemThinMaterial | 较高 |
| systemMaterial | 中等 |
| systemThickMaterial | 较低 |
| systemChromeMaterial | 最低 |

### 参考资源

- [Adopting Liquid Glass - Apple Developer](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [Build a UIKit app with the new design - WWDC25](https://developer.apple.com/videos/play/wwdc2025/284/)
- [UIBlurEffect.Style.systemUltraThinMaterial - Apple Developer](https://developer.apple.com/documentation/uikit/uiblureffect/style/systemultrathinmaterial)

## 相关文件

- `ios/Runner/LiquidGlassView.swift` - 原生视图实现
- `lib/shared/widgets/liquid_glass/liquid_glass_nav_bar.dart` - Flutter 包装
- `lib/shared/widgets/main_scaffold.dart` - 布局定位
