import AppKit

/// 弹窗内展示单个额度窗口的行视图。
final class QuotaRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let barView = SegmentedBatteryView()
    private let valueLabel = NSTextField(labelWithString: "--")
    private let resetLabel = NSTextField(labelWithString: "--")

    /// 使用代码创建额度行视图。
    ///
    /// - Parameter frameRect: 初始视图 frame。
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    /// 使用 Interface Builder 解码创建额度行视图。
    ///
    /// - Parameter coder: 归档解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// 用额度窗口更新标题、进度条、剩余百分比和重置时间。
    ///
    /// - Parameter window: 要展示的额度窗口数据。
    func update(with window: QuotaWindow) {
        titleLabel.stringValue = window.title
        barView.percent = window.remainingPercent
        valueLabel.stringValue = "\(window.remainingPercent)%"
        resetLabel.stringValue = formatReset(window.resetAt)
    }

    /// 应用弹窗主题颜色。
    ///
    /// - Parameter theme: 当前用户主题，包含文字颜色和透明度。
    func applyTheme(_ theme: QuotaTheme) {
        titleLabel.textColor = theme.primaryTextColor
        valueLabel.textColor = theme.primaryTextColor
        resetLabel.textColor = theme.mutedTextColor
    }

    /// 构建行内控件、字体、间距和固定宽度约束。
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .left

        resetLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        resetLabel.textColor = .secondaryLabelColor
        resetLabel.alignment = .left

        let rightStack = NSStackView(views: [valueLabel, resetLabel])
        rightStack.orientation = .horizontal
        rightStack.spacing = 6
        rightStack.alignment = .centerY

        let stack = NSStackView(views: [titleLabel, barView, rightStack])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(equalToConstant: 42),
            barView.widthAnchor.constraint(equalToConstant: 108),
            barView.heightAnchor.constraint(equalToConstant: 12),
            valueLabel.widthAnchor.constraint(equalToConstant: 42),
            resetLabel.widthAnchor.constraint(equalToConstant: 80),
            rightStack.widthAnchor.constraint(equalToConstant: 128),
            stack.widthAnchor.constraint(equalToConstant: 286),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// 将重置时间格式化为行内显示文本。
    ///
    /// - Parameter date: 重置时间；为 `nil` 时显示“无重置”。
    /// - Returns: 当天时间显示为 `HH:mm`，非当天显示为 `M/d HH:mm`。
    private func formatReset(_ date: Date?) -> String {
        guard let date else {
            return "无重置"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
        return formatter.string(from: date)
    }
}
