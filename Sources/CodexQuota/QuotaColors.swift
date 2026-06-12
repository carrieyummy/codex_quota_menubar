import AppKit

enum QuotaColors {
    static let loading = NSColor(calibratedRed: 156 / 255, green: 168 / 255, blue: 184 / 255, alpha: 1)
    static let ready = NSColor(calibratedRed: 85 / 255, green: 230 / 255, blue: 165 / 255, alpha: 1)
    static let warning = NSColor(calibratedRed: 255 / 255, green: 209 / 255, blue: 102 / 255, alpha: 1)
    static let danger = NSColor(calibratedRed: 255 / 255, green: 102 / 255, blue: 122 / 255, alpha: 1)
    static let inactive = NSColor(calibratedRed: 156 / 255, green: 168 / 255, blue: 184 / 255, alpha: 0.38)

    static func color(forRemainingPercent percent: Int) -> NSColor {
        if percent <= 0 {
            return danger
        }
        if percent < 10 {
            return warning
        }
        return ready
    }
}
