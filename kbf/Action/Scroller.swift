import AppKit

/// Posts synthetic scroll-wheel events at a screen point (the chosen scroll area).
///
/// Must NOT be called from inside an event-tap callback (posted events get
/// dropped there) — callers defer to the main loop, same as `Clicker`.
enum Scroller {
    /// `dy` > 0 scrolls up (toward the top), `dx` > 0 scrolls left. Pixel units.
    static func scroll(at point: CGPoint, dx: Int32, dy: Int32) {
        CGWarpMouseCursorPosition(point)
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                  wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }
}
