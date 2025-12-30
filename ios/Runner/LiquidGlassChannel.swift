import Flutter
import UIKit

/// Liquid Glass Method Channel
/// 提供 Flutter 与原生 Liquid Glass 功能之间的通信
///
/// 功能：
/// - 检查 Liquid Glass 可用性（iOS 26+）
/// - 获取系统玻璃效果配置
/// - 动态更新导航栏状态
class LiquidGlassChannel: NSObject, FlutterPlugin {

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.kkape.mynas/liquid_glass",
            binaryMessenger: registrar.messenger()
        )

        let instance = LiquidGlassChannel()
        registrar.addMethodCallDelegate(instance, channel: channel)

        print("LiquidGlassChannel: Registered")
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            // 检查是否支持 Liquid Glass (iOS 26+)
            result(isLiquidGlassSupported())

        case "getSystemInfo":
            // 获取系统信息
            result(getSystemInfo())

        case "getGlassConfig":
            // 获取玻璃效果配置
            result(getGlassConfig())

        case "hapticFeedback":
            // 触觉反馈
            if let type = call.arguments as? String {
                performHapticFeedback(type: type)
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Private Methods

    private func isLiquidGlassSupported() -> Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    private func getSystemInfo() -> [String: Any] {
        var info: [String: Any] = [
            "isLiquidGlassSupported": isLiquidGlassSupported(),
            "iosVersion": UIDevice.current.systemVersion,
            "deviceModel": UIDevice.current.model,
        ]

        // iOS 版本号
        let version = ProcessInfo.processInfo.operatingSystemVersion
        info["iosMajorVersion"] = version.majorVersion
        info["iosMinorVersion"] = version.minorVersion

        // 屏幕信息
        let screen = UIScreen.main
        info["screenScale"] = screen.scale
        info["screenWidth"] = screen.bounds.width
        info["screenHeight"] = screen.bounds.height

        // 安全区域
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            let safeArea = window.safeAreaInsets
            info["safeAreaTop"] = safeArea.top
            info["safeAreaBottom"] = safeArea.bottom
            info["safeAreaLeft"] = safeArea.left
            info["safeAreaRight"] = safeArea.right
        }

        // 辅助功能设置
        info["reduceTransparency"] = UIAccessibility.isReduceTransparencyEnabled
        info["reduceMotion"] = UIAccessibility.isReduceMotionEnabled

        return info
    }

    private func getGlassConfig() -> [String: Any] {
        var config: [String: Any] = [:]

        if #available(iOS 26.0, *) {
            // iOS 26+ Liquid Glass 配置
            config["glassType"] = "liquidGlass"
            config["supportsInteractive"] = true
            config["supportsMorphing"] = true
            config["supportsGlassEffectContainer"] = true

            // 推荐的圆角半径
            config["recommendedCornerRadius"] = 30.0
            config["navBarHeight"] = 60.0
            config["navBarBottomPadding"] = 16.0
            config["navBarHorizontalPadding"] = 16.0

        } else {
            // iOS < 26 回退配置
            config["glassType"] = "visualEffect"
            config["supportsInteractive"] = false
            config["supportsMorphing"] = false
            config["supportsGlassEffectContainer"] = false

            config["recommendedCornerRadius"] = 25.0
            config["navBarHeight"] = 56.0
            config["navBarBottomPadding"] = 0.0
            config["navBarHorizontalPadding"] = 0.0
        }

        // 通用配置
        config["blurStyle"] = UIAccessibility.isReduceTransparencyEnabled ? "solid" : "blur"

        return config
    }

    private func performHapticFeedback(type: String) {
        switch type {
        case "light":
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        case "medium":
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        case "heavy":
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        case "selection":
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
        case "success":
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case "warning":
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        case "error":
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        default:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }
}

// MARK: - Navigation Bar Specific Channel

/// 导航栏专用通道
/// 用于处理导航栏的双向通信
class LiquidGlassNavBarChannel: NSObject {
    private var channel: FlutterMethodChannel?
    private weak var platformView: LiquidGlassPlatformView?

    init(messenger: FlutterBinaryMessenger, viewId: Int64) {
        super.init()

        let channelName = "com.kkape.mynas/liquid_glass_nav_bar_\(viewId)"
        channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)

        channel?.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
    }

    func setPlatformView(_ view: LiquidGlassPlatformView) {
        self.platformView = view
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "updateSelectedIndex":
            // 从 Flutter 更新选中索引
            if let index = call.arguments as? Int {
                // 通知 Platform View 更新
                NotificationCenter.default.post(
                    name: .liquidGlassNavBarUpdateIndex,
                    object: nil,
                    userInfo: ["index": index]
                )
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// 通知 Flutter 导航项被点击
    func notifyNavTap(index: Int) {
        channel?.invokeMethod("onNavTap", arguments: index)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let liquidGlassNavBarUpdateIndex = Notification.Name("liquidGlassNavBarUpdateIndex")
}
