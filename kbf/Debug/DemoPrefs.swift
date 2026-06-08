import AppKit

/// `kbf --demo-prefs` opens the preferences window for a few seconds so its
/// design can be screenshotted.
enum DemoPrefs {
    private static var controller: PreferencesWindowController?
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let c = PreferencesWindowController()
        c.show()
        controller = c
        Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { _ in NSApp.terminate(nil) }
        app.run()
    }
}
