import Foundation

struct QuotaSnapshot: Sendable {
    let codex: QuotaBucket
    let spark: QuotaBucket?
    let fetchedAt: Date
}

struct QuotaBucket: Sendable {
    let title: String
    let fiveHour: QuotaWindow
    let weekly: QuotaWindow
}

struct QuotaWindow: Sendable {
    let title: String
    let usedPercent: Int
    let resetAt: Date?

    var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

enum QuotaError: LocalizedError, Sendable {
    case codexBinaryMissing(String)
    case processNotRunning
    case invalidResponse
    case serverError(String)
    case missingRateLimits

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
