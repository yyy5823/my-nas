import Flutter
import UIKit

/// 原生 Tab Bar 根控制器
///
/// 使用 UIViewController + UITabBar（而非 UITabBarController）实现
/// 这样 FlutterView 可以接收所有触摸事件，同时 UITabBar 悬浮在上方
///
/// 架构：
/// ```
/// UIWindow
/// └── NativeTabBarController (UIViewController)
///     └── view
///         ├── FlutterViewController.view (全屏，接收触摸)
///         └── UITabBar (底部悬浮，Liquid Glass 效果)
/// ```
class NativeTabBarController: UIViewController, UITabBarDelegate {

    // MARK: - Properties

    /// Flutter 引擎
    private let flutterEngine: FlutterEngine

    /// Flutter 视图控制器
    private let flutterViewController: FlutterViewController

    /// 原生 Tab Bar
    private let tabBar = UITabBar()

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

    /// 当前选中的 Tab 索引
    private var selectedIndex: Int = 0

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

        // 1. 嵌入 FlutterViewController
        embedFlutterViewController()

        // 2. 设置 Tab Bar
        setupTabBar()

        // 3. 设置 Method Channel
        setupMethodChannel()

        NSLog("🔮 NativeTabBarController: Setup complete")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // 确保 Tab Bar 在最前面
        view.bringSubviewToFront(tabBar)
    }

    // MARK: - Flutter Embedding

    /// 嵌入 FlutterViewController 作为子视图控制器
    private func embedFlutterViewController() {
        // 添加 FlutterViewController 作为子视图控制器
        addChild(flutterViewController)

        // 获取 Flutter view
        let flutterView = flutterViewController.view!
        flutterView.translatesAutoresizingMaskIntoConstraints = false

        // 添加到 self.view
        view.addSubview(flutterView)

        // 设置约束 - 全屏（包括安全区域）
        // Flutter 自己会处理 SafeArea
        NSLayoutConstraint.activate([
            flutterView.topAnchor.constraint(equalTo: view.topAnchor),
            flutterView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            flutterView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            flutterView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 完成子视图控制器的添加
        flutterViewController.didMove(toParent: self)

        NSLog("🔮 NativeTabBarController: Embedded FlutterViewController")
    }

    // MARK: - Tab Bar Setup

    /// 设置 Tab Bar
    private func setupTabBar() {
        tabBar.delegate = self
        tabBar.translatesAutoresizingMaskIntoConstraints = false

        // 创建 Tab Items
        var items: [UITabBarItem] = []
        for (index, config) in tabConfigs.enumerated() {
            let image = UIImage(systemName: config.icon)
            let selectedImage = UIImage(systemName: config.selectedIcon)
            let item = UITabBarItem(title: config.label, image: image, selectedImage: selectedImage)
            item.tag = index
            items.append(item)
        }
        tabBar.items = items
        tabBar.selectedItem = items.first

        // 添加到视图
        view.addSubview(tabBar)

        // 设置约束 - 底部悬浮
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 初始时隐藏，等待 Flutter 通知显示
        tabBar.isHidden = true
        tabBar.alpha = 0.0

        // iOS 26+: 不设置任何 appearance，让系统自动应用 Liquid Glass
        if #available(iOS 26.0, *) {
            NSLog("🔮 NativeTabBarController: iOS 26+ - NOT setting any appearance (Liquid Glass)")
            // 不做任何事情！让系统默认的 Liquid Glass 生效
        } else {
            // iOS < 26: 使用模糊效果作为回退
            configureAppearanceFallback()
        }

        NSLog("🔮 NativeTabBarController: Tab bar setup complete with \(tabConfigs.count) tabs")
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

    // MARK: - UITabBarDelegate

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard !isHandlingTabChange else { return }

        isHandlingTabChange = true

        let index = item.tag
        selectedIndex = index
        let route = tabConfigs[index].route

        // 通知 Flutter 切换路由
        methodChannel?.invokeMethod("onTabSelected", arguments: [
            "index": index,
            "route": route,
        ])

        NSLog("🔮 NativeTabBarController: User selected tab \(index) -> \(route)")

        isHandlingTabChange = false
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
        guard index >= 0, index < (tabBar.items?.count ?? 0) else { return }

        isHandlingTabChange = true
        selectedIndex = index
        tabBar.selectedItem = tabBar.items?[index]
        isHandlingTabChange = false

        NSLog("🔮 NativeTabBarController: Flutter set tab to \(index)")
    }

    /// 设置 Tab Bar 是否可见
    private func setTabBarVisible(_ visible: Bool) {
        UIView.animate(withDuration: 0.25) {
            self.tabBar.isHidden = !visible
            self.tabBar.alpha = visible ? 1.0 : 0.0
        }
        NSLog("🔮 NativeTabBarController: Tab bar visibility set to \(visible)")
    }

    // iOS 26+ 的 Liquid Glass 交互效果：
    // 使用独立 UITabBar（非 UITabBarController）时：
    // - 基本的 Liquid Glass 视觉效果 ✅
    // - 选中高亮效果 ✅
    // - 注意：部分高级交互（如长按拖动）可能需要 UITabBarController
}
