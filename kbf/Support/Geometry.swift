import AppKit

/// Coordinate conversions between the Accessibility API and AppKit.
///
/// AX reports positions in "global" coordinates with the origin at the TOP-left
/// of the primary display and y increasing downward. AppKit/`NSScreen` use the
/// BOTTOM-left of the primary display with y increasing upward. The flip uses the
/// primary screen height regardless of which display the rect lives on.
enum Geometry {
    /// Height of the primary display (the one owning the menu bar; its frame origin is (0,0)).
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// Convert an AX (top-left origin) rect to AppKit global (bottom-left origin) coordinates.
    static func axToCocoa(_ r: CGRect) -> CGRect {
        CGRect(x: r.origin.x, y: primaryHeight - r.origin.y - r.height, width: r.width, height: r.height)
    }

    /// Convert an AX (top-left origin) point to AppKit global coordinates.
    static func axToCocoa(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    /// Convert an AppKit global rect back to AX (top-left origin) coordinates.
    static func cocoaToAX(_ r: CGRect) -> CGRect {
        CGRect(x: r.origin.x, y: primaryHeight - r.origin.y - r.height, width: r.width, height: r.height)
    }

    /// Union of all screen frames in AppKit global coordinates.
    static var screensBounds: CGRect {
        NSScreen.screens.reduce(.null) { $0.union($1.frame) }
    }

    /// Union of all screen frames in AX (top-left origin) coordinates.
    static var screensBoundsAX: CGRect {
        NSScreen.screens.reduce(.null) { $0.union(cocoaToAX($1.frame)) }
    }

    /// True when the rect's center lies inside `bounds` — used to drop UI that
    /// reports a frame but isn't actually on screen (e.g. auto-hidden Dock tiles,
    /// whose frames sit almost entirely below the screen edge).
    static func centerVisible(_ r: CGRect, in bounds: CGRect) -> Bool {
        bounds.contains(CGPoint(x: r.midX, y: r.midY))
    }

    /// Clamp an AX (top-left) point to just inside the visible screens. Keeps clicks
    /// on edge elements (e.g. Dock tiles, which report frames hanging below the screen)
    /// on the actual pixels.
    static func clampAX(_ p: CGPoint) -> CGPoint { clamp(p, screensBoundsAX) }
    /// Clamp an AppKit (bottom-left) point to just inside the visible screens.
    static func clampCocoa(_ p: CGPoint) -> CGPoint { clamp(p, screensBounds) }

    private static func clamp(_ p: CGPoint, _ rect: CGRect) -> CGPoint {
        guard !rect.isNull else { return p }
        let b = rect.insetBy(dx: 4, dy: 4)
        return CGPoint(x: min(max(p.x, b.minX), b.maxX), y: min(max(p.y, b.minY), b.maxY))
    }
}
