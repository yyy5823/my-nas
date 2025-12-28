//
//  QuickAccessWidget.swift
//  MyNasWidgets
//
//  快捷操作小组件 - 一键访问音乐/视频/图书
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Quick Access Item

enum QuickAccessItem: String, CaseIterable {
    case music
    case video
    case book
    case photo
    case file

    var label: String {
        switch self {
        case .music: return "音乐"
        case .video: return "视频"
        case .book: return "图书"
        case .photo: return "相册"
        case .file: return "文件"
        }
    }

    var icon: String {
        switch self {
        case .music: return "music.note"
        case .video: return "play.rectangle.fill"
        case .book: return "book.fill"
        case .photo: return "photo.fill"
        case .file: return "folder.fill"
        }
    }

    var color: Color {
        switch self {
        case .music: return Color(hex: "ff6b6b")
        case .video: return Color(hex: "4ecdc4")
        case .book: return Color(hex: "ffe66d")
        case .photo: return Color(hex: "a29bfe")
        case .file: return Color(hex: "74b9ff")
        }
    }

    var urlScheme: URL {
        URL(string: "mynas://\(rawValue)")!
    }
}

// MARK: - App Intents (iOS 17+)

@available(iOS 17.0, *)
struct OpenMusicIntent: AppIntent {
    static var title: LocalizedStringResource = "打开音乐"
    static var description = IntentDescription("打开 My NAS 音乐库")

    func perform() async throws -> some IntentResult {
        return .result()
    }

    static var openAppWhenRun: Bool = true
}

@available(iOS 17.0, *)
struct OpenVideoIntent: AppIntent {
    static var title: LocalizedStringResource = "打开视频"
    static var description = IntentDescription("打开 My NAS 视频库")

    func perform() async throws -> some IntentResult {
        return .result()
    }

    static var openAppWhenRun: Bool = true
}

@available(iOS 17.0, *)
struct OpenBookIntent: AppIntent {
    static var title: LocalizedStringResource = "打开图书"
    static var description = IntentDescription("打开 My NAS 图书库")

    func perform() async throws -> some IntentResult {
        return .result()
    }

    static var openAppWhenRun: Bool = true
}

// MARK: - Timeline Entry

struct QuickAccessEntry: TimelineEntry {
    let date: Date
    let items: [QuickAccessItem]
    let nasName: String?
    let isConnected: Bool
}

// MARK: - Timeline Provider

struct QuickAccessProvider: TimelineProvider {
    func placeholder(in _: Context) -> QuickAccessEntry {
        QuickAccessEntry(
            date: Date(),
            items: [.music, .video, .book],
            nasName: "My NAS",
            isConnected: true
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (QuickAccessEntry) -> Void) {
        let entry = QuickAccessEntry(
            date: Date(),
            items: [.music, .video, .book],
            nasName: WidgetDataManager.shared.getNasName(),
            isConnected: WidgetDataManager.shared.isNasConnected()
        )
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<QuickAccessEntry>) -> Void) {
        let data = WidgetDataManager.shared.getQuickAccessData()
        let items = data.items.compactMap { QuickAccessItem(rawValue: $0) }

        let entry = QuickAccessEntry(
            date: Date(),
            items: items.isEmpty ? [.music, .video, .book] : items,
            nasName: data.nasName ?? WidgetDataManager.shared.getNasName(),
            isConnected: data.isConnected
        )

        // 快捷操作是静态的，每小时刷新一次即可
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Views

struct QuickAccessWidgetSmallView: View {
    var entry: QuickAccessEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(WidgetTheme.backgroundGradient)

            VStack(spacing: 8) {
                // Header
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                        .foregroundColor(WidgetTheme.primaryColor)
                    Text("快捷操作")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(WidgetTheme.textPrimary)
                    Spacer()
                }

                Spacer()

                // 2x2 Grid of items
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 8) {
                    ForEach(entry.items.prefix(4), id: \.rawValue) { item in
                        Link(destination: item.urlScheme) {
                            QuickAccessItemView(item: item, isSmall: true)
                        }
                    }
                }

                Spacer()
            }
            .padding(12)
        }
    }
}

struct QuickAccessWidgetMediumView: View {
    var entry: QuickAccessEntry

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(WidgetTheme.backgroundGradient)

            VStack(spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14))
                        .foregroundColor(WidgetTheme.primaryColor)
                    Text("快捷操作")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(WidgetTheme.textPrimary)

                    Spacer()

                    if let nasName = entry.nasName {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(entry.isConnected ? Color.green : Color.gray)
                                .frame(width: 6, height: 6)
                            Text(nasName)
                                .font(.caption2)
                                .foregroundColor(WidgetTheme.textSecondary)
                        }
                    }
                }

                // Horizontal row of items
                HStack(spacing: 12) {
                    ForEach(entry.items.prefix(5), id: \.rawValue) { item in
                        Link(destination: item.urlScheme) {
                            QuickAccessItemView(item: item, isSmall: false, showLabel: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }
}

struct QuickAccessItemView: View {
    let item: QuickAccessItem
    let isSmall: Bool
    var showLabel: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: isSmall ? 10 : 14)
                    .fill(item.color.opacity(0.2))
                    .frame(width: isSmall ? 44 : 56, height: isSmall ? 44 : 56)

                Image(systemName: item.icon)
                    .font(.system(size: isSmall ? 18 : 24))
                    .foregroundColor(item.color)
            }

            if showLabel {
                Text(item.label)
                    .font(.system(size: 10))
                    .foregroundColor(WidgetTheme.textSecondary)
            }
        }
    }
}

// MARK: - Widget Entry View

struct QuickAccessWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: QuickAccessEntry

    var body: some View {
        switch family {
        case .systemSmall:
            QuickAccessWidgetSmallView(entry: entry)
        case .systemMedium:
            QuickAccessWidgetMediumView(entry: entry)
        default:
            QuickAccessWidgetMediumView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

struct QuickAccessWidget: Widget {
    let kind: String = "QuickAccessWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickAccessProvider()) { entry in
            QuickAccessWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("快捷操作")
        .description("一键访问音乐、视频、图书")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    QuickAccessWidget()
} timeline: {
    QuickAccessEntry(
        date: Date(),
        items: [.music, .video, .book, .photo],
        nasName: "Synology DS920+",
        isConnected: true
    )
}

#Preview(as: .systemMedium) {
    QuickAccessWidget()
} timeline: {
    QuickAccessEntry(
        date: Date(),
        items: [.music, .video, .book, .photo, .file],
        nasName: "Synology DS920+",
        isConnected: true
    )
}
