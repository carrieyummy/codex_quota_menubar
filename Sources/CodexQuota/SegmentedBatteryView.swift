import AppKit

/// 用细线渐变条展示剩余额度百分比的视图。
final class SegmentedBatteryView: NSView {
    /// 当前剩余百分比。
    ///
    /// 期望范围为 0...100；绘制时会再次夹紧到该范围。
    var percent: Int = 0 {
        didSet {
            needsDisplay = true
        }
    }

    /// 预留的分段数量配置。
    ///
    /// 当前绘制样式为连续细线渐变，保留该属性便于后续恢复分段样式。
    var segmentCount: Int = 20 {
        didSet {
            needsDisplay = true
        }
    }

    /// Auto Layout 未给定尺寸时的默认内容尺寸。
    ///
    /// - Returns: 适合弹窗额度行的宽高。
    override var intrinsicContentSize: NSSize {
        NSSize(width: 160, height: 12)
    }

    /// 绘制背景轨道和表示剩余额度的渐变填充。
    ///
    /// - Parameter dirtyRect: 需要重绘的区域。
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let lineHeight: CGFloat = 6
        let trackRect = NSRect(
            x: bounds.minX,
            y: bounds.midY - lineHeight / 2,
            width: bounds.width,
            height: lineHeight
        ).insetBy(dx: 1, dy: 0)
        let radius = lineHeight / 2

        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)
        QuotaColors.inactive.withAlphaComponent(0.32).setFill()
        trackPath.fill()

        let clampedPercent = CGFloat(max(0, min(100, percent))) / 100
        guard clampedPercent > 0 else {
            return
        }

        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: max(lineHeight, trackRect.width * clampedPercent),
            height: trackRect.height
        )
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        fillPath.addClip()

        let startColor = QuotaColors.color(forRemainingPercent: percent).blended(withFraction: 0.18, of: .white) ?? QuotaColors.ready
        let endColor = QuotaColors.color(forRemainingPercent: percent)
        let gradient = NSGradient(starting: startColor, ending: endColor)
        gradient?.draw(in: fillRect, angle: 0)

        NSGraphicsContext.restoreGraphicsState()
    }
}
