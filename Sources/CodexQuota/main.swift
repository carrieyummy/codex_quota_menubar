import AppKit

/// 应用共享实例，负责启动 AppKit 主事件循环。
private let app = NSApplication.shared
/// 应用代理，持有菜单栏入口、弹窗和额度刷新逻辑。
private let delegate = AppDelegate()

Diagnostics.log("main starting")
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
