import AppKit

/// 额度弹窗向宿主应用代理发送的用户操作事件。
@MainActor
protocol QuotaPopoverDelegate: AnyObject {
    /// 请求重新读取额度。
    ///
    /// - Parameter controller: 发起请求的弹窗控制器。
    func quotaPopoverDidRequestRefresh(_ controller: QuotaPopoverViewController)
    /// 请求退出应用。
    ///
    /// - Parameter controller: 发起请求的弹窗控制器。
    func quotaPopoverDidRequestQuit(_ controller: QuotaPopoverViewController)
    /// 通知宿主弹窗内容高度或显示状态已改变。
    ///
    /// - Parameter controller: 布局发生变化的弹窗控制器。
    func quotaPopoverDidChangeLayout(_ controller: QuotaPopoverViewController)
}

/// 显示 Codex 额度详情、刷新状态、Spark 可见性和外观设置的弹窗控制器。
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

    /// 用户持久化的 Spark 额度显示开关。
    private var showSpark: Bool {
        get {
            UserDefaults.standard.object(forKey: sparkVisibilityKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: sparkVisibilityKey)
        }
    }

    /// 当前内容对应的主弹窗推荐尺寸。
    ///
    /// - Returns: Spark 可见时使用较高尺寸，否则使用紧凑尺寸。
    var preferredPopoverSize: NSSize {
        NSSize(width: 306, height: isSparkVisible ? 178 : 116)
    }

    /// 当前状态栏标题是否应显示 Spark 额度。
    ///
    /// - Returns: Spark 数据可用且用户开启显示时为 `true`。
    var showsSparkQuota: Bool {
        isSparkVisible
    }

    /// 当前弹窗背景不透明度百分比。
    ///
    /// - Returns: 0...95 范围内的透明度设置。
    var backgroundOpacity: Double {
        theme.opacity
    }

    /// 主弹窗以外仍属于应用内部的辅助窗口。
    ///
    /// - Returns: 当前可用的辅助窗口列表，用于外部点击判断。
    var auxiliaryWindows: [NSWindow] {
        [opacityPopover.contentViewController?.view.window].compactMap { $0 }
    }

    /// 外部状态变化时是否应保留主弹窗。
    ///
    /// - Returns: 正在打开颜色面板、颜色面板可见或透明度弹窗可见时返回 `true`。
    var shouldKeepMainPopoverForAuxiliaryWindow: Bool {
        isOpeningColorPanel || NSColorPanel.shared.isVisible || opacityPopover.isShown
    }

    /// Spark 区块是否实际可见。
    private var isSparkVisible: Bool {
        sparkAvailable && showSpark
    }

    /// 创建控制器根视图并构建弹窗内容。
    override func loadView() {
        backgroundView.frame = NSRect(origin: .zero, size: preferredPopoverSize)
        view = backgroundView
        setup()
    }

    /// 用最新额度快照更新所有额度行和刷新状态。
    ///
    /// - Parameter snapshot: app-server 返回并解析后的额度快照。
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

    /// 设置刷新中的 UI 状态。
    ///
    /// - Parameter refreshing: 为 `true` 时禁用刷新按钮并显示“刷新中”。
    func setRefreshing(_ refreshing: Bool) {
        refreshButton.isEnabled = !refreshing
        if refreshing {
            statusLabel.textColor = theme.mutedTextColor
            statusLabel.stringValue = "刷新中"
        }
    }

    /// 展示读取失败消息并恢复刷新按钮。
    ///
    /// - Parameter message: 面向用户展示的错误文本。
    func showError(_ message: String) {
        refreshButton.isEnabled = true
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
    }

    /// 构建主弹窗的控件树、约束、辅助弹窗和初始主题。
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

    /// 创建包含标题和多行额度信息的垂直区块。
    ///
    /// - Parameters:
    ///   - titleLabel: 区块标题标签。
    ///   - rows: 额度行视图列表。
    /// - Returns: 已配置布局和标题样式的区块视图。
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

    /// 配置区块标题标签的字体、颜色和截断方式。
    ///
    /// - Parameter label: 要配置的标题标签。
    private func configureSectionTitle(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .labelColor
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
    }

    /// 配置统一风格的图标按钮。
    ///
    /// - Parameters:
    ///   - button: 要配置的按钮实例。
    ///   - symbolName: SF Symbols 名称。
    ///   - tooltip: 鼠标悬停提示和无障碍描述。
    ///   - action: 点击按钮时发送给控制器的 selector。
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

    /// 构建透明度调整辅助弹窗。
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

    /// 将当前主题应用到主弹窗、辅助弹窗和全部子控件。
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

    /// 将当前主题应用到透明度辅助弹窗内的标签。
    private func applyOpacityPopoverTheme() {
        guard let stack = opacityPopover.contentViewController?.view.subviews.first as? NSStackView else {
            return
        }

        for case let label as NSTextField in stack.arrangedSubviews {
            label.textColor = label === opacityValueLabel ? theme.mutedTextColor : theme.primaryTextColor
        }
        updateOpacityControls()
    }

    /// 根据 Spark 数据可用性和用户开关更新区块显示、按钮图标和弹窗尺寸。
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

    /// 切换 Spark 额度区块显示状态。
    @objc private func toggleSparkTapped() {
        showSpark.toggle()
        applySparkVisibility()
    }

    /// 打开或关闭透明度调整弹窗。
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

    /// 响应透明度滑块变化并立即保存主题。
    @objc private func opacitySliderChanged() {
        theme.opacity = opacitySlider.doubleValue
        theme.save()
        applyTheme()
        delegate?.quotaPopoverDidChangeLayout(self)
    }

    /// 用当前主题值刷新透明度滑块和百分比文本。
    private func updateOpacityControls() {
        opacitySlider.doubleValue = theme.opacity
        opacityValueLabel.stringValue = "\(Int(round(theme.opacity)))%"
    }

    /// 将透明度辅助弹窗窗口和祖先视图调整为透明背景。
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

    /// 清除视图背景并禁用视觉效果视图的活跃材质。
    ///
    /// - Parameter view: 需要透明化的视图；为 `nil` 时不处理。
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

    /// 处理透明度辅助弹窗关闭事件，保存最终滑块值并清理事件监听。
    ///
    /// - Parameter notification: `NSPopover` 关闭通知。
    func popoverDidClose(_ notification: Notification) {
        if notification.object as? NSPopover === opacityPopover {
            saveOpacityFromSlider()
            removeOpacityPopoverEventMonitors()
        }
    }

    /// 保存透明度滑块当前值并同步主题和布局。
    private func saveOpacityFromSlider() {
        theme.opacity = opacitySlider.doubleValue
        theme.save()
        updateOpacityControls()
        applyTheme()
        delegate?.quotaPopoverDidChangeLayout(self)
    }

    /// 安装透明度辅助弹窗的外部点击监听。
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

    /// 移除透明度辅助弹窗的外部点击监听。
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

    /// 根据鼠标事件判断是否需要关闭透明度辅助弹窗。
    ///
    /// - Parameter event: AppKit 鼠标事件，包含事件所在窗口。
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

    /// 判断屏幕坐标是否位于透明度辅助弹窗内。
    ///
    /// - Parameter point: 屏幕坐标点。
    /// - Returns: 点位于透明度弹窗内时返回 `true`。
    private func isPointInsideOpacityPopover(_ point: NSPoint) -> Bool {
        guard let window = opacityPopover.contentViewController?.view.window else {
            return false
        }
        return window.frame.contains(point)
    }

    /// 判断屏幕坐标是否位于透明度按钮内。
    ///
    /// - Parameter point: 屏幕坐标点。
    /// - Returns: 点位于透明度按钮范围内时返回 `true`。
    private func isPointInsideOpacityButton(_ point: NSPoint) -> Bool {
        guard let window = opacityToggleButton.window else {
            return false
        }

        let buttonRectInWindow = opacityToggleButton.convert(opacityToggleButton.bounds, to: nil)
        let buttonRect = window.convertToScreen(buttonRectInWindow)
        return buttonRect.contains(point)
    }

    /// 打开系统颜色面板并设置当前文字颜色。
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

    /// 响应系统颜色面板变化并保存文字颜色。
    ///
    /// - Parameter sender: 触发变化的系统颜色面板。
    @objc private func textColorPanelChanged(_ sender: NSColorPanel) {
        theme.textColor = sender.color
        theme.save()
        applyTheme()
    }

    /// 将颜色面板放置在主弹窗附近且尽量保持在可见屏幕区域内。
    ///
    /// - Parameter colorPanel: 需要定位的系统颜色面板。
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

    /// 将刷新按钮点击转发给代理。
    @objc private func refreshTapped() {
        delegate?.quotaPopoverDidRequestRefresh(self)
    }

    /// 将退出按钮点击转发给代理。
    @objc private func quitTapped() {
        delegate?.quotaPopoverDidRequestQuit(self)
    }

    /// 将快照读取时间格式化为弹窗状态文本。
    ///
    /// - Parameter date: 读取完成时间。
    /// - Returns: `HH:mm:ss` 格式的本地时间字符串。
    private func formatFetchedAt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
