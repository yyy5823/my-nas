import Cocoa
import FlutterMacOS
import WidgetKit

class WidgetDataChannel {
    private let channel: FlutterMethodChannel
    private let userDefaults: UserDefaults?
    private let encoder = JSONEncoder()

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "com.kkape.mynas/macos_widgets",
            binaryMessenger: messenger
        )
        userDefaults = UserDefaults(suiteName: "group.com.kkape.mynas")
        encoder.dateEncodingStrategy = .secondsSince1970

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "updateStorageWidget":
            updateStorageWidget(call.arguments as? [String: Any], result: result)
        case "updateDownloadWidget":
            updateDownloadWidget(call.arguments as? [String: Any], result: result)
        case "updateMediaWidget":
            updateMediaWidget(call.arguments as? [String: Any], result: result)
        case "updateQuickAccessWidget":
            updateQuickAccessWidget(call.arguments as? [String: Any], result: result)
        case "updateConnectionStatus":
            updateConnectionStatus(call.arguments as? [String: Any], result: result)
        case "refreshAllWidgets":
            refreshAllWidgets(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Storage Widget

    private func updateStorageWidget(_ args: [String: Any]?, result: FlutterResult) {
        guard let args = args else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }

        let storageData: [String: Any] = [
            "usedBytes": args["usedBytes"] as? Int64 ?? 0,
            "totalBytes": args["totalBytes"] as? Int64 ?? 0,
            "lastUpdated": Date().timeIntervalSince1970
        ]

        if let data = try? JSONSerialization.data(withJSONObject: storageData) {
            userDefaults?.set(data, forKey: "widget_storage_data")
            if #available(macOS 14.0, *) {
                WidgetCenter.shared.reloadTimelines(ofKind: "StorageWidget")
            }
        }

        result(nil)
    }

    // MARK: - Download Widget

    private func updateDownloadWidget(_ args: [String: Any]?, result: FlutterResult) {
        guard let args = args else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }

        var tasks: [[String: Any]] = []
        if let taskList = args["tasks"] as? [[String: Any]] {
            for task in taskList {
                tasks.append([
                    "id": task["id"] as? String ?? "",
                    "fileName": task["fileName"] as? String ?? "",
                    "progress": task["progress"] as? Double ?? 0,
                    "speed": task["speed"] as? Int64 ?? 0,
                    "status": task["status"] as? String ?? "unknown"
                ])
            }
        }

        let downloadData: [String: Any] = [
            "tasks": tasks,
            "lastUpdated": Date().timeIntervalSince1970
        ]

        if let data = try? JSONSerialization.data(withJSONObject: downloadData) {
            userDefaults?.set(data, forKey: "widget_download_data")
            if #available(macOS 14.0, *) {
                WidgetCenter.shared.reloadTimelines(ofKind: "DownloadWidget")
            }
        }

        result(nil)
    }

    // MARK: - Media Widget

    private func updateMediaWidget(_ args: [String: Any]?, result: FlutterResult) {
        guard let args = args else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }

        let mediaData: [String: Any] = [
            "title": args["title"] as? String ?? "",
            "artist": args["artist"] as? String ?? "",
            "album": args["album"] as? String ?? "",
            "artworkPath": args["artworkPath"] as? String as Any,
            "isPlaying": args["isPlaying"] as? Bool ?? false,
            "duration": args["duration"] as? Double ?? 0,
            "position": args["position"] as? Double ?? 0,
            "lastUpdated": Date().timeIntervalSince1970
        ]

        if let data = try? JSONSerialization.data(withJSONObject: mediaData) {
            userDefaults?.set(data, forKey: "widget_media_data")
            if #available(macOS 14.0, *) {
                WidgetCenter.shared.reloadTimelines(ofKind: "MediaWidget")
            }
        }

        result(nil)
    }

    // MARK: - Quick Access Widget

    private func updateQuickAccessWidget(_ args: [String: Any]?, result: FlutterResult) {
        // Quick Access widget is mostly static, just refresh it
        if #available(macOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: "QuickAccessWidget")
        }
        result(nil)
    }

    // MARK: - Connection Status

    private func updateConnectionStatus(_ args: [String: Any]?, result: FlutterResult) {
        guard let args = args else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
            return
        }

        let isConnected = args["isConnected"] as? Bool ?? false
        let connectionName = args["connectionName"] as? String

        userDefaults?.set(isConnected, forKey: "widget_is_connected")
        if let name = connectionName {
            userDefaults?.set(name, forKey: "widget_connection_name")
        } else {
            userDefaults?.removeObject(forKey: "widget_connection_name")
        }

        // Refresh all widgets when connection status changes
        if #available(macOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }

        result(nil)
    }

    // MARK: - Refresh All Widgets

    private func refreshAllWidgets(result: FlutterResult) {
        if #available(macOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        result(nil)
    }
}
