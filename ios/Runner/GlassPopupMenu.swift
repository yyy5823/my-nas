import Flutter
import UIKit

/// iOS 26 风格自定义玻璃弹出菜单
///
/// 使用 UIVisualEffectView 创建与 iOS 26 上下文菜单相同外观的自定义弹出菜单
/// 特性：
/// - iOS 26+ 使用 UIGlassEffect 实现真正的 Liquid Glass 效果
/// - iOS 13-25 使用 UIBlurEffect 回退
/// - 平滑的弹出和关闭动画
/// - 支持菜单项图标
/// - 支持破坏性操作红色标记

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

        if #available(iOS 26.0, *) {
            NSLog("🍿 GlassPopupMenuPlugin: iOS 26+ - Will use UIGlassEffect")
        } else {
            NSLog("🍿 GlassPopupMenuPlugin: iOS < 26 - Will use UIBlurEffect")
        }
    }

    private weak var registrar: FlutterPluginRegistrar?
    private var pendingResult: FlutterResult?
    private var menuWindow: UIWindow?
    private var hasReturnedResult = false

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
        let x = args["x"] as? Double ?? 0
        let y = args["y"] as? Double ?? 0
        let isDark = args["isDark"] as? Bool ?? false
        let items = args["items"] as? [[String: Any]] ?? []

        pendingResult = result
        hasReturnedResult = false

        DispatchQueue.main.async { [weak self] in
            self?.presentMenu(at: CGPoint(x: x, y: y), items: items, isDark: isDark)
        }
    }

    private func presentMenu(at point: CGPoint, items: [[String: Any]], isDark: Bool) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            pendingResult?(FlutterError(code: "NO_WINDOW", message: "No window scene found", details: nil))
            return
        }

        var menuItems: [PopupMenuItem] = []
        for (index, item) in items.enumerated() {
            let title = item["title"] as? String ?? ""
            let icon = item["icon"] as? String
            let isDestructive = item["isDestructive"] as? Bool ?? false
            let value = item["value"] as? String ?? "\(index)"

            menuItems.append(PopupMenuItem(
                title: title,
                icon: icon,
                value: value,
                isDestructive: isDestructive
            ))
        }

        let menuWindow = UIWindow(windowScene: windowScene)
        let menuVC = GlassMenuViewController(
            menuItems: menuItems,
            anchorPoint: point,
            isDark: isDark,
            onSelect: { [weak self] value in
                guard let self = self, !self.hasReturnedResult else { return }
                self.hasReturnedResult = true
                self.pendingResult?(value)
                self.pendingResult = nil
                self.dismissMenuWindow()
            },
            onDismiss: { [weak self] in
                guard let self = self, !self.hasReturnedResult else { return }
                self.hasReturnedResult = true
                self.pendingResult?(nil)
                self.pendingResult = nil
                self.dismissMenuWindow()
            }
        )

        menuWindow.rootViewController = menuVC
        menuWindow.windowLevel = .alert + 1
        menuWindow.backgroundColor = .clear
        menuWindow.overrideUserInterfaceStyle = isDark ? .dark : .light
        menuWindow.makeKeyAndVisible()

        self.menuWindow = menuWindow
    }

    private func dismissMenuWindow() {
        guard let window = menuWindow else { return }

        window.isHidden = true
        menuWindow = nil
    }
}

struct PopupMenuItem {
    let title: String
    let icon: String?
    let value: String
    let isDestructive: Bool
}

// MARK: - Glass Menu View Controller

class GlassMenuViewController: UIViewController {
    private let menuItems: [PopupMenuItem]
    private let anchorPoint: CGPoint
    private let isDark: Bool
    private let onSelect: (String) -> Void
    private let onDismiss: () -> Void

    private var menuContainerView: UIView!
    private var glassBackgroundView: UIVisualEffectView!
    private var menuStackView: UIStackView!

    // 菜单尺寸常量
    private let menuWidth: CGFloat = 220
    private let menuItemHeight: CGFloat = 44
    private let menuCornerRadius: CGFloat = 14
    private let menuPadding: CGFloat = 8

    init(menuItems: [PopupMenuItem], anchorPoint: CGPoint, isDark: Bool, onSelect: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
        self.menuItems = menuItems
        self.anchorPoint = anchorPoint
        self.isDark = isDark
        self.onSelect = onSelect
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

        setupBackgroundDismiss()
        setupMenuContainer()
        setupGlassBackground()
        setupMenuItems()
        positionMenu()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateIn()
    }

    private func setupBackgroundDismiss() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
    }

    private func setupMenuContainer() {
        menuContainerView = UIView()
        menuContainerView.backgroundColor = .clear
        menuContainerView.layer.cornerRadius = menuCornerRadius
        menuContainerView.layer.cornerCurve = .continuous
        menuContainerView.clipsToBounds = true

        // 添加阴影到容器的父视图
        menuContainerView.layer.shadowColor = UIColor.black.cgColor
        menuContainerView.layer.shadowOffset = CGSize(width: 0, height: 8)
        menuContainerView.layer.shadowRadius = 24
        menuContainerView.layer.shadowOpacity = isDark ? 0.4 : 0.2
        menuContainerView.layer.masksToBounds = false

        view.addSubview(menuContainerView)
    }

    private func setupGlassBackground() {
        // 创建玻璃效果
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect()
            glassBackgroundView = UIVisualEffectView(effect: glassEffect)
        } else {
            let blurStyle: UIBlurEffect.Style = isDark ? .systemMaterialDark : .systemMaterial
            glassBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        }

        glassBackgroundView.layer.cornerRadius = menuCornerRadius
        glassBackgroundView.layer.cornerCurve = .continuous
        glassBackgroundView.clipsToBounds = true
        glassBackgroundView.overrideUserInterfaceStyle = isDark ? .dark : .light

        menuContainerView.addSubview(glassBackgroundView)

        glassBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glassBackgroundView.topAnchor.constraint(equalTo: menuContainerView.topAnchor),
            glassBackgroundView.bottomAnchor.constraint(equalTo: menuContainerView.bottomAnchor),
            glassBackgroundView.leadingAnchor.constraint(equalTo: menuContainerView.leadingAnchor),
            glassBackgroundView.trailingAnchor.constraint(equalTo: menuContainerView.trailingAnchor)
        ])
    }

    private func setupMenuItems() {
        menuStackView = UIStackView()
        menuStackView.axis = .vertical
        menuStackView.alignment = .fill
        menuStackView.distribution = .fill
        menuStackView.spacing = 0

        for (index, item) in menuItems.enumerated() {
            let itemButton = createMenuItemButton(item: item, index: index)
            menuStackView.addArrangedSubview(itemButton)

            // 添加分隔线（除了最后一项）
            if index < menuItems.count - 1 {
                let separator = createSeparator()
                menuStackView.addArrangedSubview(separator)
            }
        }

        glassBackgroundView.contentView.addSubview(menuStackView)

        menuStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            menuStackView.topAnchor.constraint(equalTo: glassBackgroundView.contentView.topAnchor, constant: menuPadding),
            menuStackView.bottomAnchor.constraint(equalTo: glassBackgroundView.contentView.bottomAnchor, constant: -menuPadding),
            menuStackView.leadingAnchor.constraint(equalTo: glassBackgroundView.contentView.leadingAnchor),
            menuStackView.trailingAnchor.constraint(equalTo: glassBackgroundView.contentView.trailingAnchor)
        ])
    }

    private func createMenuItemButton(item: PopupMenuItem, index: Int) -> UIView {
        // 创建容器视图
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.tag = index
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.heightAnchor.constraint(equalToConstant: menuItemHeight).isActive = true

        // 创建水平堆栈视图
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // 添加图标
        if let iconName = item.icon {
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let imageView = UIImageView(image: UIImage(systemName: iconName, withConfiguration: symbolConfig))
            imageView.tintColor = item.isDestructive ? .systemRed : (isDark ? .white : .label)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.widthAnchor.constraint(equalToConstant: 20).isActive = true
            stackView.addArrangedSubview(imageView)
        }

        // 添加标题
        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        titleLabel.textColor = item.isDestructive ? .systemRed : (isDark ? .white : .label)
        stackView.addArrangedSubview(titleLabel)

        // 添加高亮背景视图
        let highlightView = UIView()
        highlightView.backgroundColor = .clear
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        containerView.insertSubview(highlightView, at: 0)

        NSLayoutConstraint.activate([
            highlightView.topAnchor.constraint(equalTo: containerView.topAnchor),
            highlightView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            highlightView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            highlightView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])

        // 添加点击手势
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(menuItemTapped(_:)))
        containerView.addGestureRecognizer(tapGesture)
        containerView.isUserInteractionEnabled = true

        // 添加长按手势用于高亮效果
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(menuItemPressed(_:)))
        longPressGesture.minimumPressDuration = 0
        longPressGesture.cancelsTouchesInView = false
        containerView.addGestureRecognizer(longPressGesture)

        // 保存高亮视图引用
        highlightView.tag = 1000 + index

        return containerView
    }

    @objc private func menuItemPressed(_ gesture: UILongPressGestureRecognizer) {
        guard let containerView = gesture.view else { return }
        let index = containerView.tag
        let highlightView = containerView.viewWithTag(1000 + index)

        let highlightColor = isDark
            ? UIColor.white.withAlphaComponent(0.1)
            : UIColor.black.withAlphaComponent(0.05)

        switch gesture.state {
        case .began:
            UIView.animate(withDuration: 0.1) {
                highlightView?.backgroundColor = highlightColor
            }
        case .ended, .cancelled, .failed:
            UIView.animate(withDuration: 0.1) {
                highlightView?.backgroundColor = .clear
            }
        default:
            break
        }
    }

    private func createSeparator() -> UIView {
        let separator = UIView()
        separator.backgroundColor = isDark
            ? UIColor.white.withAlphaComponent(0.1)
            : UIColor.black.withAlphaComponent(0.08)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return separator
    }

    private func positionMenu() {
        let screenBounds = view.bounds
        let menuHeight = CGFloat(menuItems.count) * menuItemHeight + CGFloat(menuItems.count - 1) * 0.5 + menuPadding * 2

        // 计算菜单位置，确保不超出屏幕
        var menuX = anchorPoint.x - menuWidth + 20  // 右对齐到锚点
        var menuY = anchorPoint.y + 8  // 在锚点下方

        // 确保不超出左边界
        if menuX < 16 {
            menuX = 16
        }

        // 确保不超出右边界
        if menuX + menuWidth > screenBounds.width - 16 {
            menuX = screenBounds.width - menuWidth - 16
        }

        // 如果菜单会超出底部，则显示在锚点上方
        if menuY + menuHeight > screenBounds.height - 16 {
            menuY = anchorPoint.y - menuHeight - 8
        }

        // 确保不超出顶部
        if menuY < 16 {
            menuY = 16
        }

        menuContainerView.frame = CGRect(x: menuX, y: menuY, width: menuWidth, height: menuHeight)
    }

    private func animateIn() {
        // 初始状态：缩小并透明
        menuContainerView.alpha = 0
        menuContainerView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)

        // 设置锚点为菜单顶部右侧（因为菜单通常从右上角按钮展开）
        let anchorX = (anchorPoint.x - menuContainerView.frame.minX) / menuContainerView.bounds.width
        menuContainerView.layer.anchorPoint = CGPoint(x: min(1, max(0, anchorX)), y: 0)

        // 重新定位以补偿锚点变化
        positionMenu()

        // iOS 26 风格弹簧动画
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.5,
            options: [.curveEaseOut],
            animations: {
                self.menuContainerView.alpha = 1
                self.menuContainerView.transform = .identity
            }
        )
    }

    private func animateOut(completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseIn],
            animations: {
                self.menuContainerView.alpha = 0
                self.menuContainerView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            },
            completion: { _ in
                completion()
            }
        )
    }

    @objc private func menuItemTapped(_ gesture: UITapGestureRecognizer) {
        guard let containerView = gesture.view else { return }
        let index = containerView.tag
        guard index < menuItems.count else { return }

        let item = menuItems[index]

        // 添加简短的视觉反馈
        UIView.animate(withDuration: 0.1, animations: {
            containerView.alpha = 0.5
        }) { _ in
            self.animateOut { [weak self] in
                self?.onSelect(item.value)
            }
        }
    }

    @objc private func backgroundTapped() {
        animateOut { [weak self] in
            self?.onDismiss()
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension GlassMenuViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // 只有点击在菜单外部时才响应
        let location = touch.location(in: menuContainerView)
        return !menuContainerView.bounds.contains(location)
    }
}
