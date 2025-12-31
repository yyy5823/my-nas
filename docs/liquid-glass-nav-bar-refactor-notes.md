# Liquid Glass 导航栏实现文档

## 背景

iOS 26 引入了 Liquid Glass 设计语言，需要在应用中实现悬浮底部导航栏效果。

## 核心问题与解决方案

### 关键发现（重要！）

> **"Using UIBarAppearance or backgroundColor interferes with the glass appearance"**
> — [WWDC25: Build a UIKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/284/)

**iOS 26 中，UITabBar 默认就是透明的 Liquid Glass 效果！**
设置任何 `UIBarAppearance` 或 `backgroundColor` 都会**破坏**原生玻璃效果。

### 正确解决方案：使用原生 UITabBarController（不设置任何 appearance！）

**核心原则**：iOS 26 的 UITabBar **默认就是** Liquid Glass 效果！

根据 WWDC25 Session 284:
> **"Using UIBarAppearance or backgroundColor interferes with the glass appearance"**

**正确做法**：
1. 使用原生 `UITabBarController`
2. **不要**设置任何 `UIBarAppearance`
3. **不要**设置任何 `backgroundColor`
4. 让系统自动处理所有 Liquid Glass 特性

```swift
class LiquidGlassTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // 创建 tab items
        rebuildTabs()

        // iOS 26+: 不设置任何 appearance！
        // 这是最关键的一点！让系统默认的 Liquid Glass 生效
        if #available(iOS 26.0, *) {
            // 不做任何事情！
        } else {
            // iOS < 26: 使用模糊效果作为回退
            configureAppearanceFallback()
        }
    }

    // ❌ 不要这样做：
    // let appearance = UITabBarAppearance()
    // appearance.configureWithTransparentBackground()
    // tabBar.standardAppearance = appearance
}
```

**iOS 26 原生 Liquid Glass 自动提供的特性**：
- 选中指示器的玻璃"药丸"效果（Selection Bubble）
- 长按拖动切换 tab（Drag to switch）
- 按压动画效果（Press animation）
- tab 之间的变形动画（Morphing）
- 透镜效果（Lensing）
- 色差效果（Chromatic aberration）

## 架构设计

```
LiquidGlassContainerView (UIView)
│
├── UIVisualEffectView (iOS 26+)
│   └── UIGlassEffect(style: .clear)  ← 高透明度玻璃背景
│   └── layer.cornerRadius = 40       ← 胶囊形
│
└── UIStackView (自定义按钮容器)
    └── NavItemButton × 5 (UIControl)
        ├── UIImageView (图标)
        └── UILabel (标签)
```

**注意**：不使用 UITabBar，完全自定义按钮实现！

## 关键代码

### 玻璃背景配置（iOS 26+）

```swift
@available(iOS 26.0, *)
private func setupGlassBackground() {
    // 重要：确保 alpha = 1.0，否则效果不显示！
    self.alpha = 1.0
    self.isOpaque = false
    self.backgroundColor = .clear

    let effectView = UIVisualEffectView()
    effectView.translatesAutoresizingMaskIntoConstraints = false
    effectView.alpha = 1.0  // 关键：必须是 1.0

    // 将玻璃效果放在最底层
    insertSubview(effectView, at: 0)

    NSLayoutConstraint.activate([...])

    // 创建 UIGlassEffect
    let glassEffect = UIGlassEffect()
    glassEffect.isInteractive = true  // 直接属性访问 ✅

    // 在动画块中设置 effect（触发 materialize 动画）
    UIView.animate(withDuration: 0.3) {
        effectView.effect = glassEffect
    }

    // layer.cornerRadius 对 UIGlassEffect 可能不生效
    // 系统默认使用胶囊形状
    effectView.clipsToBounds = true
    effectView.layer.cornerRadius = cornerRadius
    effectView.layer.cornerCurve = .continuous
}
```

> **重要 API 注意事项（2025年12月更新）**：
>
> **实际可用的 API**：
> - `UIGlassEffect()` - 默认初始化 ✅ 可编译
> - `glassEffect.isInteractive = true` - 直接属性访问 ✅ 可编译
>
> **关键要求**：
> - **alpha 必须 = 1.0**：UIVisualEffectView 及其所有父视图的 alpha 必须是 1.0
> - 如果 alpha < 1，效果会完全不显示或显示不正确
> - 在动画块中设置 `effect` 属性以触发 materialize 动画
>
> **文档中提到但不可用的 API**：
> - `UIGlassEffect(glass: .clear, isInteractive: true)` ❌ 编译失败
> - `UIGlassEffect(style: .clear)` ❌ 编译失败
> - `view.cornerConfiguration = .corners(radius: .fixed(26))` ❌ 不存在
>
> **cornerConfiguration API 状态**：
> - WWDC25 视频中提到但**尚未在 iOS 26 SDK 中公开**
> - Apple Developer Forums 确认此问题存在于 Beta 3 和 Beta 4
> - 系统默认使用胶囊形状，无法自定义
>
> 参考资料：
> - [GitHub LiquidGlassReference](https://github.com/conorluddy/LiquidGlassReference)
> - [What's New in UIKit (iOS 26)](https://sebvidal.com/blog/whats-new-in-uikit-26/)
> - [Apple Developer Forums 讨论](https://developer.apple.com/forums/thread/792269)
> - [Expo GlassEffect Docs](https://docs.expo.dev/versions/latest/sdk/glass-effect/)

### 自定义按钮（不使用 UITabBar）

```swift
class NavItemButton: UIControl {
    private let iconImageView = UIImageView()
    private let labelView = UILabel()
    private let containerStack = UIStackView()

    func setupViews() {
        containerStack.axis = .vertical
        containerStack.alignment = .center
        containerStack.spacing = 4
        containerStack.isUserInteractionEnabled = false
        addSubview(containerStack)

        // 图标
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        iconImageView.image = UIImage(systemName: "film", withConfiguration: config)
        containerStack.addArrangedSubview(iconImageView)

        // 标签
        labelView.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        containerStack.addArrangedSubview(labelView)
    }
}
```

### 图标配置

```swift
// 使用较小的 pointSize 以匹配系统标准
let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
let image = UIImage(systemName: "film", withConfiguration: config)
iconImageView.image = image
iconImageView.tintColor = isSelected ? .systemBlue : .gray
```

### 点击事件处理

```swift
// 使用 UIControl 的 addTarget
button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)

@objc private func buttonTapped(_ sender: NavItemButton) {
    let index = sender.tag
    onTabSelected?(index)  // 通知 Flutter
}
```

## UIGlassEffect.Style 对比

| Style | 透明度 | 使用场景 |
|-------|--------|----------|
| `.clear` | 最高 | 媒体丰富的背景（如视频播放器） |
| `.regular` | 标准 | 大多数 UI（默认） |
| `.identity` | 禁用 | 条件性禁用玻璃效果 |

> **重要**：UITabBar 自动使用 `.regular` 样式，无法更改为 `.clear`。
> 因此必须使用 UIVisualEffectView + 自定义按钮实现高透明度效果。

## iOS 版本兼容

| iOS 版本 | 实现方式 |
|----------|----------|
| iOS 26+ | `UIGlassEffect()` + 默认胶囊形状 |
| iOS 18-25 | `UIBlurEffect(style: .systemUltraThinMaterial)` + `layer.cornerRadius` |

## 尺寸参数

| 参数 | 标准值 | 说明 |
|------|--------|------|
| 高度 | 60pt | 导航栏整体高度（更紧凑） |
| 底部间距 | 8pt | 距离屏幕底部（约 0.3cm） |
| 水平边距 | 16pt | 与内容区域宽度一致 |
| 圆角 | 30pt | 高度的一半，形成胶囊形 |
| 选中指示器 | Pill 形 | 玻璃质感背景，切换时弹簧动画 |

## 错误实现记录（避免重复）

### 错误方案 1：设置 UIBarAppearance（最常见错误！）

```swift
// ❌ 不要这样做 - 会破坏原生 Liquid Glass 效果！
let appearance = UITabBarAppearance()
appearance.configureWithTransparentBackground()
tabBar.standardAppearance = appearance
tabBar.backgroundColor = .clear
tabBar.backgroundImage = UIImage()
```

**结果**：Liquid Glass 效果被破坏，透明度降低

### 错误方案 2：尝试移除内部视图

```swift
// ❌ 不要这样做
for subview in tabBar.subviews {
    if !className.contains("TabBarButton") {
        subview.removeFromSuperview()  // 会破坏按钮显示
    }
}
```

**结果**：按钮消失或双层胶囊

### 错误方案 3：UIVisualEffectView + UITabBar 组合（双层玻璃！）

```swift
// ❌ 不要这样做 - UITabBar 自带玻璃背景，会形成双层！
class ContainerView: UIView {
    func setup() {
        // 添加 UIGlassEffect 背景
        let glassEffect = UIGlassEffect(style: .clear)
        let effectView = UIVisualEffectView(effect: glassEffect)
        addSubview(effectView)

        // 又添加 UITabBar - UITabBar 有自己的玻璃背景！
        let tabBar = UITabBar()
        addSubview(tabBar)  // ❌ 形成双层玻璃
    }
}
```

**结果**：外层高透明玻璃 + 内层不透明玻璃，双层胶囊效果

**原因**：UITabBar 在 iOS 26 会自动获得 Liquid Glass 效果（.regular 样式），
即使你在它下面添加了 UIVisualEffectView，UITabBar 依然有自己的玻璃背景。

### 错误方案 4：在 _UIBarBackground 上修改

```swift
// ❌ 不要这样做
if className == "_UIBarBackground" {
    subview.isHidden = true
}
```

**结果**：系统会在 layoutSubviews 时重新创建这些视图

### 错误方案 5：UITabBar + 透明背景设置

```swift
// ❌ 尝试清除 UITabBar 背景，让外层 UIGlassEffect 显示
let appearance = UITabBarAppearance()
appearance.configureWithTransparentBackground()
appearance.backgroundEffect = nil
appearance.backgroundColor = .clear
tabBar.standardAppearance = appearance
tabBar.backgroundColor = .clear
tabBar.backgroundImage = UIImage()
```

**结果**：仍然有双层效果，因为 iOS 26 的 UITabBar 玻璃效果无法完全禁用

### 错误方案 9：在 iOS 26 上设置 UIBarAppearance

```swift
// ❌ 不要这样做 - 即使设置透明背景也会破坏 Liquid Glass！
if #available(iOS 26.0, *) {
    let appearance = UITabBarAppearance()
    appearance.configureWithTransparentBackground()  // ❌ 会破坏玻璃效果！
    tabBar.standardAppearance = appearance
    tabBar.backgroundColor = .clear  // ❌ 也会破坏！
}
```

**结果**：Liquid Glass 效果被完全破坏，变成不透明的背景

**原因**：根据 WWDC25 Session 284:
> "Using UIBarAppearance or backgroundColor interferes with the glass appearance"

**正确做法**：
```swift
if #available(iOS 26.0, *) {
    // 不做任何事情！让系统默认的 Liquid Glass 生效
} else {
    // 只在 iOS < 26 设置外观
    configureAppearanceFallback()
}
```

### 错误方案 10：使用自定义 UIVisualEffectView + UIGlassEffect 替代 UITabBar

```swift
// ❌ 自定义实现无法获得完整的 Liquid Glass 交互效果！
let effectView = UIVisualEffectView()
let glassEffect = UIGlassEffect()
effectView.effect = glassEffect
// 然后用自定义按钮...
```

**结果**：
- 可能有基本的玻璃视觉效果
- 但**没有**选中指示器可拖动的交互
- **没有**长按拖动切换 tab
- **没有**原生的变形动画

**原因**：Liquid Glass 的完整交互效果（Selection Bubble、Drag to switch）是 UITabBarController 的原生功能，
自定义实现无法复现。

**正确做法**：使用原生 UITabBarController，不设置任何 appearance。

### 错误方案 7：视图 alpha < 1.0

```swift
// ❌ 不要这样做 - UIVisualEffect 要求 alpha = 1.0！
effectView.alpha = 0.9  // 效果会完全失效
parentView.alpha = 0.8  // 父视图透明也会导致失效
```

**结果**：Liquid Glass 效果完全不显示或显示不正确

**原因**：UIVisualEffect 需要与其下层内容正确合成。如果 UIVisualEffectView 或任何父视图的 alpha < 1，
效果会显示不正确或完全不显示。

**正确做法**：
```swift
self.alpha = 1.0
self.isOpaque = false
self.backgroundColor = .clear
effectView.alpha = 1.0  // 必须是 1.0
```

### 错误方案 8：在 Flutter UiKitView 中使用时未检查透明度

Flutter 的 `UiKitView` 可能会在某些情况下影响原生视图的渲染。
确保：
1. 视图自身 alpha = 1.0
2. 使用 `insertSubview(effectView, at: 0)` 将玻璃效果放在最底层
3. 按钮等内容放在玻璃效果上方

### 错误方案 6：自定义可拖动水滴滑块

```swift
// ❌ 不要这样做 - iOS 26 原生没有这个功能！
let longPressGesture = UILongPressGestureRecognizer(...)
let panGesture = UIPanGestureRecognizer(...)
selectionIndicator.addGestureRecognizer(longPressGesture)
selectionIndicator.addGestureRecognizer(panGesture)
```

**结果**：这不是 iOS 26 原生的选中效果！

**正确理解**：
- iOS 26 的 "selection bubble" 长按拖动功能是 UITabBarController 的原生功能
- 自定义实现不需要复制这个功能
- 正确做法：使用简单的 pill 形选中指示器，切换时有弹簧动画即可

## 参考资料

- [Build a UIKit app with the new design - WWDC25](https://developer.apple.com/videos/play/wwdc2025/284/)
- [What's New in UIKit (iOS 26)](https://sebvidal.com/blog/whats-new-in-uikit-26/)
- [Exploring tab bars on iOS 26 with Liquid Glass](https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/)
- [How to create Liquid glass for custom view in Swift](https://ashishkakkad.com/2025/06/how-to-create-liquid-glass-for-custom-view-in-swift/)
- [iOS and iPadOS 26: The MacStories Review](https://www.macstories.net/stories/ios-and-ipados-26-the-macstories-review/3/) - selection bubble 描述
- [liquid_tabbar_minimize Flutter package](https://pub.dev/packages/liquid_tabbar_minimize) - "Animated pill indicator"

## 常见问题

### sqlite3arm64ios.framework 代码签名失败

**错误信息**：
```
Failed to verify code signature of .../sqlite3arm64ios.framework : 0xe8008014 (The executable contains an invalid signature.)
```

**解决方案**：在 `ios/Podfile` 的 `post_install` 中添加签名配置：

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      # 修复预编译框架的代码签名问题
      config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Development'
      config.build_settings['CODE_SIGNING_REQUIRED'] = 'YES'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'YES'
      config.build_settings['DEVELOPMENT_TEAM'] = 'YOUR_TEAM_ID'  # 替换为你的团队 ID
    end
  end
end
```

然后重新安装 pods：
```bash
rm -rf ios/Pods ios/Podfile.lock && cd ios && pod install
```

## 相关文件

- `ios/Runner/LiquidGlassView.swift` - 原生视图实现
- `lib/shared/widgets/liquid_glass/liquid_glass_nav_bar.dart` - Flutter 包装
- `lib/shared/widgets/main_scaffold.dart` - 布局定位
