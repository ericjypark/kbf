import AppKit
import ApplicationServices

/// Finds actionable elements in a running app's frontmost window via a
/// recursive AX-tree walk (a search-predicate fast path was tried and removed:
/// it freezes on slow-AX apps — see 4a91997).
///
/// Performance: every node's role/frame/title (and its children) are read in
/// a SINGLE batched IPC call (`AX.values`), not one call per attribute. This
/// is the difference between hundreds and thousands of round-trips for a busy
/// web page. Off-screen subtrees are pruned so cost scales with the VISIBLE
/// elements, and a hard time budget bounds pathological apps.
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

    struct Diagnostics { let rawCount: Int; let rawRoles: [String: Int]; let pressableCount: Int }

    /// Apps whose accessibility tree is lazily built and needs `AXManualAccessibility`
    /// to populate (Chromium + Electron). Native AppKit apps don't — and setting it on
    /// them (Finder especially) makes their AX queries pathologically slow.
    static func needsManualAccessibility(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier?.lowercased() else { return false }
        let markers = ["chrome", "chromium", "brave", "edgemac", "company.thebrowser",
                       "electron", "vscode", "code-oss", "slack", "discord", "spotify",
                       "notion", "figma", "obsidian", "1password", "linear", "whatsapp"]
        return markers.contains { id.contains($0) }
    }

    static func find(in app: NSRunningApplication) -> [Element] { find(in: app, diagnostics: nil) }

    /// Hard cap on how long a single find may run. Some apps (notably Finder) have
    /// pathologically slow accessibility — ~7ms per IPC call — so without this a busy
    /// window could take many seconds. We return whatever was gathered by the deadline.
    static let timeBudget: CFTimeInterval = 0.8

    static func find(in app: NSRunningApplication, diagnostics: UnsafeMutablePointer<Diagnostics>?) -> [Element] {
        let deadline = CFAbsoluteTimeGetCurrent() + timeBudget
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AX.setTimeout(axApp, seconds: 0.25)

        // Wake lazily-built Chromium/Electron trees — but ONLY for those apps.
        // Setting this on native apps (e.g. Finder) makes their accessibility
        // pathologically slow. (We never set `AXEnhancedUserInterface` — it
        // disrupts native Cocoa apps.)
        if needsManualAccessibility(app) {
            AX.setValue(axApp, "AXManualAccessibility", kCFBooleanTrue)
        }

        let timing = ProcessInfo.processInfo.environment["KBF_TIMING"] != nil
        let t0 = CFAbsoluteTimeGetCurrent()
        let focused = AX.element(axApp, kAXFocusedWindowAttribute as String)
        // ⌘Tab can make an app frontmost without switching to its Space; labeling
        // a window that isn't on the active Space would paint ghost pills over the
        // wrong desktop. Skip its contents (menu bar/Dock/open menus still work).
        if let focused, let wf = AX.frame(focused),
           !WindowList.hasOnScreenWindow(pid: app.processIdentifier, near: wf) {
            diagnostics?.pointee = Diagnostics(rawCount: 0, rawRoles: [:], pressableCount: 0)
            return []
        }
        let root = focused ?? axApp
        // Bound calls on the window element too — the messaging timeout is per-element,
        // so setting it on axApp alone doesn't cover the window or its children.
        AX.setTimeout(root, seconds: 0.25)

        var nodes: [Node] = []
        walk(root: root, deadline: deadline, into: &nodes)
        if timing {
            print(String(format: "  timing: walk %.0fms for %d nodes",
                         (CFAbsoluteTimeGetCurrent() - t0) * 1000, nodes.count))
        }

        var seen = Set<String>()
        let (result, pressable) = actionable(nodes, deadline: deadline, seen: &seen)

        if let diagnostics {
            var roles: [String: Int] = [:]
            for n in nodes { roles[n.role.isEmpty ? "?" : n.role, default: 0] += 1 }
            diagnostics.pointee = Diagnostics(rawCount: nodes.count, rawRoles: roles,
                                              pressableCount: pressable)
        }
        return result
    }

    /// Role/geometry filter shared by the window walk and popup-window walks:
    /// on-screen, sensibly sized, actionable role (or pressable), de-duped by
    /// frame (web content often reports stacked duplicates).
    private static func actionable(_ nodes: [Node], deadline: CFTimeInterval,
                                   seen: inout Set<String>) -> ([Element], Int) {
        let bounds = Geometry.screensBounds
        var result: [Element] = []
        var pressable = 0
        for n in nodes {
            if CFAbsoluteTimeGetCurrent() > deadline { break }   // bound the actions lookups too
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
            let key = "\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))"
            if seen.insert(key).inserted {
                result.append(Element(ax: n.ax, role: n.role, axFrame: f, title: n.title))
            }
        }
        return (result, pressable)
    }

    /// Drop elements reporting the same frame — merged sources (window walk,
    /// menu bar, open menus, popup windows) can overlap.
    static func dedupByFrame(_ elements: [Element]) -> [Element] {
        var seen = Set<String>()
        return elements.filter {
            let f = $0.axFrame
            return seen.insert("\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))").inserted
        }
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
        AX.setTimeout(axApp, seconds: 0.25)
        if needsManualAccessibility(app) {
            AX.setValue(axApp, "AXManualAccessibility", kCFBooleanTrue)
        }
        let focused = AX.element(axApp, kAXFocusedWindowAttribute as String)
        if let focused, let wf = AX.frame(focused),
           !WindowList.hasOnScreenWindow(pid: app.processIdentifier, near: wf) {
            return []   // focused window is on another Space — nothing to scroll here
        }
        let root = focused ?? axApp
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

    // MARK: menu bar + Dock (clickable from anywhere, not in the app's window)

    private static let extrasLock = NSLock()
    private static var extrasCache: [Element] = []
    private static var extrasCacheTime: CFTimeInterval = 0
    private static var extrasRefreshing = false

    /// The frontmost app's menu-bar items (fresh) plus the Dock and right-side status
    /// items. The latter require sweeping every running app for `AXExtrasMenuBar`, which
    /// is far too slow to do on every activation (~500ms), so they're served from a cache
    /// that refreshes in the background. Call `prewarmExtras()` at launch.
    /// Items whose center is off-screen (e.g. an auto-hidden Dock's tiles) are dropped —
    /// labeling them would float pills over nothing, and the click would miss anyway.
    static func menuBarAndDock(frontApp: NSRunningApplication) -> [Element] {
        let bounds = Geometry.screensBoundsAX
        return (frontAppMenus(frontApp) + cachedExtras())
            .filter { Geometry.centerVisible($0.axFrame, in: bounds) }
    }

    /// Kick the background extras/Dock collection so it's ready by the first activation.
    static func prewarmExtras() { _ = cachedExtras() }

    private static func frontAppMenus(_ app: NSRunningApplication) -> [Element] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AX.setTimeout(axApp, seconds: 0.2)
        guard let menuBar = AX.element(axApp, kAXMenuBarAttribute as String) else { return [] }
        return AX.elements(menuBar, kAXChildrenAttribute as String).compactMap { item in
            guard let f = AX.frame(item), f.width >= 2, f.height >= 2 else { return nil }
            return Element(ax: item, role: "AXMenuBarItem", axFrame: f,
                           title: AX.string(item, kAXTitleAttribute as String))
        }
    }

    private static func cachedExtras() -> [Element] {
        extrasLock.lock()
        let cache = extrasCache
        let kickoff = (CFAbsoluteTimeGetCurrent() - extrasCacheTime > 3.0) && !extrasRefreshing
        if kickoff { extrasRefreshing = true }
        extrasLock.unlock()

        if kickoff {
            DispatchQueue.global(qos: .utility).async {
                let fresh = collectExtras()
                extrasLock.lock()
                extrasCache = fresh
                extrasCacheTime = CFAbsoluteTimeGetCurrent()
                extrasRefreshing = false
                extrasLock.unlock()
            }
        }
        return cache
    }

    /// The slow sweep (runs in the background): every app's status items + the Dock.
    private static func collectExtras() -> [Element] {
        var out: [Element] = []
        let deadline = CFAbsoluteTimeGetCurrent() + 1.0
        for running in NSWorkspace.shared.runningApplications {
            if CFAbsoluteTimeGetCurrent() > deadline { break }
            let ax = AXUIElementCreateApplication(running.processIdentifier)
            AX.setTimeout(ax, seconds: 0.1)
            guard let extras = AX.element(ax, "AXExtrasMenuBar") else { continue }
            for item in AX.elements(extras, kAXChildrenAttribute as String) {
                if let f = AX.frame(item), f.width >= 2, f.height >= 2 {
                    out.append(Element(ax: item, role: "AXMenuExtra", axFrame: f,
                                       title: AX.string(item, kAXTitleAttribute as String)
                                           ?? AX.string(item, kAXDescriptionAttribute as String)))
                }
            }
        }
        if let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) {
            let axDock = AXUIElementCreateApplication(dock.processIdentifier)
            AX.setTimeout(axDock, seconds: 0.25)
            collectDockItems(axDock, depth: 0, deadline: CFAbsoluteTimeGetCurrent() + 0.4, into: &out)
        }
        return out
    }

    private static func collectDockItems(_ el: AXUIElement, depth: Int, deadline: CFTimeInterval, into out: inout [Element]) {
        if depth > 12 || CFAbsoluteTimeGetCurrent() > deadline { return }
        for child in AX.elements(el, kAXChildrenAttribute as String) {
            let role = AX.string(child, kAXRoleAttribute as String) ?? ""
            if role == "AXDockItem", let f = AX.frame(child), f.width >= 8, f.height >= 8 {
                out.append(Element(ax: child, role: role, axFrame: f,
                                   title: AX.string(child, kAXTitleAttribute as String)))
            } else {
                collectDockItems(child, depth: depth + 1, deadline: deadline, into: &out)
            }
        }
    }

    // MARK: open menus

    /// Items of any OPEN menu: status-item menus plus the front app's own
    /// menu-bar dropdowns. An open menu hangs off the menu-bar item that
    /// spawned it — not off any window — so the focused-window walk never sees
    /// it. Status items expose an `AXMenu` child only while open; app menu-bar
    /// items expose theirs even when CLOSED, so those only count when a real
    /// on-screen popup window of the app matches the menu's frame.
    /// Disabled items (separators, section headers) are skipped.
    static func openMenuItems(frontApp: NSRunningApplication) -> [Element] {
        let deadline = CFAbsoluteTimeGetCurrent() + 0.4
        var roots: [AXUIElement] = []
        for extra in cachedExtras() {
            if CFAbsoluteTimeGetCurrent() > deadline { break }
            AX.setTimeout(extra.ax, seconds: 0.1)
            for child in AX.elements(extra.ax, kAXChildrenAttribute as String)
            where AX.string(child, kAXRoleAttribute as String) == "AXMenu" {
                roots.append(child)
            }
        }

        let popups = WindowList.popupWindows(excludingPid: pid_t(ProcessInfo.processInfo.processIdentifier))
            .filter { $0.pid == frontApp.processIdentifier }
        if !popups.isEmpty {
            let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
            AX.setTimeout(axApp, seconds: 0.2)
            if let menuBar = AX.element(axApp, kAXMenuBarAttribute as String) {
                for item in AX.elements(menuBar, kAXChildrenAttribute as String) {
                    if CFAbsoluteTimeGetCurrent() > deadline { break }
                    for child in AX.elements(item, kAXChildrenAttribute as String)
                    where AX.string(child, kAXRoleAttribute as String) == "AXMenu" {
                        guard let mf = AX.frame(child), WindowList.matchesPopup(mf, in: popups) else { continue }
                        roots.append(child)
                    }
                }
            }
        }
        guard !roots.isEmpty else { return [] }

        let bounds = Geometry.screensBounds
        var seen = Set<String>()
        var out: [Element] = []
        for root in roots {
            var nodes: [Node] = []
            walkChild(root, depth: 1, clip: nil, deadline: CFAbsoluteTimeGetCurrent() + 0.3, into: &nodes)
            for n in nodes {
                guard n.role == "AXMenuItem",
                      let f = n.frame, f.width >= 4, f.height >= 4,
                      bounds.intersects(Geometry.axToCocoa(f)),
                      AX.value(n.ax, kAXEnabledAttribute as String) as? Bool != false else { continue }
                let key = "\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))"
                if seen.insert(key).inserted {
                    out.append(Element(ax: n.ax, role: n.role, axFrame: f, title: n.title))
                }
            }
        }
        return out
    }

    /// Items inside open popup WINDOWS: Control Center popovers (battery,
    /// Wi-Fi, Now Playing), floating panels hung off status items. These are
    /// real windows above the normal layer — found via the window server,
    /// matched to the owning app's `AXWindow` by frame, then walked with the
    /// standard actionable filter. (NSMenu-style popups never appear in
    /// `AXWindows`; `openMenuItems` handles those.)
    static func popupWindowItems() -> [Element] {
        let popups = WindowList.popupWindows(excludingPid: pid_t(ProcessInfo.processInfo.processIdentifier))
        guard !popups.isEmpty else { return [] }
        let deadline = CFAbsoluteTimeGetCurrent() + 0.5
        var out: [Element] = []
        var seen = Set<String>()
        for pid in Set(popups.map(\.pid)) {
            if CFAbsoluteTimeGetCurrent() > deadline { break }
            let axApp = AXUIElementCreateApplication(pid)
            AX.setTimeout(axApp, seconds: 0.15)
            let bounds = popups.filter { $0.pid == pid }.map(\.bounds)
            for win in AX.elements(axApp, kAXWindowsAttribute as String) {
                guard let wf = AX.frame(win),
                      bounds.contains(where: { abs($0.midX - wf.midX) < 8 && abs($0.midY - wf.midY) < 8 })
                else { continue }
                AX.setTimeout(win, seconds: 0.15)
                var nodes: [Node] = []
                walkChild(win, depth: 1, clip: wf, deadline: deadline, into: &nodes)
                out += actionable(nodes, deadline: deadline, seen: &seen).0
            }
        }
        return out
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
    private static func walk(root: AXUIElement, deadline: CFTimeInterval, into out: inout [Node]) {
        let v = AX.values(root, walkAttrs)
        let clip = AX.rect(v[2], v[3])
        for c in (v[1] as? [AXUIElement] ?? []) {
            walkChild(c, depth: 1, clip: clip, deadline: deadline, into: &out)
            if out.count >= maxWalk || CFAbsoluteTimeGetCurrent() > deadline { return }
        }
    }

    private static func walkChild(_ el: AXUIElement, depth: Int, clip: CGRect?,
                                  deadline: CFTimeInterval, into out: inout [Node]) {
        if depth > 80 || out.count >= maxWalk || CFAbsoluteTimeGetCurrent() > deadline { return }
        let v = AX.values(el, walkAttrs)
        let frame = AX.rect(v[2], v[3])
        // Prune off-screen subtrees (only when we have a real, non-empty frame).
        if let clip, let f = frame, f.width > 0, f.height > 0, !clip.intersects(f) { return }
        out.append(Node(ax: el, role: v[0] as? String ?? "", frame: frame,
                        title: (v[4] as? String) ?? (v[5] as? String)))
        guard out.count < maxWalk, let children = v[1] as? [AXUIElement] else { return }
        for c in children {
            walkChild(c, depth: depth + 1, clip: clip, deadline: deadline, into: &out)
            if out.count >= maxWalk || CFAbsoluteTimeGetCurrent() > deadline { return }
        }
    }
}
