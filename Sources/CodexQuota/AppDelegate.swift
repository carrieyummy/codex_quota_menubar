import AppKit

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

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        removePopoverEventMonitors()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func quotaPopoverDidRequestRefresh(_ controller: QuotaPopoverViewController) {
        refresh()
    }

    func quotaPopoverDidRequestQuit(_ controller: QuotaPopoverViewController) {
        NSApp.terminate(nil)
    }

    func quotaPopoverDidChangeLayout(_ controller: QuotaPopoverViewController) {
        popover.contentSize = controller.preferredPopoverSize
        applyPopoverChromeAppearance()

        if let snapshot = latestSnapshot {
            updateStatusItem(snapshot: snapshot)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        applyPopoverChromeAppearance()
        installPopoverEventMonitors()
    }

    func popoverDidClose(_ notification: Notification) {
        removePopoverEventMonitors()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

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
        statusItem.length = NSStatusItem.variableLength
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.animates = false
        popover.contentSize = popoverController.preferredPopoverSize
        popover.contentViewController = popoverController
        popoverController.delegate = self
    }

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

    @objc private func closePopoverForExternalStateChange(_ notification: Notification) {
        guard popover.isShown else {
            return
        }

        if popoverController.shouldKeepMainPopoverForAuxiliaryWindow {
            return
        }

        popover.performClose(nil)
    }

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

    private func isInternalWindow(_ window: NSWindow?) -> Bool {
        guard let window else {
            return false
        }

        if window === popoverController.view.window || window === NSColorPanel.shared {
            return true
        }

        return popoverController.auxiliaryWindows.contains { $0 === window }
    }

    private func isPointInsideInternalWindow(_ point: NSPoint) -> Bool {
        if let window = popoverController.view.window, window.frame.contains(point) {
            return true
        }

        if NSColorPanel.shared.isVisible && NSColorPanel.shared.frame.contains(point) {
            return true
        }

        return popoverController.auxiliaryWindows.contains { $0.frame.contains(point) }
    }

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

    private func apply(snapshot: QuotaSnapshot) {
        popoverController.update(snapshot: snapshot)
        updateStatusItem(snapshot: snapshot)
    }

    private func updateStatusItem(snapshot: QuotaSnapshot) {
        let codexWindow = snapshot.codex.fiveHour
        let indicatorPercent = min(codexWindow.remainingPercent, snapshot.codex.weekly.remainingPercent)
        updateStatusItemDisplay(
            title: statusTitle(for: snapshot),
            color: QuotaColors.color(forRemainingPercent: indicatorPercent)
        )
    }

    private func statusTitle(for snapshot: QuotaSnapshot) -> String {
        var title = statusBarPart(prefix: "Codex", window: snapshot.codex.fiveHour)

        if popoverController.showsSparkQuota, let sparkWindow = snapshot.spark?.fiveHour {
            title += " | " + statusBarPart(prefix: "5.3", window: sparkWindow)
        }

        return title
    }

    private func updateStatusItemDisplay(title: String, color: NSColor) {
        guard let button = statusItem.button else {
            return
        }

        button.title = title
        button.image = statusBarImage(color: color)
        statusItem.length = NSStatusItem.variableLength
    }

    private func statusBarPart(prefix: String, window: QuotaWindow) -> String {
        "\(prefix) \(window.remainingPercent)% \(formatStatusBarReset(window.resetAt))"
    }

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
