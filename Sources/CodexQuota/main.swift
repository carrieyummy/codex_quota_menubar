import AppKit

private let app = NSApplication.shared
private let delegate = AppDelegate()

Diagnostics.log("main starting")
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
