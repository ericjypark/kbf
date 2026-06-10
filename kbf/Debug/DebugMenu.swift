import AppKit
import ApplicationServices

/// `kbf --debug-menu <AppName>` — reproduction harness for "open menu items
/// aren't labeled": programmatically opens the app's status-item menu, dumps
/// what the finder (and the AX focus attributes) see, then closes the menu.
enum DebugMenu {
    static func run(appName: String?) {
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
        guard let extras = AX.element(axOwner, "AXExtrasMenuBar"),
              let item = AX.elements(extras, kAXChildrenAttribute as String).first else {
            print("no status item for \(name)")
            return
        }
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
        print("owner windows: \(windows.map { "\(AX.string($0, kAXRoleAttribute as String) ?? "?")/\(AX.string($0, kAXSubroleAttribute as String) ?? "?")" })")
        let itemKids = AX.elements(item, kAXChildrenAttribute as String)
        print("status item children roles: \(itemKids.map { AX.string($0, kAXRoleAttribute as String) ?? "?" })")

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
        let open = ElementFinder.openMenuItems()
        print("ElementFinder.openMenuItems(): \(open.count) items")
        for e in open.prefix(12) {
            let f = e.axFrame
            print("   · (\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height)))  \(e.title ?? "?")")
        }

        // Close the menu.
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
        print("sent Esc")
    }
}
