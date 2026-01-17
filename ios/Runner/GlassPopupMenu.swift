import Flutter
import UIKit

/// iOS 26 风格自定义玻璃弹出菜单
///
/// 完全符合 iOS 26 设计规范的上下文菜单实现：
/// - iOS 26+ 使用 UIGlassEffect 实现 Liquid Glass 效果
/// - iOS 13-25 使用 UIBlurEffect 回退
/// - 点击按钮后按钮消失，菜单在右上角区域展示
/// - 支持拖动滑动选择（类似导航栏左右滑动）
/// - 椭圆形高亮选中区域
/// - 文字对齐（有图标和无图标的菜单项）

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
    private var anchorView: UIView?
    private var currentMenuItems: [PopupMenuItem] = []

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

        NSLog("🍿 GlassPopupMenuPlugin: showMenu at (\(x), \(y)) with \(items.count) items")

        DispatchQueue.main.async { [weak self] in
            self?.presentMenu(at: CGPoint(x: x, y: y), items: items, isDark: isDark)
        }
    }

    private func presentMenu(at point: CGPoint, items: [[String: Any]], isDark: Bool) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            NSLog("🍿 GlassPopupMenuPlugin: ERROR - No window scene found")
            pendingResult?(FlutterError(code: "NO_WINDOW", message: "No window scene found", details: nil))
            return
        }

        // 检查是否有任何菜单项带图标
        let hasAnyIcon = items.contains { ($0["icon"] as? String) != nil }

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

            NSLog("🍿 GlassPopupMenuPlugin: Item \(index): \(title) -> \(value)")
        }

        // 使用自定义玻璃弹窗（支持 iOS 26 UIGlassEffect）
        let menuWindow = UIWindow(windowScene: windowScene)
        let menuVC = GlassMenuViewController(
            menuItems: menuItems,
            anchorPoint: point,
            isDark: isDark,
            hasAnyIcon: hasAnyIcon,
            onSelect: { [weak self] value in
                guard let self = self, !self.hasReturnedResult else { return }
                self.hasReturnedResult = true
                NSLog("🍿 GlassPopupMenuPlugin: Selected value: \(value)")
                self.pendingResult?(value)
                self.pendingResult = nil
                self.dismissMenuWindow()
            },
            onDismiss: { [weak self] in
                guard let self = self, !self.hasReturnedResult else { return }
                self.hasReturnedResult = true
                NSLog("🍿 GlassPopupMenuPlugin: Menu dismissed without selection")
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

    private func cleanupSystemMenu() {
        anchorView?.removeFromSuperview()
        anchorView = nil
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
    private let hasAnyIcon: Bool
    private let onSelect: (String) -> Void
    private let onDismiss: () -> Void

    private var menuContainerView: UIView!
    private var glassBackgroundView: UIVisualEffectView!
    private var scrollView: UIScrollView!
    private var menuStackView: UIStackView!
    private var itemViews: [UIView] = []
    private var currentHighlightedIndex: Int = -1

    // 菜单尺寸常量
    private let menuWidth: CGFloat = 200
    private let menuItemHeight: CGFloat = 44
    private let menuCornerRadius: CGFloat = 14
    private let menuPadding: CGFloat = 6
    private let highlightCornerRadius: CGFloat = 8
    private let iconWidth: CGFloat = 24

    init(menuItems: [PopupMenuItem], anchorPoint: CGPoint, isDark: Bool, hasAnyIcon: Bool, onSelect: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
        self.menuItems = menuItems
        self.anchorPoint = anchorPoint
        self.isDark = isDark
        self.hasAnyIcon = hasAnyIcon
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
        setupScrollView()
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

        // 添加阴影
        menuContainerView.layer.shadowColor = UIColor.black.cgColor
        menuContainerView.layer.shadowOffset = CGSize(width: 0, height: 8)
        menuContainerView.layer.shadowRadius = 24
        menuContainerView.layer.shadowOpacity = isDark ? 0.5 : 0.25
        menuContainerView.layer.masksToBounds = false

        view.addSubview(menuContainerView)
    }

    private func setupGlassBackground() {
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

    private func setupScrollView() {
        scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delaysContentTouches = false
        // 关键修复：禁止取消内容触摸，确保菜单项点击能够正常触发
        scrollView.canCancelContentTouches = false

        glassBackgroundView.contentView.addSubview(scrollView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: glassBackgroundView.contentView.topAnchor, constant: menuPadding),
            scrollView.bottomAnchor.constraint(equalTo: glassBackgroundView.contentView.bottomAnchor, constant: -menuPadding),
            scrollView.leadingAnchor.constraint(equalTo: glassBackgroundView.contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: glassBackgroundView.contentView.trailingAnchor)
        ])

        // 添加拖动手势用于滑动选择
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        scrollView.addGestureRecognizer(panGesture)
    }

    private func setupMenuItems() {
        menuStackView = UIStackView()
        menuStackView.axis = .vertical
        menuStackView.alignment = .fill
        menuStackView.distribution = .fill
        menuStackView.spacing = 2

        for (index, item) in menuItems.enumerated() {
            let itemView = createMenuItemView(item: item, index: index)
            itemViews.append(itemView)
            menuStackView.addArrangedSubview(itemView)
        }

        scrollView.addSubview(menuStackView)

        menuStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            menuStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            menuStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            menuStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            menuStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            menuStackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }

    private func createMenuItemView(item: PopupMenuItem, index: Int) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.tag = index
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.heightAnchor.constraint(equalToConstant: menuItemHeight).isActive = true

        // 椭圆形高亮背景
        let highlightView = UIView()
        highlightView.backgroundColor = .clear
        highlightView.layer.cornerRadius = highlightCornerRadius
        highlightView.layer.cornerCurve = .continuous
        highlightView.tag = 1000 + index
        highlightView.isUserInteractionEnabled = false  // 让触摸穿透到 containerView
        containerView.addSubview(highlightView)

        highlightView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            highlightView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 2),
            highlightView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -2),
            highlightView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: menuPadding),
            highlightView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -menuPadding)
        ])

        // 内容堆栈视图
        let contentStack = UIStackView()
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 10
        contentStack.isUserInteractionEnabled = false  // 让触摸穿透到 containerView
        containerView.addSubview(contentStack)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),
            contentStack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])

        // 图标区域（固定宽度以对齐文字）
        if hasAnyIcon {
            if let iconName = item.icon {
                let symbolConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                let imageView = UIImageView(image: UIImage(systemName: iconName, withConfiguration: symbolConfig))
                imageView.tintColor = item.isDestructive ? .systemRed : (isDark ? .white : .label)
                imageView.contentMode = .center
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.widthAnchor.constraint(equalToConstant: iconWidth).isActive = true
                contentStack.addArrangedSubview(imageView)
            } else {
                // 占位符保持对齐
                let spacer = UIView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                spacer.widthAnchor.constraint(equalToConstant: iconWidth).isActive = true
                contentStack.addArrangedSubview(spacer)
            }
        }

        // 标题
        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        titleLabel.textColor = item.isDestructive ? .systemRed : (isDark ? .white : .label)
        contentStack.addArrangedSubview(titleLabel)

        // 添加点击手势
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(menuItemTapped(_:)))
        containerView.addGestureRecognizer(tapGesture)
        containerView.isUserInteractionEnabled = true

        return containerView
    }

    private func positionMenu() {
        let screenBounds = view.bounds
        let safeArea = view.safeAreaInsets
        let maxMenuHeight = screenBounds.height - safeArea.top - safeArea.bottom - 32
        let contentHeight = CGFloat(menuItems.count) * menuItemHeight + CGFloat(menuItems.count - 1) * 2 + menuPadding * 2
        let menuHeight = min(contentHeight, maxMenuHeight)

        // iOS 26 风格：菜单在按钮位置展示（右对齐到锚点）
        var menuX = anchorPoint.x - menuWidth / 2  // 以锚点为中心
        var menuY = anchorPoint.y  // 从锚点位置开始

        // 确保不超出右边界
        if menuX + menuWidth > screenBounds.width - 16 {
            menuX = screenBounds.width - menuWidth - 16
        }

        // 确保不超出左边界
        if menuX < 16 {
            menuX = 16
        }

        // 确保不超出底部
        if menuY + menuHeight > screenBounds.height - safeArea.bottom - 16 {
            menuY = anchorPoint.y - menuHeight  // 显示在锚点上方
        }

        // 确保不超出顶部
        if menuY < safeArea.top + 16 {
            menuY = safeArea.top + 16
        }

        menuContainerView.frame = CGRect(x: menuX, y: menuY, width: menuWidth, height: menuHeight)

        // 设置滚动视图内容大小
        scrollView.contentSize = CGSize(width: menuWidth, height: contentHeight - menuPadding * 2)
    }

    private func animateIn() {
        menuContainerView.alpha = 0
        menuContainerView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)

        // 锚点设置为菜单顶部中心
        menuContainerView.layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        positionMenu()

        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 0.75,
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

    private func highlightItem(at index: Int) {
        guard index != currentHighlightedIndex else { return }

        // 取消之前的高亮
        if currentHighlightedIndex >= 0 && currentHighlightedIndex < itemViews.count {
            let prevContainer = itemViews[currentHighlightedIndex]
            if let prevHighlight = prevContainer.viewWithTag(1000 + currentHighlightedIndex) {
                UIView.animate(withDuration: 0.15) {
                    prevHighlight.backgroundColor = .clear
                }
            }
        }

        currentHighlightedIndex = index

        // 添加新高亮
        if index >= 0 && index < itemViews.count {
            let container = itemViews[index]
            if let highlightView = container.viewWithTag(1000 + index) {
                let highlightColor = isDark
                    ? UIColor.white.withAlphaComponent(0.15)
                    : UIColor.black.withAlphaComponent(0.08)
                UIView.animate(withDuration: 0.15) {
                    highlightView.backgroundColor = highlightColor
                }
            }
        }
    }

    private func clearHighlight() {
        if currentHighlightedIndex >= 0 && currentHighlightedIndex < itemViews.count {
            let container = itemViews[currentHighlightedIndex]
            if let highlightView = container.viewWithTag(1000 + currentHighlightedIndex) {
                UIView.animate(withDuration: 0.15) {
                    highlightView.backgroundColor = .clear
                }
            }
        }
        currentHighlightedIndex = -1
    }

    private func indexForPoint(_ point: CGPoint) -> Int {
        let localPoint = scrollView.convert(point, from: view)
        let adjustedY = localPoint.y + scrollView.contentOffset.y

        for (index, itemView) in itemViews.enumerated() {
            let frame = itemView.frame
            if adjustedY >= frame.minY && adjustedY < frame.maxY {
                return index
            }
        }
        return -1
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: view)

        switch gesture.state {
        case .began, .changed:
            let index = indexForPoint(location)
            if menuContainerView.frame.contains(location) {
                highlightItem(at: index)
            } else {
                clearHighlight()
            }
        case .ended:
            if currentHighlightedIndex >= 0 && currentHighlightedIndex < menuItems.count {
                let item = menuItems[currentHighlightedIndex]
                selectItem(at: currentHighlightedIndex, item: item)
            } else {
                clearHighlight()
            }
        case .cancelled, .failed:
            clearHighlight()
        default:
            break
        }
    }

    @objc private func menuItemTapped(_ gesture: UITapGestureRecognizer) {
        guard let containerView = gesture.view else {
            NSLog("🍿 GlassPopupMenuPlugin: menuItemTapped - no view")
            return
        }

        let index = containerView.tag
        guard index >= 0 && index < menuItems.count else {
            NSLog("🍿 GlassPopupMenuPlugin: menuItemTapped - invalid index \(index)")
            return
        }

        let item = menuItems[index]
        NSLog("🍿 GlassPopupMenuPlugin: menuItemTapped - index \(index), value: \(item.value)")
        selectItem(at: index, item: item)
    }

    private func selectItem(at index: Int, item: PopupMenuItem) {
        // 高亮选中项
        highlightItem(at: index)

        // 短暂延迟后关闭
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.animateOut {
                self?.onSelect(item.value)
            }
        }
    }

    @objc private func backgroundTapped() {
        NSLog("🍿 GlassPopupMenuPlugin: backgroundTapped")
        animateOut { [weak self] in
            self?.onDismiss()
        }
    }
}

// MARK: - UIEditMenuInteractionDelegate (iOS 16+)

@available(iOS 16.0, *)
extension GlassPopupMenuPlugin: UIEditMenuInteractionDelegate {}

// MARK: - UIGestureRecognizerDelegate

extension GlassMenuViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let location = touch.location(in: menuContainerView)
        let isOutside = !menuContainerView.bounds.contains(location)
        return isOutside
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
