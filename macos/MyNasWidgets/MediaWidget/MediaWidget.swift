import WidgetKit
import SwiftUI
import AppIntents
import AppKit

// MARK: - Timeline Provider

struct MediaProvider: TimelineProvider {
    func placeholder(in context: Context) -> MediaEntry {
        MediaEntry(
            date: Date(),
            mediaData: MediaData(
                title: "Song Title",
                artist: "Artist Name",
                album: "Album Name",
                coverImagePath: nil,
                isPlaying: true,
                progress: 0.5,
                currentTime: 120,
                totalTime: 240,
                themeColor: nil
            ),
            artwork: nil,
            isConnected: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MediaEntry) -> Void) {
        let entry = MediaEntry(
            date: Date(),
            mediaData: WidgetDataManager.shared.getMediaData(),
            artwork: WidgetDataManager.shared.getMediaArtwork(),
            isConnected: WidgetDataManager.shared.isConnected()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MediaEntry>) -> Void) {
        let entry = MediaEntry(
            date: Date(),
            mediaData: WidgetDataManager.shared.getMediaData(),
            artwork: WidgetDataManager.shared.getMediaArtwork(),
            isConnected: WidgetDataManager.shared.isConnected()
        )
        // 每30秒更新（实时更新通过 WidgetCenter.shared.reloadTimelines）
        let nextUpdate = Calendar.current.date(byAdding: .second, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct MediaEntry: TimelineEntry {
    let date: Date
    let mediaData: MediaData?
    let artwork: NSImage?
    let isConnected: Bool
}

// MARK: - App Intents

@available(macOS 14.0, *)
struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    static var description = IntentDescription("Toggle playback")

    func perform() async throws -> some IntentResult {
        // 通过 URL Scheme 控制播放
        return .result()
    }

    static var openAppWhenRun: Bool = false
}

@available(macOS 14.0, *)
struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var description = IntentDescription("Skip to next track")

    func perform() async throws -> some IntentResult {
        return .result()
    }

    static var openAppWhenRun: Bool = false
}

@available(macOS 14.0, *)
struct PreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Track"
    static var description = IntentDescription("Go to previous track")

    func perform() async throws -> some IntentResult {
        return .result()
    }

    static var openAppWhenRun: Bool = false
}

// MARK: - Widget Views

struct MediaWidgetEntryView: View {
    var entry: MediaProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallMediaView(entry: entry)
        case .systemMedium:
            MediumMediaView(entry: entry)
        default:
            MediumMediaView(entry: entry)
        }
    }
}

struct SmallMediaView: View {
    let entry: MediaEntry

    var body: some View {
        VStack(spacing: 8) {
            if let data = entry.mediaData, data.hasContent, entry.isConnected {
                // 封面
                ZStack {
                    if let artwork = entry.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(WidgetTheme.surfaceColor)
                        Image(systemName: "music.note")
                            .font(.title)
                            .foregroundColor(WidgetTheme.secondaryColor)
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // 标题
                VStack(spacing: 2) {
                    Text(data.title ?? "Unknown")
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(data.artist ?? "Unknown Artist")
                        .font(.caption2)
                        .foregroundColor(WidgetTheme.secondaryColor)
                        .lineLimit(1)
                }

                // 播放状态
                Image(systemName: data.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(WidgetTheme.primaryColor)
            } else {
                EmptyStateView(icon: "music.note", message: "Not playing")
            }
        }
        .containerBackground(for: .widget) {
            WidgetTheme.backgroundColor
        }
        .widgetURL(URL(string: "mynas://music/player"))
    }
}

struct MediumMediaView: View {
    let entry: MediaEntry

    var body: some View {
        HStack(spacing: 12) {
            if let data = entry.mediaData, data.hasContent, entry.isConnected {
                // 左侧封面
                ZStack {
                    if let artwork = entry.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(WidgetTheme.surfaceColor)
                        Image(systemName: "music.note")
                            .font(.largeTitle)
                            .foregroundColor(WidgetTheme.secondaryColor)
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // 右侧信息和控制
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: "Now Playing", icon: "music.note")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(data.title ?? "Unknown")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        Text(data.artist ?? "Unknown Artist")
                            .font(.caption)
                            .foregroundColor(WidgetTheme.secondaryColor)
                            .lineLimit(1)

                        if let album = data.album, !album.isEmpty {
                            Text(album)
                                .font(.caption2)
                                .foregroundColor(WidgetTheme.secondaryColor.opacity(0.7))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // 进度条
                    VStack(spacing: 4) {
                        LinearProgressView(
                            progress: data.progress,
                            height: 3,
                            foregroundColor: WidgetTheme.primaryColor
                        )

                        HStack {
                            Text(data.positionFormatted)
                                .font(.caption2)
                                .foregroundColor(WidgetTheme.secondaryColor)

                            Spacer()

                            Text(data.durationFormatted)
                                .font(.caption2)
                                .foregroundColor(WidgetTheme.secondaryColor)
                        }
                    }

                    // 控制按钮
                    HStack(spacing: 16) {
                        Spacer()

                        Link(destination: URL(string: "mynas://music/previous")!) {
                            Image(systemName: "backward.fill")
                                .font(.body)
                                .foregroundColor(.primary)
                        }

                        Link(destination: URL(string: "mynas://music/playpause")!) {
                            Image(systemName: data.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title2)
                                .foregroundColor(WidgetTheme.primaryColor)
                        }

                        Link(destination: URL(string: "mynas://music/next")!) {
                            Image(systemName: "forward.fill")
                                .font(.body)
                                .foregroundColor(.primary)
                        }

                        Spacer()
                    }
                }
            } else {
                EmptyStateView(icon: "music.note", message: "Nothing is playing")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(for: .widget) {
            WidgetTheme.backgroundColor
        }
        .widgetURL(URL(string: "mynas://music/player"))
    }
}

// MARK: - Widget Configuration

struct MediaWidget: Widget {
    let kind: String = "MediaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MediaProvider()) { entry in
            MediaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Control currently playing media")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    MediaWidget()
} timeline: {
    MediaEntry(
        date: Date(),
        mediaData: MediaData(
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            coverImagePath: nil,
            isPlaying: true,
            progress: 0.4,
            currentTime: 142,
            totalTime: 354,
            themeColor: nil
        ),
        artwork: nil,
        isConnected: true
    )
}
