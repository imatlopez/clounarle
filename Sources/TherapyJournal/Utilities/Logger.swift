import Foundation

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.therapyjournal.logger", qos: .utility)

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TherapyJournal", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logFileURL = dir.appendingPathComponent("app.log")
    }

    enum Level: String {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
        case debug = "DEBUG"
    }

    func log(_ message: String, level: Level = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent

        // Format timestamp and build entry on the serial queue for thread safety
        queue.async { [weak self] in
            guard let self else { return }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            let timestamp = formatter.string(from: Date())
            let entry = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(message)\n"

            if let data = entry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: self.logFileURL, options: .atomic)
                }
            }

            #if DEBUG
            print(entry, terminator: "")
            #endif
        }
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    func warn(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warn, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
}
