import Carbon

/// Forces an ASCII-capable keyboard layout while a mode is active. The key
/// tap reads characters through the live layout, so a Korean/Japanese/…
/// input source turns typed hint labels into jamo/kana that never match.
/// The user's layout is restored when the mode ends. Main thread only.
enum InputSource {
    private static var saved: TISInputSource?

    /// Switch to the most recent ASCII-capable layout, remembering the
    /// current one. No-op if the current layout already types ASCII
    /// (so Dvorak/Colemak users are left alone).
    static func forceASCII() {
        guard saved == nil,
              let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              !isASCIICapable(current),
              let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue()
        else { return }
        saved = current
        TISSelectInputSource(ascii)
    }

    /// Restore the layout saved by `forceASCII` (no-op if none was switched).
    static func restore() {
        guard let source = saved else { return }
        saved = nil
        TISSelectInputSource(source)
    }

    private static func isASCIICapable(_ source: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue() == kCFBooleanTrue
    }
}
