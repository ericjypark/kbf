import AppKit

/// Headless validation: `kbf --debug-dump [AppName]` prints the actionable
/// elements kbf finds in an app's frontmost window. Used to verify the finder
/// without any UI. Defaults to the frontmost app.
enum DebugDump {
    static func run(appName: String?) {
        guard AccessibilityPermission.isTrusted else {
            print("NOT TRUSTED — grant Accessibility to the host process in")
            print("System Settings → Privacy & Security → Accessibility, then re-run.")
            AccessibilityPermission.prompt()
            return
        }

        let app: NSRunningApplication?
        if let name = appName {
            let match = NSWorkspace.shared.runningApplications.first { $0.localizedName == name }
            match?.activate()
            Thread.sleep(forTimeInterval: 0.7)
            app = match
        } else {
            app = NSWorkspace.shared.frontmostApplication
        }

        guard let app else { print("app \(appName ?? "?") not running"); return }

        let screens = NSScreen.screens.map {
            "[\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))×\(Int($0.frame.height)) @\($0.backingScaleFactor)x]"
        }.joined(separator: " ")
        print("screens: \(screens)")

        let start = Date()
        var diag = ElementFinder.Diagnostics(rawCount: 0, rawRoles: [:], pressableCount: 0)
        let elements = ElementFinder.find(in: app, diagnostics: &diag)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("\(app.localizedName ?? "?") (pid \(app.processIdentifier)): \(elements.count) actionable / \(diag.rawCount) raw (\(diag.pressableCount) pressable) in \(ms)ms")
        let roleHist = diag.rawRoles.sorted { $0.value > $1.value }.prefix(10)
            .map { "\($0.key):\($0.value)" }.joined(separator: " ")
        print("  raw roles: \(roleHist)")
        for (i, e) in elements.prefix(50).enumerated() {
            let f = e.axFrame
            let frameStr = "(\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height)))"
            print(String(format: "  [%2d] %-18@ %@  %@", i,
                         e.role as NSString, frameStr as NSString,
                         (e.title ?? "") as NSString))
        }
        if elements.count > 50 { print("  … and \(elements.count - 50) more") }

        let mbStart = Date()
        let extras = ElementFinder.menuBarAndDock(frontApp: app)
        print("menu bar + dock: \(extras.count) in \(Int(Date().timeIntervalSince(mbStart) * 1000))ms")
        for e in extras.prefix(24) {
            let f = e.axFrame
            print("  \(e.role.padding(toLength: 14, withPad: " ", startingAt: 0)) (\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height)))  \(e.title ?? "")")
        }

        let areas = ElementFinder.scrollAreas(in: app)
        print("scroll areas: \(areas.count)")
        for a in areas.prefix(5) {
            let f = a.axFrame
            print("  \(a.role) (\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height)))")
        }
    }
}
