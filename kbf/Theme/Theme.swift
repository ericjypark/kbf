import AppKit

/// Hint-label appearance, user-selectable (Homerow ships Dark/Light/Original;
/// kbf's "original" is its indigo accent).
enum LabelTheme: String, CaseIterable {
    case indigo, dark, light

    var displayName: String { rawValue.capitalized }

    var pill: NSColor {
        switch self {
        case .indigo: return Theme.accent
        case .dark: return NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
        case .light: return NSColor(srgbRed: 0.98, green: 0.98, blue: 0.96, alpha: 1)
        }
    }

    var text: NSColor {
        self == .light ? NSColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1) : .white
    }

    var typedText: NSColor {
        self == .light ? NSColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 0.4)
                       : NSColor.white.withAlphaComponent(0.45)
    }
}

/// Hint-label size, user-selectable.
enum HintScale: String, CaseIterable {
    case small, medium, large

    var displayName: String { rawValue.capitalized }

    var fontSize: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 12
        case .large: return 14
        }
    }
}

/// Design tokens. Label styling derives from the user's theme/size settings;
/// the accent (selection borders, active scroll area) is fixed indigo.
enum Theme {
    static let accent = NSColor(srgbRed: 0.388, green: 0.400, blue: 0.945, alpha: 1)   // indigo #6366F1
    static var hintPill: NSColor { AppSettings.shared.labelTheme.pill }
    static var hintText: NSColor { AppSettings.shared.labelTheme.text }
    static var hintTypedText: NSColor { AppSettings.shared.labelTheme.typedText }
    static var hintFont: NSFont {
        .monospacedSystemFont(ofSize: AppSettings.shared.hintScale.fontSize, weight: .bold)
    }
    static let hintCornerRadius: CGFloat = 5
    static var hintPadding: CGSize {
        let f = AppSettings.shared.hintScale.fontSize
        return CGSize(width: f / 2, height: f / 4)
    }
}
