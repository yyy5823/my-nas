//
//  MediaWidget.swift
//  MyNasWidgets
//
//  媒体播放小组件 - 显示正在播放的音乐
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - App Intents (iOS 17+)

@available(iOS 17.0, *)
struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "播放/暂停"
    static var description = IntentDescription("控制音乐播放")

    func perform() async throws -> some IntentResult {
        // 通过 URL Scheme 发送控制命令
        return .result()
    }

    static var openAppWhenRun: Bool = false
}

@available(iOS 17.0, *)
struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "下一首"
    static var description = IntentDescription("播放下一首")

    func perform() async throws -> some IntentResult {
        return .result()
    }

    static var openAppWhenRun: Bool = false
}

@available(iOS 17.0, *)
struct PreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "上一首"
    static var description = IntentDescription("播放上一首")

    func perform() async throws -> some IntentResult {
        return .result()
    }

    static var openAppWhenRun: Bool = false
}

// MARK: - Timeline Entry

struct MediaEntry: TimelineEntry {
    let date: Date
    let data: WidgetDataManager.MediaData
    let coverImage: UIImage?
}

// MARK: - Timeline Provider

struct MediaProvider: TimelineProvider {
    func placeholder(in _: Context) -> MediaEntry {
        MediaEntry(date: Date(), data: .placeholder, coverImage: nil)
    }

    func getSnapshot(in _: Context, completion: @escaping (MediaEntry) -> Void) {
        let data = WidgetDataManager.shared.getMediaData()
        let coverImage = WidgetDataManager.shared.getCoverImage()
        let entry = MediaEntry(
            date: Date(),
            data: data.hasContent ? data : .placeholder,
            coverImage: coverImage
        )
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<MediaEntry>) -> Void) {
        let data = WidgetDataManager.shared.getMediaData()
        let coverImage = WidgetDataManager.shared.getCoverImage()
        let entry = MediaEntry(date: Date(), data: data, coverImage: coverImage)

        // 播放中时每30秒刷新，否则每5分钟
        let interval = data.isPlaying ? 30 : 300
        let nextUpdate = Date().addingTimeInterval(TimeInterval(interval))
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Views

struct MediaWidgetSmallView: View {
    var entry: MediaEntry

    var body: some View {
        ZStack {
            // Background
            if let coverImage = entry.coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 20)
                    .overlay(Color.black.opacity(0.5))
            } else {
                ContainerRelativeShape()
                    .fill(WidgetTheme.backgroundGradient)
            }

            if !entry.data.hasContent {
                // 无播放内容
                VStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 32))
                        .foregroundColor(WidgetTheme.textSecondary)

                    Text("未在播放")
                        .font(.caption)
                        .foregroundColor(WidgetTheme.textSecondary)
                }
            } else {
                VStack(spacing: 8) {
                    // Cover image
                    if let coverImage = entry.coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 60, height: 60)
                            Image(systemName: "music.note")
                                .font(.system(size: 24))
                                .foregroundColor(WidgetTheme.textSecondary)
                        }
                    }

                    // Title and artist
                    VStack(spacing: 2) {
                        Text(entry.data.title ?? "未知歌曲")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(entry.data.artist ?? "未知艺术家")
                            .font(.system(size: 10))
                            .foregroundColor(WidgetTheme.textSecondary)
                            .lineLimit(1)
                    }

                    // Playing indicator
                    if entry.data.isPlaying {
                        MusicBarsView(isAnimating: true)
                            .frame(width: 20, height: 12)
                    }
                }
                .padding(12)
            }
        }
        .widgetURL(URL(string: "mynas://music/player"))
    }
}

struct MediaWidgetMediumView: View {
    var entry: MediaEntry

    var body: some View {
        ZStack {
            // Background
            if let coverImage = entry.coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 30)
                    .overlay(Color.black.opacity(0.6))
            } else {
                ContainerRelativeShape()
                    .fill(WidgetTheme.backgroundGradient)
            }

            if !entry.data.hasContent {
                // 无播放内容
                HStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 80, height: 80)
                        Image(systemName: "music.note")
                            .font(.system(size: 32))
                            .foregroundColor(WidgetTheme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("未在播放")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(WidgetTheme.textSecondary)

                        Text("点击打开音乐播放器")
                            .font(.caption)
                            .foregroundColor(WidgetTheme.primaryColor)
                    }
                }
            } else {
                HStack(spacing: 16) {
                    // Cover image
                    if let coverImage = entry.coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 80, height: 80)
                            Image(systemName: "music.note")
                                .font(.system(size: 28))
                                .foregroundColor(WidgetTheme.textSecondary)
                        }
                    }

                    // Song info and controls
                    VStack(alignment: .leading, spacing: 8) {
                        // Title and artist
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.data.title ?? "未知歌曲")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Text(entry.data.artist ?? "未知艺术家")
                                .font(.system(size: 12))
                                .foregroundColor(WidgetTheme.textSecondary)
                                .lineLimit(1)

                            if let album = entry.data.album, !album.isEmpty {
                                Text(album)
                                    .font(.system(size: 10))
                                    .foregroundColor(WidgetTheme.textSecondary.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        // Progress bar
                        VStack(spacing: 4) {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.2))
                                        .frame(height: 3)

                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(WidgetTheme.primaryColor)
                                        .frame(width: geometry.size.width * entry.data.progress, height: 3)
                                }
                            }
                            .frame(height: 3)

                            // Time labels
                            HStack {
                                Text(entry.data.currentTime.formattedDuration)
                                    .font(.system(size: 9))
                                    .foregroundColor(WidgetTheme.textSecondary)
                                Spacer()
                                Text(entry.data.totalTime.formattedDuration)
                                    .font(.system(size: 9))
                                    .foregroundColor(WidgetTheme.textSecondary)
                            }
                        }

                        // Control buttons (iOS 17+ with App Intents)
                        HStack(spacing: 16) {
                            Link(destination: URL(string: "mynas://music/previous")!) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                            }

                            Link(destination: URL(string: "mynas://music/toggle")!) {
                                Image(systemName: entry.data.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }

                            Link(destination: URL(string: "mynas://music/next")!) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                            }

                            Spacer()

                            // Playing indicator
                            if entry.data.isPlaying {
                                MusicBarsView(isAnimating: true)
                                    .frame(width: 16, height: 12)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .widgetURL(URL(string: "mynas://music/player"))
    }
}

struct MusicBarsView: View {
    let isAnimating: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< 3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(WidgetTheme.primaryColor)
                    .frame(width: 3)
                    .scaleEffect(y: isAnimating ? [0.3, 1.0, 0.5][index] : 0.3, anchor: .bottom)
            }
        }
    }
}

// MARK: - Widget Entry View

struct MediaWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: MediaEntry

    var body: some View {
        switch family {
        case .systemSmall:
            MediaWidgetSmallView(entry: entry)
        case .systemMedium:
            MediaWidgetMediumView(entry: entry)
        default:
            MediaWidgetMediumView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

struct MediaWidget: Widget {
    let kind: String = "MediaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MediaProvider()) { entry in
            MediaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("媒体播放")
        .description("显示正在播放的音乐")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    MediaWidget()
} timeline: {
    MediaEntry(date: Date(), data: .placeholder, coverImage: nil)
}

#Preview(as: .systemMedium) {
    MediaWidget()
} timeline: {
    MediaEntry(date: Date(), data: .placeholder, coverImage: nil)
}
