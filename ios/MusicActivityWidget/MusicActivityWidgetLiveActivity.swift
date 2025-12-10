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
            // 重要：使用 updateTimestamp 触发视图刷新
            // 当 ContentState 变化时，SwiftUI 会重新渲染整个 DynamicIsland
            let timestamp = context.state.updateTimestamp

            // 每次重新渲染时强制同步并获取最新的 UserDefaults 数据
            // 使用 getSharedDefaults() 确保读取到主 App 写入的最新数据
            let defaults = getSharedDefaults()

            // 调试日志（发布版本会被优化掉）
            #if DEBUG
            print("DynamicIsland: Rendering with timestamp: \(timestamp)")
            #endif

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
                // 使用已同步的 defaults（在 dynamicIsland 闭包顶部已获取）
                // 注意：不能在这里使用 let _ = timestamp 因为会导致编译错误
                // 通过传递 defaults 来确保数据一致性
                MusicCoverView(context: context, defaults: defaults)
                    .frame(width: 24, height: 24)
                    .cornerRadius(4)
            } compactTrailing: {
                // Compact 模式显示音乐波形动效
                // 使用已同步的 defaults
                let isPlaying = defaults.bool(forKey: context.attributes.prefixedKey("isPlaying"))
                let progress = defaults.double(forKey: context.attributes.prefixedKey("progress"))
                if isPlaying {
                    AnimatedMusicBars(progress: progress)
                        .frame(width: 16, height: 14)
                } else {
                    // 暂停时显示静态波形图标
                    StaticMusicBars()
                        .frame(width: 16, height: 14)
                }
            } minimal: {
                // 最小模式显示音乐波形动效
                // 使用已同步的 defaults
                let isPlaying = defaults.bool(forKey: context.attributes.prefixedKey("isPlaying"))
                let progress = defaults.double(forKey: context.attributes.prefixedKey("progress"))
                if isPlaying {
                    AnimatedMusicBars(progress: progress)
                        .frame(width: 12, height: 10)
                } else {
                    // 暂停时显示静态波形图标
                    StaticMusicBars()
                        .frame(width: 12, height: 10)
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

// MARK: - Animated Music Bars (彩色渐变音乐波形，垂直居中，基于播放进度)

struct AnimatedMusicBars: View {
    var progress: Double = 0  // 播放进度 0.0-1.0，用于影响波形

    // 使用 TimelineView 实现持续动画
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            HStack(alignment: .center, spacing: 1) {
                ForEach(0..<4, id: \.self) { index in
                    MusicBar(index: index, date: timeline.date, progress: progress)
                }
            }
        }
    }
}

// MARK: - Static Music Bars (暂停时显示的静态彩色波形)

struct StaticMusicBars: View {
    // 静态波形，不同高度
    private let heights: [CGFloat] = [0.5, 0.8, 0.6, 0.4]

    // 彩色渐变颜色数组
    private let colors: [Color] = [
        Color(red: 0.4, green: 0.8, blue: 1.0),   // 青色
        Color(red: 0.6, green: 0.5, blue: 1.0),   // 蓝紫色
        Color(red: 1.0, green: 0.5, blue: 0.7),   // 粉色
        Color(red: 1.0, green: 0.7, blue: 0.3),   // 橙色
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 1) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(colors[index])
                    .frame(width: 2)
                    .scaleEffect(y: heights[index], anchor: .center)
                    .opacity(0.5)  // 降低透明度表示暂停状态
            }
        }
    }
}

struct MusicBar: View {
    let index: Int
    let date: Date
    var progress: Double = 0

    // 彩色渐变颜色数组（从左到右）
    private var barColor: Color {
        let colors: [Color] = [
            Color(red: 0.4, green: 0.8, blue: 1.0),   // 青色
            Color(red: 0.6, green: 0.5, blue: 1.0),   // 蓝紫色
            Color(red: 1.0, green: 0.5, blue: 0.7),   // 粉色
            Color(red: 1.0, green: 0.7, blue: 0.3),   // 橙色
        ]
        return colors[index % colors.count]
    }

    var body: some View {
        // 使用播放进度来影响波形的基础相位
        let progressPhase = progress * 20.0  // 进度影响相位
        let phase = Double(index) * 1.5 + progressPhase
        let time = date.timeIntervalSinceReferenceDate

        // 基于时间和进度的波形动画
        let wave1 = sin(time * 4.0 + phase)
        let wave2 = sin(time * 2.5 + phase * 0.7) * 0.5
        let combinedWave = abs(wave1 + wave2) / 1.5

        // 高度范围从 0.25 到 1.0
        let height = 0.25 + 0.75 * combinedWave

        RoundedRectangle(cornerRadius: 0.5)
            .fill(barColor)
            .frame(width: 2)  // 更细的竖线
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

    var body: some View {
        // 同步 UserDefaults 确保获取最新数据
        defaults.synchronize()

        let coverKey = context.attributes.prefixedKey("coverImage")
        let filename = defaults.string(forKey: coverKey) ?? ""

        // 尝试加载图片
        let loadedImage = Self.loadCoverImage(filename: filename)

        return Group {
            if let uiImage = loadedImage {
                // 成功加载图片
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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
    }

    /// 从 App Group container 加载图片（静态方法，避免 self 捕获问题）
    /// - Parameter filename: 文件名（不是完整路径）
    private static func loadCoverImage(filename: String) -> UIImage? {
        // 确保文件名不为空
        guard !filename.isEmpty else {
            return nil
        }

        // 从 App Group container 加载
        guard let containerURL = getAppGroupContainerURL() else {
            return nil
        }

        let fileURL = containerURL.appendingPathComponent(filename)

        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // 使用 Data(contentsOf:) + UIImage(data:) 的方式加载
        // 根据 Apple Developer Forums，这种方式在 Widget Extension 中更可靠
        // 参考: https://developer.apple.com/forums/thread/716902
        guard let imageData = try? Data(contentsOf: fileURL) else {
            return nil
        }

        // 创建 UIImage
        guard let image = UIImage(data: imageData) else {
            return nil
        }

        return image
    }
}

// MARK: - Preview
// Note: #Preview macro requires iOS 17+, removed for iOS 16.1 compatibility
