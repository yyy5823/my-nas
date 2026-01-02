import Cocoa
import FlutterMacOS

/// 状态栏 Method Channel
class StatusBarChannel: NSObject, FlutterPlugin {
    static let channelName = "com.kkape.mynas/menu_bar"

    private var channel: FlutterMethodChannel?
    private let controller = StatusBarController.shared

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
        )
        let instance = StatusBarChannel()
        instance.channel = channel
        instance.controller.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            handleInit(call, result: result)
        case "updatePlayingState":
            handleUpdatePlayingState(call, result: result)
        case "updateMusicInfo":
            handleUpdateMusicInfo(call, result: result)
        case "updateLyric":
            handleUpdateLyric(call, result: result)
        case "setVisible":
            handleSetVisible(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleInit(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let settingsJson = args["settings"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing settings", details: nil))
            return
        }

        let settings = MenuBarSettings.fromJson(settingsJson)
        controller.initialize(settings: settings)
        result(nil)
    }

    private func handleUpdatePlayingState(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let isPlaying = args["isPlaying"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing isPlaying", details: nil))
            return
        }

        controller.updatePlayingState(isPlaying: isPlaying)
        result(nil)
    }

    private func handleUpdateMusicInfo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }

        let info = MusicInfo(
            title: args["title"] as? String ?? "",
            artist: args["artist"] as? String ?? "",
            album: args["album"] as? String,
            coverData: args["coverData"] as? FlutterStandardTypedData,
            isPlaying: args["isPlaying"] as? Bool ?? false,
            progress: args["progress"] as? Double ?? 0.0,
            currentTimeMs: args["currentTimeMs"] as? Int ?? 0,
            totalTimeMs: args["totalTimeMs"] as? Int ?? 0
        )

        controller.updateMusicInfo(info: info)
        result(nil)
    }

    private func handleUpdateLyric(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }

        controller.updateLyric(
            currentLine: args["currentLine"] as? String,
            nextLine: args["nextLine"] as? String
        )
        result(nil)
    }

    private func handleSetVisible(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let visible = args["visible"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing visible", details: nil))
            return
        }

        controller.setVisible(visible: visible)
        result(nil)
    }
}

/// 音乐信息
struct MusicInfo {
    var title: String
    var artist: String
    var album: String?
    var coverData: FlutterStandardTypedData?
    var isPlaying: Bool
    var progress: Double
    var currentTimeMs: Int
    var totalTimeMs: Int

    var coverImage: NSImage? {
        guard let data = coverData?.data else { return nil }
        return NSImage(data: data)
    }

    var currentTimeText: String {
        return formatTime(ms: currentTimeMs)
    }

    var totalTimeText: String {
        return formatTime(ms: totalTimeMs)
    }

    private func formatTime(ms: Int) -> String {
        let seconds = ms / 1000
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

/// 状态栏设置
struct MenuBarSettings {
    var enabled: Bool = true
    var showPlayingAnimation: Bool = true
    var showProgressBar: Bool = false

    static func fromJson(_ json: [String: Any]) -> MenuBarSettings {
        var settings = MenuBarSettings()
        settings.enabled = json["enabled"] as? Bool ?? true
        settings.showPlayingAnimation = json["showPlayingAnimation"] as? Bool ?? true
        settings.showProgressBar = json["showProgressBar"] as? Bool ?? false
        return settings
    }
}
