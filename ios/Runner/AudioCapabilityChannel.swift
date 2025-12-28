import Flutter
import AVFoundation

/**
 音频能力检测 Flutter 插件

 检测设备的音频直通能力
 */
class AudioCapabilityChannel: NSObject, FlutterPlugin {

    static let channelName = "com.kkape.mynas/audio_capability"

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = AudioCapabilityChannel()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPassthroughCapability":
            result(getPassthroughCapability())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// 获取音频直通能力
    private func getPassthroughCapability() -> [String: Any] {
        var isSupported = false
        var supportedCodecs: [String] = []
        var outputDevice = "unknown"
        var maxChannels = 2
        var deviceName: String? = nil

        let session = AVAudioSession.sharedInstance()

        do {
            // 激活音频会话以获取准确的路由信息
            try session.setActive(true)
        } catch {
            // 忽略激活错误
        }

        let route = session.currentRoute

        for output in route.outputs {
            let portType = output.portType

            switch portType {
            case .HDMI:
                // HDMI 输出支持直通
                isSupported = true
                outputDevice = "hdmi"
                deviceName = output.portName

                // HDMI 通常支持所有主流格式
                supportedCodecs = ["ac3", "eac3", "dts", "dts-hd", "truehd"]
                maxChannels = 8

            case .airPlay:
                // AirPlay 可能支持有限的直通
                isSupported = true
                outputDevice = "airplay"
                deviceName = output.portName

                // AirPlay 2 支持杜比全景声
                supportedCodecs = ["ac3", "eac3"]
                maxChannels = 8

            case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
                // 蓝牙不支持传统直通
                outputDevice = "bluetooth"
                deviceName = output.portName
                maxChannels = 2

            case .builtInSpeaker:
                outputDevice = "speaker"
                deviceName = "内置扬声器"
                maxChannels = 2

            case .headphones:
                outputDevice = "headphones"
                deviceName = output.portName
                maxChannels = 2

            case .usbAudio:
                // USB 音频设备可能支持直通
                isSupported = true
                outputDevice = "usb"
                deviceName = output.portName
                supportedCodecs = ["ac3", "dts"]
                maxChannels = 8

            default:
                deviceName = output.portName
            }

            // 找到第一个有效的输出设备就返回
            if isSupported {
                break
            }
        }

        return [
            "isSupported": isSupported,
            "supportedCodecs": supportedCodecs,
            "outputDevice": outputDevice,
            "maxChannels": maxChannels,
            "deviceName": deviceName as Any
        ]
    }
}
