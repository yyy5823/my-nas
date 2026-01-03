import Flutter
import UIKit

/// iOS 26 Liquid Glass 搜索栏
///
/// 使用原生 UIGlassEffect 实现真正的 iOS 26 玻璃搜索框
/// 胶囊形状，包含搜索图标和文本输入框
///
/// iOS 26+: 使用 UIGlassEffect
/// iOS 13-25: 使用 UIVisualEffectView + UIBlurEffect 回退

// MARK: - Platform View Factory

class GlassSearchBarFactory: NSObject, FlutterPlatformViewFactory {
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
        return GlassSearchBarPlatformView(
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

class GlassSearchBarPlatformView: NSObject, FlutterPlatformView, UITextFieldDelegate {
    private let containerView: UIView
    private let glassView: UIVisualEffectView
    private let contentStack: UIStackView
    private let searchIcon: UIImageView
    private let textField: UITextField
    private let clearButton: UIButton
    private var methodChannel: FlutterMethodChannel?
    private let viewId: Int64
    private var isDark: Bool
    private var height: CGFloat

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
        let placeholder = params["placeholder"] as? String ?? "搜索"
        let initialText = params["text"] as? String ?? ""
        let autofocus = params["autofocus"] as? Bool ?? false
        height = CGFloat(params["height"] as? Double ?? 44.0)
        let cornerRadius = height / 2  // 胶囊形状

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

        glassView.layer.cornerRadius = cornerRadius
        glassView.layer.cornerCurve = .continuous
        glassView.clipsToBounds = true
        glassView.overrideUserInterfaceStyle = isDark ? .dark : .light

        // 创建搜索图标
        searchIcon = UIImageView()
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        searchIcon.image = UIImage(systemName: "magnifyingglass", withConfiguration: iconConfig)
        searchIcon.tintColor = isDark ? UIColor.white.withAlphaComponent(0.6) : UIColor.black.withAlphaComponent(0.45)
        searchIcon.contentMode = .scaleAspectFit
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchIcon.widthAnchor.constraint(equalToConstant: 20),
            searchIcon.heightAnchor.constraint(equalToConstant: 20)
        ])

        // 创建文本输入框
        textField = UITextField()
        textField.placeholder = placeholder
        textField.text = initialText
        textField.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        textField.textColor = isDark ? .white : UIColor(white: 0.13, alpha: 1.0)
        textField.tintColor = isDark ? .white : .systemBlue
        textField.clearButtonMode = .never  // 我们使用自定义清除按钮
        textField.returnKeyType = .search
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.backgroundColor = .clear

        // 设置 placeholder 颜色
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: isDark
                    ? UIColor.white.withAlphaComponent(0.38)
                    : UIColor.black.withAlphaComponent(0.38)
            ]
        )

        // 创建清除按钮
        clearButton = UIButton(type: .system)
        let clearConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        clearButton.setImage(UIImage(systemName: "xmark", withConfiguration: clearConfig), for: .normal)
        clearButton.tintColor = isDark ? UIColor.white.withAlphaComponent(0.7) : UIColor.black.withAlphaComponent(0.54)
        clearButton.backgroundColor = isDark
            ? UIColor.white.withAlphaComponent(0.2)
            : UIColor.black.withAlphaComponent(0.15)
        clearButton.layer.cornerRadius = 9
        clearButton.clipsToBounds = true
        clearButton.isHidden = initialText.isEmpty
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            clearButton.widthAnchor.constraint(equalToConstant: 18),
            clearButton.heightAnchor.constraint(equalToConstant: 18)
        ])

        // 创建内容堆叠视图
        contentStack = UIStackView()
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 10

        super.init()

        // 设置代理
        textField.delegate = self

        // 添加目标动作
        textField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        clearButton.addTarget(self, action: #selector(clearButtonTapped), for: .touchUpInside)

        // 组装视图
        contentStack.addArrangedSubview(searchIcon)
        contentStack.addArrangedSubview(textField)
        contentStack.addArrangedSubview(clearButton)

        glassView.contentView.addSubview(contentStack)
        containerView.addSubview(glassView)

        // 设置布局约束
        setupConstraints()

        // 设置 Method Channel
        if let messenger = messenger {
            setupMethodChannel(messenger: messenger)
        }

        // 自动获取焦点
        if autofocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.textField.becomeFirstResponder()
            }
        }
    }

    private func setupConstraints() {
        glassView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Glass view 填充容器
            glassView.topAnchor.constraint(equalTo: containerView.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            glassView.heightAnchor.constraint(equalToConstant: height),

            // Content stack 在 glass view 内部
            contentStack.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -14)
        ])
    }

    private func setupMethodChannel(messenger: FlutterBinaryMessenger) {
        let channelName = "com.kkape.mynas/glass_search_bar_\(viewId)"
        methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)

        methodChannel?.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "updateTheme":
                if let isDark = call.arguments as? Bool {
                    self?.updateTheme(isDark: isDark)
                }
                result(nil)
            case "setText":
                if let text = call.arguments as? String {
                    self?.textField.text = text
                    self?.clearButton.isHidden = text.isEmpty
                }
                result(nil)
            case "getText":
                result(self?.textField.text ?? "")
            case "focus":
                self?.textField.becomeFirstResponder()
                result(nil)
            case "unfocus":
                self?.textField.resignFirstResponder()
                result(nil)
            case "clear":
                self?.textField.text = ""
                self?.clearButton.isHidden = true
                self?.methodChannel?.invokeMethod("onChanged", arguments: "")
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

        // 更新图标颜色
        searchIcon.tintColor = isDark
            ? UIColor.white.withAlphaComponent(0.6)
            : UIColor.black.withAlphaComponent(0.45)

        // 更新文本颜色
        textField.textColor = isDark ? .white : UIColor(white: 0.13, alpha: 1.0)
        textField.tintColor = isDark ? .white : .systemBlue

        // 更新 placeholder 颜色
        if let placeholder = textField.placeholder {
            textField.attributedPlaceholder = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: isDark
                        ? UIColor.white.withAlphaComponent(0.38)
                        : UIColor.black.withAlphaComponent(0.38)
                ]
            )
        }

        // 更新清除按钮
        clearButton.tintColor = isDark
            ? UIColor.white.withAlphaComponent(0.7)
            : UIColor.black.withAlphaComponent(0.54)
        clearButton.backgroundColor = isDark
            ? UIColor.white.withAlphaComponent(0.2)
            : UIColor.black.withAlphaComponent(0.15)
    }

    @objc private func textFieldDidChange(_ textField: UITextField) {
        let text = textField.text ?? ""
        clearButton.isHidden = text.isEmpty
        methodChannel?.invokeMethod("onChanged", arguments: text)
    }

    @objc private func clearButtonTapped() {
        // 触觉反馈
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()

        textField.text = ""
        clearButton.isHidden = true
        methodChannel?.invokeMethod("onChanged", arguments: "")
    }

    // MARK: - UITextFieldDelegate

    func textFieldDidBeginEditing(_ textField: UITextField) {
        methodChannel?.invokeMethod("onFocusChanged", arguments: true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        methodChannel?.invokeMethod("onFocusChanged", arguments: false)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = textField.text ?? ""
        methodChannel?.invokeMethod("onSubmitted", arguments: text)
        return true
    }

    func view() -> UIView {
        return containerView
    }
}

// MARK: - Plugin Registration

class GlassSearchBarPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = GlassSearchBarFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "com.kkape.mynas/glass_search_bar")

        NSLog("🔍 GlassSearchBarPlugin: Registered")

        if #available(iOS 26.0, *) {
            NSLog("🔍 GlassSearchBarPlugin: iOS 26+ - Using UIGlassEffect")
        } else {
            NSLog("🔍 GlassSearchBarPlugin: iOS < 26 - Using UIBlurEffect fallback")
        }
    }
}
