import AppKit

/// A session-level CGEventTap that, while running, routes key-down events to a
/// handler which decides whether to swallow them (so typed labels don't reach
/// the focused app). Re-enables itself if the system disables the tap.
final class KeyCaptureTap {
    /// Return `true` to swallow the event. Receives keycode, typed characters, and modifier flags.
    var onKeyDown: ((CGKeyCode, String, CGEventFlags) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let this = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: KeyCaptureTap.callback, userInfo: this) else { return }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), s, .commonModes) }
        tap = nil
        source = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let me = Unmanaged<KeyCaptureTap>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        // Extract the base character with ⌘/⌥/⌃ stripped (keep Shift) so a held
        // modifier — used to choose a click variant — doesn't mangle the hint
        // letter (⌥f would otherwise be "ƒ"). The real flags are passed through.
        let probe = event.copy()
        probe?.flags = event.flags.subtracting([.maskCommand, .maskAlternate, .maskControl])
        (probe ?? event).keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        let chars = String(utf16CodeUnits: buffer, count: length)

        let swallow = me.onKeyDown?(keyCode, chars, event.flags) ?? false
        return swallow ? nil : Unmanaged.passUnretained(event)
    }
}
