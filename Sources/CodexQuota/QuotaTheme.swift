import AppKit

struct QuotaTheme {
    static let defaultTextColor = NSColor(calibratedRed: 255 / 255, green: 174 / 255, blue: 0, alpha: 1)
    static let defaultOpacity = 0.0

    private static let textColorKey = "theme.textColor"

    var textColor: NSColor
    var opacity: Double {
        QuotaTheme.defaultOpacity
    }

    var primaryTextColor: NSColor {
        textColor.withAlphaComponent(0.94)
    }

    var mutedTextColor: NSColor {
        textColor.withAlphaComponent(0.68)
    }

    var backgroundColor: NSColor {
        .clear
    }

    static func load() -> QuotaTheme {
        let color = loadColor(forKey: textColorKey) ?? defaultTextColor
        return QuotaTheme(textColor: color)
    }

    func save() {
        QuotaTheme.saveColor(textColor, forKey: QuotaTheme.textColorKey)
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
