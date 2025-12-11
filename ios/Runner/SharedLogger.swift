import Foundation

/// 共享日志服务
/// Widget Extension 和主 App 都可以使用
/// Widget Extension 的日志会被主 App 读取后上传到 RabbitMQ
class SharedLogger {
    static let shared = SharedLogger()

    /// App Group ID
    private let appGroupId = "group.com.kkape.mynas"

    /// 日志文件名
    private let logFileName = "widget_logs.jsonl"

    /// 最大日志文件大小 (1MB)
    private let maxLogFileSize: Int = 1024 * 1024

    /// 日志队列（线程安全）
    private let logQueue = DispatchQueue(label: "com.kkape.mynas.sharedlogger", qos: .utility)

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
        log(level: .debug, message: message, file: file, function: function, line: line)
    }

    /// 记录信息日志
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .info, message: message, file: file, function: function, line: line)
    }

    /// 记录警告日志
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(level: .warning, message: message, file: file, function: function, line: line)
    }

    /// 记录错误日志
    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        log(level: .error, message: fullMessage, file: file, function: function, line: line)
    }

    /// 记录致命错误日志
    func fatal(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        var fullMessage = message
        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        log(level: .fatal, message: fullMessage, file: file, function: function, line: line)
    }

    // MARK: - Log Entry

    enum LogLevel: String, Codable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case fatal = "FATAL"
    }

    struct LogEntry: Codable {
        let timestamp: Date
        let level: LogLevel
        let message: String
        let source: String  // "MainApp" or "WidgetExtension"
        let file: String
        let function: String
        let line: Int

        var jsonString: String? {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(self) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    // MARK: - Private Methods

    private func log(level: LogLevel, message: String, file: String, function: String, line: Int) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message,
            source: isMainApp ? "MainApp" : "WidgetExtension",
            file: (file as NSString).lastPathComponent,
            function: function,
            line: line
        )

        // 控制台输出
        let timestamp = ISO8601DateFormatter().string(from: entry.timestamp)
        print("[\(timestamp)] [\(entry.level.rawValue)] [\(entry.source)] \(message)")

        // 写入共享文件（仅 ERROR 和 FATAL 级别，或者来自 Widget Extension）
        if level == .error || level == .fatal || !isMainApp {
            logQueue.async { [weak self] in
                self?.writeToFile(entry)
            }
        }
    }

    /// 检查是否在主 App 中运行
    private var isMainApp: Bool {
        // Widget Extension 的 Bundle ID 包含 ".MusicActivityWidget"
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        return !bundleId.contains("Widget")
    }

    /// 写入日志到共享文件
    private func writeToFile(_ entry: LogEntry) {
        guard let fileURL = logFileURL,
              let jsonString = entry.jsonString else { return }

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
            print("SharedLogger: Failed to write log: \(error)")
        }
    }

    // MARK: - Main App Methods (读取和清理日志)

    /// 读取所有待上传的日志（主 App 调用）
    func readPendingLogs() -> [LogEntry] {
        guard isMainApp, let fileURL = logFileURL else { return [] }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            return lines.compactMap { line -> LogEntry? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(LogEntry.self, from: data)
            }
        } catch {
            print("SharedLogger: Failed to read logs: \(error)")
            return []
        }
    }

    /// 清空已上传的日志（主 App 调用）
    func clearLogs() {
        guard isMainApp, let fileURL = logFileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 获取日志数量（主 App 调用）
    func pendingLogCount() -> Int {
        guard let fileURL = logFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else { return 0 }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            return content.components(separatedBy: "\n").filter { !$0.isEmpty }.count
        } catch {
            return 0
        }
    }
}

// MARK: - 便捷全局函数

/// 共享日志实例
let sharedLogger = SharedLogger.shared
