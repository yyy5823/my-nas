import Flutter
import UIKit

/// iOS 26 Liquid Glass 原生视图
///
/// 使用原生 UITabBarController 实现真正的 iOS 26 Liquid Glass 效果
/// iOS 26 的 UITabBar 自动获得 Liquid Glass 样式，无需任何自定义代码
///
/// 特点：
/// - 透明背景
/// - 只有选中的 tab 有玻璃"药丸"效果
/// - 选中指示器可以长按拖动切换
/// - 平滑的变形动画
/// - 按压交互效果

// MARK: - Navigation Bar Item

struct LiquidGlassNavItem {
    let id: Int
    let icon: String           // SF Symbol name (未选中)
    let selectedIcon: String   // SF Symbol name (选中)
    let label: String
}

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

// MARK: - Platform View

class LiquidGlassPlatformView: NSObject, FlutterPlatformView {
    private let tabBarController: LiquidGlassTabBarController
    private let viewId: Int64
    private let messenger: FlutterBinaryMessenger?
    private var methodChannel: FlutterMethodChannel?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        self.viewId = viewId
        self.messenger = messenger

        // 解析参数
        var items: [LiquidGlassNavItem] = []
        var selectedIndex = 0
        var isDark = false

        if let params = args as? [String: Any] {
            isDark = params["isDark"] as? Bool ?? false
            selectedIndex = params["selectedIndex"] as? Int ?? 0

            if let itemsData = params["items"] as? [[String: Any]] {
                items = itemsData.enumerated().map { index, item in
                    let icon = item["icon"] as? String ?? "circle"
                    let selectedIcon = item["selectedIcon"] as? String ?? icon
                    return LiquidGlassNavItem(
                        id: index,
                        icon: icon,
                        selectedIcon: selectedIcon,
                        label: item["label"] as? String ?? ""
                    )
                }
            }
        }

        NSLog("🔮 LiquidGlassView: init with frame: \(frame), viewId: \(viewId)")
        NSLog("🔮 LiquidGlassView: iOS version: \(UIDevice.current.systemVersion)")
        NSLog("🔮 LiquidGlassView: Parsed \(items.count) items, selectedIndex: \(selectedIndex)")

        // 创建 TabBarController
        tabBarController = LiquidGlassTabBarController(
            items: items,
            selectedIndex: selectedIndex,
            isDark: isDark
        )

        super.init()

        // 设置 Method Channel
        setupMethodChannel()

        // 设置回调
        tabBarController.onTabSelected = { [weak self] index in
            self?.handleNavTap(index)
        }
    }

    func view() -> UIView {
        return tabBarController.view
    }

    private func setupMethodChannel() {
        guard let messenger = messenger else { return }

        let channelName = "com.kkape.mynas/liquid_glass_view_\(viewId)"
        methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)

        methodChannel?.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "updateSelectedIndex":
                if let index = call.arguments as? Int {
                    self?.tabBarController.updateSelectedIndex(index)
                }
                result(nil)
            case "updateItems":
                if let itemsData = call.arguments as? [[String: Any]] {
                    let items = itemsData.enumerated().map { index, item in
                        let icon = item["icon"] as? String ?? "circle"
                        let selectedIcon = item["selectedIcon"] as? String ?? icon
                        return LiquidGlassNavItem(
                            id: index,
                            icon: icon,
                            selectedIcon: selectedIcon,
                            label: item["label"] as? String ?? ""
                        )
                    }
                    self?.tabBarController.updateItems(items)
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func handleNavTap(_ index: Int) {
        NSLog("🔮 LiquidGlassView: handleNavTap called with index: \(index)")
        // 通知 Flutter
        methodChannel?.invokeMethod("onNavTap", arguments: index)
    }
}

// MARK: - Tab Bar Controller

/// 使用原生 UITabBarController 实现 Liquid Glass 效果
/// iOS 26 的 UITabBar 自动获得 Liquid Glass 样式
class LiquidGlassTabBarController: UITabBarController, UITabBarControllerDelegate {
    private var items: [LiquidGlassNavItem]
    private var isDark: Bool
    var onTabSelected: ((Int) -> Void)?

    init(items: [LiquidGlassNavItem], selectedIndex: Int, isDark: Bool) {
        self.items = items
        self.isDark = isDark
        super.init(nibName: nil, bundle: nil)
        self.selectedIndex = selectedIndex
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NSLog("🔮 LiquidGlassTabBarController: viewDidLoad")

        // 设置透明背景
        view.backgroundColor = .clear
        view.isOpaque = false

        // 设置代理
        delegate = self

        // 配置外观
        configureAppearance()

        // 创建 tab items
        rebuildTabs()

        NSLog("🔮 LiquidGlassTabBarController: Setup complete, iOS 26+ will automatically apply Liquid Glass")
    }

    private func configureAppearance() {
        // 配置 TabBar 外观
        let appearance = UITabBarAppearance()

        if #available(iOS 26.0, *) {
            // iOS 26+: 使用透明背景，让系统自动应用 Liquid Glass
            appearance.configureWithTransparentBackground()
            NSLog("🔮 LiquidGlassTabBarController: Using transparent background for iOS 26 Liquid Glass")
        } else {
            // iOS < 26: 使用模糊效果作为回退
            appearance.configureWithDefaultBackground()
            appearance.backgroundEffect = UIBlurEffect(style: isDark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)
            NSLog("🔮 LiquidGlassTabBarController: Using blur effect fallback for iOS < 26")
        }

        // 应用外观
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }

        // 设置 TabBar 透明
        tabBar.isTranslucent = true
        tabBar.backgroundColor = .clear
    }

    private func rebuildTabs() {
        var controllers: [UIViewController] = []

        for item in items {
            // 创建空的 ViewController 作为占位
            let dummyVC = UIViewController()
            dummyVC.view.backgroundColor = .clear

            // 配置 tab bar item
            let image = UIImage(systemName: item.icon)
            let selectedImage = UIImage(systemName: item.selectedIcon)

            dummyVC.tabBarItem = UITabBarItem(
                title: item.label,
                image: image,
                selectedImage: selectedImage
            )
            dummyVC.tabBarItem.tag = item.id

            controllers.append(dummyVC)

            NSLog("🔮 LiquidGlassTabBarController: Added tab '\(item.label)' with icon '\(item.icon)'")
        }

        setViewControllers(controllers, animated: false)
        NSLog("🔮 LiquidGlassTabBarController: Created \(controllers.count) tabs")
    }

    func updateSelectedIndex(_ index: Int) {
        guard index != selectedIndex, index >= 0, index < (viewControllers?.count ?? 0) else { return }
        selectedIndex = index
        NSLog("🔮 LiquidGlassTabBarController: Updated selectedIndex to \(index)")
    }

    func updateItems(_ newItems: [LiquidGlassNavItem]) {
        items = newItems
        rebuildTabs()
    }

    // MARK: - UITabBarControllerDelegate

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        let index = viewController.tabBarItem.tag
        NSLog("🔮 LiquidGlassTabBarController: Tab selected: \(index)")
        onTabSelected?(index)
    }

    // iOS 26+ 的交互效果由系统自动处理：
    // - 选中指示器的玻璃"药丸"效果
    // - 长按拖动切换 tab
    // - 按压动画效果
    // - tab 之间的变形动画
}

// MARK: - Plugin Registration

class LiquidGlassPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = LiquidGlassViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "com.kkape.mynas/liquid_glass_view")

        NSLog("🔮 LiquidGlassPlugin: Registered")

        if #available(iOS 26.0, *) {
            NSLog("🔮 LiquidGlassPlugin: iOS 26+ detected, UITabBar will automatically get Liquid Glass")
        } else {
            NSLog("🔮 LiquidGlassPlugin: iOS < 26, using blur effect fallback")
        }
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
