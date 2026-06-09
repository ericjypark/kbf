import AppKit
import Carbon.HIToolbox
import Combine

/// A global hotkey stored as a key code + Carbon modifier mask.
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon: cmdKey, shiftKey, optionKey, controlKey

    /// Build from a Cocoa NSEvent (used by the recorder).
    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var m: UInt32 = 0
        if event.modifierFlags.contains(.command) { m |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { m |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { m |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { m |= UInt32(shiftKey) }
        modifiers = m
    }

    /// Human-readable, e.g. "⌥Space".
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + KeyName.of(keyCode)
    }
}

/// Persisted, observable user settings. (Named `AppSettings` to avoid colliding
/// with SwiftUI's `Settings` scene type.)
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var clickHotkey: Hotkey { didSet { write(clickHotkey, "clickHotkey") } }
    @Published var scrollHotkey: Hotkey { didSet { write(scrollHotkey, "scrollHotkey") } }
    @Published var searchHotkey: Hotkey { didSet { write(searchHotkey, "searchHotkey") } }
    @Published var alphabet: String { didSet { defaults.set(alphabet, forKey: "alphabet") } }
    @Published var launchAtLogin: Bool { didSet { LaunchAtLogin.set(launchAtLogin) } }
    /// Pixels per h/j/k/l press, and per ⇧-dash press.
    @Published var scrollStep: Double { didSet { defaults.set(scrollStep, forKey: "scrollStep") } }
    @Published var scrollDash: Double { didSet { defaults.set(scrollDash, forKey: "scrollDash") } }

    static let defaultScrollStep = 90.0
    static let defaultScrollDash = 360.0

    private init() {
        clickHotkey = Self.read("clickHotkey", default: Hotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)))
        scrollHotkey = Self.read("scrollHotkey", default: Hotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey)))
        searchHotkey = Self.read("searchHotkey", default: Hotkey(keyCode: UInt32(kVK_ANSI_Slash), modifiers: UInt32(optionKey)))
        alphabet = defaults.string(forKey: "alphabet") ?? String(LabelMaker.defaultAlphabet)
        launchAtLogin = LaunchAtLogin.isEnabled
        let step = defaults.double(forKey: "scrollStep")
        scrollStep = step > 0 ? step : Self.defaultScrollStep
        let dash = defaults.double(forKey: "scrollDash")
        scrollDash = dash > 0 ? dash : Self.defaultScrollDash
    }

    /// Alphabet as a clean character array (deduped, letters only, order preserved),
    /// falling back to the default if too short.
    var alphabetChars: [Character] {
        var seen = Set<Character>(), out: [Character] = []
        for c in alphabet.lowercased() where c.isLetter && seen.insert(c).inserted { out.append(c) }
        return out.count >= 2 ? out : LabelMaker.defaultAlphabet
    }

    private func write(_ hk: Hotkey, _ key: String) {
        if let data = try? JSONEncoder().encode(hk) { defaults.set(data, forKey: key) }
    }
    private static func read(_ key: String, default fallback: Hotkey) -> Hotkey {
        guard let data = UserDefaults.standard.data(forKey: key),
              let hk = try? JSONDecoder().decode(Hotkey.self, from: data) else { return fallback }
        return hk
    }
}
