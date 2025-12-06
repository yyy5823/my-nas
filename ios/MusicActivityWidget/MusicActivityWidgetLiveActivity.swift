//
//  MusicActivityWidgetLiveActivity.swift
//  MusicActivityWidget
//
//  Created by 陈奇 on 2025/12/6.
//

import ActivityKit
import WidgetKit
import SwiftUI

/// 音乐播放器 Live Activity 的属性定义
struct MusicActivityWidgetAttributes: ActivityAttributes {
    /// 动态内容状态 - 会随播放状态变化
    public struct ContentState: Codable, Hashable {
        /// 是否正在播放
        var isPlaying: Bool
        /// 当前播放进度 (0.0 - 1.0)
        var progress: Double
        /// 当前播放时间（秒）
        var currentTime: Int
        /// 总时长（秒）
        var totalTime: Int
    }

    /// 歌曲标题
    var title: String
    /// 艺术家名称
    var artist: String
    /// 专辑名称
    var album: String
    /// 封面图片路径
    var coverImage: String?
}

/// 音乐播放器 Live Activity Widget
struct MusicActivityWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MusicActivityWidgetAttributes.self) { context in
            // 锁屏/通知中心的 Live Activity 视图
            LockScreenMusicView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开状态 - 长按灵动岛时显示
                DynamicIslandExpandedRegion(.leading) {
                    // 左侧：封面图片
                    MusicCoverView(imagePath: context.attributes.coverImage)
                        .frame(width: 52, height: 52)
                        .cornerRadius(8)
                }

                DynamicIslandExpandedRegion(.center) {
                    // 中间：歌曲信息
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(.white)
                        Text(context.attributes.artist)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    // 右侧：播放状态图标
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    // 底部：进度条
                    VStack(spacing: 4) {
                        ProgressView(value: context.state.progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .white))

                        HStack {
                            Text(formatTime(context.state.currentTime))
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                            Spacer()
                            Text(formatTime(context.state.totalTime))
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                // 紧凑模式 - 左侧：封面或音符图标
                MusicCoverView(imagePath: context.attributes.coverImage)
                    .frame(width: 24, height: 24)
                    .cornerRadius(4)
            } compactTrailing: {
                // 紧凑模式 - 右侧：播放/暂停状态
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            } minimal: {
                // 最小模式 - 只显示播放状态图标
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
            .widgetURL(URL(string: "mynas://music/player"))
        }
    }

    /// 格式化时间显示
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// 锁屏音乐视图
struct LockScreenMusicView: View {
    let context: ActivityViewContext<MusicActivityWidgetAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // 封面图片
            MusicCoverView(imagePath: context.attributes.coverImage)
                .frame(width: 56, height: 56)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                // 歌曲信息
                Text(context.attributes.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(.white)
                Text(context.attributes.artist)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .lineLimit(1)

                // 进度条
                ProgressView(value: context.state.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
            }

            Spacer()

            // 播放状态图标
            Image(systemName: context.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.white)
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.8))
    }
}

/// 封面图片视图
struct MusicCoverView: View {
    let imagePath: String?

    var body: some View {
        if let path = imagePath,
           let sharedDefaults = UserDefaults(suiteName: "group.com.kkape.mynas"),
           let actualPath = sharedDefaults.string(forKey: path),
           let uiImage = UIImage(contentsOfFile: actualPath) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let path = imagePath,
                  let uiImage = UIImage(contentsOfFile: path) {
            // 直接尝试作为文件路径加载
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // 默认封面
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

#Preview("Notification", as: .content, using: MusicActivityWidgetAttributes(
    title: "Shape of You",
    artist: "Ed Sheeran",
    album: "Divide",
    coverImage: nil
)) {
    MusicActivityWidgetLiveActivity()
} contentStates: {
    MusicActivityWidgetAttributes.ContentState(isPlaying: true, progress: 0.3, currentTime: 65, totalTime: 234)
    MusicActivityWidgetAttributes.ContentState(isPlaying: false, progress: 0.7, currentTime: 163, totalTime: 234)
}
