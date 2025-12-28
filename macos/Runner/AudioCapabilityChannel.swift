import Cocoa
import FlutterMacOS
import CoreAudio
import AVFoundation

/**
 音频能力检测 Flutter 插件 (macOS)

 检测 Mac 的音频直通能力
 */
class AudioCapabilityChannel: NSObject, FlutterPlugin {

    static let channelName = "com.kkape.mynas/audio_capability"

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
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

        // 获取默认输出设备
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        guard status == noErr else {
            return [
                "isSupported": false,
                "supportedCodecs": [],
                "outputDevice": "unknown",
                "maxChannels": 2,
                "deviceName": NSNull()
            ]
        }

        // 获取设备名称
        deviceName = getDeviceName(deviceID: deviceID)

        // 获取设备传输类型
        let transportType = getTransportType(deviceID: deviceID)

        // 获取最大声道数
        maxChannels = getMaxChannels(deviceID: deviceID)

        // 根据传输类型判断能力
        switch transportType {
        case kAudioDeviceTransportTypeHDMI:
            isSupported = true
            outputDevice = "hdmi"
            supportedCodecs = ["ac3", "eac3", "dts", "dts-hd", "truehd"]

        case kAudioDeviceTransportTypeDisplayPort:
            isSupported = true
            outputDevice = "hdmi"  // DisplayPort 也支持音频直通
            supportedCodecs = ["ac3", "eac3", "dts", "dts-hd", "truehd"]

        case kAudioDeviceTransportTypeThunderbolt:
            // Thunderbolt 显示器可能支持直通
            isSupported = true
            outputDevice = "hdmi"
            supportedCodecs = ["ac3", "eac3", "dts"]

        case kAudioDeviceTransportTypeUSB:
            // USB DAC 可能支持直通
            isSupported = true
            outputDevice = "usb"
            supportedCodecs = ["ac3", "dts"]

        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            outputDevice = "bluetooth"
            // 蓝牙不支持传统直通

        case kAudioDeviceTransportTypeBuiltIn:
            outputDevice = "speaker"
            // 内置扬声器不支持直通

        case kAudioDeviceTransportTypeAirPlay:
            outputDevice = "airplay"
            isSupported = true
            supportedCodecs = ["ac3", "eac3"]

        default:
            outputDevice = "unknown"
        }

        return [
            "isSupported": isSupported,
            "supportedCodecs": supportedCodecs,
            "outputDevice": outputDevice,
            "maxChannels": maxChannels,
            "deviceName": deviceName as Any
        ]
    }

    /// 获取设备名称
    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &name
        )

        return status == noErr ? name as String : nil
    }

    /// 获取传输类型
    private func getTransportType(deviceID: AudioDeviceID) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &transportType
        )

        return status == noErr ? transportType : 0
    }

    /// 获取最大声道数
    private func getMaxChannels(deviceID: AudioDeviceID) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize
        )

        guard status == noErr, propertySize > 0 else { return 2 }

        let bufferListPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(propertySize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPtr.deallocate() }

        status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            bufferListPtr
        )

        guard status == noErr else { return 2 }

        let bufferList = bufferListPtr.assumingMemoryBound(to: AudioBufferList.self)
        var totalChannels = 0

        let numBuffers = Int(bufferList.pointee.mNumberBuffers)
        let buffersPtr = UnsafeMutableAudioBufferListPointer(bufferList)

        for i in 0..<numBuffers {
            totalChannels += Int(buffersPtr[i].mNumberChannels)
        }

        return max(totalChannels, 2)
    }
}
