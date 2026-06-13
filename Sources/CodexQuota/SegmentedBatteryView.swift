import AppKit

final class SegmentedBatteryView: NSView {
    var percent: Int = 0 {
        didSet {
            needsDisplay = true
        }
    }

    var segmentCount: Int = 20 {
        didSet {
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 160, height: 12)
    }

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
