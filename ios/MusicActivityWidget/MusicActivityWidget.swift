import ActivityKit
import SwiftUI
import WidgetKit

/// 音乐播放器 Live Activity Widget
/// 在灵动岛和锁屏上显示当前播放的音乐信息
@available(iOS 16.1, *)
struct MusicActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MusicActivityAttributes.self) { context in
            // 锁屏/通知中心的 Live Activity 视图
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开状态 - 长按灵动岛时显示
                DynamicIslandExpandedRegion(.leading) {
                    // 左侧：封面图片
                    CoverImageView(key: context.attributes.coverImageKey)
                        .frame(width: 52, height: 52)
                        .cornerRadius(8)
                }

                DynamicIslandExpandedRegion(.center) {
                    // 中间：歌曲信息
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(context.attributes.artist)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    // 右侧：播放控制
                    HStack(spacing: 12) {
                        Button(intent: MusicControlIntent(action: "previous")) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)

                        Button(intent: MusicControlIntent(action: context.state.isPlaying ? "pause" : "play")) {
                            Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20))
                        }
                        .buttonStyle(.plain)

                        Button(intent: MusicControlIntent(action: "next")) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    // 底部：进度条
                    VStack(spacing: 4) {
                        ProgressView(value: context.state.progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .white))

                        HStack {
                            Text(formatTime(context.state.currentTime))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatTime(context.state.totalTime))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                // 紧凑模式 - 左侧：封面或播放图标
                CoverImageView(key: context.attributes.coverImageKey)
                    .frame(width: 24, height: 24)
                    .cornerRadius(4)
            } compactTrailing: {
                // 紧凑模式 - 右侧：播放/暂停状态
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
            } minimal: {
                // 最小模式 - 只显示播放状态图标
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
            }
        }
    }

    /// 格式化时间显示
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// 锁屏视图
@available(iOS 16.1, *)
struct LockScreenView: View {
    let context: ActivityViewContext<MusicActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // 封面图片
            CoverImageView(key: context.attributes.coverImageKey)
                .frame(width: 56, height: 56)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                // 歌曲信息
                Text(context.attributes.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(context.attributes.artist)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                // 进度条
                ProgressView(value: context.state.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
            }

            Spacer()

            // 播放控制
            HStack(spacing: 16) {
                Button(intent: MusicControlIntent(action: "previous")) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)

                Button(intent: MusicControlIntent(action: context.state.isPlaying ? "pause" : "play")) {
                    Image(systemName: context.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                }
                .buttonStyle(.plain)

                Button(intent: MusicControlIntent(action: "next")) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
    }
}

/// 封面图片视图
@available(iOS 16.1, *)
struct CoverImageView: View {
    let key: String?

    var body: some View {
        if let key = key,
           let sharedDefaults = UserDefaults(suiteName: "group.com.kkape.mynas"),
           let imagePath = sharedDefaults.string(forKey: key),
           let uiImage = UIImage(contentsOfFile: imagePath) {
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

/// 音乐控制 Intent
@available(iOS 16.1, *)
struct MusicControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Music Control"

    @Parameter(title: "Action")
    var action: String

    init() {
        self.action = "play"
    }

    init(action: String) {
        self.action = action
    }

    func perform() async throws -> some IntentResult {
        // 通过 URL Scheme 通知主应用执行操作
        if let url = URL(string: "mynas://music/\(action)") {
            // 注意：Widget 不能直接打开 URL，需要通过其他方式通知主应用
            // 这里的实现需要配合 App Group 的 UserDefaults 来传递控制命令
            let sharedDefaults = UserDefaults(suiteName: "group.com.kkape.mynas")
            sharedDefaults?.set(action, forKey: "pendingMusicAction")
            sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pendingMusicActionTimestamp")
        }
        return .result()
    }
}
