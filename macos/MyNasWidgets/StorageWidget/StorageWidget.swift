import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct StorageProvider: TimelineProvider {
    func placeholder(in context: Context) -> StorageEntry {
        StorageEntry(
            date: Date(),
            storageData: StorageData(
                usedBytes: 500_000_000_000,
                totalBytes: 1_000_000_000_000,
                lastUpdated: Date()
            ),
            isConnected: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (StorageEntry) -> Void) {
        let entry = StorageEntry(
            date: Date(),
            storageData: WidgetDataManager.shared.getStorageData(),
            isConnected: WidgetDataManager.shared.isConnected()
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StorageEntry>) -> Void) {
        let entry = StorageEntry(
            date: Date(),
            storageData: WidgetDataManager.shared.getStorageData(),
            isConnected: WidgetDataManager.shared.isConnected()
        )
        // 每15分钟更新一次
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct StorageEntry: TimelineEntry {
    let date: Date
    let storageData: StorageData?
    let isConnected: Bool
}

// MARK: - Widget Views

struct StorageWidgetEntryView: View {
    var entry: StorageProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallStorageView(entry: entry)
        case .systemMedium:
            MediumStorageView(entry: entry)
        default:
            SmallStorageView(entry: entry)
        }
    }
}

struct SmallStorageView: View {
    let entry: StorageEntry

    var body: some View {
        VStack(spacing: 8) {
            WidgetHeader(title: "Storage", icon: "externaldrive.fill")

            if let data = entry.storageData, entry.isConnected {
                ZStack {
                    CircularProgressView(
                        progress: data.usedPercentage,
                        lineWidth: 8,
                        foregroundColor: progressColor(for: data.usedPercentage)
                    )

                    VStack(spacing: 2) {
                        Text("\(Int(data.usedPercentage * 100))%")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Used")
                            .font(.caption2)
                            .foregroundColor(WidgetTheme.secondaryColor)
                    }
                }
                .padding(4)

                Text("\(data.freeFormatted) free")
                    .font(.caption2)
                    .foregroundColor(WidgetTheme.secondaryColor)
            } else {
                EmptyStateView(icon: "externaldrive.badge.xmark", message: "Not Available")
            }
        }
        .containerBackground(for: .widget) {
            WidgetTheme.backgroundColor
        }
        .widgetURL(URL(string: "mynas://mine"))
    }

    private func progressColor(for percentage: Double) -> Color {
        if percentage > 0.9 {
            return WidgetTheme.errorColor
        } else if percentage > 0.75 {
            return WidgetTheme.warningColor
        }
        return WidgetTheme.primaryColor
    }
}

struct MediumStorageView: View {
    let entry: StorageEntry

    var body: some View {
        HStack(spacing: 16) {
            // 左侧圆环
            if let data = entry.storageData, entry.isConnected {
                ZStack {
                    CircularProgressView(
                        progress: data.usedPercentage,
                        lineWidth: 10,
                        foregroundColor: progressColor(for: data.usedPercentage)
                    )

                    VStack(spacing: 2) {
                        Text("\(Int(data.usedPercentage * 100))%")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Used")
                            .font(.caption2)
                            .foregroundColor(WidgetTheme.secondaryColor)
                    }
                }
                .frame(width: 80, height: 80)

                // 右侧详情
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeader(title: "Storage", icon: "externaldrive.fill")

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle()
                                .fill(WidgetTheme.primaryColor)
                                .frame(width: 8, height: 8)
                            Text("Used: \(data.usedFormatted)")
                                .font(.caption)
                        }

                        HStack {
                            Circle()
                                .fill(WidgetTheme.secondaryColor.opacity(0.3))
                                .frame(width: 8, height: 8)
                            Text("Free: \(data.freeFormatted)")
                                .font(.caption)
                        }

                        Text("Total: \(data.totalFormatted)")
                            .font(.caption2)
                            .foregroundColor(WidgetTheme.secondaryColor)
                    }

                    Spacer()
                }
            } else {
                EmptyStateView(icon: "externaldrive.badge.xmark", message: "Storage information not available")
                    .frame(maxWidth: .infinity)
            }
        }
        .containerBackground(for: .widget) {
            WidgetTheme.backgroundColor
        }
        .widgetURL(URL(string: "mynas://mine"))
    }

    private func progressColor(for percentage: Double) -> Color {
        if percentage > 0.9 {
            return WidgetTheme.errorColor
        } else if percentage > 0.75 {
            return WidgetTheme.warningColor
        }
        return WidgetTheme.primaryColor
    }
}

// MARK: - Widget Configuration

struct StorageWidget: Widget {
    let kind: String = "StorageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StorageProvider()) { entry in
            StorageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Storage Status")
        .description("View NAS storage usage")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    StorageWidget()
} timeline: {
    StorageEntry(
        date: .now,
        storageData: StorageData(
            usedBytes: 750_000_000_000,
            totalBytes: 1_000_000_000_000,
            lastUpdated: .now
        ),
        isConnected: true
    )
}
