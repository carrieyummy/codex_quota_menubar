import Foundation

/// 简单文件日志工具，用于记录启动和诊断信息。
enum Diagnostics {
    /// 日志文件路径。
    private static let logURL = URL(fileURLWithPath: "/tmp/codex-quota.log")

    /// 追加一行带时间戳的诊断日志。
    ///
    /// - Parameter message: 要写入的日志内容，不需要包含换行符。
    static func log(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logURL)
        }
    }
}
