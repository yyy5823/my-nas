//
//  MusicActivityWidgetLiveActivity.swift
//  MusicActivityWidget
//
//  Created by 陈奇 on 2025/12/6.
//

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Live Activities App Attributes
// 必须使用这个名称和结构，以匹配 live_activities Flutter 插件
// ContentState 必须包含 appGroupId，与插件内部定义保持一致

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

// MARK: - Shared UserDefaults Helper
// 使用 App Group 共享数据

/// App Group ID - 必须与 Flutter 端和 entitlements 配置一致
private let appGroupId = "group.com.kkape.mynas"

/// 共享的 UserDefaults 实例
let sharedDefault: UserDefaults = {
    if let defaults = UserDefaults(suiteName: appGroupId) {
        // 同步以确保获取最新数据
        defaults.synchronize()
        return defaults
    }
    // 如果 App Group 不可用，使用标准 UserDefaults（数据不会跨进程共享）
    return UserDefaults.standard
}()

/// 获取 App Group Container URL
func getAppGroupContainerURL() -> URL? {
    return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
}

// MARK: - Music Control Helper
// 通过 Darwin 通知和 UserDefaults 实现跨进程通信

/// 发送音乐控制命令到主 App
/// 使用 Darwin 通知实现即时通信
private func sendMusicControlCommand(_ command: String) {
    // 1. 保存命令到 UserDefaults
    sharedDefault.set(command, forKey: "musicControlCommand")
    sharedDefault.set(Date().timeIntervalSince1970, forKey: "musicControlTimestamp")
    sharedDefault.synchronize()

    // 2. 发送 Darwin 通知（跨进程通知）
    let notificationName = CFNotificationName("com.kkape.mynas.musicControl" as CFString)
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        notificationName,
        nil,
        nil,
        true
    )
}

// MARK: - App Intents for Music Control

@available(iOS 16.0, *)
struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "播放/暂停"
    static var description = IntentDescription("切换音乐播放状态")

    func perform() async throws -> some IntentResult {
        sendMusicControlCommand("toggle")
        return .result()
    }
}

@available(iOS 16.0, *)
struct PreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "上一首"
    static var description = IntentDescription("播放上一首")

    func perform() async throws -> some IntentResult {
        sendMusicControlCommand("previous")
        return .result()
    }
}

@available(iOS 16.0, *)
struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "下一首"
    static var description = IntentDescription("播放下一首")

    func perform() async throws -> some IntentResult {
        sendMusicControlCommand("next")
        return .result()
    }
}

@available(iOS 16.0, *)
struct FavoriteIntent: AppIntent {
    static var title: LocalizedStringResource = "收藏"
    static var description = IntentDescription("收藏当前歌曲")

    func perform() async throws -> some IntentResult {
        sendMusicControlCommand("favorite")
        return .result()
    }
}

// MARK: - Music Live Activity Widget

struct MusicActivityWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            // 锁屏/通知中心的 Live Activity 视图
            LockScreenMusicView(context: context)
        } dynamicIsland: { context in
            // 使用共享的 UserDefaults
            let defaults = sharedDefault

            return DynamicIsland {
                // 展开状态 - 长按灵动岛时显示
                DynamicIslandExpandedRegion(.leading) {
                    MusicCoverView(context: context, defaults: defaults)
                        .frame(width: 56, height: 56)
                        .cornerRadius(8)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(defaults.string(forKey: context.attributes.prefixedKey("title")) ?? "Unknown")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(.white)
                        Text(defaults.string(forKey: context.attributes.prefixedKey("artist")) ?? "Unknown Artist")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    // 收藏按钮 - 使用 AppIntent 直接执行
                    if #available(iOS 17.0, *) {
                        Button(intent: FavoriteIntent()) {
                            Image(systemName: "heart")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "heart")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    let progress = defaults.double(forKey: context.attributes.prefixedKey("progress"))
                    let currentTime = defaults.integer(forKey: context.attributes.prefixedKey("currentTime"))
                    let totalTime = defaults.integer(forKey: context.attributes.prefixedKey("totalTime"))
                    let isPlaying = defaults.bool(forKey: context.attributes.prefixedKey("isPlaying"))

                    VStack(spacing: 8) {
                        // 进度条
                        VStack(spacing: 4) {
                            ProgressView(value: progress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .white))

                            HStack {
                                Text(formatTime(currentTime))
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(formatTime(totalTime))
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                        }

                        // 播放控制按钮 - 使用 AppIntent 直接在灵动岛中执行
                        HStack(spacing: 32) {
                            // 上一首
                            if #available(iOS 17.0, *) {
                                Button(intent: PreviousTrackIntent()) {
                                    Image(systemName: "backward.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Link(destination: URL(string: "mynas://music/previous")!) {
                                    Image(systemName: "backward.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }
                            }

                            // 播放/暂停
                            if #available(iOS 17.0, *) {
                                Button(intent: PlayPauseIntent()) {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 36))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Link(destination: URL(string: "mynas://music/toggle")!) {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 36))
                                        .foregroundColor(.white)
                                }
                            }

                            // 下一首
                            if #available(iOS 17.0, *) {
                                Button(intent: NextTrackIntent()) {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Link(destination: URL(string: "mynas://music/next")!) {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                // Compact 模式显示封面
                MusicCoverView(context: context, defaults: defaults)
                    .frame(width: 24, height: 24)
                    .cornerRadius(4)
            } compactTrailing: {
                // Compact 模式显示音乐波形动效
                let isPlaying = defaults.bool(forKey: context.attributes.prefixedKey("isPlaying"))
                if isPlaying {
                    AnimatedMusicBars()
                        .frame(width: 24, height: 16)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
            } minimal: {
                // 最小模式显示音乐波形动效
                let isPlaying = defaults.bool(forKey: context.attributes.prefixedKey("isPlaying"))
                if isPlaying {
                    AnimatedMusicBars()
                        .frame(width: 16, height: 12)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                }
            }
            .widgetURL(URL(string: "mynas://music/player"))
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Animated Music Bars (更动态的音乐波形)

struct AnimatedMusicBars: View {
    // 使用 TimelineView 实现持续动画
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    MusicBar(index: index, date: timeline.date)
                }
            }
        }
    }
}

struct MusicBar: View {
    let index: Int
    let date: Date

    var body: some View {
        // 使用正弦函数创建波动效果，每个条使用不同的相位
        let phase = Double(index) * 0.8
        let time = date.timeIntervalSinceReferenceDate
        // 使用不同频率创建更自然的动画
        let height = 0.4 + 0.6 * abs(sin(time * 3.0 + phase))

        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white)
            .frame(width: 3)
            .scaleEffect(y: height, anchor: .bottom)
    }
}

// MARK: - Lock Screen View

struct LockScreenMusicView: View {
    let context: ActivityViewContext<LiveActivitiesAppAttributes>

    var body: some View {
        // 使用共享的 UserDefaults
        let defaults = sharedDefault
        let title = defaults.string(forKey: context.attributes.prefixedKey("title")) ?? "Unknown"
        let artist = defaults.string(forKey: context.attributes.prefixedKey("artist")) ?? "Unknown Artist"
        let isPlaying = defaults.bool(forKey: context.attributes.prefixedKey("isPlaying"))
        let progress = defaults.double(forKey: context.attributes.prefixedKey("progress"))

        HStack(spacing: 12) {
            MusicCoverView(context: context, defaults: defaults)
                .frame(width: 56, height: 56)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(.white)
                Text(artist)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .lineLimit(1)

                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
            }

            Spacer()

            // 播放/暂停按钮 - 使用 AppIntent 直接执行
            if #available(iOS 17.0, *) {
                Button(intent: PlayPauseIntent()) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            } else {
                Link(destination: URL(string: "mynas://music/toggle")!) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.8))
    }
}

// MARK: - Cover Image View

struct MusicCoverView: View {
    let context: ActivityViewContext<LiveActivitiesAppAttributes>
    let defaults: UserDefaults

    var body: some View {
        let coverKey = context.attributes.prefixedKey("coverImage")
        let filename = defaults.string(forKey: coverKey)

        // 尝试加载图片 - 现在 UserDefaults 存储的是文件名，不是完整路径
        if let name = filename, let uiImage = loadImage(filename: name) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else {
            // 默认占位图
            ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
            }
        }
    }

    /// 从 App Group container 加载图片
    /// - Parameter filename: 文件名（不是完整路径）
    private func loadImage(filename: String) -> UIImage? {
        // 从 App Group container 加载
        guard let containerURL = getAppGroupContainerURL() else {
            return nil
        }

        let fileURL = containerURL.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            return UIImage(contentsOfFile: fileURL.path)
        }

        return nil
    }
}

// MARK: - Preview
// Note: #Preview macro requires iOS 17+, removed for iOS 16.1 compatibility
