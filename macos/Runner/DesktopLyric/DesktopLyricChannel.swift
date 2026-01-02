import Cocoa
import FlutterMacOS

/// 桌面歌词 Method Channel
class DesktopLyricChannel: NSObject, FlutterPlugin {
    static let channelName = "com.kkape.mynas/desktop_lyric"

    private var channel: FlutterMethodChannel?
    private let controller = DesktopLyricController.shared

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
        )
        let instance = DesktopLyricChannel()
        instance.channel = channel
        instance.controller.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            handleInit(call, result: result)
        case "show":
            controller.show()
            result(nil)
        case "hide":
            controller.hide()
            result(nil)
        case "updateLyric":
            handleUpdateLyric(call, result: result)
        case "updatePlayingState":
            handleUpdatePlayingState(call, result: result)
        case "setPosition":
            handleSetPosition(call, result: result)
        case "getPosition":
            handleGetPosition(result: result)
        case "updateSettings":
            handleUpdateSettings(call, result: result)
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

        let settings = DesktopLyricSettings.fromJson(settingsJson)
        controller.initialize(settings: settings)
        result(nil)
    }

    private func handleUpdateLyric(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }

        var currentLine: LyricLine? = nil
        var nextLine: LyricLine? = nil

        if let currentData = args["currentLine"] as? [String: Any] {
            currentLine = LyricLine(
                text: currentData["text"] as? String ?? "",
                translation: currentData["translation"] as? String
            )
        }

        if let nextData = args["nextLine"] as? [String: Any] {
            nextLine = LyricLine(
                text: nextData["text"] as? String ?? "",
                translation: nextData["translation"] as? String
            )
        }

        let isPlaying = args["isPlaying"] as? Bool ?? false

        controller.updateLyric(currentLine: currentLine, nextLine: nextLine, isPlaying: isPlaying)
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

    private func handleSetPosition(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let x = args["x"] as? Double,
              let y = args["y"] as? Double else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing position", details: nil))
            return
        }

        controller.setPosition(NSPoint(x: x, y: y))
        result(nil)
    }

    private func handleGetPosition(result: @escaping FlutterResult) {
        if let position = controller.getPosition() {
            result(["x": position.x, "y": position.y])
        } else {
            result(nil)
        }
    }

    private func handleUpdateSettings(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let settingsJson = args["settings"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing settings", details: nil))
            return
        }

        let settings = DesktopLyricSettings.fromJson(settingsJson)
        controller.updateSettings(settings: settings)
        result(nil)
    }
}

/// 歌词行数据
struct LyricLine {
    let text: String
    let translation: String?

    var hasTranslation: Bool {
        return translation != nil && !translation!.isEmpty
    }
}

/// 桌面歌词设置
struct DesktopLyricSettings {
    var enabled: Bool = false
    var fontSize: CGFloat = 28.0
    var textColor: NSColor = .white
    var backgroundColor: NSColor = NSColor.black.withAlphaComponent(0.8)
    var opacity: CGFloat = 0.9
    var showTranslation: Bool = true
    var showNextLine: Bool = true
    var alwaysOnTop: Bool = true
    var lockPosition: Bool = false
    var windowX: CGFloat?
    var windowY: CGFloat?
    var windowWidth: CGFloat = 800.0
    var windowHeight: CGFloat = 120.0

    static func fromJson(_ json: [String: Any]) -> DesktopLyricSettings {
        var settings = DesktopLyricSettings()
        settings.enabled = json["enabled"] as? Bool ?? false
        settings.fontSize = CGFloat(json["fontSize"] as? Double ?? 28.0)

        if let colorValue = json["textColor"] as? Int {
            settings.textColor = NSColor(
                red: CGFloat((colorValue >> 16) & 0xFF) / 255.0,
                green: CGFloat((colorValue >> 8) & 0xFF) / 255.0,
                blue: CGFloat(colorValue & 0xFF) / 255.0,
                alpha: CGFloat((colorValue >> 24) & 0xFF) / 255.0
            )
        }

        if let colorValue = json["backgroundColor"] as? Int {
            settings.backgroundColor = NSColor(
                red: CGFloat((colorValue >> 16) & 0xFF) / 255.0,
                green: CGFloat((colorValue >> 8) & 0xFF) / 255.0,
                blue: CGFloat(colorValue & 0xFF) / 255.0,
                alpha: CGFloat((colorValue >> 24) & 0xFF) / 255.0
            )
        }

        settings.opacity = CGFloat(json["opacity"] as? Double ?? 0.9)
        settings.showTranslation = json["showTranslation"] as? Bool ?? true
        settings.showNextLine = json["showNextLine"] as? Bool ?? true
        settings.alwaysOnTop = json["alwaysOnTop"] as? Bool ?? true
        settings.lockPosition = json["lockPosition"] as? Bool ?? false

        if let x = json["windowX"] as? Double {
            settings.windowX = CGFloat(x)
        }
        if let y = json["windowY"] as? Double {
            settings.windowY = CGFloat(y)
        }

        settings.windowWidth = CGFloat(json["windowWidth"] as? Double ?? 800.0)
        settings.windowHeight = CGFloat(json["windowHeight"] as? Double ?? 120.0)

        return settings
    }
}
