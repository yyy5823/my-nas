import Cocoa
import FlutterMacOS

/// macOS 原生模糊视图 - 使用 NSVisualEffectView 实现真正的系统级毛玻璃效果
///
/// 支持的材质类型：
/// - titlebar: 标题栏材质
/// - menu: 菜单材质
/// - popover: 弹出框材质
/// - sidebar: 侧边栏材质
/// - headerView: 头部视图材质
/// - sheet: 表单材质
/// - windowBackground: 窗口背景材质
/// - hudWindow: HUD 窗口材质
/// - fullScreenUI: 全屏 UI 材质
/// - toolTip: 工具提示材质
/// - contentBackground: 内容背景材质
/// - underWindowBackground: 窗口下方背景材质
/// - underPageBackground: 页面下方背景材质
///
/// 特点：
/// - 硬件加速，性能优异
/// - 自动适配系统主题（亮色/暗色模式）
/// - 与 macOS 系统 UI 风格保持一致
/// - 支持活力效果（Vibrancy）

// MARK: - Platform View Factory

class NativeBlurViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withViewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> NSView {
        return NativeBlurPlatformView(
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    /// 声明需要解码参数
    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - Platform View

class NativeBlurPlatformView: NSView {
    private let visualEffectView: NSVisualEffectView

    init(
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger?
    ) {
        // 创建 NSVisualEffectView
        visualEffectView = NSVisualEffectView()

        super.init(frame: .zero)

        // 解析参数
        let params = args as? [String: Any] ?? [:]
        let material = params["material"] as? String ?? "contentBackground"
        let isDark = params["isDark"] as? Bool ?? false
        let cornerRadius = params["cornerRadius"] as? Double ?? 0
        let enableBorder = params["enableBorder"] as? Bool ?? true
        let borderOpacity = params["borderOpacity"] as? Double ?? 0.2
        let blendingMode = params["blendingMode"] as? String ?? "behindWindow"

        // 配置 NSVisualEffectView
        visualEffectView.material = NativeBlurPlatformView.createMaterial(material)
        visualEffectView.blendingMode = NativeBlurPlatformView.createBlendingMode(blendingMode)
        visualEffectView.state = .active

        // 设置外观
        if isDark {
            visualEffectView.appearance = NSAppearance(named: .darkAqua)
        } else {
            visualEffectView.appearance = NSAppearance(named: .aqua)
        }

        // 配置视图
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.wantsLayer = true

        // 添加到视图层级
        self.addSubview(visualEffectView)

        // 设置约束
        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: self.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])

        // 设置圆角
        if cornerRadius > 0 {
            self.wantsLayer = true
            self.layer?.cornerRadius = CGFloat(cornerRadius)
            self.layer?.masksToBounds = true
            visualEffectView.layer?.cornerRadius = CGFloat(cornerRadius)
        }

        // 设置边框（模拟玻璃边缘高光）
        if enableBorder {
            self.wantsLayer = true
            self.layer?.borderWidth = 0.5
            let borderColor = isDark
                ? NSColor.white.withAlphaComponent(CGFloat(borderOpacity))
                : NSColor.black.withAlphaComponent(CGFloat(borderOpacity * 0.5))
            self.layer?.borderColor = borderColor.cgColor
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 根据材质名称创建对应的 NSVisualEffectView.Material
    private static func createMaterial(_ material: String) -> NSVisualEffectView.Material {
        switch material {
        case "titlebar":
            return .titlebar
        case "menu":
            return .menu
        case "popover":
            return .popover
        case "sidebar":
            return .sidebar
        case "headerView":
            return .headerView
        case "sheet":
            return .sheet
        case "windowBackground":
            return .windowBackground
        case "hudWindow":
            return .hudWindow
        case "fullScreenUI":
            return .fullScreenUI
        case "toolTip":
            return .toolTip
        case "contentBackground":
            return .contentBackground
        case "underWindowBackground":
            return .underWindowBackground
        case "underPageBackground":
            return .underPageBackground
        default:
            return .contentBackground
        }
    }

    /// 根据混合模式名称创建对应的 BlendingMode
    private static func createBlendingMode(_ mode: String) -> NSVisualEffectView.BlendingMode {
        switch mode {
        case "behindWindow":
            return .behindWindow
        case "withinWindow":
            return .withinWindow
        default:
            return .behindWindow
        }
    }
}

// MARK: - Plugin Registration

class NativeBlurViewPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let factory = NativeBlurViewFactory(messenger: registrar.messenger)
        registrar.register(factory, withId: "com.kkape.mynas/native_blur_view")
    }
}
