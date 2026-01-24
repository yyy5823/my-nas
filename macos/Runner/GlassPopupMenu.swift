import Cocoa
import FlutterMacOS

/// macOS 玻璃弹出菜单（顶部悬浮，使用 NSPopover + NSGlassEffectView）
final class GlassPopupMenuPlugin: NSObject, FlutterPlugin, NSPopoverDelegate {
    private weak var registrar: FlutterPluginRegistrar?
    private var pendingResult: FlutterResult?
    private var popover: NSPopover?
    private var hasReturnedResult = false

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.kkape.mynas/glass_popup_menu",
            binaryMessenger: registrar.messenger
        )
        let instance = GlassPopupMenuPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)

        NSLog("🍿 GlassPopupMenuPlugin(macOS): Registered")
    }

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showMenu":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Arguments required", details: nil))
                return
            }
            showMenu(args: args, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func showMenu(args: [String: Any], result: @escaping FlutterResult) {
        let x = args["x"] as? Double ?? 0
        let y = args["y"] as? Double ?? 0
        let screenWidth = args["screenWidth"] as? Double ?? 0
        let screenHeight = args["screenHeight"] as? Double ?? 0
        let isDark = args["isDark"] as? Bool ?? false
        let items = args["items"] as? [[String: Any]] ?? []

        pendingResult = result
        hasReturnedResult = false

        DispatchQueue.main.async { [weak self] in
            self?.presentMenu(
                at: CGPoint(x: x, y: y),
                screenSize: CGSize(width: screenWidth, height: screenHeight),
                items: items,
                isDark: isDark
            )
        }
    }

    private func presentMenu(at point: CGPoint, screenSize: CGSize, items: [[String: Any]], isDark: Bool) {
        guard let window = NSApp.keyWindow ?? NSApplication.shared.windows.first,
              let contentView = window.contentView else {
            pendingResult?(FlutterError(code: "NO_WINDOW", message: "No key window", details: nil))
            pendingResult = nil
            return
        }

        let menuItems: [PopupMenuItem] = items.enumerated().map { index, item in
            PopupMenuItem(
                title: item["title"] as? String ?? "",
                icon: item["icon"] as? String,
                value: item["value"] as? String ?? "\(index)",
                isDestructive: item["isDestructive"] as? Bool ?? false
            )
        }

        let anchorY = screenSize.height > 0 ? screenSize.height - point.y : point.y
        let anchorRect = NSRect(x: point.x, y: anchorY, width: 1, height: 1)

        let menuVC = GlassMenuViewController(
            menuItems: menuItems,
            isDark: isDark,
            onSelect: { [weak self] value in
                guard let self, !self.hasReturnedResult else { return }
                self.hasReturnedResult = true
                self.pendingResult?(value)
                self.pendingResult = nil
                self.popover?.close()
            },
            onDismiss: { [weak self] in
                guard let self, !self.hasReturnedResult else { return }
                self.hasReturnedResult = true
                self.pendingResult?(nil)
                self.pendingResult = nil
                self.popover?.close()
            }
        )

        let pop = NSPopover()
        pop.contentViewController = menuVC
        pop.behavior = .transient
        pop.animates = true
        pop.delegate = self
        popover = pop

        pop.show(relativeTo: anchorRect, of: contentView, preferredEdge: .maxY)
    }

    func popoverDidClose(_ notification: Notification) {
        guard !hasReturnedResult else { return }
        hasReturnedResult = true
        pendingResult?(nil)
        pendingResult = nil
    }
}

private struct PopupMenuItem {
    let title: String
    let icon: String?
    let value: String
    let isDestructive: Bool
}

private final class GlassMenuViewController: NSViewController {
    private let menuItems: [PopupMenuItem]
    private let isDark: Bool
    private let onSelect: (String) -> Void
    private let onDismiss: () -> Void

    init(menuItems: [PopupMenuItem], isDark: Bool, onSelect: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
        self.menuItems = menuItems
        self.isDark = isDark
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.masksToBounds = true
        view.appearance = isDark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)

        let backgroundView: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.translatesAutoresizingMaskIntoConstraints = false
            glass.cornerRadius = 14
            backgroundView = glass
        } else {
            let visual = NSVisualEffectView()
            visual.translatesAutoresizingMaskIntoConstraints = false
            visual.material = .hudWindow
            visual.blendingMode = .withinWindow
            visual.state = .active
            visual.wantsLayer = true
            visual.layer?.cornerRadius = 14
            backgroundView = visual
        }

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for (index, item) in menuItems.enumerated() {
            let row = makeRow(for: item, index: index)
            stackView.addArrangedSubview(row)
        }

        backgroundView.addSubview(stackView)
        view.addSubview(backgroundView)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -10),
            stackView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -8),
        ])
    }

    private func makeRow(for item: PopupMenuItem, index: Int) -> NSView {
        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.title = item.title
        button.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        button.contentTintColor = item.isDestructive
            ? .systemRed
            : (isDark ? .white : NSColor.labelColor)
        button.alignment = .left
        button.target = self
        button.action = #selector(itemTapped(_:))
        button.tag = index
        button.focusRingType = .none

        if let iconName = item.icon,
           let image = NSImage(systemSymbolName: iconName, accessibilityDescription: item.title) {
            image.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imagePosition = .imageLeading
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)

        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            button.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            button.heightAnchor.constraint(equalToConstant: 32),
        ])

        return container
    }

    @objc private func itemTapped(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0 && index < menuItems.count else { return }
        onSelect(menuItems[index].value)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        onDismiss()
    }
}
