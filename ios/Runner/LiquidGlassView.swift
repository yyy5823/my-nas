import Flutter
import UIKit
import SwiftUI

/// iOS 26 Liquid Glass 原生视图
///
/// 实现真正的 iOS 26 Liquid Glass 效果：
/// - 透明背景
/// - 只有选中的 tab 有玻璃效果
/// - 玻璃块可以在 tab 之间变形移动
/// - 支持长按拖动切换

// MARK: - Navigation Bar Item

struct LiquidGlassNavItem: Identifiable {
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
    private var hostingController: UIViewController?
    private let viewId: Int64
    private let messenger: FlutterBinaryMessenger?
    private var methodChannel: FlutterMethodChannel?

    // 当前状态
    private var currentSelectedIndex: Int = 0
    private var items: [LiquidGlassNavItem] = []
    private var viewType: String = "navBar"
    private var isDark: Bool = false

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

        NSLog("🔮 LiquidGlassView: Parsed \(items.count) items, selectedIndex: \(currentSelectedIndex)")
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
        // 移除旧视图
        containerView.subviews.forEach { $0.removeFromSuperview() }
        hostingController?.view.removeFromSuperview()
        hostingController = nil

        NSLog("🔮 LiquidGlassView: setupView - viewType: \(viewType)")

        if #available(iOS 26.0, *) {
            NSLog("🔮 LiquidGlassView: Using SwiftUI with GlassEffectContainer (iOS 26+)")
            setupSwiftUIView()
        } else {
            NSLog("🔮 LiquidGlassView: Using UIKit fallback")
            setupFallbackView()
        }
    }

    // MARK: - iOS 26+ SwiftUI Implementation

    @available(iOS 26.0, *)
    private func setupSwiftUIView() {
        let navBarView = LiquidGlassNavBarView(
            items: items,
            selectedIndex: currentSelectedIndex,
            onTap: { [weak self] index in
                self?.handleNavTap(index)
            }
        )

        let hostingController = UIHostingController(rootView: navBarView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        self.hostingController = hostingController

        NSLog("🔮 LiquidGlassView: SwiftUI NavBar created successfully")
    }

    private func handleNavTap(_ index: Int) {
        NSLog("🔮 LiquidGlassView: handleNavTap called with index: \(index)")
        guard index != currentSelectedIndex else {
            NSLog("🔮 LiquidGlassView: Same index, ignoring tap")
            return
        }

        currentSelectedIndex = index

        // 通知 Flutter
        NSLog("🔮 LiquidGlassView: Invoking Flutter method 'onNavTap' with index: \(index)")
        methodChannel?.invokeMethod("onNavTap", arguments: index)
    }

    private func updateSelectedIndex(_ index: Int) {
        guard index != currentSelectedIndex else { return }
        currentSelectedIndex = index
        // 重新创建视图以更新选中状态
        setupView()
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
        effectView.layer.cornerRadius = 35
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true

        containerView.addSubview(effectView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: containerView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        // 添加导航按钮
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
            let button = createFallbackNavButton(item: item, index: index)
            stackView.addArrangedSubview(button)
        }
    }

    private func createFallbackNavButton(item: LiquidGlassNavItem, index: Int) -> UIView {
        let container = UIView()
        container.tag = index
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false

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
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleFallbackTap(_:)))
        container.addGestureRecognizer(tap)
        container.isUserInteractionEnabled = true

        return container
    }

    @objc private func handleFallbackTap(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view else { return }
        handleNavTap(view.tag)
    }
}

// MARK: - SwiftUI Views

@available(iOS 26.0, *)
struct LiquidGlassNavBarView: View {
    let items: [LiquidGlassNavItem]
    let selectedIndex: Int
    let onTap: (Int) -> Void

    @Namespace private var namespace
    @State private var draggedIndex: Int?
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    navButton(for: item)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 70)
    }

    @ViewBuilder
    private func navButton(for item: LiquidGlassNavItem) -> some View {
        let isSelected = item.id == selectedIndex

        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                onTap(item.id)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? item.selectedIcon : item.icon)
                    .font(.system(size: 22, weight: .medium))
                    .symbolRenderingMode(.hierarchical)

                Text(item.label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 只有选中的 item 有玻璃效果
        .glassEffect(
            isSelected ? .regular.interactive() : .identity,
            in: .capsule
        )
        // 使用相同的 ID 让玻璃块在 items 之间变形移动
        .glassEffectID("navSelection", in: namespace)
    }
}

// MARK: - Plugin Registration

class LiquidGlassPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = LiquidGlassViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "com.kkape.mynas/liquid_glass_view")

        NSLog("🔮 LiquidGlassPlugin: Registered")

        if #available(iOS 26.0, *) {
            NSLog("🔮 LiquidGlassPlugin: iOS 26+ detected, using SwiftUI GlassEffectContainer")
        } else {
            NSLog("🔮 LiquidGlassPlugin: iOS < 26, using UIKit fallback")
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
