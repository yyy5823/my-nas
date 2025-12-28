import Flutter
import UIKit
import AVFoundation

/**
 显示能力检测 Flutter 插件

 检测设备的 HDR 显示能力
 */
class DisplayCapabilityChannel: NSObject, FlutterPlugin {

    static let channelName = "com.kkape.mynas/display_capability"

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
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

        // iOS 16+ 支持 EDR (Extended Dynamic Range)
        if #available(iOS 16.0, *) {
            let screen = UIScreen.main
            let maxEdr = screen.potentialEDRHeadroom

            // EDR headroom > 1.0 表示支持 HDR
            isSupported = maxEdr > 1.0

            if isSupported {
                // 根据 EDR headroom 估算最大亮度
                // 标准 SDR 是 100 nits，HDR 可以到 1000+ nits
                maxLuminance = Double(maxEdr) * 100

                // iOS 设备通常支持 HDR10 和 HLG
                supportedTypes = ["hdr10", "hlg"]

                // 新款 iPhone/iPad 可能支持 Dolby Vision
                if maxEdr >= 4.0 {
                    supportedTypes.append("dolbyVision")
                }
            }
        } else if #available(iOS 10.0, *) {
            // iOS 10-15: 使用传统方式检测
            let screen = UIScreen.main

            // 检查是否是广色域显示器
            if #available(iOS 10.0, *) {
                // iPhone 7 及更新设备支持 P3 色域
                // 这些设备通常也支持 HDR
                let scale = screen.scale
                let bounds = screen.bounds

                // 大于 1080p 的 Retina 显示器可能支持 HDR
                if scale >= 3.0 && bounds.height >= 812 {
                    isSupported = true
                    supportedTypes = ["hdr10", "hlg"]
                    maxLuminance = 800 // 估算值
                    colorGamut = "P3"
                }
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
