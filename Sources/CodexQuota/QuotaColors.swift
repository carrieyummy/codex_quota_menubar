import AppKit

/// 额度状态在 UI 中使用的固定颜色集合。
enum QuotaColors {
    /// 正在刷新或尚未读取时的颜色。
    static let loading = NSColor(calibratedRed: 156 / 255, green: 168 / 255, blue: 184 / 255, alpha: 1)
    /// 剩余额度充足时的颜色。
    static let ready = NSColor(calibratedRed: 85 / 255, green: 230 / 255, blue: 165 / 255, alpha: 1)
    /// 剩余额度较低时的颜色。
    static let warning = NSColor(calibratedRed: 255 / 255, green: 209 / 255, blue: 102 / 255, alpha: 1)
    /// 剩余额度耗尽或读取失败时的颜色。
    static let danger = NSColor(calibratedRed: 255 / 255, green: 102 / 255, blue: 122 / 255, alpha: 1)
    /// 进度条未填充部分的颜色。
    static let inactive = NSColor(calibratedRed: 156 / 255, green: 168 / 255, blue: 184 / 255, alpha: 0.38)

    /// 根据剩余百分比选择状态颜色。
    ///
    /// - Parameter percent: 剩余额度百分比，通常为 0...100。
    /// - Returns: 0 返回危险色，1...9 返回警告色，10 及以上返回正常色。
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
