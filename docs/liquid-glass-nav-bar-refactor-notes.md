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

### 错误方案 11：设置 dummy ViewController 的视图属性

```swift
// ❌ 这样做没有效果
let dummyVC = UIViewController()
dummyVC.view.backgroundColor = .clear
dummyVC.view.isOpaque = false
dummyVC.view.alpha = 0  // 设置为完全透明
dummyVC.edgesForExtendedLayout = .all
dummyVC.extendedLayoutIncludesOpaqueBars = true
```

**结果**：透明度仍然很低，没有改善

**原因分析**：
问题的核心不是 dummy ViewController 的视图属性，而是**视图层级关系**和**内容延伸**的问题。

**Liquid Glass 效果的原理**：
- UITabBar 的 Liquid Glass 效果是对**它下方的内容**进行高斯模糊
- 当前架构中，UITabBarController 的 view 包含：
  1. 内容区域（dummy ViewController.view）
  2. UITabBar（底部）
- TabBar 实际上是在对 dummy ViewController.view 进行模糊
- 即使 dummy view 设置为透明，它仍然是一个"空白"，不是 Flutter 内容

**当前架构的问题**：
```
Flutter 渲染层
│
├── 页面内容（Positioned.fill）
│
└── UiKitView（Positioned bottom: 0）
    └── UITabBarController.view
        ├── dummy VC.view ← TabBar 在模糊这个，即使透明也是空白
        └── UITabBar（Liquid Glass）
```

**要实现通透的 Liquid Glass**：
- Flutter 内容必须绘制在 TabBar 的**正下方**（Underlap）
- 但 UiKitView 是作为独立层渲染的，Flutter 内容无法"穿透"到原生视图下方
- 这是 Flutter Platform View 的根本限制

## 根本性问题（重要发现！）

### UIVisualEffect 的合成要求

> **"UIVisualEffects require being composited as part of the content they are logically layered on top of to look correct."**
> — [Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uivisualeffectview)

这意味着：
- UIGlassEffect / UIVisualEffectView 必须与它要模糊的内容在**同一个视图层级**中
- 如果它们不在同一层级，效果会显示不正确或无法正确模糊下方内容

### Flutter Platform View 的限制

Flutter 在 iOS 上使用 **Hybrid Composition** 渲染 Platform View：
- 原生 UIView 被添加到视图层级之上
- 原生视图和 Flutter 内容**不在同一个视图层级**中合成
- 原生视图是 "hovering above the FlutterViewController"

**参考**：[Flutter Platform Views Documentation](https://docs.flutter.dev/platform-integration/ios/platform-views)

### 为什么当前方案透明度很低

```
┌─────────────────────────────────────────────┐
│  原生层（通过 Hybrid Composition 悬浮）      │
│  ┌─────────────────────────────────────┐    │
│  │  UITabBarController.view            │    │
│  │  ├── dummy VC.view (空白)           │    │
│  │  └── UITabBar (Liquid Glass)        │    │
│  │       └── 只能模糊 dummy VC.view！  │    │
│  └─────────────────────────────────────┘    │
├─────────────────────────────────────────────┤
│  Flutter 渲染层（独立的渲染管线）            │
│  ┌─────────────────────────────────────┐    │
│  │  页面内容                            │    │ ← UITabBar 看不到这里！
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

**结论**：UITabBar 的 Liquid Glass 效果只能模糊它自己内部的 dummy VC.view（空白），
而不是 Flutter 渲染的页面内容。这就是为什么透明度看起来很低（实际上是在模糊空白）。

## 可行的解决方向

### 方向 1：纯 Flutter 实现（推荐）

- 不使用原生 UITabBar，完全用 Flutter 实现
- 使用 `BackdropFilter` 实现毛玻璃效果
- 可以正确模糊 Flutter 内容
- 缺点：失去原生的 Selection Bubble 交互效果

```dart
ClipRRect(
  borderRadius: BorderRadius.circular(30),
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
    child: Container(
      // 导航栏内容
    ),
  ),
)
```

### 方向 2：重构应用架构（复杂）

- 将 FlutterViewController 嵌入到原生 UITabBarController 中
- 原生 UITabBarController 作为根控制器
- Flutter 内容在 UITabBarController 的 viewControllers 中渲染
- 这样 UITabBar 可以正确模糊 Flutter 内容
- 缺点：需要大幅修改应用架构，可能影响 Flutter 的状态管理

### 方向 3：接受当前效果

- 当前的 UITabBarController 实现确实有 Liquid Glass 效果
- 只是透明度不如预期（因为在模糊空白内容）
- 如果应用背景是纯色或简单图案，效果可能仍然可接受

### 方向 4：混合方案

- 导航栏用 Flutter 的 BackdropFilter 实现（正确的透明度）
- 选中指示器动画用 Flutter 实现（模拟 Selection Bubble）
- 虽然不是原生效果，但视觉上可以接近

---

## 透明度问题排查清单（2024年12月31日更新）

> **背景**：当前 app 的 Liquid Glass 导航栏透明度明显**低于**其他 iOS 26 原生 app。以下是基于网络调研整理的所有可能原因和尝试方案。

### 🔴 高优先级检查项

#### 1. 编译环境和设备
| 检查项 | 说明 | 状态 |
|--------|------|------|
| Xcode 版本 | 必须使用 Xcode 26 编译 | [ ] |
| iOS Deployment Target | 设置为 iOS 26.0+ | [ ] |
| 测试设备 | 在 iOS 26 真机上测试（非模拟器） | [ ] |

#### 2. iOS 系统设置
| 检查项 | 影响 | 状态 |
|--------|------|------|
| `Settings > Display & Brightness > Liquid Glass` | iOS 26.1+ 新增，"Tinted" 会增加不透明度 | [ ] |
| `Settings > Accessibility > Reduce Transparency` | 开启会大幅降低透明度 | [ ] |
| `Settings > Accessibility > Increase Contrast` | 可能影响玻璃效果 | [ ] |

### 🟠 中优先级：代码层面检查

#### 3. dummy ViewController 优化
**当前问题**：UITabBar 正在模糊 dummy VC 的空白视图。

尝试修改 `rebuildTabs()` 中的 dummy VC 设置：
```swift
// 尝试 1：完全透明 + 隐藏
dummyVC.view.alpha = 0
dummyVC.view.isHidden = true

// 尝试 2：布局延伸
dummyVC.edgesForExtendedLayout = .all
dummyVC.extendedLayoutIncludesOpaqueBars = true

// 尝试 3：layer 级别清除
dummyVC.view.layer.backgroundColor = UIColor.clear.cgColor
```

| 尝试 | 结果 |
|------|------|
| `view.alpha = 0` | [ ] 待测试 |
| `view.isHidden = true` | [ ] 待测试 |
| `edgesForExtendedLayout = .all` | [ ] 待测试 |
| `layer.backgroundColor = .clear.cgColor` | [ ] 待测试 |

#### 4. 视图层级 alpha 链检查
**问题**：UIVisualEffect 要求整个父视图链的 alpha 都是 1.0。

添加调试代码检查：
```swift
// 在 viewDidLoad 中添加
DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    var current: UIView? = self.tabBar
    while let v = current {
        NSLog("🔍 View: \(type(of: v)), alpha: \(v.alpha), isOpaque: \(v.isOpaque)")
        current = v.superview
    }
}
```

| 检查结果 | 状态 |
|----------|------|
| 所有父视图 alpha = 1.0 | [ ] |
| 没有视图 isOpaque = true | [ ] |

#### 5. 使用独立 UITabBar（不用 UITabBarController）
**假设**：UITabBarController 的内容视图层可能干扰透明度。

```swift
// 替代方案：直接使用 UITabBar
let tabBar = UITabBar()
tabBar.items = [...]
view.addSubview(tabBar)
// 不使用 UITabBarController
```

| 尝试 | 结果 |
|------|------|
| 独立 UITabBar | [ ] 待测试 |

### 🟡 低优先级：深度调研

#### 6. Platform View 渲染模式
**问题**：Flutter 的 Hybrid Composition 创建 "hole"，导致原生视图无法模糊 Flutter 内容。

可能的研究方向：
- [ ] 调研 Flutter 的 `texture` 渲染模式是否有帮助
- [ ] 调研是否可以截图 Flutter 内容作为原生层背景

#### 7. 对比测试
- [ ] 创建纯原生 iOS 项目，只含 UITabBarController，对比透明度
- [ ] 在原生项目中验证 Liquid Glass 效果是否正常

#### 8. UIGlassEffect 样式
**已知限制**：UITabBar 使用 `.regular` 样式，无法改为 `.clear`。

可能方案：
- [ ] 提交 Apple Feedback 请求暴露 glass style API
- [ ] 完全自定义：UIVisualEffectView + UIGlassEffect + 自定义按钮（失去原生交互）

### 测试记录模板

| 日期 | 尝试内容 | 结果 | 备注 |
|------|----------|------|------|
| YYYY-MM-DD | 描述 | ✅/❌ | |

### 最终结论

如果以上所有方案都无法解决，核心问题是 **Flutter Platform View 的根本限制**：
- 原生视图和 Flutter 内容不在同一渲染管线
- UITabBar 只能模糊其直接下层内容（dummy VC），无法看到 Flutter 内容

**推荐最终方案**：
1. 接受当前效果（如背景是纯色则影响不大）
2. 改用 Flutter 的 `BackdropFilter` 完全实现（失去原生交互效果）
3. 重构架构：原生 UITabBarController 作为根控制器（工作量大）

## 相关文件

- `ios/Runner/NativeTabBarController.swift` - 原生根控制器（UIViewController + UITabBar）
- `ios/Runner/AppDelegate.swift` - 应用入口，创建 FlutterEngine
- `lib/shared/services/native_tab_bar_service.dart` - Flutter-Native 通信服务
- `lib/shared/widgets/main_scaffold.dart` - 布局定位和 Tab 同步

---

## 2024年12月31日更新：UIViewController + UITabBar 方案

### 问题记录

使用 `UITabBarController` 作为根控制器时遇到以下问题：

1. **状态栏被遮挡** - FlutterView 插入到 UITabBarController.view 的最底层 (index 0)，但占位 ViewController 的 view 在上面
2. **触摸事件被拦截** - 占位 ViewController 的透明 view 拦截了所有触摸，导致页面无法滚动
3. **Tab 切换卡顿** - UITabBarController 在切换 VC 同时 Flutter 也在导航，造成双重动画

### 解决方案：使用 UIViewController + UITabBar

改用普通 `UIViewController` 而非 `UITabBarController`：

```swift
class NativeTabBarController: UIViewController, UITabBarDelegate {
    private let flutterEngine: FlutterEngine
    private let flutterViewController: FlutterViewController
    private let tabBar = UITabBar()

    override func viewDidLoad() {
        super.viewDidLoad()
        embedFlutterViewController()  // FlutterView 全屏
        setupTabBar()                  // UITabBar 悬浮在底部
        setupMethodChannel()
    }
}
```

### 新架构

```
UIWindow
└── NativeTabBarController (UIViewController)
    └── view
        ├── FlutterViewController.view (全屏，接收触摸)
        └── UITabBar (底部悬浮，Liquid Glass 效果)
```

**优势**：
- FlutterView 在视图层级中正确放置，接收所有触摸事件
- UITabBar 悬浮在上方，可以正确显示 Liquid Glass 效果
- 没有占位 VC 拦截触摸
- Tab 切换只触发 Flutter 路由，无原生 VC 切换动画

### UI 风格切换支持

`MainScaffold` 现在根据 `UIStyle` 动态切换：

```dart
bool _shouldUseNativeTabBar(UIStyle uiStyle) {
  if (kIsWeb) return false;
  if (!Platform.isIOS) return false;
  // 仅玻璃风格使用原生 Tab Bar
  return uiStyle.isGlass;
}
```

- **经典风格 (classic)**: 使用 Flutter 自己的导航栏
- **玻璃风格 (glass)**: 使用原生 UITabBar (Liquid Glass)

切换时自动：
- 订阅/取消原生 Tab 事件
- 显示/隐藏原生 Tab Bar
- 同步当前 Tab 索引

### 相关修改文件

| 文件 | 修改内容 |
|------|----------|
| `ios/Runner/NativeTabBarController.swift` | 改为 UIViewController + UITabBar |
| `lib/shared/widgets/main_scaffold.dart` | 添加 UI 风格切换逻辑 |

### 已知限制

使用独立 `UITabBar`（非 `UITabBarController`）时：
- 基本的 Liquid Glass 视觉效果 ✅
- 选中高亮效果 ✅
- 长按拖动切换 tab ❌（需要 UITabBarController）
- Selection Bubble 变形动画 ❌（需要 UITabBarController）

如需完整的 Liquid Glass 交互效果，可能需要探索其他方案。

---

## 2025年1月1日更新：UIStyle 和底部弹窗修复

### UIStyle：两种玻璃风格

支持三种 UI 风格：

```dart
/// UI 风格枚举
/// - classic: 经典不透明风格
/// - liquidClear: 液态玻璃 - 清澈模式（更透明）
/// - liquidTinted: 液态玻璃 - 染色模式（更高对比度）
enum UIStyle {
  classic('经典', Icons.square_rounded),
  liquidClear('玻璃 · 清澈', Icons.blur_on),
  liquidTinted('玻璃 · 染色', Icons.blur_circular);

  bool get isGlass => this != classic;
  bool get isTinted => this == liquidTinted;
}
```

**两种玻璃风格的差异**：

| 参数 | liquidClear | liquidTinted |
|------|-------------|--------------|
| blurIntensity | 20-25 | 25-30 |
| backgroundOpacity | 0.5-0.6 | 0.75-0.85 |
| tintOpacity | 0.05-0.1 | 0.1-0.15 |
| borderOpacity | 0.15-0.2 | 0.2-0.25 |
| 视觉效果 | 更透明、清澈 | 更高对比度、有色调 |

**注意**：这些差异主要体现在 Flutter 侧组件（如 AdaptiveGlassContainer）。
iOS 26 原生 UITabBar 只有一种 Liquid Glass 样式（.regular），无法区分。

**迁移处理**：旧版 `glass` 设置自动迁移到 `liquidClear`：

```dart
UIStyle? _parseUIStyle(String value) {
  // 处理旧版名称迁移
  if (value == 'glass') {
    return UIStyle.liquidClear;
  }
  // ...
}
```

### 底部弹窗被导航栏遮挡问题

**问题**：iOS 玻璃风格下，原生 UITabBar 悬浮在 Flutter 内容之上，导致底部弹窗被遮挡。

**根本原因**：Flutter 的 `MediaQuery.viewPadding.bottom` 只包含系统安全区域（如 Home Indicator），
不知道有一个原生 UITabBar 悬浮在上方。

**解决方案**：在底部弹窗中添加额外的底部间距来适应原生 Tab Bar 高度：

```dart
/// 计算底部弹窗的底部间距
double _getBottomPadding(BuildContext context, UIStyle uiStyle) {
  final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
  var padding = bottomPadding > 0 ? bottomPadding : AppSpacing.md;

  // iOS 玻璃风格下需要额外添加原生 Tab Bar 的高度
  if (!kIsWeb && Platform.isIOS && uiStyle.isGlass) {
    padding += 49;  // UITabBar 标准高度
  }

  return padding;
}
```

**修改的文件**：
- `lib/shared/widgets/app_bottom_sheet.dart` - 添加原生 Tab Bar 高度补偿
- `lib/shared/widgets/adaptive_sheet.dart` - 添加原生 Tab Bar 高度补偿

### iOS 26 底部弹窗最佳实践

根据 iOS 26 设计指南：
- iOS 26 的 sheet 自动具有 Liquid Glass 背景
- 使用 `presentationDetents`（.medium, .large）控制高度
- 不要设置自定义 `presentationBackground`
- 弹窗可以从触发按钮进行 "morphing" 变形动画

Flutter 中的适配：
- 使用 `showModalBottomSheet` 配合 `DraggableScrollableSheet`
- 添加额外的底部间距来避免被原生 Tab Bar 遮挡
- 使用 `BackdropFilter` 实现玻璃效果（Flutter 侧）

### 列表页面底部间距

**问题**：列表页面（影视、音乐、相册、阅读等）滚动到底部时，最后的内容被原生 Tab Bar 遮挡。

**解决方案**：更新 `context.scrollBottomPadding` 扩展方法，自动检测 iOS 玻璃风格并添加额外间距：

```dart
double get scrollBottomPadding {
  var padding = mediaQuery.padding.bottom;

  // iOS 玻璃风格下需要额外添加原生 Tab Bar 的高度
  if (!kIsWeb && Platform.isIOS) {
    try {
      final container = ProviderScope.containerOf(this);
      final uiStyle = container.read(uiStyleProvider);
      if (uiStyle.isGlass) {
        padding += 49;  // UITabBar 标准高度
      }
    } on Exception catch (_) {
      // 如果无法访问 provider，使用默认值
    }
  }

  return padding;
}
```

**已使用此方法的页面**（自动获得修复）：
- `video_list_page.dart`
- `music_list_page.dart`
- `music_home_page.dart`
- `photo_list_page.dart`
- `book_list_page.dart`
- `comic_list_page.dart`
- `note_tree_widget.dart`

### 相关修改文件

| 文件 | 修改内容 |
|------|----------|
| `lib/app/theme/ui_style.dart` | 定义 liquidClear/liquidTinted 两种玻璃风格及其参数 |
| `lib/shared/providers/ui_style_provider.dart` | 添加旧设置迁移逻辑（glass → liquidClear） |
| `lib/shared/widgets/adaptive_glass_container.dart` | 根据 UIStyle 选择原生模糊样式 |
| `lib/shared/widgets/app_bottom_sheet.dart` | 添加原生 Tab Bar 高度补偿 |
| `lib/shared/widgets/adaptive_sheet.dart` | 添加原生 Tab Bar 高度补偿 |
| `lib/core/extensions/context_extensions.dart` | 更新 scrollBottomPadding 支持玻璃风格 |
