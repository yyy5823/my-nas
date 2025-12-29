import Flutter
import UIKit

/// iOS 原生模糊视图 - 使用 UIVisualEffectView 实现真正的系统级毛玻璃效果
///
/// 支持的模糊样式：
/// - systemUltraThinMaterial: 超薄材质（最透明）
/// - systemThinMaterial: 薄材质
/// - systemMaterial: 标准材质
/// - systemThickMaterial: 厚材质
/// - systemChromeMaterial: Chrome 材质（导航栏风格）
/// - light / dark / extraLight: 传统模糊样式
///
/// 特点：
/// - 硬件加速，性能优异
/// - 自动适配系统主题（亮色/暗色模式）
/// - 真正的活力模糊效果（Vibrancy）
/// - 与系统 UI 风格保持一致

// MARK: - Platform View Factory

class NativeBlurViewFactory: NSObject, FlutterPlatformViewFactory {
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
        return NativeBlurPlatformView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    /// 声明需要解码参数
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - Platform View

class NativeBlurPlatformView: NSObject, FlutterPlatformView {
    private let containerView: UIView
    private let blurView: UIVisualEffectView
    private var vibrancyView: UIVisualEffectView?
    private let contentView: UIView

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        // 创建容器视图
        containerView = UIView(frame: frame)
        containerView.backgroundColor = .clear
        containerView.clipsToBounds = true

        // 解析参数
        let params = args as? [String: Any] ?? [:]
        let style = params["style"] as? String ?? "systemMaterial"
        let isDark = params["isDark"] as? Bool ?? false
        let cornerRadius = params["cornerRadius"] as? Double ?? 0
        let enableBorder = params["enableBorder"] as? Bool ?? true
        let borderOpacity = params["borderOpacity"] as? Double ?? 0.2
        let enableVibrancy = params["enableVibrancy"] as? Bool ?? false

        // 创建模糊效果
        let blurEffect = NativeBlurPlatformView.createBlurEffect(style: style, isDark: isDark)
        blurView = UIVisualEffectView(effect: blurEffect)
        blurView.frame = frame
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // 内容视图（用于放置子视图）
        contentView = UIView()
        contentView.backgroundColor = .clear
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        super.init()

        // 设置视图层级
        containerView.addSubview(blurView)

        // 如果启用 Vibrancy 效果
        if enableVibrancy {
            let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect)
            let vibrancy = UIVisualEffectView(effect: vibrancyEffect)
            vibrancy.frame = blurView.bounds
            vibrancy.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blurView.contentView.addSubview(vibrancy)
            vibrancy.contentView.addSubview(contentView)
            vibrancyView = vibrancy
        } else {
            blurView.contentView.addSubview(contentView)
        }

        // 设置圆角
        if cornerRadius > 0 {
            containerView.layer.cornerRadius = CGFloat(cornerRadius)
            blurView.layer.cornerRadius = CGFloat(cornerRadius)
            if #available(iOS 13.0, *) {
                blurView.layer.cornerCurve = .continuous
                containerView.layer.cornerCurve = .continuous
            }
        }

        // 设置边框（模拟玻璃边缘高光）
        if enableBorder {
            containerView.layer.borderWidth = 0.5
            let borderColor = isDark
                ? UIColor.white.withAlphaComponent(CGFloat(borderOpacity))
                : UIColor.black.withAlphaComponent(CGFloat(borderOpacity * 0.5))
            containerView.layer.borderColor = borderColor.cgColor
        }
    }

    func view() -> UIView {
        return containerView
    }

    /// 根据样式名称创建对应的 UIBlurEffect
    private static func createBlurEffect(style: String, isDark: Bool) -> UIBlurEffect {
        if #available(iOS 13.0, *) {
            switch style {
            case "systemUltraThinMaterial":
                return UIBlurEffect(style: isDark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)
            case "systemThinMaterial":
                return UIBlurEffect(style: isDark ? .systemThinMaterialDark : .systemThinMaterialLight)
            case "systemMaterial":
                return UIBlurEffect(style: isDark ? .systemMaterialDark : .systemMaterialLight)
            case "systemThickMaterial":
                return UIBlurEffect(style: isDark ? .systemThickMaterialDark : .systemThickMaterialLight)
            case "systemChromeMaterial":
                return UIBlurEffect(style: isDark ? .systemChromeMaterialDark : .systemChromeMaterialLight)
            case "regular":
                return UIBlurEffect(style: isDark ? .dark : .light)
            case "prominent":
                return UIBlurEffect(style: isDark ? .systemMaterialDark : .systemMaterialLight)
            default:
                return UIBlurEffect(style: isDark ? .systemMaterialDark : .systemMaterialLight)
            }
        } else {
            // iOS 12 及以下的回退
            return UIBlurEffect(style: isDark ? .dark : .light)
        }
    }
}

// MARK: - Plugin Registration

class NativeBlurViewPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = NativeBlurViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "com.kkape.mynas/native_blur_view")
    }
}
