import AppKit

final class QuotaRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let barView = SegmentedBatteryView()
    private let valueLabel = NSTextField(labelWithString: "--")
    private let resetLabel = NSTextField(labelWithString: "--")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func update(with window: QuotaWindow) {
        titleLabel.stringValue = window.title
        barView.percent = window.remainingPercent
        valueLabel.stringValue = "\(window.remainingPercent)%"
        resetLabel.stringValue = formatReset(window.resetAt)
    }

    func applyTheme(_ theme: QuotaTheme) {
        titleLabel.textColor = theme.primaryTextColor
        valueLabel.textColor = theme.primaryTextColor
        resetLabel.textColor = theme.mutedTextColor
    }

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
