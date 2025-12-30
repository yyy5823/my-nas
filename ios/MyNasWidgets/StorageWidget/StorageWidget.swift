//
//  StorageWidget.swift
//  MyNasWidgets
//
//  存储状态小组件 - 显示 NAS 存储使用情况
//

import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct StorageEntry: TimelineEntry {
    let date: Date
    let data: WidgetDataManager.StorageData
}

// MARK: - Timeline Provider

struct StorageProvider: TimelineProvider {
    func placeholder(in _: Context) -> StorageEntry {
        StorageEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in _: Context, completion: @escaping (StorageEntry) -> Void) {
        let data = WidgetDataManager.shared.getStorageData()
        let entry = StorageEntry(date: Date(), data: data.hasValidData ? data : .placeholder)
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<StorageEntry>) -> Void) {
        let data = WidgetDataManager.shared.getStorageData()
        let entry = StorageEntry(date: Date(), data: data)

        // 每15分钟刷新一次
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Views

struct StorageWidgetSmallView: View {
    var entry: StorageEntry

    var body: some View {
        Group {
            if !entry.data.isConnected || !entry.data.hasValidData {
                NotConnectedView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Header
                    HStack(spacing: 4) {
                        Image(systemName: "externaldrive.connected.to.line.below")
                            .font(.system(size: 12))
                            .foregroundColor(WidgetTheme.primaryColor)
                        Text(entry.data.nasName.isEmpty ? "NAS" : entry.data.nasName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(WidgetTheme.textPrimary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Circular progress
                    HStack {
                        Spacer()
                        StorageCircleView(
                            progress: entry.data.usagePercent,
                            isLowSpace: entry.data.isLowSpace,
                            size: 70
                        )
                        Spacer()
                    }

                    Spacer()

                    // Footer
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.data.usedBytes.formattedBytes) / \(entry.data.totalBytes.formattedBytes)")
                            .font(.system(size: 10))
                            .foregroundColor(WidgetTheme.textSecondary)
                    }
                }
                .padding(12)
            }
        }
        .widgetBackgroundCompat(WidgetTheme.backgroundGradient)
        .widgetURL(URL(string: "mynas://mine"))
    }
}

struct StorageWidgetMediumView: View {
    var entry: StorageEntry

    var body: some View {
        Group {
            if !entry.data.isConnected || !entry.data.hasValidData {
                NotConnectedView()
            } else {
                HStack(spacing: 16) {
                    // Left: Circular progress
                    StorageCircleView(
                        progress: entry.data.usagePercent,
                        isLowSpace: entry.data.isLowSpace,
                        size: 90
                    )

                    // Right: Details
                    VStack(alignment: .leading, spacing: 8) {
                        // Header
                        HStack(spacing: 4) {
                            Image(systemName: "externaldrive.connected.to.line.below")
                                .font(.system(size: 14))
                                .foregroundColor(WidgetTheme.primaryColor)
                            Text(entry.data.nasName.isEmpty ? "NAS" : entry.data.nasName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(WidgetTheme.textPrimary)
                                .lineLimit(1)
                        }

                        Spacer()

                        // Storage details
                        VStack(alignment: .leading, spacing: 4) {
                            StorageDetailRow(
                                label: "已使用",
                                value: entry.data.usedBytes.formattedBytes,
                                color: entry.data.isLowSpace ? .red : WidgetTheme.primaryColor
                            )
                            StorageDetailRow(
                                label: "可用",
                                value: (entry.data.totalBytes - entry.data.usedBytes).formattedBytes,
                                color: WidgetTheme.textSecondary
                            )
                            StorageDetailRow(
                                label: "总容量",
                                value: entry.data.totalBytes.formattedBytes,
                                color: WidgetTheme.textSecondary
                            )
                        }

                        Spacer()

                        // Adapter type badge
                        HStack {
                            Text(entry.data.adapterType.uppercased())
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(WidgetTheme.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                    }
                }
                .padding(16)
            }
        }
        .widgetBackgroundCompat(WidgetTheme.backgroundGradient)
        .widgetURL(URL(string: "mynas://mine"))
    }
}

struct StorageCircleView: View {
    let progress: Double
    let isLowSpace: Bool
    let size: CGFloat

    var progressColor: Color {
        if isLowSpace {
            return .red
        } else if progress > 0.7 {
            return .orange
        } else {
            return WidgetTheme.primaryColor
        }
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: size * 0.08)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center text
            VStack(spacing: 0) {
                Text("\(Int(progress * 100))")
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundColor(.white)
                Text("%")
                    .font(.system(size: size * 0.15))
                    .foregroundColor(WidgetTheme.textSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct StorageDetailRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(WidgetTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
        }
    }
}

// MARK: - Widget Entry View

struct StorageWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: StorageEntry

    var body: some View {
        switch family {
        case .systemSmall:
            StorageWidgetSmallView(entry: entry)
        case .systemMedium:
            StorageWidgetMediumView(entry: entry)
        default:
            StorageWidgetMediumView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

struct StorageWidget: Widget {
    let kind: String = "StorageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StorageProvider()) { entry in
            if #available(iOS 17.0, *) {
                StorageWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) {
                        WidgetTheme.backgroundGradient
                    }
            } else {
                StorageWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("存储状态")
        .description("显示 NAS 存储使用情况")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    StorageWidget()
} timeline: {
    StorageEntry(date: Date(), data: .placeholder)
}

#Preview(as: .systemMedium) {
    StorageWidget()
} timeline: {
    StorageEntry(date: Date(), data: .placeholder)
}
