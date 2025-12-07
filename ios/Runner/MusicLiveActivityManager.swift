import Foundation
import ActivityKit
import UIKit
import Flutter

/// 音乐 Live Activity 管理器
/// 专门为个人开发者账号设计，使用 pushType: nil 来避免 Push Notification 能力限制
@available(iOS 16.1, *)
class MusicLiveActivityManager {
    static let shared = MusicLiveActivityManager()

    /// App Group ID
    private let appGroupId = "group.com.kkape.mynas"

    /// Darwin 通知名称（用于从 Widget Extension 接收控制命令）
    private let darwinNotificationName = "com.kkape.mynas.musicControl"

    /// 共享的 UserDefaults
    private lazy var sharedDefaults: UserDefaults? = {
        UserDefaults(suiteName: appGroupId)
    }()

    /// 当前活动 ID
    private var currentActivityId: String?

    /// 当前活动的 UUID (用于数据前缀)
    private var currentActivityUUID: UUID?

    /// 控制命令回调
    var onControlCommand: ((String) -> Void)?

    /// 上次处理的命令时间戳（防止重复处理）
    private var lastCommandTimestamp: TimeInterval = 0

    private init() {
        // 注册 Darwin 通知监听
        registerDarwinNotificationListener()
    }

    /// 注册 Darwin 通知监听器
    /// Widget Extension 发送的控制命令会通过此通知传递
    private func registerDarwinNotificationListener() {
        let notificationName = CFNotificationName(darwinNotificationName as CFString)

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { (_, observer, name, _, _) in
                guard let observer = observer else { return }
                let manager = Unmanaged<MusicLiveActivityManager>.fromOpaque(observer).takeUnretainedValue()
                manager.handleDarwinNotification()
            },
            darwinNotificationName as CFString,
            nil,
            .deliverImmediately
        )

        print("MusicLiveActivityManager: Darwin notification listener registered for \(darwinNotificationName)")
    }

    /// 处理来自 Widget Extension 的 Darwin 通知
    private func handleDarwinNotification() {
        guard let defaults = sharedDefaults else {
            print("MusicLiveActivityManager: SharedDefaults not available for reading command")
            return
        }

        // 同步以获取最新数据
        defaults.synchronize()

        // 读取命令和时间戳
        guard let command = defaults.string(forKey: "musicControlCommand") else {
            print("MusicLiveActivityManager: No command found in UserDefaults")
            return
        }

        let timestamp = defaults.double(forKey: "musicControlTimestamp")

        // 防止重复处理同一命令
        if timestamp <= lastCommandTimestamp {
            print("MusicLiveActivityManager: Command already processed (timestamp: \(timestamp))")
            return
        }

        lastCommandTimestamp = timestamp

        print("MusicLiveActivityManager: Received control command: \(command), timestamp: \(timestamp)")

        // 在主线程调用回调
        DispatchQueue.main.async { [weak self] in
            self?.onControlCommand?(command)
        }

        // 清除命令
        defaults.removeObject(forKey: "musicControlCommand")
        defaults.synchronize()
    }

    /// 注销 Darwin 通知监听器
    func unregisterDarwinNotificationListener() {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(darwinNotificationName as CFString),
            nil
        )
        print("MusicLiveActivityManager: Darwin notification listener unregistered")
    }

    /// 检查 Live Activities 是否可用
    func areActivitiesEnabled() -> Bool {
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// 创建音乐 Live Activity
    /// - Parameters:
    ///   - data: 活动数据 (title, artist, album, isPlaying, progress, currentTime, totalTime, coverImage)
    /// - Returns: 活动 ID，如果失败则返回 nil
    func createActivity(data: [String: Any]) -> String? {
        // 检查是否已启用
        guard areActivitiesEnabled() else {
            print("MusicLiveActivityManager: Live Activities not enabled")
            return nil
        }

        // 如果已有活动，先结束它
        if currentActivityId != nil {
            endActivity()
        }

        // 创建属性
        let activityUUID = UUID()
        let attributes = LiveActivitiesAppAttributes(id: activityUUID)
        let contentState = LiveActivitiesAppAttributes.ContentState(appGroupId: appGroupId, updateTimestamp: Date().timeIntervalSince1970)

        // 保存数据到 UserDefaults
        saveDataToDefaults(data: data, prefix: activityUUID)

        do {
            let activity: Activity<LiveActivitiesAppAttributes>

            if #available(iOS 16.2, *) {
                let activityContent = ActivityContent(state: contentState, staleDate: nil)
                // 关键：使用 pushType: nil 来避免 Push Notification 限制
                activity = try Activity.request(
                    attributes: attributes,
                    content: activityContent,
                    pushType: nil
                )
            } else {
                // iOS 16.1 使用旧 API
                activity = try Activity<LiveActivitiesAppAttributes>.request(
                    attributes: attributes,
                    contentState: contentState,
                    pushType: nil
                )
            }

            currentActivityId = activity.id
            currentActivityUUID = activityUUID

            print("MusicLiveActivityManager: Activity created with ID: \(activity.id), UUID: \(activityUUID)")
            return activity.id
        } catch {
            print("MusicLiveActivityManager: Failed to create activity: \(error.localizedDescription)")
            return nil
        }
    }

    /// 更新 Live Activity
    /// - Parameters:
    ///   - data: 更新的数据
    func updateActivity(data: [String: Any]) {
        guard let activityId = currentActivityId,
              let activityUUID = currentActivityUUID else {
            print("MusicLiveActivityManager: No active activity to update")
            return
        }

        // 更新 UserDefaults 中的数据
        saveDataToDefaults(data: data, prefix: activityUUID)

        // 找到当前活动并更新
        Task {
            let activities = Activity<LiveActivitiesAppAttributes>.activities
            guard let activity = activities.first(where: { $0.id == activityId }) else {
                print("MusicLiveActivityManager: Activity not found: \(activityId)")
                return
            }

            let contentState = LiveActivitiesAppAttributes.ContentState(appGroupId: appGroupId, updateTimestamp: Date().timeIntervalSince1970)
            await activity.update(using: contentState)
        }
    }

    /// 结束 Live Activity
    func endActivity() {
        guard let activityId = currentActivityId else {
            return
        }

        Task {
            let activities = Activity<LiveActivitiesAppAttributes>.activities
            if let activity = activities.first(where: { $0.id == activityId }) {
                await activity.end(dismissalPolicy: .immediate)
                print("MusicLiveActivityManager: Activity ended: \(activityId)")
            }
        }

        // 清理 UserDefaults
        if let uuid = currentActivityUUID {
            clearDefaultsData(prefix: uuid)
        }

        currentActivityId = nil
        currentActivityUUID = nil
    }

    /// 结束所有 Live Activities
    func endAllActivities() {
        Task {
            for activity in Activity<LiveActivitiesAppAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
            print("MusicLiveActivityManager: All activities ended")
        }

        currentActivityId = nil
        currentActivityUUID = nil
    }

    /// 保存数据到 UserDefaults
    private func saveDataToDefaults(data: [String: Any], prefix: UUID) {
        guard let defaults = sharedDefaults else {
            print("MusicLiveActivityManager: SharedDefaults not available")
            return
        }

        print("MusicLiveActivityManager: Saving data to UserDefaults with UUID prefix: \(prefix)")

        for (key, value) in data {
            let prefixedKey = "\(prefix)_\(key)"

            // 处理图片数据
            if key == "coverImage" {
                print("MusicLiveActivityManager: Processing coverImage, type: \(type(of: value))")
                // Flutter 发送的 Uint8List 会被转换为 FlutterStandardTypedData
                if let typedData = value as? FlutterStandardTypedData {
                    print("MusicLiveActivityManager: coverImage is FlutterStandardTypedData, size: \(typedData.data.count)")
                    if let imagePath = saveImageToFile(data: typedData.data, filename: "cover_\(prefix.hashValue).jpg") {
                        print("MusicLiveActivityManager: coverImage saved to: \(imagePath), key: \(prefixedKey)")
                        defaults.set(imagePath, forKey: prefixedKey)
                    } else {
                        print("MusicLiveActivityManager: Failed to save coverImage from FlutterStandardTypedData")
                    }
                } else if let data = value as? Data {
                    // 直接作为 Data 类型
                    print("MusicLiveActivityManager: coverImage is Data, size: \(data.count)")
                    if let imagePath = saveImageToFile(data: data, filename: "cover_\(prefix.hashValue).jpg") {
                        print("MusicLiveActivityManager: coverImage saved to: \(imagePath)")
                        defaults.set(imagePath, forKey: prefixedKey)
                    } else {
                        print("MusicLiveActivityManager: Failed to save coverImage from Data")
                    }
                } else {
                    print("MusicLiveActivityManager: coverImage is unknown type, cannot process")
                }
            } else {
                defaults.set(value, forKey: prefixedKey)
            }
        }

        defaults.synchronize()
    }

    /// 清理 UserDefaults 数据
    private func clearDefaultsData(prefix: UUID) {
        guard let defaults = sharedDefaults else { return }

        let keys = ["title", "artist", "album", "isPlaying", "progress", "currentTime", "totalTime", "coverImage"]
        for key in keys {
            defaults.removeObject(forKey: "\(prefix)_\(key)")
        }
        defaults.synchronize()
    }

    /// 保存图片到 App Group 目录
    /// 返回文件名（不是完整路径），Widget Extension 会使用自己的 App Group container URL 拼接
    private func saveImageToFile(data: Data, filename: String) -> String? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            print("MusicLiveActivityManager: Cannot access App Group container for appGroupId: \(appGroupId)")
            return nil
        }

        print("MusicLiveActivityManager: App Group container URL: \(containerURL.path)")

        let fileURL = containerURL.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            print("MusicLiveActivityManager: Image saved successfully, path: \(fileURL.path), size: \(data.count) bytes")

            // 验证文件是否存在
            let exists = FileManager.default.fileExists(atPath: fileURL.path)
            print("MusicLiveActivityManager: File exists after save: \(exists)")

            // 返回文件名而不是完整路径，Widget Extension 会使用自己的 container URL 拼接
            return filename
        } catch {
            print("MusicLiveActivityManager: Failed to save image: \(error)")
            return nil
        }
    }
}

// MARK: - LiveActivitiesAppAttributes
// 必须与 Widget Extension 中的定义完全一致

struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable, Codable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        var appGroupId: String
        // 添加更新时间戳，用于强制 Widget 刷新
        var updateTimestamp: TimeInterval
    }

    var id: UUID

    // 提供默认初始化器
    init(id: UUID = UUID()) {
        self.id = id
    }

    // 显式实现 Codable 以确保 id 正确编解码
    enum CodingKeys: String, CodingKey {
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
    }
}

extension LiveActivitiesAppAttributes {
    func prefixedKey(_ key: String) -> String {
        return "\(id)_\(key)"
    }
}
