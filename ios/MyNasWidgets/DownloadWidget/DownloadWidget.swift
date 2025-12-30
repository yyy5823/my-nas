//
//  DownloadWidget.swift
//  MyNasWidgets
//
//  下载进度小组件 - 显示当前下载任务
//

import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct DownloadEntry: TimelineEntry {
    let date: Date
    let data: WidgetDataManager.DownloadData
}

// MARK: - Timeline Provider

struct DownloadProvider: TimelineProvider {
    func placeholder(in _: Context) -> DownloadEntry {
        DownloadEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in _: Context, completion: @escaping (DownloadEntry) -> Void) {
        let data = WidgetDataManager.shared.getDownloadData()
        let entry = DownloadEntry(date: Date(), data: data.hasActiveDownloads ? data : .placeholder)
        completion(entry)
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<DownloadEntry>) -> Void) {
        let data = WidgetDataManager.shared.getDownloadData()
        let entry = DownloadEntry(date: Date(), data: data)

        // 下载中时每分钟刷新，否则每15分钟
        let interval = data.hasActiveDownloads ? 1 : 15
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: interval, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Views

struct DownloadWidgetSmallView: View {
    var entry: DownloadEntry

    var body: some View {
        Group {
            if !entry.data.hasActiveDownloads {
                // 无下载任务
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 32))
                        .foregroundColor(WidgetTheme.textSecondary)

                    Text("无下载任务")
                        .font(.caption)
                        .foregroundColor(WidgetTheme.textSecondary)

                    if entry.data.completedCount > 0 {
                        Text("已完成 \(entry.data.completedCount) 个")
                            .font(.caption2)
                            .foregroundColor(WidgetTheme.textSecondary.opacity(0.7))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Header
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(WidgetTheme.primaryColor)
                        Text("下载中")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(WidgetTheme.textPrimary)
                        Spacer()
                        Text("\(entry.data.activeCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(WidgetTheme.primaryColor)
                    }

                    Spacer()

                    // Progress circle
                    HStack {
                        Spacer()
                        DownloadProgressCircle(progress: entry.data.overallProgress, size: 60)
                        Spacer()
                    }

                    Spacer()

                    // Current file
                    if let fileName = entry.data.currentFileName {
                        Text(fileName)
                            .font(.system(size: 10))
                            .foregroundColor(WidgetTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(12)
            }
        }
        .widgetBackgroundCompat(WidgetTheme.backgroundGradient)
        .widgetURL(URL(string: "mynas://mine"))
    }
}

struct DownloadWidgetMediumView: View {
    var entry: DownloadEntry

    var body: some View {
        Group {
            if !entry.data.hasActiveDownloads {
                // 无下载任务
                HStack(spacing: 20) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 40))
                        .foregroundColor(WidgetTheme.textSecondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("无下载任务")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(WidgetTheme.textSecondary)

                        if entry.data.completedCount > 0 {
                            Text("已完成 \(entry.data.completedCount) 个任务")
                                .font(.caption)
                                .foregroundColor(WidgetTheme.textSecondary.opacity(0.7))
                        }

                        Text("点击查看下载管理")
                            .font(.caption2)
                            .foregroundColor(WidgetTheme.primaryColor)
                    }
                }
            } else {
                HStack(spacing: 16) {
                    // Left: Progress circle
                    DownloadProgressCircle(progress: entry.data.overallProgress, size: 80)

                    // Right: Task list
                    VStack(alignment: .leading, spacing: 8) {
                        // Header
                        HStack {
                            Text("下载任务")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(WidgetTheme.textPrimary)
                            Spacer()
                            Text("\(entry.data.activeCount) / \(entry.data.totalCount)")
                                .font(.caption)
                                .foregroundColor(WidgetTheme.textSecondary)
                        }

                        // Task list (show up to 2)
                        ForEach(entry.data.activeTasks.prefix(2), id: \.id) { task in
                            DownloadTaskRow(task: task)
                        }

                        if entry.data.activeCount > 2 {
                            Text("还有 \(entry.data.activeCount - 2) 个任务...")
                                .font(.caption2)
                                .foregroundColor(WidgetTheme.textSecondary)
                        }

                        Spacer()
                    }
                }
                .padding(16)
            }
        }
        .widgetBackgroundCompat(WidgetTheme.backgroundGradient)
        .widgetURL(URL(string: "mynas://mine"))
    }
}

struct DownloadProgressCircle: View {
    let progress: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: size * 0.1)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    WidgetTheme.primaryColor,
                    style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center icon and text
            VStack(spacing: 2) {
                Image(systemName: "arrow.down")
                    .font(.system(size: size * 0.2))
                    .foregroundColor(WidgetTheme.primaryColor)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: size * 0.18, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

struct DownloadTaskRow: View {
    let task: WidgetDataManager.DownloadTaskSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.fileName)
                .font(.system(size: 11))
                .foregroundColor(WidgetTheme.textPrimary)
                .lineLimit(1)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(WidgetTheme.primaryColor)
                        .frame(width: geometry.size.width * task.progress, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Widget Entry View

struct DownloadWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: DownloadEntry

    var body: some View {
        switch family {
        case .systemSmall:
            DownloadWidgetSmallView(entry: entry)
        case .systemMedium:
            DownloadWidgetMediumView(entry: entry)
        default:
            DownloadWidgetMediumView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

struct DownloadWidget: Widget {
    let kind: String = "DownloadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DownloadProvider()) { entry in
            if #available(iOS 17.0, *) {
                DownloadWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) {
                        WidgetTheme.backgroundGradient
                    }
            } else {
                DownloadWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("下载进度")
        .description("显示当前下载任务")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    DownloadWidget()
} timeline: {
    DownloadEntry(date: Date(), data: .placeholder)
}

#Preview(as: .systemMedium) {
    DownloadWidget()
} timeline: {
    DownloadEntry(date: Date(), data: .placeholder)
}
