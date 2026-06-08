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
}
