import Cocoa
import FlutterMacOS
import CoreVideo

/**
 显示能力检测 Flutter 插件 (macOS)

 检测 Mac 显示器的 HDR 能力
 */
class DisplayCapabilityChannel: NSObject, FlutterPlugin {

    static let channelName = "com.kkape.mynas/display_capability"

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
        )
        let instance = DisplayCapabilityChannel()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getHdrCapability":
            result(getHdrCapability())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// 获取 HDR 能力
    private func getHdrCapability() -> [String: Any] {
        var isSupported = false
        var supportedTypes: [String] = []
        var maxLuminance: Double = 0
        var colorGamut: String? = nil

        guard let screen = NSScreen.main else {
            return [
                "isSupported": false,
                "supportedTypes": [],
                "maxLuminance": 0,
                "colorGamut": NSNull()
            ]
        }

        // macOS 10.15+ 支持 EDR (Extended Dynamic Range)
        if #available(macOS 10.15, *) {
            // 获取最大 EDR 值
            let maxEdr = screen.maximumExtendedDynamicRangeColorComponentValue

            // EDR > 1.0 表示支持 HDR
            isSupported = maxEdr > 1.0

            if isSupported {
                // 根据 EDR 值估算最大亮度
                maxLuminance = Double(maxEdr) * 100

                // macOS 支持 HDR10 和 HLG
                supportedTypes = ["hdr10", "hlg"]

                // 检查是否支持 Dolby Vision
                // Pro Display XDR 和新款 MacBook Pro 支持 DV
                if maxEdr >= 6.0 {
                    supportedTypes.append("dolbyVision")
                }

                // 检查 HDR10+ 支持
                if maxEdr >= 4.0 {
                    supportedTypes.append("hdr10+")
                }
            }
        }

        // 检测色域
        if let colorSpace = screen.colorSpace {
            let name = colorSpace.localizedName ?? ""
            if name.contains("P3") || name.contains("Display P3") {
                colorGamut = "P3"
            } else if name.contains("2020") || name.contains("Rec. 2020") {
                colorGamut = "Rec.2020"
            } else if name.contains("sRGB") {
                colorGamut = "sRGB"
            }
        }

        // 获取屏幕描述信息
        let deviceDescription = screen.deviceDescription
        if let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            // 使用 Core Graphics 获取更多显示器信息
            if let displayMode = CGDisplayCopyDisplayMode(screenNumber) {
                // 可以获取刷新率等信息
                _ = displayMode.refreshRate
            }
        }

        return [
            "isSupported": isSupported,
            "supportedTypes": supportedTypes,
            "maxLuminance": maxLuminance,
            "colorGamut": colorGamut as Any
        ]
    }
}
