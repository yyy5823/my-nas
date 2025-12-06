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
// ContentState 必须包含 appGroupId，与插件定义保持一致

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

// MARK: - Shared UserDefaults Helper
// 使用 App Group 共享数据

/// 获取 App Group 的 UserDefaults
/// - Parameter appGroupId: App Group ID，如果为空则使用默认值
/// - Returns: UserDefaults 实例
func getSharedDefaults(appGroupId: String?) -> UserDefaults {
    let groupId = appGroupId ?? "group.com.kkape.mynas"
    if let defaults = UserDefaults(suiteName: groupId) {
        return defaults
    }
    // 如果 App Group 不可用，使用标准 UserDefaults（数据不会跨进程共享）
    print("Warning: App Group '\(groupId)' not available, falling back to standard UserDefaults")
    return UserDefaults.standard
}

/// 默认的 sharedDefault（向后兼容）
let sharedDefault: UserDefaults = getSharedDefaults(appGroupId: nil)

// MARK: - Music Live Activity Widget

struct MusicActivityWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            // 锁屏/通知中心的 Live Activity 视图
            LockScreenMusicView(context: context)
        } dynamicIsland: { context in
            // 从 context.state 获取 appGroupId，使用动态 UserDefaults
            let defaults = getSharedDefaults(appGroupId: context.state.appGroupId)

            return DynamicIsland {
                // 展开状态 - 长按灵动岛时显示
                DynamicIslandExpandedRegion(.leading) {
                    MusicCoverView(context: context, defaults: defaults)
                        .frame(width: 52, height: 52)
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
                    let isPlaying = defaults.bool(forKey: context.attributes.prefixedKey("isPlaying"))
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    let progress = defaults.double(forKey: context.attributes.prefixedKey("progress"))
                    let currentTime = defaults.integer(forKey: context.attributes.prefixedKey("currentTime"))
                    let totalTime = defaults.integer(forKey: context.attributes.prefixedKey("totalTime"))

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
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                MusicCoverView(context: context, defaults: defaults)
                    .frame(width: 24, height: 24)
                    .cornerRadius(4)
            } compactTrailing: {
                let isPlaying = defaults.bool(forKey: context.attributes.prefixedKey("isPlaying"))
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            } minimal: {
                let isPlaying = defaults.bool(forKey: context.attributes.prefixedKey("isPlaying"))
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
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

// MARK: - Lock Screen View

struct LockScreenMusicView: View {
    let context: ActivityViewContext<LiveActivitiesAppAttributes>

    var body: some View {
        // 从 context.state 获取 appGroupId，使用动态 UserDefaults
        let defaults = getSharedDefaults(appGroupId: context.state.appGroupId)
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
        if let imagePath = defaults.string(forKey: context.attributes.prefixedKey("coverImage")),
           let uiImage = UIImage(contentsOfFile: imagePath) {
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
