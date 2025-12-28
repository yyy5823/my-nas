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
    let title: String
    let artist: String
    let album: String
    let artworkPath: String?
    let isPlaying: Bool
    let duration: Double
    let position: Double
    let lastUpdated: Date

    var progress: Double {
        guard duration > 0 else { return 0 }
        return position / duration
    }

    var positionFormatted: String {
        formatTime(position)
    }

    var durationFormatted: String {
        formatTime(duration)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

enum QuickAccessType: String, Codable, CaseIterable {
    case music
    case video
    case books

    var displayName: String {
        switch self {
        case .music: return "Music"
        case .video: return "Video"
        case .books: return "Books"
        }
    }

    var iconName: String {
        switch self {
        case .music: return "music.note"
        case .video: return "play.rectangle"
        case .books: return "book"
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
        guard let mediaData = getMediaData(),
              let artworkPath = mediaData.artworkPath else {
            return nil
        }
        return NSImage(contentsOfFile: artworkPath)
    }

    // MARK: - Connection Status

    func isConnected() -> Bool {
        return userDefaults?.bool(forKey: "widget_is_connected") ?? false
    }

    func getConnectionName() -> String? {
        return userDefaults?.string(forKey: "widget_connection_name")
    }
}
