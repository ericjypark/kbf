import AppKit

/// `kbf --debug-click <App> <index>` — finds elements, performs a left click on
/// element[index], and reports which path was taken (AXPress vs synthetic) plus
/// cursor movement, so we can see WHY a click does or doesn't register.
enum DebugClick {
    static func run(appName: String?, index: Int) {
        guard AccessibilityPermission.isTrusted else { print("NOT TRUSTED"); return }

        let app: NSRunningApplication?
        if let name = appName {
            let m = NSWorkspace.shared.runningApplications.first { $0.localizedName == name }
            m?.activate(); Thread.sleep(forTimeInterval: 0.7); app = m
        } else { app = NSWorkspace.shared.frontmostApplication }
        guard let app else { print("app not found"); return }

        let elements = ElementFinder.find(in: app)
        print("\(app.localizedName ?? "?"): \(elements.count) elements; clicking index \(index)")
        guard index < elements.count else { print("index out of range"); return }

        let e = elements[index]
        let actions = AX.actions(e.ax).sorted().joined(separator: ",")
        print("  role=\(e.role) title=\(e.title ?? "") frame=\(e.axFrame)")
        print("  axCenter=\(e.axCenter)  cocoaCenter=\(Geometry.axToCocoa(e.axCenter))")
        print("  actions=[\(actions)]")

        let before = NSEvent.mouseLocation
        let outcome = Clicker.perform(.left, on: e)
        Thread.sleep(forTimeInterval: 0.25)
        let after = NSEvent.mouseLocation
        print("  outcome=\(outcome)")
        print("  cursor before=\(Int(before.x)),\(Int(before.y)) after=\(Int(after.x)),\(Int(after.y)) (Cocoa coords)")
    }
}
