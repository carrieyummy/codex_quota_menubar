import AppKit

struct QuotaTheme {
    static let defaultTextColor = NSColor(calibratedRed: 255 / 255, green: 174 / 255, blue: 0, alpha: 1)
    static let defaultOpacity = 0.0
    static let minOpacity = 0.0
    static let maxOpacity = 95.0

    private static let textColorKey = "theme.textColor"
    private static let opacityKey = "theme.backgroundOpacity"

    var textColor: NSColor
    var opacity: Double

    var primaryTextColor: NSColor {
        textColor.withAlphaComponent(0.94)
    }

    var mutedTextColor: NSColor {
        textColor.withAlphaComponent(0.68)
    }

    var backgroundColor: NSColor {
        NSColor.white.withAlphaComponent(opacity / 100)
    }

    static func load() -> QuotaTheme {
        let color = loadColor(forKey: textColorKey) ?? defaultTextColor
        let opacity = clamp(UserDefaults.standard.object(forKey: opacityKey) as? Double ?? defaultOpacity)
        return QuotaTheme(textColor: color, opacity: opacity)
    }

    func save() {
        QuotaTheme.saveColor(textColor, forKey: QuotaTheme.textColorKey)
        UserDefaults.standard.set(QuotaTheme.clamp(opacity), forKey: QuotaTheme.opacityKey)
    }

    private static func clamp(_ value: Double) -> Double {
        min(maxOpacity, max(minOpacity, value))
    }

    private static func loadColor(forKey key: String) -> NSColor? {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else {
            return nil
        }
        return color
    }

    private static func saveColor(_ color: NSColor, forKey key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}

final class ThemedBackgroundView: NSView {
    private let cornerRadius: CGFloat = 9

    var backgroundColor: NSColor = .clear {
        didSet {
            applyLayerAppearance()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    private func configureLayer() {
        wantsLayer = true
        applyLayerAppearance()
    }

    private func applyLayerAppearance() {
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
    }
}
