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

/// 共享的 UserDefaults 实例（内部使用，外部应调用 getSharedDefaults() 获取同步后的实例）
private let _sharedDefault: UserDefaults = {
    if let defaults = UserDefaults(suiteName: appGroupId) {
        return defaults
    }
    // 如果 App Group 不可用，使用标准 UserDefaults（数据不会跨进程共享）
    return UserDefaults.standard
}()

/// 获取同步后的 UserDefaults 实例
/// 每次调用都会 synchronize() 确保获取最新数据
/// 这对于 Widget Extension 从主 App 读取更新后的数据很重要
func getSharedDefaults() -> UserDefaults {
    _sharedDefault.synchronize()
    return _sharedDefault
}

/// 保持向后兼容，但不推荐直接使用
var sharedDefault: UserDefaults {
    return getSharedDefaults()
}

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
            // 使用 updateTimestamp 触发视图刷新
            let _ = context.state.updateTimestamp

            // 使用共享的 UserDefaults（每次访问都会同步）
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
                // 每次渲染都重新获取最新的 defaults 数据
                let freshDefaults = getSharedDefaults()
                MusicCoverView(context: context, defaults: freshDefaults)
                    .frame(width: 24, height: 24)
                    .cornerRadius(4)
            } compactTrailing: {
                // Compact 模式显示音乐波形动效
                // 每次渲染都重新获取最新状态
                let freshDefaults = getSharedDefaults()
                let isPlaying = freshDefaults.bool(forKey: context.attributes.prefixedKey("isPlaying"))
                if isPlaying {
                    AnimatedMusicBars()
                        .frame(width: 24, height: 16)
                } else {
                    // 暂停时显示静态波形图标
                    StaticMusicBars()
                        .frame(width: 24, height: 16)
                }
            } minimal: {
                // 最小模式显示音乐波形动效
                // 每次渲染都重新获取最新状态
                let freshDefaults = getSharedDefaults()
                let isPlaying = freshDefaults.bool(forKey: context.attributes.prefixedKey("isPlaying"))
                if isPlaying {
                    AnimatedMusicBars()
                        .frame(width: 16, height: 12)
                } else {
                    // 暂停时显示静态波形图标
                    StaticMusicBars()
                        .frame(width: 16, height: 12)
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

// MARK: - Animated Music Bars (彩色渐变音乐波形，垂直居中)

struct AnimatedMusicBars: View {
    // 使用 TimelineView 实现持续动画
    // 使用 .periodic 代替 .animation，确保动画持续更新
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { timeline in
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(0..<5, id: \.self) { index in
                    MusicBar(index: index, date: timeline.date, totalBars: 5)
                }
            }
        }
    }
}

// MARK: - Static Music Bars (暂停时显示的静态彩色波形)

struct StaticMusicBars: View {
    // 静态波形，不同高度
    private let heights: [CGFloat] = [0.4, 0.7, 0.5, 0.8, 0.3]

    // 彩色渐变颜色数组
    private let colors: [Color] = [
        Color(red: 0.0, green: 0.8, blue: 1.0),   // 青色
        Color(red: 0.4, green: 0.6, blue: 1.0),   // 蓝色
        Color(red: 0.8, green: 0.4, blue: 1.0),   // 紫色
        Color(red: 1.0, green: 0.4, blue: 0.6),   // 粉色
        Color(red: 1.0, green: 0.6, blue: 0.2),   // 橙色
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [colors[index], colors[index].opacity(0.6)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                    .scaleEffect(y: heights[index], anchor: .center)
                    .opacity(0.6)  // 稍微降低透明度表示暂停状态
            }
        }
    }
}

struct MusicBar: View {
    let index: Int
    let date: Date
    let totalBars: Int

    // 彩色渐变颜色数组（从左到右）
    private var barColor: Color {
        let colors: [Color] = [
            Color(red: 0.0, green: 0.8, blue: 1.0),   // 青色
            Color(red: 0.4, green: 0.6, blue: 1.0),   // 蓝色
            Color(red: 0.8, green: 0.4, blue: 1.0),   // 紫色
            Color(red: 1.0, green: 0.4, blue: 0.6),   // 粉色
            Color(red: 1.0, green: 0.6, blue: 0.2),   // 橙色
        ]
        return colors[index % colors.count]
    }

    var body: some View {
        // 使用正弦函数创建波动效果，每个条使用不同的相位和频率
        let phase = Double(index) * 1.3
        let time = date.timeIntervalSinceReferenceDate
        // 使用多个正弦波叠加创建更随机、更明显的动画效果
        let wave1 = sin(time * 5.0 + phase)
        let wave2 = sin(time * 3.0 + phase * 0.8) * 0.4
        let wave3 = sin(time * 7.0 + phase * 1.5) * 0.2
        let combinedWave = abs(wave1 + wave2 + wave3) / 1.6
        // 高度范围从 0.2 到 1.0，变化更明显
        let height = 0.2 + 0.8 * combinedWave

        RoundedRectangle(cornerRadius: 1.5)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [barColor, barColor.opacity(0.6)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 3)
            .scaleEffect(y: height, anchor: .center)  // 垂直居中对齐
    }
}

// MARK: - Lock Screen View

struct LockScreenMusicView: View {
    let context: ActivityViewContext<LiveActivitiesAppAttributes>

    var body: some View {
        // 使用 updateTimestamp 触发视图刷新
        // 当 ContentState 更新时，SwiftUI 会重新渲染这个视图
        let _ = context.state.updateTimestamp

        // 使用共享的 UserDefaults（每次访问都会同步）
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

    /// 获取封面图片（同步 UserDefaults 并加载）
    private var coverImage: UIImage? {
        // 同步以获取最新数据
        defaults.synchronize()
        let coverKey = context.attributes.prefixedKey("coverImage")
        guard let filename = defaults.string(forKey: coverKey),
              !filename.isEmpty else {
            return nil
        }
        return loadImage(filename: filename)
    }

    var body: some View {
        if let uiImage = coverImage {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else {
            // 默认占位图 - 使用渐变背景增强视觉效果
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.3, green: 0.3, blue: 0.4),
                        Color(red: 0.2, green: 0.2, blue: 0.3)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    /// 从 App Group container 加载图片
    /// - Parameter filename: 文件名（不是完整路径）
    private func loadImage(filename: String) -> UIImage? {
        // 从 App Group container 加载
        guard let containerURL = getAppGroupContainerURL() else {
            print("MusicCoverView: Cannot get App Group container URL")
            return nil
        }

        let fileURL = containerURL.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let image = UIImage(contentsOfFile: fileURL.path) {
                return image
            } else {
                print("MusicCoverView: Failed to create UIImage from file: \(fileURL.path)")
            }
        } else {
            print("MusicCoverView: File not found: \(fileURL.path)")
        }

        return nil
    }
}

// MARK: - Preview
// Note: #Preview macro requires iOS 17+, removed for iOS 16.1 compatibility
