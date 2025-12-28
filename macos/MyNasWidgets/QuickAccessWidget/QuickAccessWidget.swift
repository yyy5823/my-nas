import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Provider

struct QuickAccessProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickAccessEntry {
        QuickAccessEntry(date: Date(), isConnected: true, connectionName: "MyNAS")
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickAccessEntry) -> Void) {
        let entry = QuickAccessEntry(
            date: Date(),
            isConnected: WidgetDataManager.shared.isConnected(),
            connectionName: WidgetDataManager.shared.getConnectionName()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickAccessEntry>) -> Void) {
        let entry = QuickAccessEntry(
            date: Date(),
            isConnected: WidgetDataManager.shared.isConnected(),
            connectionName: WidgetDataManager.shared.getConnectionName()
        )
        // 静态小组件，1小时后更新
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct QuickAccessEntry: TimelineEntry {
    let date: Date
    let isConnected: Bool
    let connectionName: String?
}

// MARK: - App Intents

@available(macOS 14.0, *)
struct OpenMusicIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Music"
    static var description = IntentDescription("Open MyNAS music library")

    func perform() async throws -> some IntentResult {
        return .result()
    }

    static var openAppWhenRun: Bool = true
}

@available(macOS 14.0, *)
struct OpenVideoIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Video"
    static var description = IntentDescription("Open MyNAS video library")

    func perform() async throws -> some IntentResult {
        return .result()
    }

    static var openAppWhenRun: Bool = true
}

@available(macOS 14.0, *)
struct OpenBooksIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Books"
    static var description = IntentDescription("Open MyNAS books library")

    func perform() async throws -> some IntentResult {
        return .result()
    }

    static var openAppWhenRun: Bool = true
}

// MARK: - Widget Views

struct QuickAccessWidgetEntryView: View {
    var entry: QuickAccessProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallQuickAccessView(entry: entry)
        case .systemMedium:
            MediumQuickAccessView(entry: entry)
        default:
            MediumQuickAccessView(entry: entry)
        }
    }
}

struct SmallQuickAccessView: View {
    let entry: QuickAccessEntry

    var body: some View {
        VStack(spacing: 8) {
            WidgetHeader(title: "Quick Access", icon: "bolt.fill")

            if entry.isConnected {
                HStack(spacing: 12) {
                    QuickAccessButton(type: .music, size: 36)
                    QuickAccessButton(type: .video, size: 36)
                }
            } else {
                EmptyStateView(icon: "wifi.slash", message: "Not Connected")
            }
        }
        .containerBackground(for: .widget) {
            WidgetTheme.backgroundColor
        }
    }
}

struct MediumQuickAccessView: View {
    let entry: QuickAccessEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                WidgetHeader(title: "Quick Access", icon: "bolt.fill")
                if let name = entry.connectionName {
                    Text(name)
                        .font(.caption2)
                        .foregroundColor(WidgetTheme.secondaryColor)
                }
            }

            if entry.isConnected {
                HStack(spacing: 16) {
                    ForEach(QuickAccessType.allCases, id: \.self) { type in
                        QuickAccessButton(type: type, size: 44)
                    }
                    Spacer()
                }
            } else {
                EmptyStateView(icon: "wifi.slash", message: "Not Connected")
                    .frame(maxWidth: .infinity)
            }
        }
        .containerBackground(for: .widget) {
            WidgetTheme.backgroundColor
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
        .configurationDisplayName("Quick Access")
        .description("Quickly access your music, videos, and books")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    QuickAccessWidget()
} timeline: {
    QuickAccessEntry(date: .now, isConnected: true, connectionName: "MyNAS")
    QuickAccessEntry(date: .now, isConnected: false, connectionName: nil)
}
