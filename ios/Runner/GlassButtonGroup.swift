import Flutter
import UIKit

/// iOS 26 Liquid Glass 按钮组
///
/// 使用原生 UIGlassEffect 实现真正的 iOS 26 玻璃效果
/// 多个按钮组合在同一个胶囊形玻璃背景中
///
/// iOS 26+: 使用 UIGlassEffect
/// iOS 13-25: 使用 UIVisualEffectView + UIBlurEffect 回退

// MARK: - Button Data

struct GlassButtonItem {
    let icon: String       // SF Symbol name
    let tooltip: String?
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

        var items: [GlassButtonItem] = []
        if let itemsData = params["items"] as? [[String: Any]] {
            items = itemsData.map { item in
                GlassButtonItem(
                    icon: item["icon"] as? String ?? "circle",
                    tooltip: item["tooltip"] as? String
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
            // 直接使用 glassEffect 初始化，避免动画块中的捕获问题
            glassView = UIVisualEffectView(effect: glassEffect)
        } else {
            // iOS 13-25 回退
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
        stackView.distribution = .equalSpacing
        stackView.spacing = CGFloat(spacing)

        super.init()

        // 创建按钮
        for (index, item) in items.enumerated() {
            let button = createButton(item: item, size: buttonSize, index: index)
            buttons.append(button)
            stackView.addArrangedSubview(button)

            // 添加分隔线（除了最后一个）
            if index < items.count - 1 {
                let separator = createSeparator()
                stackView.addArrangedSubview(separator)
            }
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

        // 配置图标 - iOS 26 风格使用更大、更清晰的图标
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let image = UIImage(systemName: item.icon, withConfiguration: config)
        button.setImage(image, for: .normal)
        button.tintColor = isDark ? .white : UIColor(white: 0.2, alpha: 1.0)

        // 设置大小 - 增加触摸区域
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: CGFloat(size)),
            button.heightAnchor.constraint(equalToConstant: CGFloat(size))
        ])

        // 添加点击事件
        button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)

        // 添加触觉反馈和按压效果
        if #available(iOS 26.0, *) {
            // iOS 26 的玻璃效果按钮有内置的交互反馈
        }

        // 设置 tooltip（iOS 15+）
        if #available(iOS 15.0, *), let tooltip = item.tooltip {
            button.toolTip = tooltip
        }

        return button
    }

    private func createSeparator() -> UIView {
        let separator = UIView()
        separator.backgroundColor = isDark
            ? UIColor.white.withAlphaComponent(0.15)
            : UIColor.black.withAlphaComponent(0.1)
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalToConstant: 0.5),
            separator.heightAnchor.constraint(equalToConstant: 22)
        ])
        return separator
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

            // Stack view 在 glass view 内部居中，iOS 26 风格更宽松的内边距
            stackView.topAnchor.constraint(equalTo: glassView.contentView.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor, constant: -4),
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
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func updateTheme(isDark: Bool) {
        self.isDark = isDark
        containerView.overrideUserInterfaceStyle = isDark ? .dark : .light
        glassView.overrideUserInterfaceStyle = isDark ? .dark : .light

        // 更新按钮颜色
        for button in buttons {
            button.tintColor = isDark ? .white : .darkGray
        }

        // 更新分隔线颜色
        for view in stackView.arrangedSubviews {
            if !(view is UIButton) {
                view.backgroundColor = isDark
                    ? UIColor.white.withAlphaComponent(0.15)
                    : UIColor.black.withAlphaComponent(0.1)
            }
        }
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        // 触觉反馈
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()

        // 通知 Flutter
        methodChannel?.invokeMethod("onButtonTap", arguments: sender.tag)
    }

    func view() -> UIView {
        return containerView
    }
}

// MARK: - Plugin Registration

class GlassButtonGroupPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = GlassButtonGroupFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "com.kkape.mynas/glass_button_group")

        NSLog("🔮 GlassButtonGroupPlugin: Registered")

        if #available(iOS 26.0, *) {
            NSLog("🔮 GlassButtonGroupPlugin: iOS 26+ - Using UIGlassEffect")
        } else {
            NSLog("🔮 GlassButtonGroupPlugin: iOS < 26 - Using UIBlurEffect fallback")
        }
    }
}
