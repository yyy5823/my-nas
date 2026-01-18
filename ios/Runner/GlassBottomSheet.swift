import Flutter
import UIKit

/// iOS 26 原生玻璃底部弹框
///
/// 使用 UISheetPresentationController 实现真正的 iOS 底部弹框
/// iOS 26+ 自动应用 Liquid Glass 效果
/// iOS 15-25 使用标准 Sheet 样式
///
/// 特性：
/// - 支持多种高度档位（小、中、大、全屏）
/// - 支持拖拽关闭
/// - 支持点击背景关闭
/// - 自动圆角和安全区处理

// MARK: - Plugin Registration

class GlassBottomSheetPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.kkape.mynas/glass_bottom_sheet",
            binaryMessenger: registrar.messenger()
        )

        let instance = GlassBottomSheetPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)

        NSLog("📋 GlassBottomSheetPlugin: Registered")

        if #available(iOS 26.0, *) {
            NSLog("📋 GlassBottomSheetPlugin: iOS 26+ - Using Liquid Glass sheets")
        } else if #available(iOS 15.0, *) {
            NSLog("📋 GlassBottomSheetPlugin: iOS 15-25 - Using UISheetPresentationController")
        } else {
            NSLog("📋 GlassBottomSheetPlugin: iOS < 15 - Using standard modal")
        }
    }

    private weak var registrar: FlutterPluginRegistrar?
    private var presentedSheets: [Int: SheetViewController] = [:]
    private var nextSheetId = 0

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showSheet":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Arguments required", details: nil))
                return
            }
            showSheet(args: args, result: result)

        case "showSectionedSheet":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Arguments required", details: nil))
                return
            }
            showSectionedSheet(args: args, result: result)

        case "dismissSheet":
            guard let args = call.arguments as? [String: Any],
                  let sheetId = args["sheetId"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "sheetId required", details: nil))
                return
            }
            dismissSheet(sheetId: sheetId, result: result)

        case "updateSheet":
            guard let args = call.arguments as? [String: Any],
                  let sheetId = args["sheetId"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "sheetId required", details: nil))
                return
            }
            updateSheet(sheetId: sheetId, args: args, result: result)

        case "updateSheetLoading":
            guard let args = call.arguments as? [String: Any],
                  let sheetId = args["sheetId"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "sheetId required", details: nil))
                return
            }
            updateSheetLoading(sheetId: sheetId, args: args, result: result)

        case "showFilterSheet":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Arguments required", details: nil))
                return
            }
            showFilterSheet(args: args, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Show Sheet

    private func showSheet(args: [String: Any], result: @escaping FlutterResult) {
        let isDark = args["isDark"] as? Bool ?? false
        let title = args["title"] as? String
        let items = args["items"] as? [[String: Any]] ?? []
        let showDragHandle = args["showDragHandle"] as? Bool ?? true
        let dismissOnTapBackground = args["dismissOnTapBackground"] as? Bool ?? true
        let initialDetent = args["initialDetent"] as? String ?? "medium"
        let allowedDetents = args["allowedDetents"] as? [String] ?? ["medium", "large"]
        let showCancelButton = args["showCancelButton"] as? Bool ?? true

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                result(FlutterError(code: "NO_ROOT_VC", message: "No root view controller", details: nil))
                return
            }

            // 查找最顶层的 presented controller
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }

            let sheetId = self.nextSheetId
            self.nextSheetId += 1

            let sheetVC = SheetViewController(
                sheetId: sheetId,
                title: title,
                items: items,
                isDark: isDark,
                showDragHandle: showDragHandle,
                showCancelButton: showCancelButton,
                onDismiss: { [weak self] selectedValue in
                    self?.handleSheetDismiss(sheetId: sheetId, selectedValue: selectedValue)
                },
                onItemSelected: { [weak self] value in
                    self?.handleItemSelected(sheetId: sheetId, value: value)
                }
            )

            // 配置 Sheet Presentation Controller
            if #available(iOS 15.0, *) {
                sheetVC.modalPresentationStyle = .pageSheet

                if let sheet = sheetVC.sheetPresentationController {
                    // 配置 detents
                    var detents: [UISheetPresentationController.Detent] = []

                    for detent in allowedDetents {
                        switch detent {
                        case "small":
                            if #available(iOS 16.0, *) {
                                detents.append(.custom { _ in 200 })
                            } else {
                                detents.append(.medium())
                            }
                        case "medium":
                            detents.append(.medium())
                        case "large":
                            detents.append(.large())
                        default:
                            detents.append(.medium())
                        }
                    }

                    sheet.detents = detents.isEmpty ? [.medium()] : detents
                    sheet.prefersGrabberVisible = showDragHandle
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = true
                    sheet.preferredCornerRadius = 24

                    // 设置初始 detent
                    switch initialDetent {
                    case "small":
                        if #available(iOS 16.0, *) {
                            sheet.selectedDetentIdentifier = .init("small")
                        }
                    case "medium":
                        sheet.selectedDetentIdentifier = .medium
                    case "large":
                        sheet.selectedDetentIdentifier = .large
                    default:
                        sheet.selectedDetentIdentifier = .medium
                    }

                    // iOS 26+ Liquid Glass 样式
                    if #available(iOS 26.0, *) {
                        // 移除自定义背景以显示 Liquid Glass 效果
                        // iOS 26 自动应用玻璃效果
                    }
                }
            } else {
                sheetVC.modalPresentationStyle = .formSheet
            }

            // 设置主题
            sheetVC.overrideUserInterfaceStyle = isDark ? .dark : .light

            // 保存引用
            self.presentedSheets[sheetId] = sheetVC

            topVC.present(sheetVC, animated: true) {
                result(sheetId)
            }
        }
    }

    // MARK: - Dismiss Sheet

    private func dismissSheet(sheetId: Int, result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            guard let sheet = self?.presentedSheets[sheetId] else {
                result(nil)
                return
            }

            sheet.dismiss(animated: true) { [weak self] in
                self?.presentedSheets.removeValue(forKey: sheetId)
                result(nil)
            }
        }
    }

    // MARK: - Update Sheet

    private func updateSheet(sheetId: Int, args: [String: Any], result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            guard let sheet = self?.presentedSheets[sheetId] else {
                result(FlutterError(code: "NOT_FOUND", message: "Sheet not found", details: nil))
                return
            }

            if let items = args["items"] as? [[String: Any]] {
                sheet.updateItems(items)
            }

            if let title = args["title"] as? String {
                sheet.updateTitle(title)
            }

            result(nil)
        }
    }

    // MARK: - Sectioned Sheet

    private var presentedSectionedSheets: [Int: SectionedSheetViewController] = [:]

    private func showSectionedSheet(args: [String: Any], result: @escaping FlutterResult) {
        let isDark = args["isDark"] as? Bool ?? false
        let title = args["title"] as? String
        let sections = args["sections"] as? [[String: Any]] ?? []
        let actions = args["actions"] as? [[String: Any]] ?? []
        let headerInfo = args["headerInfo"] as? String
        let showDragHandle = args["showDragHandle"] as? Bool ?? true
        let initialDetent = args["initialDetent"] as? String ?? "medium"
        let allowedDetents = args["allowedDetents"] as? [String] ?? ["medium", "large"]
        let showCancelButton = args["showCancelButton"] as? Bool ?? true

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                result(FlutterError(code: "NO_ROOT_VC", message: "No root view controller", details: nil))
                return
            }

            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }

            let sheetId = self.nextSheetId
            self.nextSheetId += 1

            let sheetVC = SectionedSheetViewController(
                sheetId: sheetId,
                title: title,
                sections: sections,
                actions: actions,
                headerInfo: headerInfo,
                isDark: isDark,
                showDragHandle: showDragHandle,
                showCancelButton: showCancelButton,
                onDismiss: { [weak self] selectedValue in
                    self?.handleSectionedSheetDismiss(sheetId: sheetId, selectedValue: selectedValue)
                },
                onItemSelected: { [weak self] sectionIndex, itemIndex, value in
                    self?.handleSectionedItemSelected(sheetId: sheetId, sectionIndex: sectionIndex, itemIndex: itemIndex, value: value)
                },
                onActionTapped: { [weak self] actionId in
                    self?.handleActionTapped(sheetId: sheetId, actionId: actionId)
                }
            )

            if #available(iOS 15.0, *) {
                sheetVC.modalPresentationStyle = .pageSheet
                if let sheet = sheetVC.sheetPresentationController {
                    var detents: [UISheetPresentationController.Detent] = []
                    for detent in allowedDetents {
                        switch detent {
                        case "small":
                            if #available(iOS 16.0, *) {
                                detents.append(.custom { _ in 200 })
                            } else {
                                detents.append(.medium())
                            }
                        case "medium":
                            detents.append(.medium())
                        case "large":
                            detents.append(.large())
                        default:
                            detents.append(.medium())
                        }
                    }
                    sheet.detents = detents.isEmpty ? [.medium()] : detents
                    sheet.prefersGrabberVisible = showDragHandle
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = true
                    sheet.preferredCornerRadius = 24

                    switch initialDetent {
                    case "small":
                        if #available(iOS 16.0, *) {
                            sheet.selectedDetentIdentifier = .init("small")
                        }
                    case "medium":
                        sheet.selectedDetentIdentifier = .medium
                    case "large":
                        sheet.selectedDetentIdentifier = .large
                    default:
                        sheet.selectedDetentIdentifier = .medium
                    }
                }
            } else {
                sheetVC.modalPresentationStyle = .formSheet
            }

            sheetVC.overrideUserInterfaceStyle = isDark ? .dark : .light
            self.presentedSectionedSheets[sheetId] = sheetVC

            topVC.present(sheetVC, animated: true) {
                result(sheetId)
            }
        }
    }

    private func updateSheetLoading(sheetId: Int, args: [String: Any], result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            if let sheet = self?.presentedSectionedSheets[sheetId] {
                if let isLoading = args["isLoading"] as? Bool {
                    sheet.updateLoading(isLoading)
                }
                if let loadingItemValue = args["loadingItemValue"] as? String {
                    sheet.updateLoadingItem(loadingItemValue)
                }
                result(nil)
            } else {
                result(FlutterError(code: "NOT_FOUND", message: "Sheet not found", details: nil))
            }
        }
    }

    private func handleSectionedSheetDismiss(sheetId: Int, selectedValue: String?) {
        presentedSectionedSheets.removeValue(forKey: sheetId)
        guard let messenger = registrar?.messenger() else { return }
        let channel = FlutterMethodChannel(name: "com.kkape.mynas/glass_bottom_sheet", binaryMessenger: messenger)
        channel.invokeMethod("onDismiss", arguments: ["sheetId": sheetId, "selectedValue": selectedValue as Any])
    }

    private func handleSectionedItemSelected(sheetId: Int, sectionIndex: Int, itemIndex: Int, value: String) {
        guard let messenger = registrar?.messenger() else { return }
        let channel = FlutterMethodChannel(name: "com.kkape.mynas/glass_bottom_sheet", binaryMessenger: messenger)
        channel.invokeMethod("onItemSelected", arguments: [
            "sheetId": sheetId,
            "sectionIndex": sectionIndex,
            "itemIndex": itemIndex,
            "value": value
        ])
    }

    private func handleActionTapped(sheetId: Int, actionId: String) {
        guard let messenger = registrar?.messenger() else { return }
        let channel = FlutterMethodChannel(name: "com.kkape.mynas/glass_bottom_sheet", binaryMessenger: messenger)
        channel.invokeMethod("onActionTapped", arguments: ["sheetId": sheetId, "actionId": actionId])
    }

    // MARK: - Callbacks

    private func handleSheetDismiss(sheetId: Int, selectedValue: String?) {
        presentedSheets.removeValue(forKey: sheetId)

        guard let messenger = registrar?.messenger() else { return }

        let channel = FlutterMethodChannel(
            name: "com.kkape.mynas/glass_bottom_sheet",
            binaryMessenger: messenger
        )

        channel.invokeMethod("onDismiss", arguments: [
            "sheetId": sheetId,
            "selectedValue": selectedValue as Any
        ])
    }

    private func handleItemSelected(sheetId: Int, value: String) {
        guard let messenger = registrar?.messenger() else { return }

        let channel = FlutterMethodChannel(
            name: "com.kkape.mynas/glass_bottom_sheet",
            binaryMessenger: messenger
        )

        channel.invokeMethod("onItemSelected", arguments: [
            "sheetId": sheetId,
            "value": value
        ])
    }
}

// MARK: - Sheet View Controller

class SheetViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let sheetId: Int
    private var sheetTitle: String?
    private var items: [[String: Any]]
    private let isDark: Bool
    private let showDragHandle: Bool
    private let showCancelButton: Bool
    private let onDismiss: (String?) -> Void
    private let onItemSelected: (String) -> Void

    private var tableView: UITableView!
    private var titleLabel: UILabel?
    private var headerView: UIView!
    private var selectedValue: String?

    init(
        sheetId: Int,
        title: String?,
        items: [[String: Any]],
        isDark: Bool,
        showDragHandle: Bool,
        showCancelButton: Bool,
        onDismiss: @escaping (String?) -> Void,
        onItemSelected: @escaping (String) -> Void
    ) {
        self.sheetId = sheetId
        self.sheetTitle = title
        self.items = items
        self.isDark = isDark
        self.showDragHandle = showDragHandle
        self.showCancelButton = showCancelButton
        self.onDismiss = onDismiss
        self.onItemSelected = onItemSelected
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // iOS 26+ 使用系统玻璃效果，不设置自定义背景
        if #available(iOS 26.0, *) {
            view.backgroundColor = .clear
        } else {
            view.backgroundColor = isDark ? .systemBackground : .systemBackground
        }

        setupHeaderView()
        setupTableView()
        setupConstraints()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            onDismiss(selectedValue)
        }
    }

    private func setupHeaderView() {
        headerView = UIView()
        headerView.backgroundColor = .clear
        view.addSubview(headerView)

        // 标题
        if let title = sheetTitle, !title.isEmpty {
            let label = UILabel()
            label.text = title
            label.font = .systemFont(ofSize: 18, weight: .semibold)
            label.textColor = isDark ? .white : .label
            label.textAlignment = .center
            headerView.addSubview(label)
            titleLabel = label
        }

        // 关闭按钮（圆形 X 图标在左侧）
        if showCancelButton {
            let closeButton = UIButton(type: .system)
            let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
            let xImage = UIImage(systemName: "xmark.circle.fill", withConfiguration: config)
            closeButton.setImage(xImage, for: .normal)
            closeButton.tintColor = isDark ? UIColor(white: 1.0, alpha: 0.5) : UIColor(white: 0.0, alpha: 0.3)
            closeButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
            headerView.addSubview(closeButton)

            closeButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                closeButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
                closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: 30),
                closeButton.heightAnchor.constraint(equalToConstant: 30)
            ])
        }
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SheetItemCell.self, forCellReuseIdentifier: "SheetItemCell")
        tableView.separatorStyle = .singleLine
        tableView.rowHeight = 54

        // iOS 26+ 透明背景以显示玻璃效果
        if #available(iOS 26.0, *) {
            tableView.backgroundColor = .clear
        } else {
            tableView.backgroundColor = .clear
        }

        view.addSubview(tableView)
    }

    private func setupConstraints() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false

        var constraints = [
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: sheetTitle != nil ? 50 : 0),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]

        if let titleLabel = titleLabel {
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            constraints.append(contentsOf: [
                titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
            ])
        }

        NSLayoutConstraint.activate(constraints)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    func updateItems(_ newItems: [[String: Any]]) {
        items = newItems
        tableView.reloadData()
    }

    func updateTitle(_ newTitle: String) {
        sheetTitle = newTitle
        titleLabel?.text = newTitle
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SheetItemCell", for: indexPath) as! SheetItemCell
        let item = items[indexPath.row]
        cell.configure(with: item, isDark: isDark)
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let item = items[indexPath.row]
        let value = item["value"] as? String ?? "\(indexPath.row)"

        // 触觉反馈
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()

        selectedValue = value
        onItemSelected(value)

        // 自动关闭
        if item["autoDismiss"] as? Bool ?? true {
            dismiss(animated: true)
        }
    }
}

// MARK: - Sheet Item Cell

class SheetItemCell: UITableViewCell {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let checkmarkView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // 图标
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        // 标题
        titleLabel.font = .systemFont(ofSize: 17)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // 副标题
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        // 选中标记
        checkmarkView.image = UIImage(systemName: "checkmark")
        checkmarkView.tintColor = .systemBlue
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.isHidden = true
        contentView.addSubview(checkmarkView)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: checkmarkView.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            checkmarkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmarkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 20),
            checkmarkView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    func configure(with item: [String: Any], isDark: Bool) {
        let title = item["title"] as? String ?? ""
        let subtitle = item["subtitle"] as? String
        let iconName = item["icon"] as? String
        let isSelected = item["isSelected"] as? Bool ?? false
        let isDestructive = item["isDestructive"] as? Bool ?? false

        // 配置标题
        titleLabel.text = title
        titleLabel.textColor = isDestructive ? .systemRed : (isDark ? .white : .label)

        // 配置副标题
        if let subtitle = subtitle, !subtitle.isEmpty {
            subtitleLabel.text = subtitle
            subtitleLabel.isHidden = false
        } else {
            subtitleLabel.isHidden = true
        }

        // 配置图标
        if let iconName = iconName {
            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            iconView.image = UIImage(systemName: iconName, withConfiguration: config)
            iconView.tintColor = isDestructive ? .systemRed : .systemBlue
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }

        // 配置选中状态
        checkmarkView.isHidden = !isSelected

        // iOS 26+ 透明单元格背景
        if #available(iOS 26.0, *) {
            backgroundColor = .clear
        } else {
            backgroundColor = isDark ? .secondarySystemBackground : .systemBackground
        }
    }
}

// MARK: - Sectioned Sheet View Controller

class SectionedSheetViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let sheetId: Int
    private var sheetTitle: String?
    private var sections: [[String: Any]]
    private var actions: [[String: Any]]
    private var headerInfo: String?
    private let isDark: Bool
    private let showDragHandle: Bool
    private let showCancelButton: Bool
    private let onDismiss: (String?) -> Void
    private let onItemSelected: (Int, Int, String) -> Void
    private let onActionTapped: (String) -> Void

    private var tableView: UITableView!
    private var titleLabel: UILabel?
    private var headerView: UIView!
    private var actionsStackView: UIStackView!
    private var selectedValue: String?
    private var loadingItemValue: String?
    private var isLoading = false

    init(
        sheetId: Int,
        title: String?,
        sections: [[String: Any]],
        actions: [[String: Any]],
        headerInfo: String?,
        isDark: Bool,
        showDragHandle: Bool,
        showCancelButton: Bool,
        onDismiss: @escaping (String?) -> Void,
        onItemSelected: @escaping (Int, Int, String) -> Void,
        onActionTapped: @escaping (String) -> Void
    ) {
        self.sheetId = sheetId
        self.sheetTitle = title
        self.sections = sections
        self.actions = actions
        self.headerInfo = headerInfo
        self.isDark = isDark
        self.showDragHandle = showDragHandle
        self.showCancelButton = showCancelButton
        self.onDismiss = onDismiss
        self.onItemSelected = onItemSelected
        self.onActionTapped = onActionTapped
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 26.0, *) {
            view.backgroundColor = .clear
        } else {
            view.backgroundColor = isDark ? .systemBackground : .systemBackground
        }

        setupHeaderView()
        setupTableView()
        setupActionsView()
        setupConstraints()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            onDismiss(selectedValue)
        }
    }

    private func setupHeaderView() {
        headerView = UIView()
        headerView.backgroundColor = .clear
        view.addSubview(headerView)

        if let title = sheetTitle, !title.isEmpty {
            let label = UILabel()
            label.text = title
            label.font = .systemFont(ofSize: 18, weight: .semibold)
            label.textColor = isDark ? .white : .label
            label.textAlignment = .center
            headerView.addSubview(label)
            titleLabel = label
        }

        if showCancelButton {
            let cancelButton = UIButton(type: .system)
            cancelButton.setTitle("取消", for: .normal)
            cancelButton.titleLabel?.font = .systemFont(ofSize: 17)
            cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
            headerView.addSubview(cancelButton)

            cancelButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                cancelButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
                cancelButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
            ])
        }
    }

    private func setupTableView() {
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SectionedItemCell.self, forCellReuseIdentifier: "SectionedItemCell")
        tableView.separatorStyle = .singleLine
        tableView.rowHeight = 54

        if #available(iOS 26.0, *) {
            tableView.backgroundColor = .clear
        } else {
            tableView.backgroundColor = .clear
        }

        view.addSubview(tableView)
    }

    private func setupActionsView() {
        actionsStackView = UIStackView()
        actionsStackView.axis = .horizontal
        actionsStackView.spacing = 12
        actionsStackView.distribution = .fillEqually
        view.addSubview(actionsStackView)

        for action in actions {
            let actionId = action["id"] as? String ?? ""
            let actionTitle = action["title"] as? String ?? ""
            let iconName = action["icon"] as? String

            let button = UIButton(type: .system)
            button.setTitle(actionTitle, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.backgroundColor = .systemBlue.withAlphaComponent(0.15)
            button.layer.cornerRadius = 10
            button.tag = actions.firstIndex(where: { ($0["id"] as? String) == actionId }) ?? 0
            button.addTarget(self, action: #selector(actionButtonTapped(_:)), for: .touchUpInside)

            if let iconName = iconName {
                let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
                button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
            }

            actionsStackView.addArrangedSubview(button)
        }
    }

    private func setupConstraints() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        actionsStackView.translatesAutoresizingMaskIntoConstraints = false

        let hasActions = !actions.isEmpty
        let actionsHeight: CGFloat = hasActions ? 48 : 0

        var constraints = [
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: sheetTitle != nil ? 50 : 0),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: actionsStackView.topAnchor, constant: -8),

            actionsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            actionsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            actionsStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            actionsStackView.heightAnchor.constraint(equalToConstant: actionsHeight)
        ]

        if let titleLabel = titleLabel {
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            constraints.append(contentsOf: [
                titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
            ])
        }

        NSLayoutConstraint.activate(constraints)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func actionButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        if index < actions.count {
            let actionId = actions[index]["id"] as? String ?? ""
            onActionTapped(actionId)
        }
    }

    func updateLoading(_ loading: Bool) {
        isLoading = loading
        tableView.reloadData()
    }

    func updateLoadingItem(_ value: String?) {
        loadingItemValue = value
        tableView.reloadData()
    }

    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionData = sections[section]
        let items = sectionData["items"] as? [[String: Any]] ?? []
        return items.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let sectionData = sections[section]
        return sectionData["header"] as? String
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SectionedItemCell", for: indexPath) as! SectionedItemCell
        let sectionData = sections[indexPath.section]
        let items = sectionData["items"] as? [[String: Any]] ?? []
        let item = items[indexPath.row]

        let itemValue = item["value"] as? String ?? ""
        let isItemLoading = loadingItemValue == itemValue && isLoading

        cell.configure(with: item, isDark: isDark, isLoading: isItemLoading)
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let sectionData = sections[indexPath.section]
        let items = sectionData["items"] as? [[String: Any]] ?? []
        let item = items[indexPath.row]
        let value = item["value"] as? String ?? "\(indexPath.row)"

        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()

        selectedValue = value
        onItemSelected(indexPath.section, indexPath.row, value)

        if item["autoDismiss"] as? Bool ?? true {
            dismiss(animated: true)
        }
    }
}

// MARK: - Sectioned Item Cell

class SectionedItemCell: UITableViewCell {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let checkmarkView = UIImageView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 17)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        checkmarkView.image = UIImage(systemName: "checkmark")
        checkmarkView.tintColor = .systemBlue
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.isHidden = true
        contentView.addSubview(checkmarkView)

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        contentView.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: checkmarkView.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            checkmarkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmarkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 20),
            checkmarkView.heightAnchor.constraint(equalToConstant: 20),

            loadingIndicator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            loadingIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    func configure(with item: [String: Any], isDark: Bool, isLoading: Bool = false) {
        let title = item["title"] as? String ?? ""
        let subtitle = item["subtitle"] as? String
        let iconName = item["icon"] as? String
        let isSelected = item["isSelected"] as? Bool ?? false

        titleLabel.text = title
        titleLabel.textColor = isDark ? .white : .label

        if let subtitle = subtitle, !subtitle.isEmpty {
            subtitleLabel.text = subtitle
            subtitleLabel.isHidden = false
        } else {
            subtitleLabel.isHidden = true
        }

        if let iconName = iconName {
            let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            iconView.image = UIImage(systemName: iconName, withConfiguration: config)
            iconView.tintColor = .systemBlue
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }

        if isLoading {
            checkmarkView.isHidden = true
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
            checkmarkView.isHidden = !isSelected
        }

        if #available(iOS 26.0, *) {
            backgroundColor = .clear
        } else {
            backgroundColor = isDark ? .secondarySystemBackground : .systemBackground
        }
    }
}
