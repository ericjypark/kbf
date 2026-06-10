import AppKit
import ApplicationServices

/// `kbf --debug-menu <AppName> [itemIndex]` — reproduction harness for "open
/// popup items aren't labeled": lists the app's status items (no index given),
/// or opens the chosen one, dumps what the finder (and the AX focus attributes)
/// see, then closes it.
enum DebugMenu {
    static func run(appName: String?, itemIndex: Int?) {
        guard AccessibilityPermission.isTrusted else {
            print("NOT TRUSTED — grant Accessibility to the host process first.")
            return
        }
        guard let name = appName,
              let owner = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) else {
            print("app \(appName ?? "?") not running")
            return
        }
        ElementFinder.prewarmExtras()   // openMenuItems() reads the extras cache
        Thread.sleep(forTimeInterval: 1.5)
        let axOwner = AXUIElementCreateApplication(owner.processIdentifier)
        AX.setTimeout(axOwner, seconds: 0.3)
        guard let extras = AX.element(axOwner, "AXExtrasMenuBar") else {
            print("no extras menu bar for \(name)")
            return
        }
        let items = AX.elements(extras, kAXChildrenAttribute as String)
        guard let idx = itemIndex else {
            print("status items of \(name) — rerun with an index to press one:")
            for (i, it) in items.enumerated() {
                let f = AX.frame(it)
                print("  [\(i)] \(AX.string(it, kAXTitleAttribute as String) ?? AX.string(it, kAXDescriptionAttribute as String) ?? "?")  \(f.map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))×\(Int($0.height)))" } ?? "")")
            }
            return
        }
        guard idx < items.count else { print("index \(idx) out of range (\(items.count) items)"); return }
        let item = items[idx]
        AX.setTimeout(item, seconds: 0.3)
        print("status item actions: \(AX.actions(item))")
        print("pressing status item of \(name)… (call may time out while the menu tracks)")
        AX.perform(item, "AXPress")
        Thread.sleep(forTimeInterval: 2.0)   // window for an external `screencapture` to verify the menu is up

        // Who would beginFinding target right now?
        print("NSWorkspace.frontmostApplication: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")")
        let sys = AXUIElementCreateSystemWide()
        AX.setTimeout(sys, seconds: 0.3)
        if let fApp = AX.element(sys, "AXFocusedApplication") {
            var pid: pid_t = 0
            AXUIElementGetPid(fApp, &pid)
            let app = NSRunningApplication(processIdentifier: pid)
            print("AX focused application: \(app?.localizedName ?? "?") (pid \(pid))")
        } else {
            print("AX focused application: nil")
        }
        if let fEl = AX.element(sys, kAXFocusedUIElementAttribute as String) {
            print("AX focused element: role=\(AX.string(fEl, kAXRoleAttribute as String) ?? "?")")
        } else {
            print("AX focused element: nil")
        }

        // Where does the open menu live in the owner's AX tree?
        print("owner has focused window: \(AX.element(axOwner, kAXFocusedWindowAttribute as String) != nil)")
        if let fEl = AX.element(axOwner, kAXFocusedUIElementAttribute as String) {
            print("owner focused element: role=\(AX.string(fEl, kAXRoleAttribute as String) ?? "?")")
        } else {
            print("owner focused element: nil")
        }
        let appKids = AX.elements(axOwner, kAXChildrenAttribute as String)
        print("owner app children roles: \(appKids.map { AX.string($0, kAXRoleAttribute as String) ?? "?" })")
        let windows = AX.elements(axOwner, kAXWindowsAttribute as String)
        print("owner windows:")
        for w in windows {
            let f = AX.frame(w)
            print("  \(AX.string(w, kAXRoleAttribute as String) ?? "?")/\(AX.string(w, kAXSubroleAttribute as String) ?? "?")  \(f.map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))×\(Int($0.height)))" } ?? "no frame")")
        }
        let itemKids = AX.elements(item, kAXChildrenAttribute as String)
        print("status item children roles: \(itemKids.map { AX.string($0, kAXRoleAttribute as String) ?? "?" })")

        // Window-server view: every on-screen window the owner has (layer reveals popups).
        if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
            print("CGWindowList rows for pid \(owner.processIdentifier):")
            for w in list where w[kCGWindowOwnerPID as String] as? pid_t == owner.processIdentifier {
                let layer = w[kCGWindowLayer as String] as? Int ?? -1
                let alpha = w[kCGWindowAlpha as String] as? Double ?? -1
                let dict = w[kCGWindowBounds as String] as? NSDictionary
                let b = dict.flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
                print("  layer=\(layer) alpha=\(String(format: "%.1f", alpha)) (\(Int(b.minX)),\(Int(b.minY)) \(Int(b.width))×\(Int(b.height)))")
            }
        }

        // Sweep every running app: who has an AXMenu child on its app element?
        for running in NSWorkspace.shared.runningApplications {
            let ax = AXUIElementCreateApplication(running.processIdentifier)
            AX.setTimeout(ax, seconds: 0.1)
            let kids = AX.elements(ax, kAXChildrenAttribute as String)
            let menus = kids.filter { AX.string($0, kAXRoleAttribute as String) == "AXMenu" }
            guard !menus.isEmpty else { continue }
            print("OPEN MENU in \(running.localizedName ?? "?") (pid \(running.processIdentifier)):")
            for menu in menus {
                let items = AX.elements(menu, kAXChildrenAttribute as String)
                print("  AXMenu with \(items.count) children, frame=\(AX.frame(menu).map(String.init(describing:)) ?? "?")")
                for mi in items.prefix(6) {
                    print("    · \(AX.string(mi, kAXRoleAttribute as String) ?? "?")  \(AX.string(mi, kAXTitleAttribute as String) ?? "")")
                }
            }
        }

        // What does the current finder return for the owner?
        let found = ElementFinder.find(in: owner)
        let menuItems = found.filter { $0.role == "AXMenuItem" }
        print("ElementFinder.find(owner): \(found.count) elements, \(menuItems.count) AXMenuItems")
        for e in menuItems.prefix(8) { print("   · \(e.title ?? "?")") }

        // What click mode now merges in regardless of the frontmost app:
        let open = ElementFinder.openMenuItems(frontApp: owner)
        print("ElementFinder.openMenuItems(): \(open.count) items")
        for e in open.prefix(12) {
            let f = e.axFrame
            print("   · (\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height)))  \(e.title ?? "?")")
        }
        let popupItems = ElementFinder.popupWindowItems()
        print("ElementFinder.popupWindowItems(): \(popupItems.count) items")
        for e in popupItems.prefix(14) {
            let f = e.axFrame
            print("   · \(e.role)  (\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height)))  \(e.title ?? "?")")
        }

        // Close the menu.
        sendEsc()
    }

    /// `kbf --debug-appmenu [itemIndex]` — presses the FRONT app's menu-bar
    /// item (default 1 = the app menu), dumps where the open dropdown lives,
    /// then closes it.
    static func runAppMenu(itemIndex: Int) {
        guard AccessibilityPermission.isTrusted else {
            print("NOT TRUSTED — grant Accessibility to the host process first.")
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication else { print("no front app"); return }
        ElementFinder.prewarmExtras()
        Thread.sleep(forTimeInterval: 1.5)
        let axApp = AXUIElementCreateApplication(front.processIdentifier)
        AX.setTimeout(axApp, seconds: 0.3)
        guard let menuBar = AX.element(axApp, kAXMenuBarAttribute as String) else {
            print("no menu bar for \(front.localizedName ?? "?")"); return
        }
        let items = AX.elements(menuBar, kAXChildrenAttribute as String)
        guard itemIndex < items.count else { print("index \(itemIndex) out of range (\(items.count))"); return }

        // Do CLOSED menu-bar items expose an AXMenu child (and with what frame)?
        print("\(front.localizedName ?? "?") menu bar, CLOSED state:")
        for (i, it) in items.prefix(5).enumerated() {
            let kids = AX.elements(it, kAXChildrenAttribute as String).map {
                "\(AX.string($0, kAXRoleAttribute as String) ?? "?")\(AX.frame($0).map { f in "(\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height)))" } ?? "(no frame)")"
            }
            print("  [\(i)] \(AX.string(it, kAXTitleAttribute as String) ?? "?"): \(kids)")
        }

        let item = items[itemIndex]
        AX.setTimeout(item, seconds: 0.3)
        print("pressing [\(itemIndex)] \(AX.string(item, kAXTitleAttribute as String) ?? "?")…")
        AX.perform(item, "AXPress")
        Thread.sleep(forTimeInterval: 1.0)

        for child in AX.elements(item, kAXChildrenAttribute as String) {
            print("OPEN item child: \(AX.string(child, kAXRoleAttribute as String) ?? "?") frame=\(AX.frame(child).map { f in "(\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height)))" } ?? "?")")
        }
        print("popup windows for pid \(front.processIdentifier):")
        for p in WindowList.popupWindows(excludingPid: pid_t(ProcessInfo.processInfo.processIdentifier))
        where p.pid == front.processIdentifier {
            print("  layer=\(p.layer) (\(Int(p.bounds.minX)),\(Int(p.bounds.minY)) \(Int(p.bounds.width))×\(Int(p.bounds.height)))")
        }
        let open = ElementFinder.openMenuItems(frontApp: front)
        print("ElementFinder.openMenuItems(front): \(open.count) items")
        for e in open.prefix(10) { print("   · \(e.title ?? "?")") }

        sendEsc()
    }

    private static func sendEsc() {
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
        print("sent Esc")
    }

    /// `kbf --debug-windows <AppName>` — walks EVERY AXWindow of the app and
    /// prints a role histogram plus, for roles the finder ignores, samples
    /// with their advertised actions. For diagnosing "this window's contents
    /// don't get labels".
    static func runWindows(appName: String?) {
        guard AccessibilityPermission.isTrusted else {
            print("NOT TRUSTED — grant Accessibility to the host process first.")
            return
        }
        guard let name = appName,
              let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) else {
            print("app \(appName ?? "?") not running")
            return
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AX.setTimeout(axApp, seconds: 0.3)
        let windows = AX.elements(axApp, kAXWindowsAttribute as String)
        print("\(name): \(windows.count) AXWindows")
        for (i, win) in windows.enumerated() {
            let f = AX.frame(win)
            print("window [\(i)] \(AX.string(win, kAXSubroleAttribute as String) ?? "?") \(f.map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))×\(Int($0.height)))" } ?? "no frame")")
            var nodes: [(AXUIElement, String, CGRect?)] = []
            walkAll(win, depth: 0, into: &nodes)
            var roles: [String: Int] = [:]
            for n in nodes { roles[n.1, default: 0] += 1 }
            print("  roles: \(roles.sorted { $0.value > $1.value }.map { "\($0.key):\($0.value)" }.joined(separator: " "))")
            // Sample elements the finder would IGNORE (role not actionable),
            // sized like real controls — print their actions so we can see
            // what role/action combination the app uses.
            var shown = 0
            for (el, role, frame) in nodes where shown < 12 {
                guard !ElementFinder.actionableRoles.contains(role),
                      let fr = frame, fr.width >= 24, fr.height >= 24, fr.width <= 400, fr.height <= 400
                else { continue }
                let actions = AX.actions(el)
                guard role != "AXGroup" || !actions.isEmpty else { continue }   // skip inert layout groups
                let title = AX.string(el, kAXTitleAttribute as String)
                    ?? AX.string(el, kAXDescriptionAttribute as String) ?? ""
                print("  ignored: \(role) (\(Int(fr.minX)),\(Int(fr.minY)) \(Int(fr.width))×\(Int(fr.height))) actions=\(actions.sorted()) \(title)")
                shown += 1
            }
        }
    }

    private static func walkAll(_ el: AXUIElement, depth: Int, into out: inout [(AXUIElement, String, CGRect?)]) {
        if depth > 60 || out.count > 1500 { return }
        let role = AX.string(el, kAXRoleAttribute as String) ?? "?"
        out.append((el, role, AX.frame(el)))
        for c in AX.elements(el, kAXChildrenAttribute as String) {
            walkAll(c, depth: depth + 1, into: &out)
            if out.count > 1500 { return }
        }
    }
}
