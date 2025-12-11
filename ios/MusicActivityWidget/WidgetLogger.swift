import Foundation

/// Widget Extension 专用日志服务
/// 将日志写入 App Group 共享存储，由主 App 读取后上传到 RabbitMQ
class WidgetLogger {
    static let shared = WidgetLogger()

    /// App Group ID
    private let appGroupId = "group.com.kkape.mynas"

    /// 日志文件名
    private let logFileName = "widget_logs.jsonl"

    /// 最大日志文件大小 (512KB - Widget 内存受限)
    private let maxLogFileSize: Int = 512 * 1024

    /// 共享的 UserDefaults
    private lazy var sharedDefaults: UserDefaults? = {
        UserDefaults(suiteName: appGroupId)
    }()

    /// App Group Container URL
    private lazy var containerURL: URL? = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }()

    /// 日志文件 URL
    private var logFileURL: URL? {
        containerURL?.appendingPathComponent(logFileName)
    }

    private init() {}

    // MARK: - Public API

    /// 记录调试日志
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        log(level: "DEBUG", message: message, file: file, function: function, line: line)
        #endif
    }

    /// 记录信息日志
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: "INFO", message: message, file: file, function: function, line: line)
    }

    /// 记录警告日志
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: "WARNING", message: message, file: file, function: function, line: line)
    }

    /// 记录错误日志（会被上传到 RabbitMQ）
    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        log(level: "ERROR", message: fullMessage, file: file, function: function, line: line, writeToFile: true)
    }

    /// 记录致命错误日志（会被上传到 RabbitMQ）
    func fatal(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        log(level: "FATAL", message: fullMessage, file: file, function: function, line: line, writeToFile: true)
    }

    // MARK: - Private Methods

    private func log(level: String, message: String, file: String, function: String, line: Int, writeToFile: Bool = false) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fileName = (file as NSString).lastPathComponent

        // 控制台输出
        print("[\(timestamp)] [\(level)] [Widget] \(message)")

        // 仅错误级别写入文件
        if writeToFile || level == "ERROR" || level == "FATAL" {
            writeLogToFile(
                timestamp: timestamp,
                level: level,
                message: message,
                file: fileName,
                function: function,
                line: line
            )
        }
    }

    /// 写入日志到共享文件
    private func writeLogToFile(timestamp: String, level: String, message: String, file: String, function: String, line: Int) {
        guard let fileURL = logFileURL else { return }

        // 构建 JSON 行
        let entry: [String: Any] = [
            "timestamp": timestamp,
            "level": level,
            "message": message,
            "source": "WidgetExtension",
            "file": file,
            "function": function,
            "line": line
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: entry),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let line = jsonString + "\n"

        do {
            // 检查文件大小，超过限制则清空
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int,
               size > maxLogFileSize {
                try? FileManager.default.removeItem(at: fileURL)
            }

            // 追加写入
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try line.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            // Widget 中无法打印太多日志，静默失败
        }
    }
}

// MARK: - 便捷全局实例
let widgetLogger = WidgetLogger.shared
