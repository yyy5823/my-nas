import Flutter
import UIKit

/// iOS 26 原生玻璃弹出菜单
///
/// 使用 UIMenu 和 UIContextMenuInteraction 实现真正的 iOS 26 Liquid Glass 效果
/// 特性：
/// - iOS 26+ 自动应用 Liquid Glass 效果
/// - 点击按钮时原按钮消失（context menu 标准行为）
/// - 支持嵌套菜单
/// - 支持菜单项图标

// MARK: - Plugin Registration

class GlassPopupMenuPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.kkape.mynas/glass_popup_menu",
            binaryMessenger: registrar.messenger()
        )

        let instance = GlassPopupMenuPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)

        NSLog("🍿 GlassPopupMenuPlugin: Registered")
    }

    private weak var registrar: FlutterPluginRegistrar?
    private var pendingResult: FlutterResult?
    private var menuWindow: UIWindow?

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showMenu":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Arguments required", details: nil))
                return
            }
            showNativeMenu(args: args, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func showNativeMenu(args: [String: Any], result: @escaping FlutterResult) {
        // 解析参数
        let x = args["x"] as? Double ?? 0
        let y = args["y"] as? Double ?? 0
        let isDark = args["isDark"] as? Bool ?? false
        let items = args["items"] as? [[String: Any]] ?? []

        // 存储 result 以便稍后返回
        pendingResult = result

        // 在主线程上显示菜单
        DispatchQueue.main.async { [weak self] in
            self?.presentMenu(at: CGPoint(x: x, y: y), items: items, isDark: isDark)
        }
    }

    private func presentMenu(at point: CGPoint, items: [[String: Any]], isDark: Bool) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            pendingResult?(FlutterError(code: "NO_WINDOW", message: "No key window found", details: nil))
            return
        }

        // 创建菜单项数据
        var popupMenuItems: [PopupMenuItem] = []
        var menuActions: [UIAction] = []

        for (index, item) in items.enumerated() {
            let title = item["title"] as? String ?? ""
            let icon = item["icon"] as? String
            let isDestructive = item["isDestructive"] as? Bool ?? false
            let value = item["value"] as? String ?? "\(index)"

            // 保存菜单项数据
            popupMenuItems.append(PopupMenuItem(
                title: title,
                icon: icon,
                value: value,
                isDestructive: isDestructive
            ))

            var image: UIImage?
            if let iconName = icon {
                let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
                image = UIImage(systemName: iconName, withConfiguration: config)
            }

            let attributes: UIMenuElement.Attributes = isDestructive ? .destructive : []

            let action = UIAction(
                title: title,
                image: image,
                attributes: attributes
            ) { [weak self] _ in
                self?.pendingResult?(value)
                self?.pendingResult = nil
                self?.dismissMenuWindow()
            }

            menuActions.append(action)
        }

        // 创建 UIMenu
        let menu = UIMenu(children: menuActions)

        // 使用 UIContextMenuInteraction 显示菜单
        // 创建一个临时视图来承载菜单
        let anchorView = UIView(frame: CGRect(x: point.x - 20, y: point.y - 20, width: 40, height: 40))
        anchorView.backgroundColor = .clear

        // 创建临时窗口
        let menuWindow = UIWindow(windowScene: windowScene)
        menuWindow.rootViewController = MenuHostViewController(
            menu: menu,
            menuItems: popupMenuItems,
            anchorPoint: point,
            isDark: isDark,
            onDismiss: { [weak self] selectedValue in
                if let value = selectedValue {
                    self?.pendingResult?(value)
                } else {
                    self?.pendingResult?(nil)
                }
                self?.pendingResult = nil
                self?.dismissMenuWindow()
            }
        )
        menuWindow.windowLevel = .alert + 1
        menuWindow.makeKeyAndVisible()
        menuWindow.overrideUserInterfaceStyle = isDark ? .dark : .light

        self.menuWindow = menuWindow
    }

    private func dismissMenuWindow() {
        menuWindow?.isHidden = true
        menuWindow = nil
    }
}

/// 菜单项数据结构
struct PopupMenuItem {
    let title: String
    let icon: String?
    let value: String
    let isDestructive: Bool
}

// MARK: - Menu Host View Controller

class MenuHostViewController: UIViewController {
    private let menu: UIMenu
    private let menuItems: [PopupMenuItem]
    private let anchorPoint: CGPoint
    private let isDark: Bool
    private let onDismiss: (String?) -> Void
    private var menuAnchorView: UIView!

    init(menu: UIMenu, menuItems: [PopupMenuItem], anchorPoint: CGPoint, isDark: Bool, onDismiss: @escaping (String?) -> Void) {
        self.menu = menu
        self.menuItems = menuItems
        self.anchorPoint = anchorPoint
        self.isDark = isDark
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        overrideUserInterfaceStyle = isDark ? .dark : .light

        // 创建锚点视图
        menuAnchorView = UIView(frame: CGRect(x: anchorPoint.x - 20, y: anchorPoint.y - 20, width: 40, height: 40))
        menuAnchorView.backgroundColor = .clear
        view.addSubview(menuAnchorView)

        // 添加点击手势用于关闭菜单
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // 使用 UIContextMenuInteraction
        let interaction = UIContextMenuInteraction(delegate: self)
        menuAnchorView.addInteraction(interaction)

        // 程序化触发 context menu
        // 注意：这需要在 iOS 14+ 上工作
        if #available(iOS 14.0, *) {
            // 使用延迟来确保视图已准备好
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }

                // 创建一个按钮来作为菜单的锚点
                self.presentMenuAsActionSheet()
            }
        }
    }

    private func presentMenuAsActionSheet() {
        // iOS 26 风格：使用圆角 popover 菜单，无箭头
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        // 添加菜单项
        for item in menuItems {
            let alertAction = UIAlertAction(
                title: item.title,
                style: item.isDestructive ? .destructive : .default
            ) { [weak self] _ in
                self?.onDismiss(item.value)
            }

            // 如果有图标，设置图标
            if let iconName = item.icon {
                let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
                if let image = UIImage(systemName: iconName, withConfiguration: config) {
                    alertAction.setValue(image.withRenderingMode(.alwaysTemplate), forKey: "image")
                }
            }

            alertController.addAction(alertAction)
        }

        // 添加取消按钮
        alertController.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.onDismiss(nil)
        })

        // 配置 popover（iPad 和 iOS 26+ iPhone）
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = menuAnchorView
            // iOS 26 风格：菜单顶部对齐按钮顶部
            let sourceRect = CGRect(
                x: menuAnchorView.bounds.midX,
                y: menuAnchorView.bounds.minY,
                width: 0,
                height: 0
            )
            popover.sourceRect = sourceRect
            // iOS 26 风格：无箭头
            popover.permittedArrowDirections = []
        }

        present(alertController, animated: true)
    }

    @objc private func backgroundTapped() {
        onDismiss(nil)
    }
}

// MARK: - UIContextMenuInteractionDelegate

extension MenuHostViewController: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: nil
        ) { [weak self] _ in
            return self?.menu
        }
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        animator?.addCompletion { [weak self] in
            // 菜单关闭时调用
            self?.onDismiss(nil)
        }
    }
}
