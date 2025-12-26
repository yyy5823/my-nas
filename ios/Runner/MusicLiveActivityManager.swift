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

        // 清理上次残留的 Live Activities（防止 app 意外退出后灵动岛残留）
        cleanupStaleActivities()
    }

    /// 清理残留的 Live Activities
    /// 在 app 启动时调用，确保没有上次意外退出留下的灵动岛
    private func cleanupStaleActivities() {
        Task {
            let activities = Activity<LiveActivitiesAppAttributes>.activities
            if !activities.isEmpty {
                print("MusicLiveActivityManager: Found \(activities.count) stale activities, cleaning up...")
                for activity in activities {
                    await activity.end(dismissalPolicy: .immediate)
                }
                print("MusicLiveActivityManager: Stale activities cleaned up")
            }
        }
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
            print("MusicLiveActivityManager: Ending existing activity before creating new one")
            endActivity()
        }

        // 创建属性
        let activityUUID = UUID()
        let attributes = LiveActivitiesAppAttributes(id: activityUUID)

        // 1. 先保存数据到 UserDefaults
        saveDataToDefaults(data: data, prefix: activityUUID)

        // 2. 确保 UserDefaults 已同步到磁盘
        sharedDefaults?.synchronize()

        // 3. 使用毫秒级时间戳
        let timestamp = Date().timeIntervalSince1970 * 1000
        let contentState = LiveActivitiesAppAttributes.ContentState(appGroupId: appGroupId, updateTimestamp: timestamp)

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

            print("MusicLiveActivityManager: Activity created with ID: \(activity.id), UUID: \(activityUUID), data keys: \(data.keys)")
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

        // 1. 先更新 UserDefaults 中的数据并确保同步
        saveDataToDefaults(data: data, prefix: activityUUID)

        // 2. 确保 UserDefaults 已同步到磁盘
        sharedDefaults?.synchronize()

        // 3. 使用唯一的时间戳确保每次更新都被识别为新状态
        let timestamp = Date().timeIntervalSince1970 * 1000

        // 4. 找到当前活动并更新
        Task {
            let activities = Activity<LiveActivitiesAppAttributes>.activities
            guard let activity = activities.first(where: { $0.id == activityId }) else {
                print("MusicLiveActivityManager: Activity not found: \(activityId)")
                return
            }

            // ActivityKit 会比较 ContentState，如果相同则不会触发 Widget 刷新
            // 使用高精度时间戳（毫秒级）确保每次更新都是唯一的
            let contentState = LiveActivitiesAppAttributes.ContentState(appGroupId: appGroupId, updateTimestamp: timestamp)

            if #available(iOS 16.2, *) {
                // iOS 16.2+ 使用 ActivityContent，可以设置 staleDate
                let activityContent = ActivityContent(state: contentState, staleDate: nil)
                await activity.update(activityContent)
                print("MusicLiveActivityManager: Activity updated with iOS 16.2+ API, timestamp: \(timestamp), data keys: \(data.keys)")
            } else {
                // iOS 16.1 使用旧 API
                await activity.update(using: contentState)
                print("MusicLiveActivityManager: Activity updated with iOS 16.1 API, timestamp: \(timestamp)")
            }
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

        // 清理 UserDefaults 和封面文件
        if let uuid = currentActivityUUID {
            clearDefaultsData(prefix: uuid)
            cleanupCoverFiles(prefix: uuid)
        }

        currentActivityId = nil
        currentActivityUUID = nil
    }

    /// 结束所有 Live Activities
    func endAllActivities() {
        // 使用信号量确保同步执行（对于 app 终止场景很重要）
        let semaphore = DispatchSemaphore(value: 0)
        let activities = Activity<LiveActivitiesAppAttributes>.activities

        // 清理当前活动的封面文件和 UserDefaults
        if let uuid = currentActivityUUID {
            clearDefaultsData(prefix: uuid)
            cleanupCoverFiles(prefix: uuid)
        }

        if activities.isEmpty {
            print("MusicLiveActivityManager: No activities to end")
            currentActivityId = nil
            currentActivityUUID = nil
            return
        }

        print("MusicLiveActivityManager: Ending \(activities.count) activities...")

        Task {
            for activity in activities {
                await activity.end(dismissalPolicy: .immediate)
            }
            print("MusicLiveActivityManager: All activities ended")
            semaphore.signal()
        }

        // 等待最多 1 秒
        _ = semaphore.wait(timeout: .now() + 1.0)

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
                // 使用固定文件名，避免 Widget Extension 缓存问题
                // Widget Extension 会根据文件名缓存图片，使用固定名称确保每次都能正确加载
                let filename = "cover_\(prefix.hashValue).png"

                // Flutter 发送的 Uint8List 会被转换为 FlutterStandardTypedData
                if let typedData = value as? FlutterStandardTypedData {
                    print("MusicLiveActivityManager: coverImage is FlutterStandardTypedData, size: \(typedData.data.count)")
                    if let imagePath = saveImageToFile(data: typedData.data, filename: filename) {
                        print("MusicLiveActivityManager: coverImage saved to: \(imagePath), key: \(prefixedKey)")
                        defaults.set(imagePath, forKey: prefixedKey)
                    } else {
                        print("MusicLiveActivityManager: Failed to save coverImage from FlutterStandardTypedData")
                    }
                } else if let data = value as? Data {
                    // 直接作为 Data 类型
                    print("MusicLiveActivityManager: coverImage is Data, size: \(data.count)")
                    if let imagePath = saveImageToFile(data: data, filename: filename) {
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

        let keys = ["title", "artist", "album", "isPlaying", "progress", "currentTime", "totalTime", "coverImage", "themeColor"]
        for key in keys {
            defaults.removeObject(forKey: "\(prefix)_\(key)")
        }
        defaults.synchronize()
    }

    /// 清理旧的封面文件（在 Activity 结束时调用）
    private func cleanupCoverFiles(prefix: UUID) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return
        }

        let filename = "cover_\(prefix.hashValue).png"
        let fileURL = containerURL.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
            print("MusicLiveActivityManager: Deleted cover file: \(filename)")
        }
    }

    /// 保存图片到 App Group 目录
    /// 返回文件名（不是完整路径），Widget Extension 会使用自己的 App Group container URL 拼接
    /// 注意：会压缩图片以适应 Widget Extension 的内存限制
    private func saveImageToFile(data: Data, filename: String) -> String? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            print("MusicLiveActivityManager: Cannot access App Group container for appGroupId: \(appGroupId)")
            return nil
        }

        print("MusicLiveActivityManager: App Group container URL: \(containerURL.path)")

        // 尝试将数据解析为图片并压缩
        // Widget Extension 有内存限制，大图片可能无法正确显示
        guard let originalImage = UIImage(data: data) else {
            print("MusicLiveActivityManager: Failed to create UIImage from data, size: \(data.count)")
            return nil
        }

        print("MusicLiveActivityManager: Original image size: \(originalImage.size), data size: \(data.count)")

        // Live Activity 有严格的内存限制
        // 根据 Apple Developer Forums 建议，图片应压缩到约 84px
        // 参考: https://developer.apple.com/forums/thread/716902
        // 参考: https://www.fabrizioduroni.it/blog/post/2023/01/10/widget-ios-swiftui-image-problem
        let maxSize: CGFloat = 80  // 使用 80px 以确保在所有设备上都能渲染
        let targetWidth: CGFloat
        let targetHeight: CGFloat

        // 保持正方形以简化 Live Activity 显示
        targetWidth = maxSize
        targetHeight = maxSize

        // 使用原图的 imageRendererFormat 确保正确的色彩空间
        let format = originalImage.imageRendererFormat
        format.scale = 1.0  // 使用 1x 避免生成过大的图片
        format.opaque = true  // 不需要透明度，避免内存问题

        let targetSize = CGSize(width: targetWidth, height: targetHeight)
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        let resizedImage = renderer.image { context in
            // 填充黑色背景（音乐封面通常是深色背景）
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            // 计算居中裁剪的区域（保持宽高比，居中裁剪为正方形）
            let sourceAspect = originalImage.size.width / originalImage.size.height
            var drawRect: CGRect

            if sourceAspect > 1 {
                // 宽图：垂直填满，水平居中裁剪
                let scaledWidth = targetHeight * sourceAspect
                let xOffset = (targetWidth - scaledWidth) / 2
                drawRect = CGRect(x: xOffset, y: 0, width: scaledWidth, height: targetHeight)
            } else {
                // 高图或正方形：水平填满，垂直居中裁剪
                let scaledHeight = targetWidth / sourceAspect
                let yOffset = (targetHeight - scaledHeight) / 2
                drawRect = CGRect(x: 0, y: yOffset, width: targetWidth, height: scaledHeight)
            }

            originalImage.draw(in: drawRect)
        }

        // 使用 PNG 格式保存（PNG 在 Widget 中更可靠）
        // 根据多个开发者的经验，PNG 比 JPEG 在 Live Activity 中更稳定
        guard let compressedData = resizedImage.pngData() else {
            print("MusicLiveActivityManager: Failed to create PNG data")
            return nil
        }

        print("MusicLiveActivityManager: Compressed to PNG - targetSize: \(targetSize), dataSize: \(compressedData.count) bytes")

        return saveCompressedImage(compressedData, filename: filename, containerURL: containerURL)
    }

    /// 保存压缩后的图片数据到文件
    private func saveCompressedImage(_ imageData: Data, filename: String, containerURL: URL) -> String? {
        let fileURL = containerURL.appendingPathComponent(filename)

        do {
            // 保存压缩后的图片数据
            try imageData.write(to: fileURL)
            print("MusicLiveActivityManager: Image saved successfully, path: \(fileURL.path), size: \(imageData.count) bytes")

            // 验证文件是否存在并可读
            let exists = FileManager.default.fileExists(atPath: fileURL.path)
            print("MusicLiveActivityManager: File exists after save: \(exists)")

            // 验证图片可以被正确加载
            if let savedData = try? Data(contentsOf: fileURL),
               let verifyImage = UIImage(data: savedData) {
                print("MusicLiveActivityManager: Image verification passed, size: \(verifyImage.size)")
            } else {
                print("MusicLiveActivityManager: Image verification failed!")
            }

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
