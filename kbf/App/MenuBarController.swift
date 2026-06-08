import AppKit

/// Owns the menu-bar status item and its dropdown.
final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onTriggerClick: () -> Void
    private let onTriggerScroll: () -> Void
    private let onTriggerSearch: () -> Void
    private let onOpenPreferences: () -> Void

    init(onTriggerClick: @escaping () -> Void,
         onTriggerScroll: @escaping () -> Void,
         onTriggerSearch: @escaping () -> Void,
         onOpenPreferences: @escaping () -> Void) {
        self.onTriggerClick = onTriggerClick
        self.onTriggerScroll = onTriggerScroll
        self.onTriggerSearch = onTriggerSearch
        self.onOpenPreferences = onOpenPreferences
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: "kbf")
            button.image?.isTemplate = true
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let header = menu.addItem(withTitle: "kbf", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(.separator())

        let click = menu.addItem(withTitle: "Click Mode  (⌥Space)", action: #selector(triggerClick), keyEquivalent: "")
        click.target = self
        let scroll = menu.addItem(withTitle: "Scroll Mode  (⌥⇧Space)", action: #selector(triggerScroll), keyEquivalent: "")
        scroll.target = self
        let search = menu.addItem(withTitle: "Search Mode  (⌥/)", action: #selector(triggerSearch), keyEquivalent: "")
        search.target = self

        if !AccessibilityPermission.isTrusted {
            menu.addItem(.separator())
            let warn = menu.addItem(withTitle: "⚠︎ Grant Accessibility access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            warn.target = self
        }

        menu.addItem(.separator())
        let prefs = menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit kbf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func triggerClick() { onTriggerClick() }
    @objc private func triggerScroll() { onTriggerScroll() }
    @objc private func triggerSearch() { onTriggerSearch() }

    @objc private func openPreferences() { onOpenPreferences() }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.prompt()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
