import Flutter
import UIKit

/// 原生日志桥接通道
/// 将 Swift 端的日志通过 Method Channel 发送到 Flutter 端
/// Flutter 端可以将这些日志上传到 RabbitMQ
class NativeLogBridge: NSObject, FlutterPlugin {

    private var channel: FlutterMethodChannel?

    /// 定时上传任务
    private var uploadTimer: Timer?

    /// 上传间隔（秒）
    private let uploadInterval: TimeInterval = 30

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.kkape.mynas/native_log_bridge",
            binaryMessenger: registrar.messenger()
        )

        let instance = NativeLogBridge()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)

        // 启动定时上传
        instance.startPeriodicUpload()

        print("NativeLogBridge: Registered and started periodic upload")
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPendingLogs":
            // Flutter 主动获取待上传的日志
            let logs = SharedLogger.shared.readPendingLogs()
            let logDicts = logs.map { entry -> [String: Any] in
                return [
                    "timestamp": ISO8601DateFormatter().string(from: entry.timestamp),
                    "level": entry.level.rawValue,
                    "message": entry.message,
                    "source": entry.source,
                    "file": entry.file,
                    "function": entry.function,
                    "line": entry.line
                ]
            }
            result(logDicts)

        case "clearLogs":
            // Flutter 通知日志已上传成功，可以清空
            SharedLogger.shared.clearLogs()
            result(nil)

        case "getPendingLogCount":
            // 获取待上传日志数量
            result(SharedLogger.shared.pendingLogCount())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Periodic Upload

    /// 启动定时上传
    private func startPeriodicUpload() {
        // 在主线程启动定时器
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.uploadTimer = Timer.scheduledTimer(
                withTimeInterval: self.uploadInterval,
                repeats: true
            ) { [weak self] _ in
                self?.notifyFlutterToUpload()
            }
        }
    }

    /// 通知 Flutter 上传日志
    private func notifyFlutterToUpload() {
        let count = SharedLogger.shared.pendingLogCount()
        if count > 0 {
            print("NativeLogBridge: Notifying Flutter to upload \(count) logs")
            channel?.invokeMethod("uploadPendingLogs", arguments: ["count": count])
        }
    }

    /// 停止定时上传
    func stopPeriodicUpload() {
        uploadTimer?.invalidate()
        uploadTimer = nil
    }

    deinit {
        stopPeriodicUpload()
    }
}
