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

    /// 共享的 UserDefaults
    private lazy var sharedDefaults: UserDefaults? = {
        UserDefaults(suiteName: appGroupId)
    }()

    /// 当前活动 ID
    private var currentActivityId: String?

    /// 当前活动的 UUID (用于数据前缀)
    private var currentActivityUUID: UUID?

    private init() {}

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
        let contentState = LiveActivitiesAppAttributes.ContentState(appGroupId: appGroupId)

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

            print("MusicLiveActivityManager: Activity created with ID: \(activity.id)")
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

            let contentState = LiveActivitiesAppAttributes.ContentState(appGroupId: appGroupId)
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

        for (key, value) in data {
            let prefixedKey = "\(prefix)_\(key)"

            // 处理图片数据
            if key == "coverImage" {
                // Flutter 发送的 Uint8List 会被转换为 FlutterStandardTypedData
                if let typedData = value as? FlutterStandardTypedData {
                    if let imagePath = saveImageToFile(data: typedData.data, filename: "cover_\(prefix.hashValue).jpg") {
                        defaults.set(imagePath, forKey: prefixedKey)
                    }
                } else if let data = value as? Data {
                    // 直接作为 Data 类型
                    if let imagePath = saveImageToFile(data: data, filename: "cover_\(prefix.hashValue).jpg") {
                        defaults.set(imagePath, forKey: prefixedKey)
                    }
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
    private func saveImageToFile(data: Data, filename: String) -> String? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            print("MusicLiveActivityManager: Cannot access App Group container")
            return nil
        }

        let fileURL = containerURL.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            return fileURL.path
        } catch {
            print("MusicLiveActivityManager: Failed to save image: \(error)")
            return nil
        }
    }
}

// MARK: - LiveActivitiesAppAttributes
// 必须与 Widget Extension 中的定义完全一致

struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        var appGroupId: String
    }

    var id = UUID()
}

extension LiveActivitiesAppAttributes {
    func prefixedKey(_ key: String) -> String {
        return "\(id)_\(key)"
    }
}
