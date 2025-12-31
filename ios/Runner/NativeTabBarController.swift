import Flutter
import UIKit

/// 原生 UITabBarController 作为根控制器
///
/// 将 FlutterViewController 嵌入到 UITabBarController 中，
/// 让 UITabBar 可以正确模糊 Flutter 内容，实现真正的 iOS 26 Liquid Glass 效果
///
/// 架构：
/// ```
/// UIWindow
/// └── NativeTabBarController (根控制器)
///     ├── FlutterViewController.view (作为底层内容)
///     └── UITabBar (可以正确模糊 Flutter 内容)
/// ```
class NativeTabBarController: UITabBarController, UITabBarControllerDelegate {

    // MARK: - Properties

    /// Flutter 引擎
    private let flutterEngine: FlutterEngine

    /// Flutter 视图控制器
    private let flutterViewController: FlutterViewController

    /// 与 Flutter 通信的 Method Channel
    private var methodChannel: FlutterMethodChannel?

    /// Tab 配置
    private struct NavTabConfig {
        let icon: String           // SF Symbol name (未选中)
        let selectedIcon: String   // SF Symbol name (选中)
        let label: String
        let route: String          // Flutter 路由
    }

    /// 5 个 Tab 的配置
    private let tabConfigs: [NavTabConfig] = [
        NavTabConfig(icon: "film", selectedIcon: "film.fill", label: "影视", route: "/video"),
        NavTabConfig(icon: "music.note.list", selectedIcon: "music.note.list", label: "曲库", route: "/music"),
        NavTabConfig(icon: "photo.on.rectangle", selectedIcon: "photo.on.rectangle.fill", label: "相册", route: "/photo"),
        NavTabConfig(icon: "book", selectedIcon: "book.fill", label: "阅读", route: "/reading"),
        NavTabConfig(icon: "person.circle", selectedIcon: "person.circle.fill", label: "我的", route: "/mine"),
    ]

    /// 是否正在处理 tab 切换（防止循环）
    private var isHandlingTabChange = false

    // MARK: - Initialization

    init(flutterEngine: FlutterEngine) {
        self.flutterEngine = flutterEngine
        self.flutterViewController = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        NSLog("🔮 NativeTabBarController: viewDidLoad")

        // 设置代理
        delegate = self

        // 创建 Tab 视图控制器
        setupTabs()

        // 设置 Method Channel
        setupMethodChannel()

        // 初始时隐藏 tab bar，等待 Flutter 通知显示
        // 这样在 loading 页面时不会显示 tab bar
        tabBar.isHidden = true
        tabBar.alpha = 0.0

        // iOS 26+: 不设置任何 appearance，让系统自动应用 Liquid Glass
        // 这是最关键的一点！
        if #available(iOS 26.0, *) {
            NSLog("🔮 NativeTabBarController: iOS 26+ - NOT setting any appearance (letting system apply Liquid Glass)")
            // 不做任何事情！让系统默认的 Liquid Glass 生效
        } else {
            // iOS < 26: 使用模糊效果作为回退
            configureAppearanceFallback()
        }

        NSLog("🔮 NativeTabBarController: Setup complete with \(tabConfigs.count) tabs")
    }

    // MARK: - Tab Setup

    /// 创建 Tab 视图控制器
    ///
    /// 关键：每个 Tab 都使用同一个 FlutterViewController 的 view 作为内容
    /// 这样 UITabBar 就能正确模糊 Flutter 内容
    private func setupTabs() {
        var controllers: [UIViewController] = []

        for (index, tab) in tabConfigs.enumerated() {
            // 创建容器 ViewController
            let containerVC = FlutterContainerViewController()
            containerVC.view.backgroundColor = .clear

            // 配置 tab bar item
            let image = UIImage(systemName: tab.icon)
            let selectedImage = UIImage(systemName: tab.selectedIcon)

            containerVC.tabBarItem = UITabBarItem(
                title: tab.label,
                image: image,
                selectedImage: selectedImage
            )
            containerVC.tabBarItem.tag = index

            controllers.append(containerVC)

            NSLog("🔮 NativeTabBarController: Added tab '\(tab.label)' with icon '\(tab.icon)'")
        }

        setViewControllers(controllers, animated: false)

        // 将 FlutterViewController 的 view 添加到当前选中的 tab
        embedFlutterView()
    }

    /// 将 FlutterViewController 的 view 嵌入到当前选中的 tab
    private func embedFlutterView() {
        guard let selectedVC = selectedViewController else { return }

        // 将 Flutter view 作为子视图添加
        // 这样 UITabBar 就能正确模糊 Flutter 内容
        let flutterView = flutterViewController.view!
        flutterView.translatesAutoresizingMaskIntoConstraints = false

        // 先移除旧的 Flutter view（如果存在）
        flutterView.removeFromSuperview()

        // 添加到新的容器
        selectedVC.view.addSubview(flutterView)

        // 设置约束，让 Flutter view 填满整个容器
        // 注意：不设置底部约束到 safeAreaLayoutGuide，让内容延伸到 tab bar 下方
        NSLayoutConstraint.activate([
            flutterView.topAnchor.constraint(equalTo: selectedVC.view.topAnchor),
            flutterView.leadingAnchor.constraint(equalTo: selectedVC.view.leadingAnchor),
            flutterView.trailingAnchor.constraint(equalTo: selectedVC.view.trailingAnchor),
            flutterView.bottomAnchor.constraint(equalTo: selectedVC.view.bottomAnchor),
        ])

        NSLog("🔮 NativeTabBarController: Embedded Flutter view in tab \(selectedIndex)")
    }

    // MARK: - Appearance

    /// iOS < 26 的回退外观配置
    private func configureAppearanceFallback() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        // 使用系统模糊效果
        let isDark = traitCollection.userInterfaceStyle == .dark
        appearance.backgroundEffect = UIBlurEffect(style: isDark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)

        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        tabBar.isTranslucent = true

        NSLog("🔮 NativeTabBarController: Using blur effect fallback for iOS < 26")
    }

    /// 响应深色/浅色模式变化
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // iOS < 26: 更新模糊效果
        if #unavailable(iOS 26.0) {
            if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                configureAppearanceFallback()
            }
        }

        // 通知 Flutter 深色模式变化
        let isDark = traitCollection.userInterfaceStyle == .dark
        methodChannel?.invokeMethod("onThemeChanged", arguments: isDark)
    }

    // MARK: - Method Channel

    private func setupMethodChannel() {
        let channelName = "com.kkape.mynas/native_tab_bar"
        methodChannel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: flutterEngine.binaryMessenger
        )

        methodChannel?.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterMethodNotImplemented)
                return
            }

            switch call.method {
            case "setSelectedIndex":
                if let index = call.arguments as? Int {
                    self.setSelectedTab(index)
                }
                result(nil)

            case "getSelectedIndex":
                result(self.selectedIndex)

            case "getTabBarHeight":
                result(self.tabBar.frame.height)

            case "getSafeAreaBottom":
                result(self.view.safeAreaInsets.bottom)

            case "isLiquidGlassSupported":
                if #available(iOS 26.0, *) {
                    result(true)
                } else {
                    result(false)
                }

            case "setTabBarVisible":
                if let visible = call.arguments as? Bool {
                    self.setTabBarVisible(visible)
                }
                result(nil)

            case "isTabBarVisible":
                result(!self.tabBar.isHidden)

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        NSLog("🔮 NativeTabBarController: Method channel setup complete")
    }

    /// 从 Flutter 设置选中的 tab
    private func setSelectedTab(_ index: Int) {
        guard !isHandlingTabChange else { return }
        guard index >= 0, index < (viewControllers?.count ?? 0) else { return }

        isHandlingTabChange = true
        selectedIndex = index
        embedFlutterView()
        isHandlingTabChange = false

        NSLog("🔮 NativeTabBarController: Flutter set tab to \(index)")
    }

    /// 设置 Tab Bar 是否可见
    ///
    /// 用于在 loading 页面隐藏 tab bar
    private func setTabBarVisible(_ visible: Bool) {
        UIView.animate(withDuration: 0.25) {
            self.tabBar.isHidden = !visible
            self.tabBar.alpha = visible ? 1.0 : 0.0
        }
        NSLog("🔮 NativeTabBarController: Tab bar visibility set to \(visible)")
    }

    // MARK: - UITabBarControllerDelegate

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard !isHandlingTabChange else { return }

        isHandlingTabChange = true

        let index = viewController.tabBarItem.tag
        let route = tabConfigs[index].route

        // 重新嵌入 Flutter view 到新选中的 tab
        embedFlutterView()

        // 通知 Flutter 切换路由
        methodChannel?.invokeMethod("onTabSelected", arguments: [
            "index": index,
            "route": route,
        ])

        NSLog("🔮 NativeTabBarController: User selected tab \(index) -> \(route)")

        isHandlingTabChange = false
    }

    // iOS 26+ 的 Liquid Glass 交互效果由系统自动处理：
    // - 选中指示器的玻璃"药丸"效果（Selection Bubble）
    // - 长按拖动切换 tab（Drag to switch）
    // - 按压动画效果（Press animation）
    // - tab 之间的变形动画（Morphing）
    // - 透镜效果（Lensing）
    // - 色差效果（Chromatic aberration）
}

// MARK: - Flutter Container View Controller

/// Flutter 内容的容器视图控制器
///
/// 每个 Tab 都使用这个容器，FlutterViewController 的 view 会被嵌入其中
class FlutterContainerViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        // 让内容延伸到 tab bar 下方
        edgesForExtendedLayout = .all
        extendedLayoutIncludesOpaqueBars = true
    }
}
