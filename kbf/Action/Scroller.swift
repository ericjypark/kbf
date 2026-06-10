import AppKit

/// Posts synthetic scroll-wheel events at a screen point (the chosen scroll area).
///
/// Must NOT be called from inside an event-tap callback (posted events get
/// dropped there) — callers defer to the main loop, same as `Clicker`.
enum Scroller {
    /// `dy` > 0 scrolls up (toward the top), `dx` > 0 scrolls left. Pixel units.
    static func scroll(at point: CGPoint, dx: Int32, dy: Int32) {
        CGWarpMouseCursorPosition(point)
        post(dx: dx, dy: dy)
    }

    // MARK: smooth scrolling (main thread only)

    private static var animation: Timer?
    private static let tick = 1.0 / 120.0
    private static let steps = 24   // × tick ≈ 0.2s glide

    /// Animated scroll: the same total delta as `scroll`, glided over ~0.2s
    /// with an ease-out curve. A new call (or `stopAnimation`) cancels any
    /// glide still in flight.
    static func smoothScroll(at point: CGPoint, dx: Int32, dy: Int32) {
        stopAnimation()
        CGWarpMouseCursorPosition(point)
        let xs = ScrollAnimation.deltas(total: dx, steps: steps)
        let ys = ScrollAnimation.deltas(total: dy, steps: steps)
        var i = 0
        let timer = Timer(timeInterval: tick, repeats: true) { timer in
            let sx = i < xs.count ? xs[i] : 0
            let sy = i < ys.count ? ys[i] : 0
            if sx != 0 || sy != 0 { post(dx: sx, dy: sy) }
            i += 1
            if i >= max(xs.count, ys.count) { timer.invalidate() }
        }
        animation = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    static func stopAnimation() {
        animation?.invalidate()
        animation = nil
    }

    private static func post(dx: Int32, dy: Int32) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                  wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }
}
