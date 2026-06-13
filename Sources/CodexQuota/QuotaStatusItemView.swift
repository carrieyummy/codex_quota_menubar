import AppKit

/// 自绘菜单栏状态项视图。
///
/// 当前主流程使用系统 `NSStatusBarButton`，该视图保留为自绘状态栏方案。
final class QuotaStatusItemView: NSControl {
    /// 点击回调。
    ///
    /// 左键或右键按下时都会触发。
    var onClick: (() -> Void)?

    private var title = "Codex --"
    private var indicatorColor = QuotaColors.loading
    private let menuFont = NSFont.menuBarFont(ofSize: 0)

    /// 状态项的默认内容尺寸。
    ///
    /// - Returns: 基于文本宽度和系统菜单栏高度计算的尺寸。
    override var intrinsicContentSize: NSSize {
        NSSize(width: measuredWidth, height: NSStatusBar.system.thickness)
    }

    /// 建议的状态项宽度。
    ///
    /// - Returns: 基于当前标题测量得到的宽度。
    var preferredWidth: CGFloat {
        measuredWidth
    }

    /// 更新状态项标题和颜色。
    ///
    /// - Parameters:
    ///   - title: 状态栏显示文本。
    ///   - indicatorColor: 左侧圆点颜色。
    func update(title: String, indicatorColor: NSColor) {
        self.title = title
        self.indicatorColor = indicatorColor
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    /// 处理左键点击。
    ///
    /// - Parameter event: 鼠标按下事件；当前仅用于触发回调。
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    /// 处理右键点击。
    ///
    /// - Parameter event: 鼠标按下事件；当前仅用于触发回调。
    override func rightMouseDown(with event: NSEvent) {
        onClick?()
    }

    /// 绘制状态圆点和标题文本。
    ///
    /// - Parameter dirtyRect: 需要重绘的区域。
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

    /// 测量当前标题所需的状态项宽度。
    ///
    /// - Returns: 文本宽度加圆点和间距后的最小宽度。
    private var measuredWidth: CGFloat {
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: menuFont]).width)
        return max(30, textWidth + 18)
    }
}
