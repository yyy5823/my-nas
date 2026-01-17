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

// MARK: - Custom Glass Container View

/// 自定义玻璃容器视图，确保圆角始终正确应用
/// 解决菜单弹出/关闭时圆角闪烁的问题
class GlassContainerView: UIView {
    private let glassView: UIVisualEffectView
    private let cornerRadius: CGFloat
    
    init(cornerRadius: CGFloat, isDark: Bool) {
        self.cornerRadius = cornerRadius
        
        // 创建玻璃效果视图
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect()
            glassEffect.isInteractive = true
            glassView = UIVisualEffectView(effect: glassEffect)
        } else {
            let blurStyle: UIBlurEffect.Style = isDark ? .systemThinMaterialDark : .systemThinMaterialLight
            glassView = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        }
        
        super.init(frame: .zero)
        
        // 设置视图属性
        backgroundColor = .clear
        clipsToBounds = true
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        
        // 设置玻璃视图
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.clipsToBounds = true
        glassView.layer.cornerRadius = cornerRadius
        glassView.layer.cornerCurve = .continuous
        glassView.overrideUserInterfaceStyle = isDark ? .dark : .light
        
        addSubview(glassView)
        
        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var contentView: UIView {
        return glassView.contentView
    }
    
    func updateTheme(isDark: Bool) {
        glassView.overrideUserInterfaceStyle = isDark ? .dark : .light
        
        // 只在非 iOS 26 时更新 blur effect（iOS 26 使用 UIGlassEffect 自动响应主题）
        if #unavailable(iOS 26.0) {
            let blurStyle: UIBlurEffect.Style = isDark ? .systemThinMaterialDark : .systemThinMaterialLight
            glassView.effect = UIBlurEffect(style: blurStyle)
        }
    }
    
    /// 强制在 layout 时重新应用圆角，防止系统重置
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // 确保圆角始终正确应用
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        glassView.layer.cornerRadius = cornerRadius
        glassView.layer.cornerCurve = .continuous
    }
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
    private let glassContainer: GlassContainerView
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
        let cornerRadius = params["cornerRadius"] as? Double ?? 22.0

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

        // 创建自定义玻璃容器（确保圆角始终正确）
        glassContainer = GlassContainerView(cornerRadius: CGFloat(cornerRadius), isDark: isDark)
        glassContainer.translatesAutoresizingMaskIntoConstraints = false
        glassContainer.overrideUserInterfaceStyle = isDark ? .dark : .light

        // 创建按钮堆叠视图
        stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = CGFloat(max(spacing, 8.0))
        stackView.translatesAutoresizingMaskIntoConstraints = false

        super.init()

        // 创建按钮
        for (index, item) in buttonItems.enumerated() {
            let button = createButton(item: item, size: buttonSize, index: index)
            buttons.append(button)
            stackView.addArrangedSubview(button)
        }

        // 设置视图层级
        glassContainer.contentView.addSubview(stackView)
        containerView.addSubview(glassContainer)

        // 设置布局约束
        setupConstraints()

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

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Glass container 填充容器
            glassContainer.topAnchor.constraint(equalTo: containerView.topAnchor),
            glassContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            glassContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            glassContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            // Stack view 在 glass container 内部居中
            stackView.centerYAnchor.constraint(equalTo: glassContainer.contentView.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: glassContainer.contentView.leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: glassContainer.contentView.trailingAnchor, constant: -10)
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
        glassContainer.overrideUserInterfaceStyle = isDark ? .dark : .light
        glassContainer.updateTheme(isDark: isDark)

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
