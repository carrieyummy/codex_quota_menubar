import AppKit

/// macOS 应用代理，负责菜单栏状态项、额度弹窗、刷新周期和外部事件关闭策略。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, QuotaPopoverDelegate {
    private let client = CodexAppServerClient()
    private let popover = NSPopover()
    private let popoverController = QuotaPopoverViewController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var refreshTimer: Timer?
    private var isRefreshing = false
    private var latestSnapshot: QuotaSnapshot?

    /// 应用启动完成后的初始化入口。
    ///
    /// - Parameter notification: AppKit 发送的启动完成通知。
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        configurePopoverCloseObservers()
        refresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// 应用退出前清理定时器、事件监听和通知观察者。
    ///
    /// - Parameter notification: AppKit 发送的退出通知。
    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        removePopoverEventMonitors()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// 响应弹窗中的手动刷新请求。
    ///
    /// - Parameter controller: 发起请求的额度弹窗控制器。
    func quotaPopoverDidRequestRefresh(_ controller: QuotaPopoverViewController) {
        refresh()
    }

    /// 响应弹窗中的退出请求。
    ///
    /// - Parameter controller: 发起请求的额度弹窗控制器。
    func quotaPopoverDidRequestQuit(_ controller: QuotaPopoverViewController) {
        NSApp.terminate(nil)
    }

    /// 响应弹窗内容高度变化并同步状态栏展示。
    ///
    /// - Parameter controller: 布局发生变化的额度弹窗控制器。
    func quotaPopoverDidChangeLayout(_ controller: QuotaPopoverViewController) {
        popover.contentSize = controller.preferredPopoverSize
        applyPopoverChromeAppearance()

        if let snapshot = latestSnapshot {
            updateStatusItem(snapshot: snapshot)
        }
    }

    /// 弹窗显示后应用透明外观并安装外部点击监听。
    ///
    /// - Parameter notification: `NSPopover` 显示通知。
    func popoverDidShow(_ notification: Notification) {
        applyPopoverChromeAppearance()
        installPopoverEventMonitors()
    }

    /// 弹窗关闭后移除外部点击监听。
    ///
    /// - Parameter notification: `NSPopover` 关闭通知。
    func popoverDidClose(_ notification: Notification) {
        removePopoverEventMonitors()
    }

    /// 切换主额度弹窗显示状态。
    ///
    /// - Parameter sender: 触发点击的 AppKit 对象；未使用。
    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    /// 配置菜单栏状态项的初始标题、图标和点击行为。
    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.title = "Codex --"
        button.image = statusBarImage(color: QuotaColors.loading)
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItemLength(for: button.title)
    }

    /// 配置主额度弹窗及其内容控制器。
    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.animates = false
        popover.contentSize = popoverController.preferredPopoverSize
        popover.contentViewController = popoverController
        popoverController.delegate = self
    }

    /// 注册会导致主弹窗关闭的系统状态变化通知。
    private func configurePopoverCloseObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closePopoverForExternalStateChange),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closePopoverForExternalStateChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(closePopoverForExternalStateChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(closePopoverForExternalStateChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    /// 在应用失焦、屏幕变化、活动应用或空间切换时关闭主弹窗。
    ///
    /// - Parameter notification: 触发关闭判断的系统通知。
    @objc private func closePopoverForExternalStateChange(_ notification: Notification) {
        guard popover.isShown else {
            return
        }

        if popoverController.shouldKeepMainPopoverForAuxiliaryWindow {
            return
        }

        popover.performClose(nil)
    }

    /// 在菜单栏按钮下方显示主额度弹窗。
    private func showPopover() {
        guard let button = statusItem.button else {
            return
        }

        popover.contentSize = popoverController.preferredPopoverSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.async { [weak self] in
            self?.applyPopoverChromeAppearance()
        }
    }

    /// 将主弹窗窗口和其祖先视图调整为透明背景。
    private func applyPopoverChromeAppearance() {
        guard let window = popoverController.view.window else {
            return
        }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = popoverController.backgroundOpacity > 0

        makeTransparent(window.contentView)

        var ancestor = popoverController.view.superview
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

    /// 安装本地和全局鼠标事件监听，用于点击外部时关闭主弹窗。
    private func installPopoverEventMonitors() {
        removePopoverEventMonitors()

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.closePopoverIfClickIsOutside(event)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.closePopoverIfClickIsOutside(event)
            }
        }
    }

    /// 移除主弹窗相关的鼠标事件监听。
    private func removePopoverEventMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    /// 根据鼠标事件判断是否需要关闭主弹窗。
    ///
    /// - Parameter event: AppKit 鼠标事件，包含事件所在窗口。
    private func closePopoverIfClickIsOutside(_ event: NSEvent) {
        guard popover.isShown else {
            removePopoverEventMonitors()
            return
        }

        if isInternalWindow(event.window) {
            return
        }

        let mousePoint = NSEvent.mouseLocation
        if isPointInsideStatusButton(mousePoint) || isPointInsideInternalWindow(mousePoint) {
            return
        }

        popover.performClose(nil)
    }

    /// 判断窗口是否属于主弹窗或其辅助窗口。
    ///
    /// - Parameter window: 待判断窗口；可为 `nil`。
    /// - Returns: 属于内部窗口时返回 `true`。
    private func isInternalWindow(_ window: NSWindow?) -> Bool {
        guard let window else {
            return false
        }

        if window === popoverController.view.window || window === NSColorPanel.shared {
            return true
        }

        return popoverController.auxiliaryWindows.contains { $0 === window }
    }

    /// 判断屏幕坐标是否位于主弹窗、颜色面板或辅助弹窗内。
    ///
    /// - Parameter point: 屏幕坐标点。
    /// - Returns: 点位于内部窗口时返回 `true`。
    private func isPointInsideInternalWindow(_ point: NSPoint) -> Bool {
        if let window = popoverController.view.window, window.frame.contains(point) {
            return true
        }

        if NSColorPanel.shared.isVisible && NSColorPanel.shared.frame.contains(point) {
            return true
        }

        return popoverController.auxiliaryWindows.contains { $0.frame.contains(point) }
    }

    /// 判断屏幕坐标是否位于菜单栏状态按钮内。
    ///
    /// - Parameter point: 屏幕坐标点。
    /// - Returns: 点位于状态按钮范围内时返回 `true`。
    private func isPointInsideStatusButton(_ point: NSPoint) -> Bool {
        guard
            let button = statusItem.button,
            let buttonWindow = button.window
        else {
            return false
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRect = buttonWindow.convertToScreen(buttonRectInWindow)
        return buttonRect.contains(point)
    }

    /// 生成状态栏圆点图标。
    ///
    /// - Parameter color: 圆点主色，表示加载、正常、警告或错误状态。
    /// - Returns: 可直接赋给 `NSStatusBarButton.image` 的非模板图片。
    private func statusBarImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()

        let circleRect = NSRect(x: 2, y: 2, width: 10, height: 10)
        color.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: circleRect.insetBy(dx: -1, dy: -1)).fill()

        color.setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        color.blended(withFraction: 0.38, of: .white)?.setFill()
        NSBezierPath(ovalIn: NSRect(x: 4, y: 8, width: 3, height: 2)).fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// 刷新额度数据，并在成功或失败时同步弹窗和状态栏。
    private func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        let currentTitle = latestSnapshot.map { statusTitle(for: $0) } ?? "Codex --"
        updateStatusItemDisplay(title: currentTitle, color: QuotaColors.loading)
        popoverController.setRefreshing(true)

        client.readRateLimits { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false

                switch result {
                case .success(let snapshot):
                    self.latestSnapshot = snapshot
                    self.apply(snapshot: snapshot)
                case .failure(let error):
                    self.popoverController.showError(error.localizedDescription)
                    if self.latestSnapshot == nil {
                        self.updateStatusItemDisplay(title: "Codex !", color: QuotaColors.danger)
                    } else if let snapshot = self.latestSnapshot {
                        self.updateStatusItemDisplay(title: self.statusTitle(for: snapshot), color: QuotaColors.danger)
                    }
                }
            }
        }
    }

    /// 将新快照应用到主弹窗和状态栏。
    ///
    /// - Parameter snapshot: 最新读取到的额度快照。
    private func apply(snapshot: QuotaSnapshot) {
        popoverController.update(snapshot: snapshot)
        updateStatusItem(snapshot: snapshot)
    }

    /// 根据快照中的最紧张额度更新状态栏颜色和标题。
    ///
    /// - Parameter snapshot: 用于计算状态栏显示的额度快照。
    private func updateStatusItem(snapshot: QuotaSnapshot) {
        let codexWindow = snapshot.codex.fiveHour
        let indicatorPercent = min(codexWindow.remainingPercent, snapshot.codex.weekly.remainingPercent)
        updateStatusItemDisplay(
            title: statusTitle(for: snapshot),
            color: QuotaColors.color(forRemainingPercent: indicatorPercent)
        )
    }

    /// 生成状态栏完整标题。
    ///
    /// - Parameter snapshot: 当前额度快照。
    /// - Returns: Codex 主额度标题，并在启用时追加 Spark 标题。
    private func statusTitle(for snapshot: QuotaSnapshot) -> String {
        var title = statusBarPart(prefix: "Codex", window: snapshot.codex.fiveHour)

        if popoverController.showsSparkQuota, let sparkWindow = snapshot.spark?.fiveHour {
            title += " | " + statusBarPart(prefix: "5.3", window: sparkWindow)
        }

        return title
    }

    /// 设置状态栏标题、图标颜色，并强制刷新布局。
    ///
    /// - Parameters:
    ///   - title: 状态栏显示文本。
    ///   - color: 状态圆点颜色。
    private func updateStatusItemDisplay(title: String, color: NSColor) {
        guard let button = statusItem.button else {
            return
        }

        button.title = title
        button.image = statusBarImage(color: color)
        updateStatusItemLength(for: title)
        flushStatusItemLayout()
    }

    /// 根据标题内容调整状态项宽度，避免菜单栏文本被截断。
    ///
    /// - Parameter title: 即将显示的状态栏标题。
    private func updateStatusItemLength(for title: String) {
        guard let button = statusItem.button else {
            statusItem.length = NSStatusItem.variableLength
            return
        }

        let font = button.font ?? NSFont.menuBarFont(ofSize: 0)
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        let imageWidth: CGFloat = button.image == nil ? 0 : 16
        let horizontalPadding: CGFloat = 10
        statusItem.length = max(34, textWidth + imageWidth + horizontalPadding)
    }

    /// 立即刷新状态栏按钮布局和窗口显示。
    private func flushStatusItemLayout() {
        guard let button = statusItem.button else {
            return
        }

        button.needsLayout = true
        button.layoutSubtreeIfNeeded()
        button.window?.displayIfNeeded()
    }

    /// 生成单个额度窗口的状态栏片段。
    ///
    /// - Parameters:
    ///   - prefix: 模型短名称，例如 `Codex` 或 `5.3`。
    ///   - window: 要显示的额度窗口。
    /// - Returns: 包含剩余百分比和重置时间的短文本。
    private func statusBarPart(prefix: String, window: QuotaWindow) -> String {
        "\(prefix) \(window.remainingPercent)% \(formatStatusBarReset(window.resetAt))"
    }

    /// 将重置时间格式化为状态栏紧凑文本。
    ///
    /// - Parameter date: 重置时间；为 `nil` 时显示占位符。
    /// - Returns: 当天时间显示为 `HH:mm`，非当天显示为 `M/d HH:mm`。
    private func formatStatusBarReset(_ date: Date?) -> String {
        guard let date else {
            return "--"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
        return formatter.string(from: date)
    }
}
