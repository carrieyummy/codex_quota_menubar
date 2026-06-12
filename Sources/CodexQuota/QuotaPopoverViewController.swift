import AppKit

@MainActor
protocol QuotaPopoverDelegate: AnyObject {
    func quotaPopoverDidRequestRefresh(_ controller: QuotaPopoverViewController)
    func quotaPopoverDidRequestQuit(_ controller: QuotaPopoverViewController)
    func quotaPopoverDidChangeLayout(_ controller: QuotaPopoverViewController)
}

final class QuotaPopoverViewController: NSViewController {
    weak var delegate: QuotaPopoverDelegate?

    private let sparkVisibilityKey = "showSparkQuota"
    private let backgroundView = ThemedBackgroundView()
    private let headerTitleLabel = NSTextField(labelWithString: "刷新时间")
    private let codexTitleLabel = NSTextField(labelWithString: "Codex 限额")
    private let sparkTitleLabel = NSTextField(labelWithString: "GPT-5.3-Codex-Spark 限额")
    private let codexFiveHourRow = QuotaRowView()
    private let codexWeeklyRow = QuotaRowView()
    private let sparkFiveHourRow = QuotaRowView()
    private let sparkWeeklyRow = QuotaRowView()
    private let statusLabel = NSTextField(labelWithString: "正在读取...")
    private let refreshButton = NSButton()
    private let quitButton = NSButton()
    private let sparkToggleButton = NSButton()
    private let themeToggleButton = NSButton()
    private let sparkSection = NSStackView()
    private var sparkAvailable = false
    private var theme = QuotaTheme.load()

    private var showSpark: Bool {
        get {
            UserDefaults.standard.object(forKey: sparkVisibilityKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: sparkVisibilityKey)
        }
    }

    var preferredPopoverSize: NSSize {
        NSSize(width: 306, height: isSparkVisible ? 178 : 116)
    }

    var showsSparkQuota: Bool {
        isSparkVisible
    }

    var backgroundOpacity: Double {
        theme.opacity
    }

    private var isSparkVisible: Bool {
        sparkAvailable && showSpark
    }

    override func loadView() {
        backgroundView.frame = NSRect(origin: .zero, size: preferredPopoverSize)
        view = backgroundView
        setup()
    }

    func update(snapshot: QuotaSnapshot) {
        codexFiveHourRow.update(with: snapshot.codex.fiveHour)
        codexWeeklyRow.update(with: snapshot.codex.weekly)

        sparkAvailable = snapshot.spark != nil
        if let spark = snapshot.spark {
            sparkFiveHourRow.update(with: spark.fiveHour)
            sparkWeeklyRow.update(with: spark.weekly)
        }

        refreshButton.isEnabled = true
        statusLabel.textColor = theme.mutedTextColor
        statusLabel.stringValue = formatFetchedAt(snapshot.fetchedAt)
        applySparkVisibility()
    }

    func setRefreshing(_ refreshing: Bool) {
        refreshButton.isEnabled = !refreshing
        if refreshing {
            statusLabel.textColor = theme.mutedTextColor
            statusLabel.stringValue = "刷新中"
        }
    }

    func showError(_ message: String) {
        refreshButton.isEnabled = true
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
    }

    private func setup() {
        headerTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        headerTitleLabel.alignment = .left

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.lineBreakMode = .byTruncatingTail

        configureIconButton(
            themeToggleButton,
            symbolName: "paintpalette",
            tooltip: "字体颜色",
            action: #selector(openTextColorPanel)
        )
        configureIconButton(
            sparkToggleButton,
            symbolName: "eye",
            tooltip: "显示/隐藏 Spark 限额",
            action: #selector(toggleSparkTapped)
        )
        configureIconButton(
            refreshButton,
            symbolName: "arrow.clockwise",
            tooltip: "刷新",
            action: #selector(refreshTapped)
        )
        configureIconButton(
            quitButton,
            symbolName: "xmark.circle",
            tooltip: "退出",
            action: #selector(quitTapped)
        )

        let header = NSStackView(views: [headerTitleLabel, statusLabel, NSView(), themeToggleButton, sparkToggleButton, refreshButton, quitButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6

        let codexSection = makeSection(titleLabel: codexTitleLabel, rows: [codexFiveHourRow, codexWeeklyRow])
        let sparkRows = NSStackView(views: [sparkFiveHourRow, sparkWeeklyRow])
        sparkRows.orientation = .vertical
        sparkRows.alignment = .leading
        sparkRows.spacing = 7
        sparkSection.setViews([sparkTitleLabel, sparkRows], in: .top)
        sparkSection.orientation = .vertical
        sparkSection.alignment = .leading
        sparkSection.spacing = 5
        configureSectionTitle(sparkTitleLabel)

        let stack = NSStackView(views: [header, codexSection, sparkSection])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -10),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        applyTheme()
        applySparkVisibility()
    }

    private func makeSection(titleLabel: NSTextField, rows: [NSView]) -> NSStackView {
        configureSectionTitle(titleLabel)
        let rowStack = NSStackView(views: rows)
        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = 7

        let section = NSStackView(views: [titleLabel, rowStack])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 5
        return section
    }

    private func configureSectionTitle(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .labelColor
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, tooltip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.bezelStyle = .rounded
        button.isBordered = false
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func applyTheme() {
        backgroundView.backgroundColor = theme.backgroundColor
        headerTitleLabel.textColor = theme.primaryTextColor
        statusLabel.textColor = theme.mutedTextColor
        codexTitleLabel.textColor = theme.primaryTextColor
        sparkTitleLabel.textColor = theme.primaryTextColor
        codexFiveHourRow.applyTheme(theme)
        codexWeeklyRow.applyTheme(theme)
        sparkFiveHourRow.applyTheme(theme)
        sparkWeeklyRow.applyTheme(theme)
        themeToggleButton.contentTintColor = theme.primaryTextColor
        sparkToggleButton.contentTintColor = theme.primaryTextColor
        refreshButton.contentTintColor = theme.primaryTextColor
        quitButton.contentTintColor = theme.primaryTextColor
    }

    private func applySparkVisibility() {
        sparkSection.isHidden = !isSparkVisible
        sparkToggleButton.isHidden = !sparkAvailable
        sparkToggleButton.image = NSImage(
            systemSymbolName: showSpark ? "eye" : "eye.slash",
            accessibilityDescription: "显示/隐藏 Spark 限额"
        )
        preferredContentSize = preferredPopoverSize
        delegate?.quotaPopoverDidChangeLayout(self)
    }

    @objc private func toggleSparkTapped() {
        showSpark.toggle()
        applySparkVisibility()
    }

    @objc private func openTextColorPanel() {
        let colorPanel = NSColorPanel.shared
        colorPanel.showsAlpha = false
        colorPanel.color = theme.textColor
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(textColorPanelChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        colorPanel.makeKeyAndOrderFront(nil)
        positionColorPanel(colorPanel)
    }

    @objc private func textColorPanelChanged(_ sender: NSColorPanel) {
        theme.textColor = sender.color
        theme.save()
        applyTheme()
    }

    private func positionColorPanel(_ colorPanel: NSColorPanel) {
        guard let quotaWindow = view.window else {
            return
        }

        let gap: CGFloat = 8
        let quotaFrame = quotaWindow.frame
        let panelSize = colorPanel.frame.size
        let visibleFrame = quotaWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let rightX = quotaFrame.maxX + gap
        let leftX = quotaFrame.minX - panelSize.width - gap
        let sideY = min(max(quotaFrame.maxY - panelSize.height, visibleFrame.minY), visibleFrame.maxY - panelSize.height)

        let origin: NSPoint
        if rightX + panelSize.width <= visibleFrame.maxX {
            origin = NSPoint(x: rightX, y: sideY)
        } else if leftX >= visibleFrame.minX {
            origin = NSPoint(x: leftX, y: sideY)
        } else {
            let x = min(max(quotaFrame.minX, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
            let belowY = quotaFrame.minY - panelSize.height - gap
            let aboveY = quotaFrame.maxY + gap

            if belowY >= visibleFrame.minY {
                origin = NSPoint(x: x, y: belowY)
            } else if aboveY + panelSize.height <= visibleFrame.maxY {
                origin = NSPoint(x: x, y: aboveY)
            } else {
                origin = NSPoint(
                    x: min(max(rightX, visibleFrame.minX), visibleFrame.maxX - panelSize.width),
                    y: sideY
                )
            }
        }
        colorPanel.setFrameOrigin(origin)
    }

    @objc private func refreshTapped() {
        delegate?.quotaPopoverDidRequestRefresh(self)
    }

    @objc private func quitTapped() {
        delegate?.quotaPopoverDidRequestQuit(self)
    }

    private func formatFetchedAt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
