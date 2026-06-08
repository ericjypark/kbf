import AppKit

/// `kbf --demo-search` shows the search bar with sample content for a few
/// seconds so its design can be screenshotted and iterated on.
enum DemoSearch {
    private static var bar: SearchBar?
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let b = SearchBar()
        b.show()
        b.update(query: "Settings", count: 7)
        bar = b
        Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in NSApp.terminate(nil) }
        app.run()
    }
}
