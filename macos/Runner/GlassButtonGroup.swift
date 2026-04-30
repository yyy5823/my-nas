import Cocoa
import FlutterMacOS

/// macOS 版 Liquid Glass 按钮组
///
/// 使用 NSGlassEffectView (macOS 26+) 提供原生水滴玻璃效果
/// 旧系统回退到 NSVisualEffectView
struct MacGlassButtonItem {
    let icon: String
    let tooltip: String?
}

final class GlassButtonGroupFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withViewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> NSView {
        return GlassButtonGroupPlatformView(
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

final class GlassButtonGroupPlatformView: NSView {
    private let glassView: NSView
    private let stackView: NSStackView
    private var buttons: [NSButton] = []
    private var methodChannel: FlutterMethodChannel?
    private let viewId: Int64
    private var isDark: Bool

    init(
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        self.viewId = viewId

        let params = args as? [String: Any] ?? [:]
        isDark = params["isDark"] as? Bool ?? false
        let buttonSize = params["buttonSize"] as? Double ?? 36.0
        let spacing = params["spacing"] as? Double ?? 0.0
        let cornerRadius = params["cornerRadius"] as? Double ?? 20.0

        var items: [MacGlassButtonItem] = []
        if let itemsData = params["items"] as? [[String: Any]] {
            items = itemsData.map { item in
                MacGlassButtonItem(
                    icon: item["icon"] as? String ?? "circle",
                    tooltip: item["tooltip"] as? String
                )
            }
        }

        // 玻璃背景。使用 NSClassFromString 运行时查找 NSGlassEffectView，避免编译期
        // 依赖 macOS 26 SDK（CI 上的 Xcode 15 等老版本仍能编译）。
        var resolvedGlass: NSView? = nil
        if #available(macOS 26.0, *),
           let cls = NSClassFromString("NSGlassEffectView") as? NSObject.Type,
           let glass = cls.init() as? NSView {
            glass.translatesAutoresizingMaskIntoConstraints = false
            glass.setValue(CGFloat(cornerRadius), forKey: "cornerRadius")
            resolvedGlass = glass
        }
        if let glass = resolvedGlass {
            glassView = glass
        } else {
            let visualEffect = NSVisualEffectView()
            visualEffect.translatesAutoresizingMaskIntoConstraints = false
            visualEffect.material = .hudWindow
            visualEffect.blendingMode = .withinWindow
            visualEffect.state = .active
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = CGFloat(cornerRadius)
            glassView = visualEffect
        }

        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = CGFloat(cornerRadius)
        glassView.layer?.masksToBounds = true

        stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = CGFloat(max(spacing, 8.0))
        stackView.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)

        self.wantsLayer = true
        self.layer?.masksToBounds = false
        self.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)

        // 创建按钮
        for (index, item) in items.enumerated() {
            let button = createButton(item: item, size: buttonSize, index: index)
            buttons.append(button)
            stackView.addArrangedSubview(button)
        }

        glassView.addSubview(stackView)
        self.addSubview(glassView)

        setupConstraints(cornerRadius: cornerRadius)

        if let messenger {
            setupMethodChannel(messenger: messenger)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func createButton(item: MacGlassButtonItem, size: Double, index: Int) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.imagePosition = .imageOnly
        button.focusRingType = .none
        button.tag = index

        if let image = NSImage(
            systemSymbolName: item.icon,
            accessibilityDescription: item.tooltip
        ) {
            image.size = NSSize(width: size * 0.55, height: size * 0.55)
            button.image = image
        }

        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: CGFloat(size)),
            button.heightAnchor.constraint(equalToConstant: CGFloat(size))
        ])

        button.target = self
        button.action = #selector(buttonTapped(_:))
        button.contentTintColor = isDark ? .white : NSColor(white: 0.2, alpha: 1.0)

        if #available(macOS 11.0, *), let tooltip = item.tooltip {
            button.toolTip = tooltip
        }

        return button
    }

    private func setupConstraints(cornerRadius: Double) {
        glassView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: self.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: self.trailingAnchor),

            stackView.topAnchor.constraint(equalTo: glassView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
        ])

        self.layer?.cornerRadius = CGFloat(cornerRadius)
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
        let newAppearance: NSAppearance? = isDark
            ? NSAppearance(named: .darkAqua)
            : NSAppearance(named: .aqua)

        self.appearance = newAppearance
        // appearance 是 NSView 上的属性，无论是 NSGlassEffectView 还是 NSVisualEffectView
        // 都可以直接设置，无需向下转型。
        glassView.appearance = newAppearance

        buttons.forEach { $0.contentTintColor = isDark ? .white : NSColor(white: 0.2, alpha: 1.0) }
    }

    @objc private func buttonTapped(_ sender: NSButton) {
        methodChannel?.invokeMethod("onButtonTap", arguments: sender.tag)
    }
}

final class GlassButtonGroupPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = GlassButtonGroupFactory(messenger: registrar.messenger)
        registrar.register(factory, withId: "com.kkape.mynas/glass_button_group")

        NSLog("🔮 GlassButtonGroupPlugin(macOS): Registered")
    }
}
