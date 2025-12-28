//
//  WidgetDataChannel.swift
//  Runner
//
//  Flutter Method Channel for updating widget data
//

import Flutter
import Foundation
import WidgetKit

class WidgetDataChannel: NSObject, FlutterPlugin {
    private static let channelName = "com.kkape.mynas/ios_widgets"
    private static let appGroupId = "group.com.kkape.mynas"

    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupId)
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = WidgetDataChannel()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "updateStorageWidget":
            handleUpdateStorageWidget(call: call, result: result)
        case "updateDownloadWidget":
            handleUpdateDownloadWidget(call: call, result: result)
        case "updateQuickAccessWidget":
            handleUpdateQuickAccessWidget(call: call, result: result)
        case "updateMediaWidget":
            handleUpdateMediaWidget(call: call, result: result)
        case "updateConnectionStatus":
            handleUpdateConnectionStatus(call: call, result: result)
        case "refreshAllWidgets":
            handleRefreshAllWidgets(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Storage Widget

    private func handleUpdateStorageWidget(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let defaults = userDefaults else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: args)
            defaults.set(jsonData, forKey: "widget_storage_data")

            // Also set connection status for quick access
            let isConnected = args["isConnected"] as? Bool ?? false
            let nasName = args["nasName"] as? String
            defaults.set(isConnected, forKey: "widget_nas_connected")
            if let nasName = nasName {
                defaults.set(nasName, forKey: "widget_nas_name")
            }

            defaults.synchronize()

            // Reload widgets
            if #available(iOS 14.0, *) {
                WidgetCenter.shared.reloadTimelines(ofKind: "StorageWidget")
            }

            result(nil)
        } catch {
            result(FlutterError(code: "ENCODE_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Download Widget

    private func handleUpdateDownloadWidget(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let defaults = userDefaults else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: args)
            defaults.set(jsonData, forKey: "widget_download_data")
            defaults.synchronize()

            // Reload widgets
            if #available(iOS 14.0, *) {
                WidgetCenter.shared.reloadTimelines(ofKind: "DownloadWidget")
            }

            result(nil)
        } catch {
            result(FlutterError(code: "ENCODE_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Quick Access Widget

    private func handleUpdateQuickAccessWidget(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let defaults = userDefaults else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: args)
            defaults.set(jsonData, forKey: "widget_quick_access_data")
            defaults.synchronize()

            // Reload widgets
            if #available(iOS 14.0, *) {
                WidgetCenter.shared.reloadTimelines(ofKind: "QuickAccessWidget")
            }

            result(nil)
        } catch {
            result(FlutterError(code: "ENCODE_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Media Widget

    private func handleUpdateMediaWidget(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let defaults = userDefaults else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
        }

        // Extract cover image data if present
        var jsonArgs = args
        if let coverData = args["coverImageData"] as? FlutterStandardTypedData {
            // Save cover image separately
            defaults.set(coverData.data, forKey: "widget_cover_image")
            jsonArgs.removeValue(forKey: "coverImageData")
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonArgs)
            defaults.set(jsonData, forKey: "widget_media_data")
            defaults.synchronize()

            // Reload widgets
            if #available(iOS 14.0, *) {
                WidgetCenter.shared.reloadTimelines(ofKind: "MediaWidget")
            }

            result(nil)
        } catch {
            result(FlutterError(code: "ENCODE_ERROR", message: error.localizedDescription, details: nil))
        }
    }

    // MARK: - Connection Status

    private func handleUpdateConnectionStatus(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let defaults = userDefaults else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
        }

        let isConnected = args["isConnected"] as? Bool ?? false
        let connectionName = args["connectionName"] as? String

        defaults.set(isConnected, forKey: "widget_is_connected")
        if let name = connectionName {
            defaults.set(name, forKey: "widget_connection_name")
        } else {
            defaults.removeObject(forKey: "widget_connection_name")
        }
        defaults.synchronize()

        // Refresh all widgets when connection status changes
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }

        result(nil)
    }

    // MARK: - Refresh All Widgets

    private func handleRefreshAllWidgets(result: @escaping FlutterResult) {
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        result(nil)
    }
}
