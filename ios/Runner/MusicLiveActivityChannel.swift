import Flutter
import UIKit
import MediaPlayer

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
        // forceRefreshNowPlaying 不需要 iOS 16.1+，单独处理
        if call.method == "forceRefreshNowPlaying" {
            // 强制刷新 Now Playing 信息
            // 通过清除再恢复的方式绕过 iOS MediaRemote 的去重机制
            self.forceRefreshNowPlaying()
            result(nil)
            return
        }

        // Live Activity 相关方法需要 iOS 16.1+
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

// MARK: - Now Playing Refresh
extension MusicLiveActivityChannel {
    /// 本地维护的 nowPlayingInfo 字典
    /// 业界最佳实践：永远不要读取 MPNowPlayingInfoCenter.nowPlayingInfo，只写入
    /// 参考: https://developer.apple.com/forums/thread/32475
    private static var localNowPlayingInfo: [String: Any] = [:]

    /// 刷新计数器
    private static var refreshCounter: Int = 0

    /// 强制刷新 Now Playing 信息
    ///
    /// 业界最佳实践（来自 Apple Developer Forums）：
    /// 1. 维护本地字典，不读取 nowPlayingInfo（只写入）
    /// 2. 正确设置 playbackRate（播放=1.0，暂停=0.0）
    /// 3. 使用 becomeNowPlayingApplication() 告诉系统当前 App 是音频播放器
    ///
    /// 参考:
    /// - https://developer.apple.com/forums/thread/32475
    /// - https://github.com/ryanheise/audio_service/issues/684
    func forceRefreshNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        let commandCenter = MPRemoteCommandCenter.shared()

        // 获取当前信息（用于备份，但主要依赖本地字典）
        guard let currentInfo = center.nowPlayingInfo, !currentInfo.isEmpty else {
            print("MusicLiveActivityChannel: No nowPlayingInfo to refresh")
            return
        }

        MusicLiveActivityChannel.refreshCounter += 1
        let counter = MusicLiveActivityChannel.refreshCounter

        print("MusicLiveActivityChannel: Force refreshing Now Playing (counter=\(counter))")

        // 更新本地字典
        var updatedInfo = currentInfo

        // 关键：确保 playbackRate 正确设置
        // 这是 iOS 判断 App 是否是"活跃音频播放器"的关键字段
        let currentRate = updatedInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 1.0
        updatedInfo[MPNowPlayingInfoPropertyPlaybackRate] = currentRate

        // 更新 elapsedPlaybackTime 确保内容不同
        if let elapsed = updatedInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double {
            let offset = Double(counter) * 0.0001
            updatedInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed + offset
        }

        // 保存到本地字典
        MusicLiveActivityChannel.localNowPlayingInfo = updatedInfo

        // 方法 1：直接设置（不清除）
        // 根据 Apple 论坛的建议，直接设置整个字典比清除再恢复更可靠
        center.nowPlayingInfo = updatedInfo

        // 方法 2：确保 Remote Commands 处于激活状态
        // 这会让系统知道当前 App 是活跃的音频播放器
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true

        print("MusicLiveActivityChannel: Now Playing refreshed (rate=\(currentRate))")
    }

    /// 设置当前 App 为活跃的音频播放器
    /// 在需要确保灵动岛显示时调用
    func becomeActiveNowPlayingApp() {
        let center = MPNowPlayingInfoCenter.default()

        // 如果有本地缓存的信息，使用它来刷新
        if !MusicLiveActivityChannel.localNowPlayingInfo.isEmpty {
            var info = MusicLiveActivityChannel.localNowPlayingInfo

            // 确保 playbackRate 为 1.0（表示正在播放）
            info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0

            center.nowPlayingInfo = info
            print("MusicLiveActivityChannel: Set as active Now Playing app")
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
