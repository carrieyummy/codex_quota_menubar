import AppKit

@MainActor
protocol QuotaPopoverDelegate: AnyObject {
    func quotaPopoverDidRequestRefresh(_ controller: QuotaPopoverViewController)
    func quotaPopoverDidRequestQuit(_ controller: QuotaPopoverViewController)
    func quotaPopoverDidChangeLayout(_ controller: QuotaPopoverViewController)
}

final class QuotaPopoverViewController: NSViewController, NSPopoverDelegate {
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
    private let opacityToggleButton = NSButton()
    private let opacityPopover = NSPopover()
    private let opacitySlider = NSSlider()
    private let opacityValueLabel = NSTextField(labelWithString: "")
    private let sparkSection = NSStackView()
    private var opacityLocalMouseMonitor: Any?
    private var opacityGlobalMouseMonitor: Any?
    private var isOpeningColorPanel = false
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

    var auxiliaryWindows: [NSWindow] {
        [opacityPopover.contentViewController?.view.window].compactMap { $0 }
    }

    var shouldKeepMainPopoverForAuxiliaryWindow: Bool {
        isOpeningColorPanel || NSColorPanel.shared.isVisible || opacityPopover.isShown
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
        headerTitleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        headerTitleLabel.alignment = .left

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        statusLabel.lineBreakMode = .byTruncatingTail

        configureIconButton(
            themeToggleButton,
            symbolName: "paintpalette",
            tooltip: "字体颜色",
            action: #selector(openTextColorPanel)
        )
        configureIconButton(
            opacityToggleButton,
            symbolName: "circle.lefthalf.filled",
            tooltip: "窗口透明度",
            action: #selector(toggleOpacityPopover)
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

        let header = NSStackView(views: [headerTitleLabel, statusLabel, NSView(), themeToggleButton, opacityToggleButton, sparkToggleButton, refreshButton, quitButton])
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

        configureOpacityPopover()
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

    private func configureOpacityPopover() {
        let contentView = ThemedBackgroundView(frame: NSRect(x: 0, y: 0, width: 210, height: 54))
        contentView.backgroundColor = theme.backgroundColor

        let titleLabel = NSTextField(labelWithString: "透明度")
        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.alignment = .left

        opacitySlider.minValue = QuotaTheme.minOpacity
        opacitySlider.maxValue = QuotaTheme.maxOpacity
        opacitySlider.doubleValue = theme.opacity
        opacitySlider.isContinuous = true
        opacitySlider.target = self
        opacitySlider.action = #selector(opacitySliderChanged)
        opacitySlider.translatesAutoresizingMaskIntoConstraints = false

        opacityValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        opacityValueLabel.alignment = .right

        let stack = NSStackView(views: [titleLabel, opacitySlider, opacityValueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            opacitySlider.widthAnchor.constraint(equalToConstant: 104),
            opacityValueLabel.widthAnchor.constraint(equalToConstant: 34),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        let viewController = NSViewController()
        viewController.view = contentView

        opacityPopover.behavior = .applicationDefined
        opacityPopover.delegate = self
        opacityPopover.animates = false
        opacityPopover.contentSize = contentView.frame.size
        opacityPopover.contentViewController = viewController

        updateOpacityControls()
    }

    private func applyTheme() {
        backgroundView.backgroundColor = theme.backgroundColor
        if let opacityBackgroundView = opacityPopover.contentViewController?.view as? ThemedBackgroundView {
            opacityBackgroundView.backgroundColor = theme.backgroundColor
        }
        headerTitleLabel.textColor = theme.primaryTextColor
        statusLabel.textColor = theme.mutedTextColor
        codexTitleLabel.textColor = theme.primaryTextColor
        sparkTitleLabel.textColor = theme.primaryTextColor
        codexFiveHourRow.applyTheme(theme)
        codexWeeklyRow.applyTheme(theme)
        sparkFiveHourRow.applyTheme(theme)
        sparkWeeklyRow.applyTheme(theme)
        themeToggleButton.contentTintColor = theme.primaryTextColor
        opacityToggleButton.contentTintColor = theme.primaryTextColor
        sparkToggleButton.contentTintColor = theme.primaryTextColor
        refreshButton.contentTintColor = theme.primaryTextColor
        quitButton.contentTintColor = theme.primaryTextColor
        applyOpacityPopoverTheme()
    }

    private func applyOpacityPopoverTheme() {
        guard let stack = opacityPopover.contentViewController?.view.subviews.first as? NSStackView else {
            return
        }

        for case let label as NSTextField in stack.arrangedSubviews {
            label.textColor = label === opacityValueLabel ? theme.mutedTextColor : theme.primaryTextColor
        }
        updateOpacityControls()
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

    @objc private func toggleOpacityPopover() {
        if opacityPopover.isShown {
            opacityPopover.performClose(nil)
            return
        }

        updateOpacityControls()
        opacityPopover.show(relativeTo: opacityToggleButton.bounds, of: opacityToggleButton, preferredEdge: .maxY)
        installOpacityPopoverEventMonitors()
        DispatchQueue.main.async { [weak self] in
            self?.applyAuxiliaryPopoverChromeAppearance()
        }
    }

    @objc private func opacitySliderChanged() {
        theme.opacity = opacitySlider.doubleValue
        theme.save()
        applyTheme()
        delegate?.quotaPopoverDidChangeLayout(self)
    }

    private func updateOpacityControls() {
        opacitySlider.doubleValue = theme.opacity
        opacityValueLabel.stringValue = "\(Int(round(theme.opacity)))%"
    }

    private func applyAuxiliaryPopoverChromeAppearance() {
        guard let window = opacityPopover.contentViewController?.view.window else {
            return
        }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = theme.opacity > 0

        makeTransparent(window.contentView)

        var ancestor = opacityPopover.contentViewController?.view.superview
        while let view = ancestor {
            makeTransparent(view)
            ancestor = view.superview
        }
    }

    private func makeTransparent(_ view: NSView?) {
        guard let view else {
            return
        }

        if let visualEffectView = view as? NSVisualEffectView {
            visualEffectView.state = .inactive
            visualEffectView.material = .contentBackground
        }

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
    }

    func popoverDidClose(_ notification: Notification) {
        if notification.object as? NSPopover === opacityPopover {
            saveOpacityFromSlider()
            removeOpacityPopoverEventMonitors()
        }
    }

    private func saveOpacityFromSlider() {
        theme.opacity = opacitySlider.doubleValue
        theme.save()
        updateOpacityControls()
        applyTheme()
        delegate?.quotaPopoverDidChangeLayout(self)
    }

    private func installOpacityPopoverEventMonitors() {
        removeOpacityPopoverEventMonitors()

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        opacityLocalMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.closeOpacityPopoverIfClickIsOutside(event)
            return event
        }
        opacityGlobalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.closeOpacityPopoverIfClickIsOutside(event)
            }
        }
    }

    private func removeOpacityPopoverEventMonitors() {
        if let opacityLocalMouseMonitor {
            NSEvent.removeMonitor(opacityLocalMouseMonitor)
            self.opacityLocalMouseMonitor = nil
        }

        if let opacityGlobalMouseMonitor {
            NSEvent.removeMonitor(opacityGlobalMouseMonitor)
            self.opacityGlobalMouseMonitor = nil
        }
    }

    private func closeOpacityPopoverIfClickIsOutside(_ event: NSEvent) {
        guard opacityPopover.isShown else {
            removeOpacityPopoverEventMonitors()
            return
        }

        if event.window === opacityPopover.contentViewController?.view.window {
            return
        }

        let mousePoint = NSEvent.mouseLocation
        if isPointInsideOpacityPopover(mousePoint) || isPointInsideOpacityButton(mousePoint) {
            return
        }

        opacityPopover.performClose(nil)
    }

    private func isPointInsideOpacityPopover(_ point: NSPoint) -> Bool {
        guard let window = opacityPopover.contentViewController?.view.window else {
            return false
        }
        return window.frame.contains(point)
    }

    private func isPointInsideOpacityButton(_ point: NSPoint) -> Bool {
        guard let window = opacityToggleButton.window else {
            return false
        }

        let buttonRectInWindow = opacityToggleButton.convert(opacityToggleButton.bounds, to: nil)
        let buttonRect = window.convertToScreen(buttonRectInWindow)
        return buttonRect.contains(point)
    }

    @objc private func openTextColorPanel() {
        isOpeningColorPanel = true
        let colorPanel = NSColorPanel.shared
        colorPanel.showsAlpha = false
        colorPanel.color = theme.textColor
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(textColorPanelChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        colorPanel.makeKeyAndOrderFront(nil)
        positionColorPanel(colorPanel)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isOpeningColorPanel = false
        }
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
