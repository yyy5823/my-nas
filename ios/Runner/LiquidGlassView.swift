import Flutter
import UIKit

/// iOS 26 Liquid Glass 原生视图
///
/// 使用 UIKit 的 UIGlassEffect + UIVisualEffectView 实现真正的 Liquid Glass 效果
/// 这是 WWDC25 推荐的 UIKit 实现方式
///
/// iOS 26+: 使用原生 UIGlassEffect API
/// iOS < 26: 回退到 UIBlurEffect

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
    private let containerView: UIView
    private var glassEffectView: UIVisualEffectView?
    private var glassContainerView: UIVisualEffectView?
    private let viewId: Int64
    private let messenger: FlutterBinaryMessenger?
    private var methodChannel: FlutterMethodChannel?

    // 当前状态
    private var currentSelectedIndex: Int = 0
    private var items: [LiquidGlassNavItem] = []
    private var viewType: String = "navBar"
    private var isDark: Bool = false
    private var cornerRadius: CGFloat = 30
    private var isInteractive: Bool = true

    // UI 元素
    private var navButtons: [UIView] = []

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        self.viewId = viewId
        self.messenger = messenger
        containerView = UIView(frame: frame)
        containerView.backgroundColor = .clear
        containerView.clipsToBounds = false

        super.init()

        NSLog("🔮 LiquidGlassView: init with frame: \(frame), viewId: \(viewId)")
        NSLog("🔮 LiquidGlassView: iOS version: \(UIDevice.current.systemVersion)")

        // 解析参数
        parseArguments(args)

        // 设置 Method Channel
        setupMethodChannel()

        // 创建视图
        setupView()
    }

    func view() -> UIView {
        return containerView
    }

    private func parseArguments(_ args: Any?) {
        guard let params = args as? [String: Any] else { return }

        viewType = params["viewType"] as? String ?? "navBar"
        isDark = params["isDark"] as? Bool ?? false
        currentSelectedIndex = params["selectedIndex"] as? Int ?? 0
        cornerRadius = CGFloat(params["cornerRadius"] as? Double ?? 30)
        isInteractive = params["isInteractive"] as? Bool ?? true

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

    private func setupMethodChannel() {
        guard let messenger = messenger else { return }

        let channelName = "com.kkape.mynas/liquid_glass_view_\(viewId)"
        methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)

        methodChannel?.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "updateSelectedIndex":
                if let index = call.arguments as? Int {
                    self?.updateSelectedIndex(index)
                }
                result(nil)
            case "updateItems":
                if let itemsData = call.arguments as? [[String: Any]] {
                    self?.updateItems(itemsData)
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func setupView() {
        // 移除所有子视图
        containerView.subviews.forEach { $0.removeFromSuperview() }
        glassEffectView = nil
        glassContainerView = nil
        navButtons.removeAll()

        NSLog("🔮 LiquidGlassView: setupView - viewType: \(viewType), iOS 26+: \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26)")

        if #available(iOS 26.0, *) {
            NSLog("🔮 LiquidGlassView: Using UIGlassEffect (iOS 26+)")
            setupUIKitLiquidGlassView()
        } else {
            NSLog("🔮 LiquidGlassView: Using UIBlurEffect fallback")
            setupFallbackView()
        }
    }

    // MARK: - iOS 26+ UIKit Liquid Glass Implementation

    @available(iOS 26.0, *)
    private func setupUIKitLiquidGlassView() {
        switch viewType {
        case "navBar":
            setupNavBarWithGlassEffect()
        case "card":
            setupCardWithGlassEffect()
        case "sheet":
            setupSheetWithGlassEffect()
        default:
            setupCardWithGlassEffect()
        }
    }

    @available(iOS 26.0, *)
    private func setupNavBarWithGlassEffect() {
        // 创建 Glass Container (用于多个玻璃元素的容器)
        let containerEffect = UIGlassContainerEffect()
        containerEffect.spacing = 20
        let containerEffectView = UIVisualEffectView(effect: containerEffect)
        containerEffectView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(containerEffectView)

        NSLayoutConstraint.activate([
            containerEffectView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            containerEffectView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            containerEffectView.topAnchor.constraint(equalTo: containerView.topAnchor),
            containerEffectView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        glassContainerView = containerEffectView

        // 创建主玻璃效果视图
        let glassEffect = UIGlassEffect()
        glassEffect.isInteractive = isInteractive

        let effectView = UIVisualEffectView(effect: nil)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        // 设置圆角 - iOS 26 使用 cornerConfiguration
        effectView.layer.cornerRadius = cornerRadius
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
        containerEffectView.contentView.addSubview(effectView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: containerEffectView.contentView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: containerEffectView.contentView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: containerEffectView.contentView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: containerEffectView.contentView.bottomAnchor),
        ])

        glassEffectView = effectView

        // 添加导航按钮
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false

        effectView.contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor, constant: -8),
        ])

        for (index, item) in items.enumerated() {
            let button = createNavButton(item: item, index: index)
            stackView.addArrangedSubview(button)
            navButtons.append(button)
        }

        // 使用动画应用玻璃效果 (materialize animation)
        UIView.animate(withDuration: 0.3) {
            effectView.effect = glassEffect
        }

        // 添加阴影
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.15
        containerView.layer.shadowOffset = CGSize(width: 0, height: 10)
        containerView.layer.shadowRadius = 20

        NSLog("🔮 LiquidGlassView: NavBar with UIGlassEffect created successfully")
    }

    @available(iOS 26.0, *)
    private func setupCardWithGlassEffect() {
        let glassEffect = UIGlassEffect()
        glassEffect.isInteractive = isInteractive

        let effectView = UIVisualEffectView(effect: nil)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.layer.cornerRadius = cornerRadius
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
        containerView.addSubview(effectView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: containerView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        glassEffectView = effectView

        UIView.animate(withDuration: 0.3) {
            effectView.effect = glassEffect
        }
    }

    @available(iOS 26.0, *)
    private func setupSheetWithGlassEffect() {
        let glassEffect = UIGlassEffect()

        let effectView = UIVisualEffectView(effect: nil)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        // 只有顶部圆角
        effectView.layer.cornerRadius = cornerRadius
        effectView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
        containerView.addSubview(effectView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: containerView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        glassEffectView = effectView

        UIView.animate(withDuration: 0.3) {
            effectView.effect = glassEffect
        }
    }

    // MARK: - Navigation Button Creation

    private func createNavButton(item: LiquidGlassNavItem, index: Int) -> UIView {
        let container = UIView()
        container.tag = index

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let isSelected = index == currentSelectedIndex
        let iconName = isSelected ? item.selectedIcon : item.icon

        let imageView = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        imageView.image = UIImage(systemName: iconName, withConfiguration: config)
        imageView.tintColor = isSelected ? .label : .secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalToConstant: 24)
        ])

        let label = UILabel()
        label.text = item.label
        label.font = .systemFont(ofSize: 10, weight: isSelected ? .semibold : .regular)
        label.textColor = isSelected ? .label : .secondaryLabel
        label.textAlignment = .center

        stack.addArrangedSubview(imageView)
        stack.addArrangedSubview(label)

        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        // 添加点击手势
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleNavTapGesture(_:)))
        container.addGestureRecognizer(tap)
        container.isUserInteractionEnabled = true

        return container
    }

    @objc private func handleNavTapGesture(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view else { return }
        handleNavTap(view.tag)
    }

    private func handleNavTap(_ index: Int) {
        guard index != currentSelectedIndex else { return }

        currentSelectedIndex = index

        // 通知 Flutter
        methodChannel?.invokeMethod("onNavTap", arguments: index)

        // 更新按钮状态
        updateNavButtonStates()
    }

    private func updateNavButtonStates() {
        for (index, button) in navButtons.enumerated() {
            guard let stack = button.subviews.first as? UIStackView,
                  let imageView = stack.arrangedSubviews.first as? UIImageView,
                  let label = stack.arrangedSubviews.last as? UILabel else { continue }

            let isSelected = index == currentSelectedIndex
            let item = items[index]
            let iconName = isSelected ? item.selectedIcon : item.icon

            UIView.animate(withDuration: 0.2) {
                let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
                imageView.image = UIImage(systemName: iconName, withConfiguration: config)
                imageView.tintColor = isSelected ? .label : .secondaryLabel
                label.font = .systemFont(ofSize: 10, weight: isSelected ? .semibold : .regular)
                label.textColor = isSelected ? .label : .secondaryLabel
            }
        }
    }

    private func updateSelectedIndex(_ index: Int) {
        guard index != currentSelectedIndex else { return }
        currentSelectedIndex = index
        updateNavButtonStates()
    }

    private func updateItems(_ itemsData: [[String: Any]]) {
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
        setupView()
    }

    // MARK: - Fallback View (iOS < 26)

    private func setupFallbackView() {
        let blurEffect = UIBlurEffect(style: isDark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)
        let effectView = UIVisualEffectView(effect: blurEffect)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.layer.cornerRadius = cornerRadius
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true

        // 阴影容器
        let shadowView = UIView()
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.backgroundColor = .clear
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = 0.15
        shadowView.layer.shadowOffset = CGSize(width: 0, height: 10)
        shadowView.layer.shadowRadius = 20

        containerView.addSubview(shadowView)
        shadowView.addSubview(effectView)

        NSLayoutConstraint.activate([
            shadowView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            shadowView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            shadowView.topAnchor.constraint(equalTo: containerView.topAnchor),
            shadowView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: shadowView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: shadowView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: shadowView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: shadowView.bottomAnchor),
        ])

        // 添加高光边框
        effectView.layer.borderWidth = 0.5
        effectView.layer.borderColor = (isDark
            ? UIColor.white.withAlphaComponent(0.2)
            : UIColor.black.withAlphaComponent(0.1)).cgColor

        glassEffectView = effectView

        // 如果是导航栏，添加按钮
        if viewType == "navBar" {
            let stackView = UIStackView()
            stackView.axis = .horizontal
            stackView.distribution = .fillEqually
            stackView.alignment = .center
            stackView.translatesAutoresizingMaskIntoConstraints = false

            effectView.contentView.addSubview(stackView)

            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
                stackView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
                stackView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
            ])

            for (index, item) in items.enumerated() {
                let button = createNavButton(item: item, index: index)
                stackView.addArrangedSubview(button)
                navButtons.append(button)
            }
        }
    }
}

// MARK: - Plugin Registration

class LiquidGlassPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = LiquidGlassViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "com.kkape.mynas/liquid_glass_view")

        NSLog("🔮 LiquidGlassPlugin: Registered")

        if #available(iOS 26.0, *) {
            NSLog("🔮 LiquidGlassPlugin: UIGlassEffect available")
        } else {
            NSLog("🔮 LiquidGlassPlugin: UIGlassEffect NOT available")
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
