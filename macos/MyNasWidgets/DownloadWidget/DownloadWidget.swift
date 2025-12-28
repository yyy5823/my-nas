import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct DownloadProvider: TimelineProvider {
    func placeholder(in context: Context) -> DownloadEntry {
        DownloadEntry(
            date: Date(),
            downloadData: DownloadData(
                tasks: [
                    DownloadTaskData(
                        id: "1",
                        fileName: "movie.mkv",
                        progress: 0.65,
                        speed: 5_000_000,
                        status: "downloading"
                    )
                ],
                lastUpdated: Date()
            ),
            isConnected: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DownloadEntry) -> Void) {
        let entry = DownloadEntry(
            date: Date(),
            downloadData: WidgetDataManager.shared.getDownloadData(),
            isConnected: WidgetDataManager.shared.isConnected()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DownloadEntry>) -> Void) {
        let entry = DownloadEntry(
            date: Date(),
            downloadData: WidgetDataManager.shared.getDownloadData(),
            isConnected: WidgetDataManager.shared.isConnected()
        )
        // 每分钟更新一次（实时更新通过 WidgetCenter.shared.reloadTimelines）
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct DownloadEntry: TimelineEntry {
    let date: Date
    let downloadData: DownloadData?
    let isConnected: Bool
}

// MARK: - Widget Views

struct DownloadWidgetEntryView: View {
    var entry: DownloadProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallDownloadView(entry: entry)
        case .systemMedium:
            MediumDownloadView(entry: entry)
        default:
            SmallDownloadView(entry: entry)
        }
    }
}

struct SmallDownloadView: View {
    let entry: DownloadEntry

    var body: some View {
        VStack(spacing: 8) {
            WidgetHeader(title: "Downloads", icon: "arrow.down.circle.fill")

            if let data = entry.downloadData, !data.tasks.isEmpty, entry.isConnected {
                ZStack {
                    CircularProgressView(
                        progress: data.totalProgress,
                        lineWidth: 8,
                        foregroundColor: WidgetTheme.primaryColor
                    )

                    VStack(spacing: 2) {
                        Text("\(Int(data.totalProgress * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("\(data.activeCount) tasks")
                            .font(.caption2)
                            .foregroundColor(WidgetTheme.secondaryColor)
                    }
                }
                .padding(4)

                if let firstTask = data.tasks.first {
                    Text(firstTask.speedFormatted)
                        .font(.caption2)
                        .foregroundColor(WidgetTheme.secondaryColor)
                }
            } else {
                EmptyStateView(icon: "arrow.down.circle", message: "No downloads")
            }
        }
        .containerBackground(for: .widget) {
            WidgetTheme.backgroundColor
        }
    }
}

struct MediumDownloadView: View {
    let entry: DownloadEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Downloads", icon: "arrow.down.circle.fill")

            if let data = entry.downloadData, !data.tasks.isEmpty, entry.isConnected {
                ForEach(data.tasks.prefix(3), id: \.id) { task in
                    DownloadTaskRow(task: task)
                }

                if data.tasks.count > 3 {
                    Text("+ \(data.tasks.count - 3) more")
                        .font(.caption2)
                        .foregroundColor(WidgetTheme.secondaryColor)
                }
            } else {
                EmptyStateView(icon: "arrow.down.circle", message: "No active downloads")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(for: .widget) {
            WidgetTheme.backgroundColor
        }
    }
}

struct DownloadTaskRow: View {
    let task: DownloadTaskData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.fileName)
                    .font(.caption)
                    .lineLimit(1)

                Spacer()

                Text("\(Int(task.progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(WidgetTheme.secondaryColor)
            }

            LinearProgressView(
                progress: task.progress,
                height: 4,
                foregroundColor: statusColor(for: task.status)
            )

            HStack {
                Image(systemName: statusIcon(for: task.status))
                    .font(.caption2)
                    .foregroundColor(statusColor(for: task.status))

                Text(task.speedFormatted)
                    .font(.caption2)
                    .foregroundColor(WidgetTheme.secondaryColor)
            }
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "downloading": return WidgetTheme.primaryColor
        case "paused": return WidgetTheme.warningColor
        case "error": return WidgetTheme.errorColor
        case "completed": return WidgetTheme.successColor
        default: return WidgetTheme.secondaryColor
        }
    }

    private func statusIcon(for status: String) -> String {
        switch status {
        case "downloading": return "arrow.down"
        case "paused": return "pause.fill"
        case "error": return "exclamationmark.triangle.fill"
        case "completed": return "checkmark.circle.fill"
        default: return "questionmark.circle"
        }
    }
}

// MARK: - Widget Configuration

struct DownloadWidget: Widget {
    let kind: String = "DownloadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DownloadProvider()) { entry in
            DownloadWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Downloads")
        .description("Monitor download progress")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    DownloadWidget()
} timeline: {
    DownloadEntry(
        date: .now,
        downloadData: DownloadData(
            tasks: [
                DownloadTaskData(id: "1", fileName: "movie.mkv", progress: 0.65, speed: 5_000_000, status: "downloading"),
                DownloadTaskData(id: "2", fileName: "album.zip", progress: 0.30, speed: 2_500_000, status: "downloading")
            ],
            lastUpdated: .now
        ),
        isConnected: true
    )
}
