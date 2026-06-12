import AppKit

final class QuotaStatusItemView: NSControl {
    var onClick: (() -> Void)?

    private var title = "Codex --"
    private var indicatorColor = QuotaColors.loading
    private let menuFont = NSFont.menuBarFont(ofSize: 0)

    override var intrinsicContentSize: NSSize {
        NSSize(width: measuredWidth, height: NSStatusBar.system.thickness)
    }

    var preferredWidth: CGFloat {
        measuredWidth
    }

    func update(title: String, indicatorColor: NSColor) {
        self.title = title
        self.indicatorColor = indicatorColor
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let dotDiameter: CGFloat = 10
        let dotRect = NSRect(
            x: 2,
            y: round((bounds.height - dotDiameter) / 2),
            width: dotDiameter,
            height: dotDiameter
        )

        indicatorColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: dotRect.insetBy(dx: -1, dy: -1)).fill()

        indicatorColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        indicatorColor.blended(withFraction: 0.38, of: .white)?.setFill()
        NSBezierPath(ovalIn: NSRect(x: dotRect.minX + 2, y: dotRect.minY + 6, width: 3, height: 2)).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: menuFont,
            .foregroundColor: NSColor.labelColor
        ]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let textOrigin = NSPoint(
            x: dotRect.maxX + 4,
            y: round((bounds.height - textSize.height) / 2)
        )
        (title as NSString).draw(at: textOrigin, withAttributes: attributes)
    }

    private var measuredWidth: CGFloat {
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: menuFont]).width)
        return max(30, textWidth + 18)
    }
}
