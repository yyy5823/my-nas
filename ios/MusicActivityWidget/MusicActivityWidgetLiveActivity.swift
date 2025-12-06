//
//  MusicActivityWidgetLiveActivity.swift
//  MusicActivityWidget
//
//  Created by 陈奇 on 2025/12/6.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activities App Attributes
// 必须使用这个名称和结构，以匹配 live_activities Flutter 插件
// ContentState 必须包含 appGroupId，与插件内部定义保持一致

struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable, Codable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        var appGroupId: String
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
    print("MusicActivityWidget: Initializing sharedDefault with appGroupId: \(appGroupId)")
    if let defaults = UserDefaults(suiteName: appGroupId) {
        print("MusicActivityWidget: Successfully created UserDefaults for App Group")
        // 同步以确保获取最新数据
        defaults.synchronize()
        return defaults
    }
    // 如果 App Group 不可用，使用标准 UserDefaults（数据不会跨进程共享）
    print("MusicActivityWidget: Warning: App Group '\(appGroupId)' not available, falling back to standard UserDefaults")
    return UserDefaults.standard
}()

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
                    // 收藏按钮
                    Link(destination: URL(string: "mynas://music/favorite")!) {
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

                        // 播放控制按钮
                        HStack(spacing: 32) {
                            // 上一首
                            Link(destination: URL(string: "mynas://music/previous")!) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                            }

                            // 播放/暂停
                            Link(destination: URL(string: "mynas://music/toggle")!) {
                                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.white)
                            }

                            // 下一首
                            Link(destination: URL(string: "mynas://music/next")!) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
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
                    MusicWaveformView()
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
                    MusicWaveformView()
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

// MARK: - Music Waveform Animation View (for Dynamic Island minimal/compact modes)

struct MusicWaveformView: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                WaveformBar(delay: Double(index) * 0.15)
            }
        }
    }
}

struct WaveformBar: View {
    let delay: Double

    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.white)
            .frame(width: 3)
            .scaleEffect(y: isAnimating ? 1.0 : 0.3, anchor: .bottom)
            .animation(
                Animation.easeInOut(duration: 0.4)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
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

            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.white)
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
        let imagePath = defaults.string(forKey: coverKey)

        // 调试日志
        let _ = {
            print("MusicCoverView: Looking for cover with key: \(coverKey)")
            print("MusicCoverView: Activity ID: \(context.attributes.id)")
            if let path = imagePath {
                print("MusicCoverView: Found image path: \(path)")
                let fileExists = FileManager.default.fileExists(atPath: path)
                print("MusicCoverView: File exists at path: \(fileExists)")
                if fileExists {
                    if let image = UIImage(contentsOfFile: path) {
                        print("MusicCoverView: Successfully loaded image, size: \(image.size)")
                    } else {
                        print("MusicCoverView: Failed to create UIImage from file")
                    }
                }
            } else {
                print("MusicCoverView: No image path found in UserDefaults")
                // 打印所有相关的 keys
                let allKeys = defaults.dictionaryRepresentation().keys.filter { $0.contains("coverImage") }
                print("MusicCoverView: All coverImage keys in defaults: \(allKeys)")
            }
        }()

        if let path = imagePath,
           let uiImage = UIImage(contentsOfFile: path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Preview
// Note: #Preview macro requires iOS 17+, removed for iOS 16.1 compatibility
