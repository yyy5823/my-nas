import Flutter
import UIKit

/// iOS 26 Liquid Glass 按钮组
///
/// 使用原生 UIGlassEffect 实现真正的 iOS 26 玻璃效果
/// 多个按钮组合在同一个胶囊形玻璃背景中
///
/// iOS 26+: 使用 UIGlassEffect
/// iOS 13-25: 使用 UIVisualEffectView + UIBlurEffect 回退
///
/// 对于弹出菜单按钮：
/// - iOS 14+: 使用原生 UIButton.menu + showsMenuAsPrimaryAction，点击即弹出原生菜单
/// - iOS 13: 使用 UIContextMenuInteraction
/// - iOS < 13: 通过 MethodChannel 回退到 Flutter 弹窗

// MARK: - Button Data

struct GlassButtonItem {
    let icon: String       // SF Symbol name
    let tooltip: String?
    let isMenuButton: Bool
    let menuItems: [GlassMenuItem]
}

struct GlassMenuItem {
    let title: String
    let icon: String?
    let value: String
    let isDestructive: Bool
}

// MARK: - Platform View Factory

class GlassButtonGroupFactory: NSObject, FlutterPlatformViewFactory {
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
        return GlassButtonGroupPlatformView(
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

class GlassButtonGroupPlatformView: NSObject, FlutterPlatformView {
    private let containerView: UIView
    private let glassView: UIVisualEffectView
    private let stackView: UIStackView
    private var buttons: [UIButton] = []
    private var methodChannel: FlutterMethodChannel?
    private let viewId: Int64
    private var isDark: Bool
    private var buttonItems: [GlassButtonItem] = []

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        self.viewId = viewId

        // 解析参数
        let params = args as? [String: Any] ?? [:]
        isDark = params["isDark"] as? Bool ?? false
        let buttonSize = params["buttonSize"] as? Double ?? 36.0
        let spacing = params["spacing"] as? Double ?? 0.0
        let cornerRadius = params["cornerRadius"] as? Double ?? 20.0

        // 解析按钮数据
        if let itemsData = params["items"] as? [[String: Any]] {
            buttonItems = itemsData.map { item in
                var menuItems: [GlassMenuItem] = []
                if let menuData = item["menuItems"] as? [[String: Any]] {
                    menuItems = menuData.map { menuItem in
                        GlassMenuItem(
                            title: menuItem["title"] as? String ?? "",
                            icon: menuItem["icon"] as? String,
                            value: menuItem["value"] as? String ?? "",
                            isDestructive: menuItem["isDestructive"] as? Bool ?? false
                        )
                    }
                }
                return GlassButtonItem(
                    icon: item["icon"] as? String ?? "circle",
                    tooltip: item["tooltip"] as? String,
                    isMenuButton: item["isMenuButton"] as? Bool ?? false,
                    menuItems: menuItems
                )
            }
        }

        // 创建容器
        containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.overrideUserInterfaceStyle = isDark ? .dark : .light

        // 创建玻璃效果视图
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect()
            glassEffect.isInteractive = true
            glassView = UIVisualEffectView(effect: glassEffect)
        } else {
            let blurStyle: UIBlurEffect.Style = isDark ? .systemThinMaterialDark : .systemThinMaterialLight
            glassView = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        }

        glassView.layer.cornerRadius = CGFloat(cornerRadius)
        glassView.layer.cornerCurve = .continuous
        glassView.clipsToBounds = true
        glassView.overrideUserInterfaceStyle = isDark ? .dark : .light

        // 创建按钮堆叠视图
        stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = CGFloat(max(spacing, 8.0))

        super.init()

        // 创建按钮
        for (index, item) in buttonItems.enumerated() {
            let button = createButton(item: item, size: buttonSize, index: index)
            buttons.append(button)
            stackView.addArrangedSubview(button)
        }

        // 设置视图层级
        glassView.contentView.addSubview(stackView)
        containerView.addSubview(glassView)

        // 设置布局约束
        setupConstraints(buttonSize: buttonSize, cornerRadius: cornerRadius)

        // 设置 Method Channel
        if let messenger = messenger {
            setupMethodChannel(messenger: messenger)
        }
    }

    private func createButton(item: GlassButtonItem, size: Double, index: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = index

        // 配置图标
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let image = UIImage(systemName: item.icon, withConfiguration: config)
        button.setImage(image, for: .normal)
        button.tintColor = isDark ? .white : UIColor(white: 0.2, alpha: 1.0)

        // 设置大小 - 使用较低优先级避免约束冲突
        button.translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = button.widthAnchor.constraint(equalToConstant: CGFloat(size))
        let heightConstraint = button.heightAnchor.constraint(equalToConstant: CGFloat(size))
        widthConstraint.priority = .defaultHigh
        heightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])

        // 如果是菜单按钮，配置原生 UIMenu
        if item.isMenuButton && !item.menuItems.isEmpty {
            configureNativeMenu(for: button, items: item.menuItems, index: index)
        } else {
            // 普通按钮 - 添加点击事件
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        }

        // 设置 tooltip（iOS 15+）
        if #available(iOS 15.0, *), let tooltip = item.tooltip {
            button.toolTip = tooltip
        }

        return button
    }

    /// 配置原生 UIMenu - iOS 14+ 系统会自动应用 Liquid Glass 样式
    private func configureNativeMenu(for button: UIButton, items: [GlassMenuItem], index: Int) {
        if #available(iOS 14.0, *) {
            // iOS 14+: 使用原生 UIButton.menu，点击即弹出
            // 系统会自动应用 iOS 26 Liquid Glass 样式
            let actions = items.map { item -> UIAction in
                var image: UIImage?
                if let iconName = item.icon {
                    let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                    image = UIImage(systemName: iconName, withConfiguration: config)
                }

                return UIAction(
                    title: item.title,
                    image: image,
                    attributes: item.isDestructive ? .destructive : [],
                    handler: { [weak self] _ in
                        NSLog("🍿 GlassButtonGroup: Native menu selected: \(item.value)")
                        self?.methodChannel?.invokeMethod("onMenuItemSelected", arguments: [
                            "buttonIndex": index,
                            "value": item.value
                        ])
                    }
                )
            }

            let menu = UIMenu(title: "", children: actions)
            button.menu = menu
            button.showsMenuAsPrimaryAction = true  // 点击即显示菜单，无需长按

            NSLog("🍿 GlassButtonGroup: Configured native UIMenu for button \(index) with \(items.count) items")
        } else {
            // iOS 13: 使用 UIContextMenuInteraction
            let interaction = UIContextMenuInteraction(delegate: self)
            button.addInteraction(interaction)
            // 也添加点击事件作为回退
            button.addTarget(self, action: #selector(menuButtonTapped(_:)), for: .touchUpInside)
        }
    }

    private func setupConstraints(buttonSize: Double, cornerRadius: Double) {
        glassView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Glass view 填充容器
            glassView.topAnchor.constraint(equalTo: containerView.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            // Stack view 在 glass view 内部居中
            stackView.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -10)
        ])
    }

    private func setupMethodChannel(messenger: FlutterBinaryMessenger) {
        let channelName = "com.kkape.mynas/glass_button_group_\(viewId)"
        methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)

        methodChannel?.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "updateTheme":
                if let isDark = call.arguments as? Bool {
                    self?.updateTheme(isDark: isDark)
                }
                result(nil)
            case "updateMenuItems":
                if let args = call.arguments as? [String: Any],
                   let buttonIndex = args["buttonIndex"] as? Int,
                   let menuData = args["items"] as? [[String: Any]] {
                    self?.updateMenuItems(at: buttonIndex, items: menuData)
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func updateMenuItems(at buttonIndex: Int, items: [[String: Any]]) {
        guard buttonIndex >= 0 && buttonIndex < buttons.count else { return }

        let menuItems = items.map { item in
            GlassMenuItem(
                title: item["title"] as? String ?? "",
                icon: item["icon"] as? String,
                value: item["value"] as? String ?? "",
                isDestructive: item["isDestructive"] as? Bool ?? false
            )
        }

        if #available(iOS 14.0, *) {
            let button = buttons[buttonIndex]
            let actions = menuItems.map { item -> UIAction in
                var image: UIImage?
                if let iconName = item.icon {
                    let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                    image = UIImage(systemName: iconName, withConfiguration: config)
                }

                return UIAction(
                    title: item.title,
                    image: image,
                    attributes: item.isDestructive ? .destructive : [],
                    handler: { [weak self] _ in
                        self?.methodChannel?.invokeMethod("onMenuItemSelected", arguments: [
                            "buttonIndex": buttonIndex,
                            "value": item.value
                        ])
                    }
                )
            }
            button.menu = UIMenu(title: "", children: actions)
        }

        // 同时更新本地存储的菜单项
        if buttonIndex < buttonItems.count {
            buttonItems[buttonIndex] = GlassButtonItem(
                icon: buttonItems[buttonIndex].icon,
                tooltip: buttonItems[buttonIndex].tooltip,
                isMenuButton: true,
                menuItems: menuItems
            )
        }
    }

    private func updateTheme(isDark: Bool) {
        self.isDark = isDark
        containerView.overrideUserInterfaceStyle = isDark ? .dark : .light
        glassView.overrideUserInterfaceStyle = isDark ? .dark : .light

        for button in buttons {
            button.tintColor = isDark ? .white : UIColor(white: 0.2, alpha: 1.0)
        }
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        methodChannel?.invokeMethod("onButtonTap", arguments: sender.tag)
    }

    @objc private func menuButtonTapped(_ sender: UIButton) {
        // iOS 13 回退: 通知 Flutter 显示菜单
        let index = sender.tag
        methodChannel?.invokeMethod("onMenuButtonTap", arguments: index)
    }

    func view() -> UIView {
        return containerView
    }
}

// MARK: - UIContextMenuInteractionDelegate (iOS 13 fallback)

extension GlassButtonGroupPlatformView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let button = interaction.view as? UIButton else { return nil }
        let index = button.tag
        guard index >= 0 && index < buttonItems.count else { return nil }

        let item = buttonItems[index]
        guard item.isMenuButton else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let actions = item.menuItems.map { menuItem -> UIAction in
                var image: UIImage?
                if let iconName = menuItem.icon {
                    let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                    image = UIImage(systemName: iconName, withConfiguration: config)
                }

                return UIAction(
                    title: menuItem.title,
                    image: image,
                    attributes: menuItem.isDestructive ? .destructive : [],
                    handler: { _ in
                        self?.methodChannel?.invokeMethod("onMenuItemSelected", arguments: [
                            "buttonIndex": index,
                            "value": menuItem.value
                        ])
                    }
                )
            }
            return UIMenu(title: "", children: actions)
        }
    }
}

// MARK: - Plugin Registration

class GlassButtonGroupPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = GlassButtonGroupFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "com.kkape.mynas/glass_button_group")

        NSLog("🔮 GlassButtonGroupPlugin: Registered")

        if #available(iOS 26.0, *) {
            NSLog("🔮 GlassButtonGroupPlugin: iOS 26+ - Using UIGlassEffect with native menus")
        } else if #available(iOS 14.0, *) {
            NSLog("🔮 GlassButtonGroupPlugin: iOS 14+ - Using native UIButton.menu")
        } else {
            NSLog("🔮 GlassButtonGroupPlugin: iOS < 14 - Using UIContextMenuInteraction fallback")
        }
    }
}
