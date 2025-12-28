//
//  WidgetDataManager.swift
//  MyNasWidgets
//
//  Shared data manager for all widgets
//

import Foundation
import SwiftUI

/// 小组件数据管理器
/// 负责从 App Group 共享存储中读取数据
class WidgetDataManager {
    static let shared = WidgetDataManager()

    private let appGroupId = "group.com.kkape.mynas"
    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    // MARK: - Storage Data

    struct StorageData: Codable {
        let totalBytes: Int
        let usedBytes: Int
        let nasName: String
        let adapterType: String
        let lastUpdated: Int
        let isConnected: Bool

        var usagePercent: Double {
            totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
        }

        var isLowSpace: Bool {
            usagePercent > 0.9
        }

        var hasValidData: Bool {
            totalBytes > 0
        }

        static let placeholder = StorageData(
            totalBytes: 1_000_000_000_000,
            usedBytes: 650_000_000_000,
            nasName: "My NAS",
            adapterType: "synology",
            lastUpdated: Int(Date().timeIntervalSince1970 * 1000),
            isConnected: true
        )

        static let empty = StorageData(
            totalBytes: 0,
            usedBytes: 0,
            nasName: "",
            adapterType: "unknown",
            lastUpdated: 0,
            isConnected: false
        )
    }

    func getStorageData() -> StorageData {
        guard let defaults = userDefaults,
              let jsonData = defaults.data(forKey: "widget_storage_data"),
              let data = try? JSONDecoder().decode(StorageData.self, from: jsonData) else {
            return .empty
        }
        return data
    }

    // MARK: - Download Data

    struct DownloadTaskSummary: Codable {
        let id: String
        let fileName: String
        let progress: Double
        let status: String
    }

    struct DownloadData: Codable {
        let activeTasks: [DownloadTaskSummary]
        let completedCount: Int
        let totalCount: Int
        let lastUpdated: Int

        var activeCount: Int {
            activeTasks.count
        }

        var hasActiveDownloads: Bool {
            !activeTasks.isEmpty
        }

        var overallProgress: Double {
            guard !activeTasks.isEmpty else { return 0 }
            let sum = activeTasks.reduce(0.0) { $0 + $1.progress }
            return sum / Double(activeTasks.count)
        }

        var currentFileName: String? {
            activeTasks.first?.fileName
        }

        static let placeholder = DownloadData(
            activeTasks: [
                DownloadTaskSummary(id: "1", fileName: "movie.mkv", progress: 0.45, status: "downloading")
            ],
            completedCount: 3,
            totalCount: 5,
            lastUpdated: Int(Date().timeIntervalSince1970 * 1000)
        )

        static let empty = DownloadData(
            activeTasks: [],
            completedCount: 0,
            totalCount: 0,
            lastUpdated: 0
        )
    }

    func getDownloadData() -> DownloadData {
        guard let defaults = userDefaults,
              let jsonData = defaults.data(forKey: "widget_download_data"),
              let data = try? JSONDecoder().decode(DownloadData.self, from: jsonData) else {
            return .empty
        }
        return data
    }

    // MARK: - Media Data

    struct MediaData: Codable {
        let title: String?
        let artist: String?
        let album: String?
        let coverImagePath: String?
        let isPlaying: Bool
        let progress: Double
        let currentTime: Int
        let totalTime: Int
        let themeColor: Int?

        var hasContent: Bool {
            title != nil && !(title?.isEmpty ?? true)
        }

        static let placeholder = MediaData(
            title: "Song Title",
            artist: "Artist Name",
            album: "Album Name",
            coverImagePath: nil,
            isPlaying: true,
            progress: 0.45,
            currentTime: 120,
            totalTime: 300,
            themeColor: nil
        )

        static let empty = MediaData(
            title: nil,
            artist: nil,
            album: nil,
            coverImagePath: nil,
            isPlaying: false,
            progress: 0,
            currentTime: 0,
            totalTime: 0,
            themeColor: nil
        )
    }

    func getMediaData() -> MediaData {
        guard let defaults = userDefaults,
              let jsonData = defaults.data(forKey: "widget_media_data"),
              let data = try? JSONDecoder().decode(MediaData.self, from: jsonData) else {
            return .empty
        }
        return data
    }

    /// 获取封面图片
    func getCoverImage() -> UIImage? {
        guard let defaults = userDefaults,
              let imageData = defaults.data(forKey: "widget_cover_image") else {
            return nil
        }
        return UIImage(data: imageData)
    }

    // MARK: - Quick Access Data

    struct QuickAccessData: Codable {
        let items: [String]
        let nasName: String?
        let isConnected: Bool

        static let defaultData = QuickAccessData(
            items: ["music", "video", "book"],
            nasName: nil,
            isConnected: false
        )
    }

    func getQuickAccessData() -> QuickAccessData {
        guard let defaults = userDefaults,
              let jsonData = defaults.data(forKey: "widget_quick_access_data"),
              let data = try? JSONDecoder().decode(QuickAccessData.self, from: jsonData) else {
            return .defaultData
        }
        return data
    }

    // MARK: - Connection Status

    func isNasConnected() -> Bool {
        userDefaults?.bool(forKey: "widget_nas_connected") ?? false
    }

    func getNasName() -> String? {
        userDefaults?.string(forKey: "widget_nas_name")
    }
}

// MARK: - Utility Extensions

extension Int {
    /// 格式化字节数为人类可读的字符串
    var formattedBytes: String {
        let bytes = Double(self)
        let kb = bytes / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        let tb = gb / 1024

        if tb >= 1 {
            return String(format: "%.1f TB", tb)
        } else if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.1f KB", kb)
        } else {
            return "\(self) B"
        }
    }
}

extension Int {
    /// 格式化秒数为时间字符串
    var formattedDuration: String {
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        let seconds = self % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

extension Color {
    /// 从 ARGB 整数创建颜色
    init(argb: Int) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// 从十六进制字符串创建颜色
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 1
            g = 1
            b = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
