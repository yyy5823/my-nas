import Flutter
import UIKit

/// Flutter Method Channel for Music Live Activity
/// 为个人开发者账号提供不依赖 Push Notification 的 Live Activity 支持
class MusicLiveActivityChannel: NSObject, FlutterPlugin {

    /// EventChannel sink 用于发送控制命令到 Flutter
    private var eventSink: FlutterEventSink?

    static func register(with registrar: FlutterPluginRegistrar) {
        // Method Channel
        let methodChannel = FlutterMethodChannel(
            name: "com.kkape.mynas/music_live_activity",
            binaryMessenger: registrar.messenger()
        )

        // Event Channel 用于接收来自灵动岛的控制命令
        let eventChannel = FlutterEventChannel(
            name: "com.kkape.mynas/music_live_activity_events",
            binaryMessenger: registrar.messenger()
        )

        let instance = MusicLiveActivityChannel()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)

        // 设置控制命令回调
        if #available(iOS 16.1, *) {
            MusicLiveActivityManager.shared.onControlCommand = { [weak instance] command in
                print("MusicLiveActivityChannel: Forwarding command to Flutter: \(command)")
                instance?.eventSink?(command)
            }
        }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if #available(iOS 16.1, *) {
            switch call.method {
            case "areActivitiesEnabled":
                result(MusicLiveActivityManager.shared.areActivitiesEnabled())

            case "createActivity":
                guard let args = call.arguments as? [String: Any],
                      let data = args["data"] as? [String: Any] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing data argument", details: nil))
                    return
                }

                if let activityId = MusicLiveActivityManager.shared.createActivity(data: data) {
                    result(activityId)
                } else {
                    result(FlutterError(code: "CREATE_FAILED", message: "Failed to create activity", details: nil))
                }

            case "updateActivity":
                guard let args = call.arguments as? [String: Any],
                      let data = args["data"] as? [String: Any] else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Missing data argument", details: nil))
                    return
                }

                MusicLiveActivityManager.shared.updateActivity(data: data)
                result(nil)

            case "endActivity":
                MusicLiveActivityManager.shared.endActivity()
                result(nil)

            case "endAllActivities":
                MusicLiveActivityManager.shared.endAllActivities()
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        } else {
            result(FlutterError(code: "UNSUPPORTED", message: "Live Activities require iOS 16.1+", details: nil))
        }
    }
}

// MARK: - FlutterStreamHandler
extension MusicLiveActivityChannel: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        print("MusicLiveActivityChannel: EventChannel listening started")
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        print("MusicLiveActivityChannel: EventChannel listening cancelled")
        return nil
    }
}
