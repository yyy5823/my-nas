import Flutter
import UIKit

/// Flutter Method Channel for Music Live Activity
/// 为个人开发者账号提供不依赖 Push Notification 的 Live Activity 支持
class MusicLiveActivityChannel: NSObject, FlutterPlugin {

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.kkape.mynas/music_live_activity",
            binaryMessenger: registrar.messenger()
        )
        let instance = MusicLiveActivityChannel()
        registrar.addMethodCallDelegate(instance, channel: channel)
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
