import Carbon

/// Keycode→ASCII translation for non-ASCII input sources (Korean, Japanese, …).
///
/// The key tap reads characters through the live layout, so with an IME active
/// the typed hint labels arrive as jamo/kana and never match. Switching the
/// system input source (and reverting on exit) fixes that but is invasive: the
/// revert resets the focused field's IME context, which dismisses popups
/// anchored to inputs. Instead, while a non-ASCII source is active, keys are
/// translated through the user's ASCII-capable layout — the system input
/// source is never touched.
enum InputSource {
    /// The characters this key would produce on the user's ASCII layout, or
    /// nil when the current source already types ASCII (caller uses the event
    /// string as-is — keeps Dvorak/Colemak untouched). Main thread only.
    static func asciiOverrideChars(keyCode: CGKeyCode, shift: Bool) -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              !isASCIICapable(current) else { return nil }
        return translateToASCII(keyCode: keyCode, shift: shift)
    }

    /// 'uchr' data of the most recent ASCII-capable layout, fetched lazily and
    /// kept alive for the process lifetime.
    private static let asciiLayoutData: CFData? = {
        guard let src = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
    }()

    static func translateToASCII(keyCode: CGKeyCode, shift: Bool) -> String? {
        guard let data = asciiLayoutData,
              let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let mods: UInt32 = shift ? UInt32(shiftKey >> 8) : 0
        let err = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDown), mods,
                                 UInt32(LMGetKbdType()), UInt32(1 << kUCKeyTranslateNoDeadKeysBit),
                                 &deadKeys, chars.count, &length, &chars)
        guard err == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    private static func isASCIICapable(_ source: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else { return false }
        return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue() == kCFBooleanTrue
    }
}
