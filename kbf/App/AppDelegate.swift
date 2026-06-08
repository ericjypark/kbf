import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private let mode = ModeController()
    private let hotKeys = HotKeyManager()
    private let prefs = PreferencesWindowController()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When hosting unit tests, skip normal startup (no hotkeys/menu side effects).
        if NSClassFromString("XCTestCase") != nil { return }
        Log.find.log("launch: trusted=\(AccessibilityPermission.isTrusted, privacy: .public)")
        if !AccessibilityPermission.isTrusted {
            AccessibilityPermission.prompt()
        }

        registerHotkeys()
        // Re-register whenever a hotkey setting changes (async so values are updated).
        AppSettings.shared.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.registerHotkeys() } }
            .store(in: &cancellables)

        menuBar = MenuBarController(
            onTriggerClick: { [weak self] in self?.mode.enterClick() },
            onTriggerScroll: { [weak self] in self?.mode.enterScroll() },
            onTriggerSearch: { [weak self] in self?.mode.enterSearch() },
            onOpenPreferences: { [weak self] in self?.prefs.show() })
    }

    private func registerHotkeys() {
        let s = AppSettings.shared
        hotKeys.register(id: 1, keyCode: s.clickHotkey.keyCode, modifiers: s.clickHotkey.modifiers) { [weak self] in
            self?.mode.toggleClick()
        }
        hotKeys.register(id: 2, keyCode: s.scrollHotkey.keyCode, modifiers: s.scrollHotkey.modifiers) { [weak self] in
            self?.mode.enterScroll()
        }
        hotKeys.register(id: 3, keyCode: s.searchHotkey.keyCode, modifiers: s.searchHotkey.modifiers) { [weak self] in
            self?.mode.enterSearch()
        }
    }
}
