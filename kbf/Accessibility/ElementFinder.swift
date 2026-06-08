import AppKit
import ApplicationServices

/// Finds actionable elements in a running app's frontmost window.
///
/// Fast path: the `AXUIElementsForSearchPredicate` parameterized attribute
/// (one traversal inside the target process). Fallback: a recursive AX-tree
/// walk for apps whose windows don't support the predicate (e.g. Chromium,
/// which returns `kAXErrorParameterizedAttributeUnsupported`).
///
/// Performance: every node's role/frame/title (and, in the walk, its children)
/// are read in a SINGLE batched IPC call (`AX.values`), not one call per
/// attribute. This is the difference between hundreds and thousands of
/// round-trips for a busy web page.
enum ElementFinder {
    /// Roles we always treat as clickable, regardless of advertised actions.
    static let actionableRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
        "AXMenuButton", "AXMenuItem", "AXMenuBarItem", "AXTextField", "AXSecureTextField",
        "AXTextArea", "AXComboBox", "AXSlider", "AXStepper", "AXIncrementor",
        "AXDisclosureTriangle", "AXTabButton", "AXColorWell", "AXSegmentedControl",
    ]
    /// Roles that are clickable only if they advertise a press action (bounded
    /// extra actions lookups — keeps the common path fast).
    static let maybeClickable: Set<String> = ["AXImage", "AXCell", "AXRow"]
    static let pressActions: Set<String> = ["AXPress", "AXOpen", "AXPick", "AXConfirm"]

    private static let maxWalk = 4000
    private static let nodeAttrs = [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute,
                                    kAXTitleAttribute, kAXDescriptionAttribute].map { $0 as String }
    private static let walkAttrs = [kAXRoleAttribute, kAXChildrenAttribute, kAXPositionAttribute,
                                    kAXSizeAttribute, kAXTitleAttribute, kAXDescriptionAttribute].map { $0 as String }

    private struct Node { let ax: AXUIElement; let role: String; let frame: CGRect?; let title: String? }

    struct Diagnostics { let rawCount: Int; let usedFastPath: Bool; let rawRoles: [String: Int]; let pressableCount: Int }

    static func find(in app: NSRunningApplication) -> [Element] { find(in: app, diagnostics: nil) }

    static func find(in app: NSRunningApplication, diagnostics: UnsafeMutablePointer<Diagnostics>?) -> [Element] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AX.setTimeout(axApp, seconds: 0.5)

        // Wake lazily-built Chromium/Electron trees. `AXManualAccessibility` is the
        // flag those runtimes check; it's ignored by native apps. We deliberately do
        // NOT set `AXEnhancedUserInterface` — it disrupts native Cocoa apps (Finder).
        AX.setValue(axApp, "AXManualAccessibility", kCFBooleanTrue)

        let root = AX.element(axApp, kAXFocusedWindowAttribute as String) ?? axApp

        var nodes: [Node] = []
        let usedFast: Bool
        if let fast = AX.searchPredicate(root: root), !fast.isEmpty,
           fast.prefix(20).contains(where: { AX.string($0, kAXRoleAttribute as String) != nil }) {
            // Predicate succeeded AND returns readable elements. (Some apps, e.g. Finder,
            // return a few unreadable elements from the predicate — treat as failure.)
            usedFast = true
            nodes.reserveCapacity(fast.count)
            for el in fast { nodes.append(makeNode(el)) }
        } else {
            usedFast = false
            walk(root: root, into: &nodes)
        }

        let bounds = Geometry.screensBounds
        var seen = Set<String>()
        var result: [Element] = []
        var pressable = 0
        for n in nodes {
            guard let f = n.frame, f.width >= 4, f.height >= 4, f.width < 6000, f.height < 6000,
                  bounds.intersects(Geometry.axToCocoa(f)) else { continue }
            let keep: Bool
            if actionableRoles.contains(n.role) {
                keep = true
            } else if maybeClickable.contains(n.role) {
                let hit = !AX.actions(n.ax).isDisjoint(with: pressActions)
                if hit { pressable += 1 }
                keep = hit
            } else {
                keep = false
            }
            guard keep else { continue }
            // de-dup elements reporting the exact same frame (common in web content)
            let key = "\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))"
            if seen.insert(key).inserted {
                result.append(Element(ax: n.ax, role: n.role, axFrame: f, title: n.title))
            }
        }

        if let diagnostics {
            var roles: [String: Int] = [:]
            for n in nodes { roles[n.role.isEmpty ? "?" : n.role, default: 0] += 1 }
            diagnostics.pointee = Diagnostics(rawCount: nodes.count, usedFastPath: usedFast,
                                              rawRoles: roles, pressableCount: pressable)
        }
        return result
    }

    // MARK: scroll areas (for scroll mode)

    static let scrollRoles: Set<String> = ["AXScrollArea", "AXWebArea"]
    private static let scrollAttrs = [kAXRoleAttribute, kAXChildrenAttribute,
                                      kAXPositionAttribute, kAXSizeAttribute].map { $0 as String }

    /// Scrollable containers in the frontmost window whose VISIBLE region is
    /// sizable, de-duplicated by viewport (nested web area + scroll area collapse
    /// to one), largest-visible first.
    static func scrollAreas(in app: NSRunningApplication) -> [Element] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AX.setTimeout(axApp, seconds: 0.5)
        AX.setValue(axApp, "AXManualAccessibility", kCFBooleanTrue)
        let root = AX.element(axApp, kAXFocusedWindowAttribute as String) ?? axApp
        let visible = Geometry.screensBoundsAX
        var found: [Element] = []
        collectScroll(root, depth: 0, visible: visible, into: &found)

        var seen = Set<String>()
        return found
            .sorted { visibleArea($0.axFrame, visible) > visibleArea($1.axFrame, visible) }
            .filter { e in
                // Collapse nested areas sharing the same column (origin + width);
                // the largest-visible one is kept (we sorted by visible area first).
                let vr = e.axFrame.intersection(visible)
                let key = "\(Int(vr.minX / 8)),\(Int(vr.minY / 8)),\(Int(vr.width / 8))"
                return seen.insert(key).inserted
            }
    }

    private static func visibleArea(_ f: CGRect, _ visible: CGRect) -> CGFloat {
        let r = f.intersection(visible)
        return r.isNull ? 0 : r.width * r.height
    }

    private static func collectScroll(_ el: AXUIElement, depth: Int, visible: CGRect, into out: inout [Element]) {
        if depth > 80 || out.count > 200 { return }
        let v = AX.values(el, scrollAttrs)
        let role = v[0] as? String ?? ""
        if scrollRoles.contains(role), let f = AX.rect(v[2], v[3]) {
            let vr = f.intersection(visible)
            if !vr.isNull, vr.width > 120, vr.height > 120 {
                out.append(Element(ax: el, role: role, axFrame: f, title: nil))
            }
        }
        for c in (v[1] as? [AXUIElement] ?? []) {
            collectScroll(c, depth: depth + 1, visible: visible, into: &out)
        }
    }

    private static func makeNode(_ el: AXUIElement) -> Node {
        let v = AX.values(el, nodeAttrs)
        return Node(ax: el, role: v[0] as? String ?? "", frame: AX.rect(v[1], v[2]),
                    title: (v[3] as? String) ?? (v[4] as? String))
    }

    /// Walk the tree, pruning subtrees whose frame is entirely off-screen.
    /// The clip = the focused window's frame: scrolled-away/off-viewport content
    /// (the bulk of a long web page) has frames outside it and is skipped, so cost
    /// scales with VISIBLE elements, not the whole document.
    private static func walk(root: AXUIElement, into out: inout [Node]) {
        let v = AX.values(root, walkAttrs)
        let clip = AX.rect(v[2], v[3])
        for c in (v[1] as? [AXUIElement] ?? []) {
            walkChild(c, depth: 1, clip: clip, into: &out)
            if out.count >= maxWalk { return }
        }
    }

    private static func walkChild(_ el: AXUIElement, depth: Int, clip: CGRect?, into out: inout [Node]) {
        if depth > 80 || out.count >= maxWalk { return }
        let v = AX.values(el, walkAttrs)
        let frame = AX.rect(v[2], v[3])
        // Prune off-screen subtrees (only when we have a real, non-empty frame).
        if let clip, let f = frame, f.width > 0, f.height > 0, !clip.intersects(f) { return }
        out.append(Node(ax: el, role: v[0] as? String ?? "", frame: frame,
                        title: (v[4] as? String) ?? (v[5] as? String)))
        guard out.count < maxWalk, let children = v[1] as? [AXUIElement] else { return }
        for c in children {
            walkChild(c, depth: depth + 1, clip: clip, into: &out)
            if out.count >= maxWalk { return }
        }
    }
}
