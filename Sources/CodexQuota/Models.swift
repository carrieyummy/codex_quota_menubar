import Foundation

/// 表示一次从 Codex app-server 读取到的额度快照。
///
/// - codex: Codex 主模型额度桶，必须存在。
/// - spark: GPT-5.3-Codex-Spark 额度桶；旧版响应或账号无该额度时为 `nil`。
/// - fetchedAt: 本次快照读取完成的本地时间。
struct QuotaSnapshot: Sendable {
    let codex: QuotaBucket
    let spark: QuotaBucket?
    let fetchedAt: Date
}

/// 表示同一额度类型下的两个时间窗口。
///
/// - title: UI 中显示的额度名称。
/// - fiveHour: 5 小时窗口额度。
/// - weekly: 周窗口额度。
struct QuotaBucket: Sendable {
    let title: String
    let fiveHour: QuotaWindow
    let weekly: QuotaWindow
}

/// 表示单个限额窗口的使用情况。
///
/// - title: UI 中显示的窗口名称。
/// - usedPercent: 已使用百分比，来自 app-server 响应，期望范围为 0...100。
/// - resetAt: 限额重置时间；当服务端未返回 `resetsAt` 时为 `nil`。
struct QuotaWindow: Sendable {
    let title: String
    let usedPercent: Int
    let resetAt: Date?

    /// 剩余百分比。
    ///
    /// - Returns: 将 `100 - usedPercent` 夹在 0...100 后得到的剩余额度百分比。
    var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

/// 读取或解析 Codex 额度时可能出现的错误。
enum QuotaError: LocalizedError, Sendable {
    /// 指定路径下找不到可执行的 Codex 二进制。
    case codexBinaryMissing(String)
    /// app-server 进程未运行或已退出。
    case processNotRunning
    /// app-server 返回了无法识别的 JSON-RPC 响应。
    case invalidResponse
    /// app-server 返回了错误消息。
    case serverError(String)
    /// 响应里缺少额度字段。
    case missingRateLimits

    /// 面向用户展示的错误说明。
    ///
    /// - Returns: 本地化错误描述字符串。
    var errorDescription: String? {
        switch self {
        case .codexBinaryMissing(let path):
            return "Codex binary not found at \(path)"
        case .processNotRunning:
            return "Codex app-server is not running"
        case .invalidResponse:
            return "Codex app-server returned an invalid response"
        case .serverError(let message):
            return message
        case .missingRateLimits:
            return "Rate limit fields were missing from the response"
        }
    }
}
