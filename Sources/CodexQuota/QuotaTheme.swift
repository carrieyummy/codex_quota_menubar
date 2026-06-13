import AppKit

/// 用户可持久化的弹窗外观主题。
struct QuotaTheme {
    /// 默认文字颜色。
    static let defaultTextColor = NSColor(calibratedRed: 255 / 255, green: 174 / 255, blue: 0, alpha: 1)
    /// 默认背景不透明度百分比。
    static let defaultOpacity = 0.0
    /// 背景不透明度最小值。
    static let minOpacity = 0.0
    /// 背景不透明度最大值，保留少量透明空间避免完全遮挡。
    static let maxOpacity = 95.0

    private static let textColorKey = "theme.textColor"
    private static let opacityKey = "theme.backgroundOpacity"

    /// 基准文字颜色。
    var textColor: NSColor
    /// 背景不透明度百分比，保存和使用前会限制到 `minOpacity...maxOpacity`。
    var opacity: Double

    /// 主文本颜色。
    ///
    /// - Returns: 基准文字颜色的高不透明度版本。
    var primaryTextColor: NSColor {
        textColor.withAlphaComponent(0.94)
    }

    /// 次级文本颜色。
    ///
    /// - Returns: 基准文字颜色的较低不透明度版本。
    var mutedTextColor: NSColor {
        textColor.withAlphaComponent(0.68)
    }

    /// 弹窗背景颜色。
    ///
    /// - Returns: 按 `opacity` 转换 alpha 后的白色背景。
    var backgroundColor: NSColor {
        NSColor.white.withAlphaComponent(opacity / 100)
    }

    /// 从 `UserDefaults` 读取主题设置。
    ///
    /// - Returns: 已保存主题；缺少或解码失败时返回默认主题。
    static func load() -> QuotaTheme {
        let color = loadColor(forKey: textColorKey) ?? defaultTextColor
        let opacity = clamp(UserDefaults.standard.object(forKey: opacityKey) as? Double ?? defaultOpacity)
        return QuotaTheme(textColor: color, opacity: opacity)
    }

    /// 保存当前主题到 `UserDefaults`。
    func save() {
        QuotaTheme.saveColor(textColor, forKey: QuotaTheme.textColorKey)
        UserDefaults.standard.set(QuotaTheme.clamp(opacity), forKey: QuotaTheme.opacityKey)
    }

    /// 将不透明度限制在允许范围内。
    ///
    /// - Parameter value: 原始不透明度百分比。
    /// - Returns: 夹紧到 `minOpacity...maxOpacity` 后的值。
    private static func clamp(_ value: Double) -> Double {
        min(maxOpacity, max(minOpacity, value))
    }

    /// 从 `UserDefaults` 解码颜色。
    ///
    /// - Parameter key: 存储颜色数据的键名。
    /// - Returns: 解码成功的颜色；没有数据或解码失败时为 `nil`。
    private static func loadColor(forKey key: String) -> NSColor? {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else {
            return nil
        }
        return color
    }

    /// 将颜色安全归档并保存到 `UserDefaults`。
    ///
    /// - Parameters:
    ///   - color: 要保存的颜色。
    ///   - key: 存储颜色数据的键名。
    private static func saveColor(_ color: NSColor, forKey key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// 支持圆角和半透明背景的基础视图。
final class ThemedBackgroundView: NSView {
    private let cornerRadius: CGFloat = 9

    /// 视图背景颜色；设置后会立即同步到底层 layer。
    var backgroundColor: NSColor = .clear {
        didSet {
            applyLayerAppearance()
        }
    }

    /// 使用代码创建背景视图。
    ///
    /// - Parameter frameRect: 初始视图 frame。
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    /// 使用 Interface Builder 解码创建背景视图。
    ///
    /// - Parameter coder: 归档解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    /// 使用左上角作为布局原点，便于弹窗内容定位。
    ///
    /// - Returns: 始终返回 `true`。
    override var isFlipped: Bool {
        true
    }

    /// 允许 AppKit 按非不透明视图合成背景。
    ///
    /// - Returns: 始终返回 `false`。
    override var isOpaque: Bool {
        false
    }

    /// 启用 layer 并应用初始圆角背景样式。
    private func configureLayer() {
        wantsLayer = true
        applyLayerAppearance()
    }

    /// 将背景色、圆角和裁剪设置同步到底层 layer。
    private func applyLayerAppearance() {
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
    }
}
