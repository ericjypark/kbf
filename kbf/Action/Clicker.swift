import AppKit
import ApplicationServices

/// Performs an action on a chosen element. Prefers the semantic AX action;
/// falls back to a synthetic mouse click at the element's center.
///
/// Note: AX positions and CGEvent mouse positions share the same global
/// coordinate space (top-left origin), so `Element.axCenter` is used directly
/// for cursor warping and synthetic clicks — no flip needed.
enum Clicker {
    enum Action { case left, double, right, command, move }

    enum Outcome: CustomStringConvertible {
        case axAction(String)
        case synthesized(CGPoint)
        case moved(CGPoint)
        case none
        var description: String {
            switch self {
            case .axAction(let a): return "AXAction(\(a))"
            case .synthesized(let p): return "synthClick @\(Int(p.x)),\(Int(p.y))"
            case .moved(let p): return "moved @\(Int(p.x)),\(Int(p.y))"
            case .none: return "none"
            }
        }
    }

    @discardableResult
    static func perform(_ action: Action, on element: Element) -> Outcome {
        // Clamp on-screen so off-screen-center elements (e.g. Dock tiles) click real pixels.
        let p = Geometry.clampAX(element.axCenter)
        if action != .move { clickFeedback() }
        switch action {
        case .left:
            if let a = axPress(element) { return .axAction(a) }
            synthClick(at: p, button: .left, clicks: 1)
            return .synthesized(p)
        case .double:
            synthClick(at: p, button: .left, clicks: 2)
            return .synthesized(p)
        case .right:
            if AX.perform(element.ax, "AXShowMenu") { return .axAction("AXShowMenu") }
            synthClick(at: p, button: .right, clicks: 1)
            return .synthesized(p)
        case .command:
            synthClick(at: p, button: .left, clicks: 1, flags: .maskCommand)
            return .synthesized(p)
        case .move:
            CGWarpMouseCursorPosition(p)
            return .moved(p)
        }
    }

    /// A synthetic left click with an explicit click-state. Posting two of these at
    /// the same point (state 1 then 2) within the double-click interval is what makes
    /// the OS register a real double-click — used by "type the label twice".
    @discardableResult
    static func leftClick(on element: Element, clickState: Int64) -> Outcome {
        clickFeedback()
        let p = Geometry.clampAX(element.axCenter)
        let src = CGEventSource(stateID: .combinedSessionState)
        CGWarpMouseCursorPosition(p)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let e = CGEvent(mouseEventSource: src, mouseType: type,
                                  mouseCursorPosition: p, mouseButton: .left) else { continue }
            e.setIntegerValueField(.mouseEventClickState, value: clickState)
            e.post(tap: .cghidEventTap)
        }
        return .synthesized(p)
    }

    /// Optional audible tick on every click action (off by default).
    private static func clickFeedback() {
        guard AppSettings.shared.clickSound else { return }
        NSSound(named: "Tink")?.play()
    }

    private static func axPress(_ element: Element) -> String? {
        let actions = AX.actions(element.ax)
        for a in ["AXPress", "AXOpen", "AXConfirm", "AXPick"] where actions.contains(a) {
            if AX.perform(element.ax, a) { return a }
        }
        return nil
    }

    private static func synthClick(at p: CGPoint, button: CGMouseButton, clicks: Int,
                                   flags: CGEventFlags = []) {
        let (down, up): (CGEventType, CGEventType) = button == .right
            ? (.rightMouseDown, .rightMouseUp)
            : (.leftMouseDown, .leftMouseUp)
        let src = CGEventSource(stateID: .combinedSessionState)
        CGWarpMouseCursorPosition(p)
        for click in 1...clicks {
            for type in [down, up] {
                guard let e = CGEvent(mouseEventSource: src, mouseType: type,
                                      mouseCursorPosition: p, mouseButton: button) else { continue }
                if !flags.isEmpty { e.flags = flags }
                e.setIntegerValueField(.mouseEventClickState, value: Int64(click))
                e.post(tap: .cghidEventTap)
            }
        }
    }
}
