import AppKit

/// Minimal design tokens. Expanded into a full Raycast/Linear-style system in a later milestone.
enum Theme {
    static let accent = NSColor(srgbRed: 0.388, green: 0.400, blue: 0.945, alpha: 1)   // indigo #6366F1
    static let accentDim = NSColor(srgbRed: 0.388, green: 0.400, blue: 0.945, alpha: 0.35)
    static let hintText = NSColor.white
    static let hintTypedText = NSColor.white.withAlphaComponent(0.45)
    static let hintFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    static let hintCornerRadius: CGFloat = 5
    static let hintPadding = CGSize(width: 6, height: 3)
}
