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
    /// 核心问题：iOS MediaRemote 框架有系统级去重机制
    /// "Setting identical nowPlayingInfo, skipping update"
    /// 即使修改 elapsedPlaybackTime，只要核心内容（标题、艺术家、封面像素）相同，iOS 就跳过
    ///
    /// 解决方案：清空 → 延迟 → 重设
    /// 参考: https://developer.apple.com/videos/play/wwdc2022/110338/
    /// 参考: https://github.com/ryanheise/audio_service/issues/684
    func forceRefreshNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        let commandCenter = MPRemoteCommandCenter.shared()

        // 获取当前信息
        guard let currentInfo = center.nowPlayingInfo, !currentInfo.isEmpty else {
            print("MusicLiveActivityChannel: No nowPlayingInfo to refresh")
            return
        }

        MusicLiveActivityChannel.refreshCounter += 1
        let counter = MusicLiveActivityChannel.refreshCounter

        print("MusicLiveActivityChannel: Force refreshing Now Playing (counter=\(counter)) - using clear-delay-reset strategy")

        // 保存当前信息到本地字典
        MusicLiveActivityChannel.localNowPlayingInfo = currentInfo

        // 获取当前播放速率
        let currentRate = currentInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 1.0

        // 步骤 1: 清空 nowPlayingInfo，强制 iOS 忘记当前状态
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        print("MusicLiveActivityChannel: Cleared nowPlayingInfo")

        // 步骤 2: 延迟后重新设置（给 iOS 充足时间处理清空操作）
        // 使用 150ms 延迟确保 iOS MediaRemote 框架完成状态重置
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // 重新构建 nowPlayingInfo
            var updatedInfo = currentInfo

            // 确保 playbackRate 正确设置
            updatedInfo[MPNowPlayingInfoPropertyPlaybackRate] = currentRate

            // 重新设置 nowPlayingInfo
            center.nowPlayingInfo = updatedInfo

            // 设置 playbackState
            if currentRate > 0 {
                center.playbackState = .playing
            } else {
                center.playbackState = .paused
            }

            // 确保 Remote Commands 处于激活状态
            commandCenter.playCommand.isEnabled = true
            commandCenter.pauseCommand.isEnabled = true
            commandCenter.togglePlayPauseCommand.isEnabled = true
            commandCenter.nextTrackCommand.isEnabled = true
            commandCenter.previousTrackCommand.isEnabled = true

            print("MusicLiveActivityChannel: Now Playing restored (rate=\(currentRate), state=\(currentRate > 0 ? "playing" : "paused"))")
        }
    }

    /// 设置当前 App 为活跃的音频播放器
    /// 在需要确保灵动岛显示时调用
    func becomeActiveNowPlayingApp() {
        let center = MPNowPlayingInfoCenter.default()
        let commandCenter = MPRemoteCommandCenter.shared()

        // 如果有本地缓存的信息，使用它来刷新
        if !MusicLiveActivityChannel.localNowPlayingInfo.isEmpty {
            var info = MusicLiveActivityChannel.localNowPlayingInfo

            // 确保 playbackRate 为 1.0（表示正在播放）
            info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0

            center.nowPlayingInfo = info
            center.playbackState = .playing

            // 确保 Remote Commands 处于激活状态
            commandCenter.playCommand.isEnabled = true
            commandCenter.pauseCommand.isEnabled = true
            commandCenter.togglePlayPauseCommand.isEnabled = true
            commandCenter.nextTrackCommand.isEnabled = true
            commandCenter.previousTrackCommand.isEnabled = true

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
