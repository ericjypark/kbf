import AppKit
import SwiftUI

/// Hosts the SwiftUI preferences in a dark, frameless-ish window. Because kbf is
/// an accessory (menu-bar) app, opening the window activates the app so its
/// controls can take focus; closing it returns to the background.
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingView(rootView: PreferencesView())
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.isMovableByWindowBackground = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1.0)
            w.contentView = host
            w.isReleasedWhenClosed = false
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Return focus to the previously active app.
        NSApp.hide(nil)
    }
}
