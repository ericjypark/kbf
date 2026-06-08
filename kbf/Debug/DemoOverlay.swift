import AppKit

/// `kbf --demo [AppName]` activates an app, draws the hint overlay over it for a
/// few seconds, then exits. Used to visually verify label placement / coordinates.
enum DemoOverlay {
    private static var overlay: OverlayWindowController?

    static func run(appName: String?) {
        guard AccessibilityPermission.isTrusted else {
            print("NOT TRUSTED — grant Accessibility first."); return
        }

        let nsApp = NSApplication.shared
        nsApp.setActivationPolicy(.accessory)

        let app: NSRunningApplication?
        if let name = appName {
            let match = NSWorkspace.shared.runningApplications.first { $0.localizedName == name }
            match?.activate()
            Thread.sleep(forTimeInterval: 0.7)
            app = match
        } else {
            app = NSWorkspace.shared.frontmostApplication
        }
        guard let app else { print("app not found"); return }

        let elements = ElementFinder.find(in: app)
        let labels = LabelMaker.labels(elements.count)
        let assignments = zip(labels, elements).map { (label: $0, element: $1) }
        let o = OverlayWindowController()
        o.show(assignments)
        o.update(typed: "")
        overlay = o
        print("demo: \(elements.count) hints over \(app.localizedName ?? "?") for 3s")

        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in NSApp.terminate(nil) }
        nsApp.run()
    }
}
