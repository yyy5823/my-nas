import Flutter
import UIKit

/// iOS 26 Liquid Glass 原生视图
///
/// 使用原生 UITabBar 实现悬浮导航栏效果
/// iOS 26+ 使用 UIGlassEffect 实现真正的 Liquid Glass 效果
///
/// 特点：
/// - 原生 UITabBar 外观和交互
/// - 透明/玻璃背景
/// - 支持深色/浅色模式
/// - 胶囊形悬浮设计

// MARK: - Platform View Factory

class LiquidGlassViewFactory: NSObject, FlutterPlatformViewFactory {
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
        return LiquidGlassPlatformView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - Custom Container View (忽略安全区域)

/// 自定义容器视图，重写 safeAreaInsets 返回 .zero
/// 这样 UITabBar 就不会预留安全区域空间
class SafeAreaIgnoringContainerView: UIView {
    override var safeAreaInsets: UIEdgeInsets {
        return .zero
    }
}

// MARK: - Custom TabBar (填满容器)

/// 自定义 UITabBar，确保填满容器高度并垂直居中内容
class FullHeightTabBar: UITabBar {

    private var containerHeight: CGFloat = 70
    // UITabBar 标准内容高度
    private let standardTabBarContentHeight: CGFloat = 49

    func setContainerHeight(_ height: CGFloat) {
        containerHeight = height
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var safeAreaInsets: UIEdgeInsets {
        return .zero
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: containerHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var sizeThatFits = super.sizeThatFits(size)
        sizeThatFits.height = containerHeight
        return sizeThatFits
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // 计算垂直偏移量，使内容居中
        let verticalOffset = (containerHeight - standardTabBarContentHeight) / 2

        // 调整所有 TabBarButton 的位置
        for subview in subviews {
            let className = String(describing: type(of: subview))
            if className.contains("TabBarButton") {
                var frame = subview.frame
                // 将按钮向下移动，使其在容器中垂直居中
                frame.origin.y = verticalOffset
                frame.size.height = standardTabBarContentHeight
                subview.frame = frame
            }
        }
    }
}

// MARK: - Platform View

class LiquidGlassPlatformView: NSObject, FlutterPlatformView {
    private let containerView: SafeAreaIgnoringContainerView
    private let tabBar: FullHeightTabBar
    private var backgroundEffectView: UIVisualEffectView?
    private let viewId: Int64
    private let messenger: FlutterBinaryMessenger?
    private var methodChannel: FlutterMethodChannel?
    private var isDark: Bool = false

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        self.viewId = viewId
        self.messenger = messenger

        // 创建容器视图（忽略安全区域）
        containerView = SafeAreaIgnoringContainerView(frame: frame)
        containerView.backgroundColor = .clear
        containerView.clipsToBounds = true
        containerView.layer.cornerRadius = frame.height / 2
        containerView.layer.cornerCurve = .continuous

        // 创建 TabBar
        tabBar = FullHeightTabBar(frame: containerView.bounds)
        tabBar.setContainerHeight(frame.height)
        tabBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tabBar.insetsLayoutMarginsFromSafeArea = false

        // 解析参数
        var items: [UITabBarItem] = []
        var selectedIndex = 0

        if let params = args as? [String: Any] {
            isDark = params["isDark"] as? Bool ?? false
            selectedIndex = params["selectedIndex"] as? Int ?? 0

            if let itemsData = params["items"] as? [[String: Any]] {
                items = itemsData.enumerated().map { index, item in
                    let icon = item["icon"] as? String ?? "circle"
                    let selectedIcon = item["selectedIcon"] as? String ?? icon
                    let label = item["label"] as? String ?? ""

                    let tabItem = UITabBarItem(
                        title: label,
                        image: UIImage(systemName: icon),
                        selectedImage: UIImage(systemName: selectedIcon)
                    )
                    tabItem.tag = index
                    return tabItem
                }
            }
        }

        super.init()

        // 设置界面风格
        containerView.overrideUserInterfaceStyle = isDark ? .dark : .light
        tabBar.overrideUserInterfaceStyle = isDark ? .dark : .light

        // 设置背景效果
        setupBackground(frame: containerView.bounds)

        // 配置 TabBar 外观
        configureTabBarAppearance()

        // 设置 TabBar items
        tabBar.items = items
        tabBar.selectedItem = items.indices.contains(selectedIndex) ? items[selectedIndex] : items.first
        tabBar.delegate = self

        // 添加到容器
        containerView.addSubview(tabBar)

        // 设置 Method Channel
        setupMethodChannel()

        // Debug 日志
        NSLog("🔮 LiquidGlassView: Created with frame \(frame), isDark: \(isDark), items: \(items.count)")
    }

    func view() -> UIView {
        return containerView
    }

    private func setupBackground(frame: CGRect) {
        backgroundEffectView?.removeFromSuperview()

        if #available(iOS 26.0, *) {
            // iOS 26+: 使用 Liquid Glass 效果
            let glassEffect = UIGlassEffect()
            let effectView = UIVisualEffectView(effect: glassEffect)
            effectView.frame = frame
            effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            effectView.layer.cornerRadius = frame.height / 2
            effectView.layer.cornerCurve = .continuous
            effectView.clipsToBounds = true
            effectView.overrideUserInterfaceStyle = isDark ? .dark : .light
            containerView.insertSubview(effectView, at: 0)
            backgroundEffectView = effectView

            NSLog("🔮 LiquidGlassView: Using UIGlassEffect (iOS 26+)")
        } else {
            // iOS < 26: 使用模糊效果
            let blurStyle: UIBlurEffect.Style = isDark ? .systemThinMaterialDark : .systemThinMaterialLight
            let blurEffect = UIBlurEffect(style: blurStyle)
            let effectView = UIVisualEffectView(effect: blurEffect)
            effectView.frame = frame
            effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            effectView.layer.cornerRadius = frame.height / 2
            effectView.layer.cornerCurve = .continuous
            effectView.clipsToBounds = true

            // 添加边框
            effectView.layer.borderWidth = 0.5
            effectView.layer.borderColor = isDark
                ? UIColor.white.withAlphaComponent(0.1).cgColor
                : UIColor.black.withAlphaComponent(0.05).cgColor

            containerView.insertSubview(effectView, at: 0)
            backgroundEffectView = effectView

            NSLog("🔮 LiquidGlassView: Using UIBlurEffect (iOS < 26)")
        }
    }

    private func configureTabBarAppearance() {
        // 完全透明背景（由 backgroundEffectView 提供玻璃效果）
        tabBar.backgroundImage = UIImage()
        tabBar.shadowImage = UIImage()
        tabBar.backgroundColor = .clear
        tabBar.barTintColor = .clear
        tabBar.isTranslucent = true

        // 使用现代外观 API
        if #available(iOS 15.0, *) {
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.shadowColor = .clear
            appearance.shadowImage = nil
            appearance.backgroundImage = nil
            appearance.backgroundEffect = nil

            // 配置 item 外观
            let itemAppearance = UITabBarItemAppearance()

            // 正常状态
            itemAppearance.normal.iconColor = isDark
                ? UIColor.white.withAlphaComponent(0.6)
                : UIColor.black.withAlphaComponent(0.5)
            itemAppearance.normal.titleTextAttributes = [
                .foregroundColor: isDark
                    ? UIColor.white.withAlphaComponent(0.6)
                    : UIColor.black.withAlphaComponent(0.5),
                .font: UIFont.systemFont(ofSize: 10, weight: .regular)
            ]

            // 选中状态
            itemAppearance.selected.iconColor = .systemBlue
            itemAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor.systemBlue,
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
            ]

            appearance.stackedLayoutAppearance = itemAppearance
            appearance.inlineLayoutAppearance = itemAppearance
            appearance.compactInlineLayoutAppearance = itemAppearance

            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
        } else {
            // iOS 14 及以下
            tabBar.tintColor = .systemBlue
            tabBar.unselectedItemTintColor = isDark
                ? UIColor.white.withAlphaComponent(0.6)
                : UIColor.black.withAlphaComponent(0.5)
        }
    }

    private func setupMethodChannel() {
        guard let messenger = messenger else { return }

        let channelName = "com.kkape.mynas/liquid_glass_view_\(viewId)"
        methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)

        methodChannel?.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "updateSelectedIndex":
                if let index = call.arguments as? Int,
                   let items = self?.tabBar.items,
                   items.indices.contains(index) {
                    self?.tabBar.selectedItem = items[index]
                }
                result(nil)
            case "updateItems":
                if let itemsData = call.arguments as? [[String: Any]] {
                    let newItems = itemsData.enumerated().map { index, item in
                        let icon = item["icon"] as? String ?? "circle"
                        let selectedIcon = item["selectedIcon"] as? String ?? icon
                        let label = item["label"] as? String ?? ""

                        let tabItem = UITabBarItem(
                            title: label,
                            image: UIImage(systemName: icon),
                            selectedImage: UIImage(systemName: selectedIcon)
                        )
                        tabItem.tag = index
                        return tabItem
                    }
                    self?.tabBar.items = newItems
                    if let firstItem = newItems.first {
                        self?.tabBar.selectedItem = firstItem
                    }
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func handleNavTap(_ index: Int) {
        methodChannel?.invokeMethod("onNavTap", arguments: index)
    }
}

// MARK: - UITabBarDelegate

extension LiquidGlassPlatformView: UITabBarDelegate {
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        handleNavTap(item.tag)
    }
}

// MARK: - Plugin Registration

class LiquidGlassPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = LiquidGlassViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "com.kkape.mynas/liquid_glass_view")
    }
}

// MARK: - Availability Check

extension LiquidGlassPlugin {
    static var isLiquidGlassSupported: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }
}
