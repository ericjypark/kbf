import ApplicationServices

/// Gate for the Accessibility permission kbf needs to read other apps and click.
enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Triggers the system prompt + adds kbf to the Accessibility list (greyed until enabled).
    @discardableResult
    static func prompt() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
}
