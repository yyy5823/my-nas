import Flutter
import UIKit
import SwiftUI

/// iOS 26 Liquid Glass 原生视图
///
/// 使用 SwiftUI 的 .glassEffect() 和 GlassEffectContainer 实现真正的 Liquid Glass 效果
/// 包含：
/// - 悬浮底部导航栏
/// - 玻璃卡片
/// - 底部弹窗容器
///
/// iOS 26+: 使用原生 Liquid Glass API
/// iOS < 26: 回退到 UIVisualEffectView

// MARK: - Navigation Bar Item

struct LiquidGlassNavItem: Identifiable {
    let id: Int
    let icon: String      // SF Symbol name
    let label: String
}

// MARK: - SwiftUI Views (iOS 26+)

@available(iOS 26.0, *)
struct LiquidGlassNavBarView: View {
    let items: [LiquidGlassNavItem]
    let selectedIndex: Int
    let isDark: Bool
    let onTap: (Int) -> Void

    @Namespace private var navNamespace

    var body: some View {
        // 使用 GlassEffectContainer 包裹所有玻璃元素
        // 这样可以实现元素之间的 morphing 动画效果
        GlassEffectContainer {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    Button(action: {
                        withAnimation(.bouncy(duration: 0.3)) {
                            onTap(item.id)
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: selectedIndex == item.id ? item.icon + ".fill" : item.icon)
                                .font(.system(size: 22, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                            Text(item.label)
                                .font(.system(size: 10, weight: selectedIndex == item.id ? .semibold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(selectedIndex == item.id ? .primary : .secondary)
                    }
                    // 使用 .glass 按钮样式获得原生交互效果
                    .buttonStyle(.glass)
                    // 为选中项添加 glassEffectID 实现 morphing
                    .glassEffectID("nav_\(item.id)", in: navNamespace)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        // 外层容器使用胶囊形玻璃效果
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
    }
}

@available(iOS 26.0, *)
struct LiquidGlassCardView: View {
    let cornerRadius: CGFloat
    let isInteractive: Bool

    var body: some View {
        Color.clear
            .glassEffect(
                isInteractive ? .regular.interactive() : .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

@available(iOS 26.0, *)
struct LiquidGlassSheetView: View {
    let cornerRadius: CGFloat

    var body: some View {
        Color.clear
            .glassEffect(
                .regular,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cornerRadius,
                    style: .continuous
                )
            )
    }
}

// MARK: - Platform View Factory

class LiquidGlassViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger
    private var channel: FlutterMethodChannel?

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
    private var cornerRadius: CGFloat = 30
    private var isInteractive: Bool = true

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

        // 解析参数
        parseArguments(args)

        // 设置 Method Channel 用于接收更新
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

        // 解析导航项
        if let itemsData = params["items"] as? [[String: Any]] {
            items = itemsData.enumerated().map { index, item in
                LiquidGlassNavItem(
                    id: index,
                    icon: item["icon"] as? String ?? "circle",
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
        // 移除旧视图
        hostingController?.view.removeFromSuperview()
        hostingController = nil

        if #available(iOS 26.0, *) {
            setupLiquidGlassView()
        } else {
            setupFallbackView()
        }
    }

    @available(iOS 26.0, *)
    private func setupLiquidGlassView() {
        let swiftUIView: AnyView

        switch viewType {
        case "navBar":
            swiftUIView = AnyView(
                LiquidGlassNavBarView(
                    items: items,
                    selectedIndex: currentSelectedIndex,
                    isDark: isDark,
                    onTap: { [weak self] index in
                        self?.handleNavTap(index)
                    }
                )
            )
        case "card":
            swiftUIView = AnyView(
                LiquidGlassCardView(
                    cornerRadius: cornerRadius,
                    isInteractive: isInteractive
                )
            )
        case "sheet":
            swiftUIView = AnyView(
                LiquidGlassSheetView(cornerRadius: cornerRadius)
            )
        default:
            swiftUIView = AnyView(
                LiquidGlassCardView(
                    cornerRadius: cornerRadius,
                    isInteractive: isInteractive
                )
            )
        }

        let hosting = UIHostingController(rootView: swiftUIView)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(hosting.view)

        // 使用 Auto Layout 确保正确布局
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        hostingController = hosting

        print("LiquidGlassView: setupLiquidGlassView completed (iOS 26+)")
    }

    private func setupFallbackView() {
        // iOS < 26 回退到 UIVisualEffectView
        // 使用 Auto Layout 确保正确布局
        let blurEffect = UIBlurEffect(style: isDark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)
        let effectView = UIVisualEffectView(effect: blurEffect)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.layer.cornerRadius = cornerRadius
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true

        // 添加阴影容器
        let shadowView = UIView()
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.backgroundColor = .clear
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = 0.15
        shadowView.layer.shadowOffset = CGSize(width: 0, height: 10)
        shadowView.layer.shadowRadius = 20

        containerView.addSubview(shadowView)
        shadowView.addSubview(effectView)

        // 设置阴影视图约束
        NSLayoutConstraint.activate([
            shadowView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            shadowView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            shadowView.topAnchor.constraint(equalTo: containerView.topAnchor),
            shadowView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        // 设置效果视图约束
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: shadowView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: shadowView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: shadowView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: shadowView.bottomAnchor),
        ])

        // 添加高光边框（模拟玻璃高光）
        let borderLayer = CAGradientLayer()
        borderLayer.colors = [
            (isDark ? UIColor.white.withAlphaComponent(0.3) : UIColor.white.withAlphaComponent(0.8)).cgColor,
            (isDark ? UIColor.white.withAlphaComponent(0.1) : UIColor.white.withAlphaComponent(0.3)).cgColor,
            UIColor.clear.cgColor,
            (isDark ? UIColor.white.withAlphaComponent(0.05) : UIColor.black.withAlphaComponent(0.05)).cgColor,
        ]
        borderLayer.locations = [0, 0.3, 0.7, 1]
        borderLayer.startPoint = CGPoint(x: 0.5, y: 0)
        borderLayer.endPoint = CGPoint(x: 0.5, y: 1)
        borderLayer.cornerRadius = cornerRadius

        // 创建边框 mask
        let borderMask = CAShapeLayer()
        borderMask.lineWidth = 1.0
        borderMask.fillColor = UIColor.clear.cgColor
        borderMask.strokeColor = UIColor.white.cgColor
        borderLayer.mask = borderMask

        // 在布局后更新边框
        DispatchQueue.main.async { [weak effectView, weak borderLayer, weak borderMask] in
            guard let effectView = effectView, let borderLayer = borderLayer, let borderMask = borderMask else { return }
            borderLayer.frame = effectView.bounds
            let path = UIBezierPath(roundedRect: effectView.bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: self.cornerRadius)
            borderMask.path = path.cgPath
            effectView.layer.addSublayer(borderLayer)
        }

        // 如果是导航栏，添加按钮
        if viewType == "navBar" {
            addFallbackNavItems(to: effectView.contentView)
        }

        print("LiquidGlassView: setupFallbackView completed, isDark: \(isDark), cornerRadius: \(cornerRadius)")
    }

    private func addFallbackNavItems(to contentView: UIView) {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false

        for (index, item) in items.enumerated() {
            let button = createFallbackNavButton(item: item, index: index)
            stackView.addArrangedSubview(button)
        }

        contentView.addSubview(stackView)

        // 使用 Auto Layout
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func createFallbackNavButton(item: LiquidGlassNavItem, index: Int) -> UIView {
        let container = UIView()

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let isSelected = index == currentSelectedIndex
        let iconName = isSelected ? item.icon + ".fill" : item.icon

        let imageView = UIImageView()
        imageView.image = UIImage(systemName: iconName)
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
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleFallbackNavTap(_:)))
        container.addGestureRecognizer(tap)
        container.tag = index
        container.isUserInteractionEnabled = true

        // 选中状态背景
        if isSelected {
            let bgView = UIView()
            bgView.backgroundColor = UIColor.label.withAlphaComponent(0.1)
            bgView.layer.cornerRadius = 16
            bgView.translatesAutoresizingMaskIntoConstraints = false
            container.insertSubview(bgView, at: 0)
            NSLayoutConstraint.activate([
                bgView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                bgView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                bgView.widthAnchor.constraint(equalToConstant: 56),
                bgView.heightAnchor.constraint(equalToConstant: 44)
            ])
        }

        return container
    }

    @objc private func handleFallbackNavTap(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view else { return }
        handleNavTap(view.tag)
    }

    private func handleNavTap(_ index: Int) {
        guard index != currentSelectedIndex else { return }

        currentSelectedIndex = index

        // 通知 Flutter
        methodChannel?.invokeMethod("onNavTap", arguments: index)

        // 更新视图
        setupView()
    }

    private func updateSelectedIndex(_ index: Int) {
        guard index != currentSelectedIndex else { return }
        currentSelectedIndex = index
        setupView()
    }

    private func updateItems(_ itemsData: [[String: Any]]) {
        items = itemsData.enumerated().map { index, item in
            LiquidGlassNavItem(
                id: index,
                icon: item["icon"] as? String ?? "circle",
                label: item["label"] as? String ?? ""
            )
        }
        setupView()
    }
}

// MARK: - Plugin Registration

class LiquidGlassPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        // 注册导航栏视图
        let navBarFactory = LiquidGlassViewFactory(messenger: registrar.messenger())
        registrar.register(navBarFactory, withId: "com.kkape.mynas/liquid_glass_view")

        print("LiquidGlassPlugin: Registered with viewType: com.kkape.mynas/liquid_glass_view")
    }
}

// MARK: - Availability Check

extension LiquidGlassPlugin {
    /// 检查是否支持 Liquid Glass（iOS 26+）
    static var isLiquidGlassSupported: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }
}
