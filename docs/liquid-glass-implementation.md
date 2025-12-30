# iOS 26 Liquid Glass 实现记录

## 目标
在 iOS 26+ 设备上实现真正的 Liquid Glass (水滴玻璃) 效果，用于底部导航栏。

## 环境
- 设备: iPhone (programApe)
- iOS 版本: 26.2
- Flutter Platform View: UiKitView

---

## ✅ 最终正确方案：使用原生 UITabBarController

### 关键发现

**iOS 26 的 UITabBar 自动获得 Liquid Glass 效果，无需任何自定义代码！**

这是最重要的发现：不要尝试手动创建玻璃效果，而是使用原生 `UITabBarController`，让系统自动处理。

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

    private func rebuildTabs() {
        var controllers: [UIViewController] = []
        for item in items {
            let dummyVC = UIViewController()
            dummyVC.view.backgroundColor = .clear
            dummyVC.tabBarItem = UITabBarItem(
                title: item.label,
                image: UIImage(systemName: item.icon),
                selectedImage: UIImage(systemName: item.selectedIcon)
            )
            controllers.append(dummyVC)
        }
        setViewControllers(controllers, animated: false)
    }
}
```

### 为什么这样做有效？

1. **iOS 26 的 UITabBar 内置 Liquid Glass**
   - Apple 在 iOS 26 中为 UITabBar 添加了原生 Liquid Glass 支持
   - 只需使用透明背景，系统会自动应用效果
   - 无需手动使用 `UIGlassEffect` 或 SwiftUI `.glassEffect()`

2. **系统自动处理所有交互效果**
   - 选中指示器的玻璃"药丸"效果
   - 长按拖动切换 tab
   - 按压动画效果
   - tab 之间的变形动画

3. **参考实现**
   - `native_glass_navbar` Flutter 包使用相同方法
   - 创建 `UITabBarController` + 空的 `UIViewController` 作为占位
   - 返回 `controller.view` 作为 Platform View

---

## ❌ 之前的错误尝试

### 错误方法 1: SwiftUI .glassEffect() 直接应用

```swift
var body: some View {
    HStack { /* nav items */ }
    .glassEffect(.regular.interactive(), in: .capsule)
}
```

**结果:** 失败 - 在 Flutter Platform View 的 UIKit 环境中无法正确渲染

### 错误方法 2: UIGlassEffect() 默认初始化

```swift
let glassEffect = UIGlassEffect()  // 默认是 .regular
let effectView = UIVisualEffectView(effect: glassEffect)
```

**结果:** 毛玻璃效果，不是真正的透明玻璃

### 错误方法 3: UIGlassEffect(style: .clear)

```swift
let glassEffect = UIGlassEffect(style: .clear)
let effectView = UIVisualEffectView(effect: glassEffect)
```

**结果:** 仍然不透明，无法实现真正的 Liquid Glass 效果

### 错误方法 4: SwiftUI GlassEffectContainer + glassEffectID

```swift
GlassEffectContainer(spacing: 8) {
    HStack {
        ForEach(items) { item in
            Button { onTap(item.id) } label: { /* ... */ }
            .glassEffect(isSelected ? .regular.interactive() : .identity, in: .capsule)
            .glassEffectID("navSelection", in: namespace)
        }
    }
}
```

**结果:**
- 导航栏完全不透明
- 选中效果始终在第一个上面不会变动
- 选中效果按住没有变化
- 导航栏按住没有变化

**问题:** 这种方法试图手动创建玻璃效果，但在 Flutter Platform View 环境中不起作用

---

## iOS 26 Liquid Glass 效果特点

基于 iOS 26 音乐 App 的观察：

1. **透明背景** - 整个导航栏背景是透明的
2. **选中指示器** - 只有选中的 tab 有玻璃"药丸"背景
3. **变形动画** - 玻璃块在 tab 之间平滑变形移动
4. **长按拖动** - 选中指示器可以长按拖动切换 tab
5. **按压效果** - 按压时有交互反馈

所有这些效果在使用原生 `UITabBarController` 时由系统自动提供。

---

## 文件清单

### Swift (原生端)
- `ios/Runner/LiquidGlassView.swift` - 使用 UITabBarController 实现
- `ios/Runner/AppDelegate.swift` - 注册 LiquidGlassPlugin

### Dart (Flutter 端)
- `lib/shared/widgets/liquid_glass/liquid_glass_nav_bar.dart` - Flutter 组件
- `lib/shared/widgets/liquid_glass/liquid_glass_service.dart` - 平台服务

---

## 调试日志标识

所有 Liquid Glass 相关日志使用 `🔮 LiquidGlassView:` 或 `🔮 LiquidGlassTabBarController:` 前缀：

```bash
# 实时查看日志
log stream --predicate 'subsystem == "com.apple.os_log"' | grep "LiquidGlass"
```

---

## 参考资料

- WWDC25: Meet the Liquid Glass design system
- WWDC25: Build with UIKit and Liquid Glass
- Apple Developer: UITabBarController
- `native_glass_navbar` Flutter 包 (正确使用 UITabBarController)
