import Foundation
import WidgetKit
import AppKit

// MARK: - Data Models

struct StorageData: Codable {
    let usedBytes: Int64
    let totalBytes: Int64
    let lastUpdated: Date

    var usedPercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    var usedFormatted: String {
        ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file)
    }

    var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var freeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes - usedBytes, countStyle: .file)
    }
}

struct DownloadTaskData: Codable {
    let id: String
    let fileName: String
    let progress: Double
    let speed: Int64
    let status: String

    var speedFormatted: String {
        ByteCountFormatter.string(fromByteCount: speed, countStyle: .file) + "/s"
    }
}

struct DownloadData: Codable {
    let tasks: [DownloadTaskData]
    let lastUpdated: Date

    var activeCount: Int {
        tasks.filter { $0.status == "downloading" }.count
    }

    var totalProgress: Double {
        guard !tasks.isEmpty else { return 0 }
        return tasks.reduce(0) { $0 + $1.progress } / Double(tasks.count)
    }
}

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

    var positionFormatted: String {
        formatTime(Double(currentTime))
    }

    var durationFormatted: String {
        formatTime(Double(totalTime))
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
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

enum QuickAccessType: String, Codable, CaseIterable {
    case music
    case video
    case reading // 对应路由 /reading

    var displayName: String {
        switch self {
        case .music: return "Music"
        case .video: return "Video"
        case .reading: return "Books"
        }
    }

    var iconName: String {
        switch self {
        case .music: return "music.note"
        case .video: return "play.rectangle"
        case .reading: return "book"
        }
    }

    var deepLink: URL {
        URL(string: "mynas://\(rawValue)")!
    }
}

// MARK: - Widget Data Manager

class WidgetDataManager {
    static let shared = WidgetDataManager()

    private let userDefaults: UserDefaults?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {
        userDefaults = UserDefaults(suiteName: "group.com.kkape.mynas")
        decoder.dateDecodingStrategy = .secondsSince1970
        encoder.dateEncodingStrategy = .secondsSince1970
    }

    // MARK: - Storage Data

    func getStorageData() -> StorageData? {
        guard let data = userDefaults?.data(forKey: "widget_storage_data"),
              let storageData = try? decoder.decode(StorageData.self, from: data) else {
            return nil
        }
        return storageData
    }

    // MARK: - Download Data

    func getDownloadData() -> DownloadData? {
        guard let data = userDefaults?.data(forKey: "widget_download_data"),
              let downloadData = try? decoder.decode(DownloadData.self, from: data) else {
            return nil
        }
        return downloadData
    }

    // MARK: - Media Data

    func getMediaData() -> MediaData? {
        guard let data = userDefaults?.data(forKey: "widget_media_data"),
              let mediaData = try? decoder.decode(MediaData.self, from: data) else {
            return nil
        }
        return mediaData
    }

    func getMediaArtwork() -> NSImage? {
        // 首先尝试从封面图片数据读取
        if let imageData = userDefaults?.data(forKey: "widget_cover_image"),
           let image = NSImage(data: imageData) {
            return image
        }

        // 其次尝试从路径读取
        guard let mediaData = getMediaData(),
              let coverPath = mediaData.coverImagePath else {
            return nil
        }
        return NSImage(contentsOfFile: coverPath)
    }

    // MARK: - Connection Status

    func isConnected() -> Bool {
        return userDefaults?.bool(forKey: "widget_is_connected") ?? false
    }

    func getConnectionName() -> String? {
        return userDefaults?.string(forKey: "widget_connection_name")
    }
}
