import AppKit

/// 可作为辅助窗口使用的浮动面板。
final class QuotaFloatingPanel: NSPanel {
    /// 允许面板成为 key window，以便接收键盘和控件焦点。
    ///
    /// - Returns: 始终返回 `true`。
    override var canBecomeKey: Bool {
        true
    }

    /// 避免辅助面板成为主窗口，保持菜单栏应用的轻量交互。
    ///
    /// - Returns: 始终返回 `false`。
    override var canBecomeMain: Bool {
        false
    }
}
