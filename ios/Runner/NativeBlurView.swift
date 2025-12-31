import Flutter
import UIKit

/// iOS 原生模糊视图 - 使用系统级毛玻璃效果
///
/// iOS 26+: 使用 UIGlassEffect 实现真正的 Liquid Glass 效果
/// - 折射、高光、菲涅尔效果
/// - 动态光影响应设备运动
/// - 支持交互动画
///
/// iOS 13-25: 使用 UIVisualEffectView + UIBlurEffect
/// - systemUltraThinMaterial: 超薄材质（最透明）
/// - systemThinMaterial: 薄材质
/// - systemMaterial: 标准材质
/// - systemThickMaterial: 厚材质
/// - systemChromeMaterial: Chrome 材质（导航栏风格）
///
/// 特点：
/// - 硬件加速，性能优异
/// - 自动适配系统主题（亮色/暗色模式）
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
    private let effectView: UIVisualEffectView
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
        let isInteractive = params["isInteractive"] as? Bool ?? false
        let useLiquidGlass = params["useLiquidGlass"] as? Bool ?? true

        // 内容视图（用于放置子视图）
        contentView = UIView()
        contentView.backgroundColor = .clear
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // 设置容器视图的用户界面风格，确保正确响应深色/浅色模式
        containerView.overrideUserInterfaceStyle = isDark ? .dark : .light

        // 根据 iOS 版本选择效果
        if #available(iOS 26.0, *), useLiquidGlass {
            // iOS 26+: 使用 Liquid Glass 效果
            let glassEffect = UIGlassEffect()
            glassEffect.isInteractive = isInteractive

            // 先创建空 effect 的视图，然后通过动画设置 effect
            // 这样可以获得正确的 materialize 动画效果
            effectView = UIVisualEffectView(effect: nil)
            effectView.frame = frame
            effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            // 确保 effectView 也继承正确的界面风格
            effectView.overrideUserInterfaceStyle = isDark ? .dark : .light

            // 设置圆角
            if cornerRadius > 0 {
                effectView.layer.cornerRadius = CGFloat(cornerRadius)
                effectView.layer.cornerCurve = .continuous
                effectView.clipsToBounds = true
            }

            // 根据风格添加染色层
            // systemThinMaterial = 清澈模式（无染色）
            // systemMaterial = 染色模式（添加淡淡的背景色）
            let isClearStyle = style == "systemThinMaterial" || style == "systemUltraThinMaterial"
            if !isClearStyle {
                // 染色模式：添加一层淡淡的背景色
                let tintView = UIView()
                tintView.frame = effectView.bounds
                tintView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                tintView.backgroundColor = isDark
                    ? UIColor.white.withAlphaComponent(0.05)
                    : UIColor.black.withAlphaComponent(0.03)
                effectView.contentView.insertSubview(tintView, at: 0)
            }

            // 使用动画设置 effect（materialize 动画）
            UIView.animate(withDuration: 0.3) { [weak effectView] in
                effectView?.effect = glassEffect
            }

            NSLog("🔮 NativeBlurView: Using UIGlassEffect for \(style), isClear: \(isClearStyle)")
        } else {
            // iOS 13-25: 使用传统模糊效果
            let blurEffect = NativeBlurPlatformView.createBlurEffect(style: style, isDark: isDark)
            effectView = UIVisualEffectView(effect: blurEffect)
            effectView.frame = frame
            effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

            // 设置圆角
            if cornerRadius > 0 {
                effectView.layer.cornerRadius = CGFloat(cornerRadius)
                if #available(iOS 13.0, *) {
                    effectView.layer.cornerCurve = .continuous
                }
                effectView.clipsToBounds = true
            }
        }

        super.init()

        // 设置视图层级
        containerView.addSubview(effectView)

        // 如果启用 Vibrancy 效果（仅 iOS 26 以下）
        if #available(iOS 26.0, *) {
            // iOS 26 的 UIGlassEffect 自带活力效果
            effectView.contentView.addSubview(contentView)
        } else if enableVibrancy, let blurEffect = effectView.effect as? UIBlurEffect {
            let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect)
            let vibrancy = UIVisualEffectView(effect: vibrancyEffect)
            vibrancy.frame = effectView.bounds
            vibrancy.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            effectView.contentView.addSubview(vibrancy)
            vibrancy.contentView.addSubview(contentView)
            vibrancyView = vibrancy
        } else {
            effectView.contentView.addSubview(contentView)
        }

        // 设置容器圆角
        if cornerRadius > 0 {
            containerView.layer.cornerRadius = CGFloat(cornerRadius)
            if #available(iOS 13.0, *) {
                containerView.layer.cornerCurve = .continuous
            }
        }

        // 设置边框（仅 iOS 26 以下需要手动添加）
        if #available(iOS 26.0, *) {
            // iOS 26 的 Liquid Glass 自带边框效果
        } else if enableBorder {
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

    /// 根据样式名称创建对应的 UIBlurEffect（iOS 13-25）
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
