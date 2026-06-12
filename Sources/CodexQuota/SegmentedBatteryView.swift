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
        NSSize(width: 160, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let gap: CGFloat = 2
        let segmentWidth = max(1, (bounds.width - gap * CGFloat(segmentCount - 1)) / CGFloat(segmentCount))
        let filledCount = Int(ceil(CGFloat(max(0, min(100, percent))) / 100 * CGFloat(segmentCount)))

        for index in 0..<segmentCount {
            let x = bounds.minX + CGFloat(index) * (segmentWidth + gap)
            let verticalInset: CGFloat = bounds.height < 12 ? 1 : 2
            let rect = NSRect(x: x, y: bounds.minY, width: segmentWidth, height: bounds.height)
                .insetBy(dx: 0.5, dy: verticalInset)
            let color = index < filledCount ? QuotaColors.color(forRemainingPercent: percent) : QuotaColors.inactive
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }
}
