import ApplicationServices

/// Thin, typed wrappers over the C Accessibility (AXUIElement) API.
enum AX {
    // MARK: attribute reads
    static func value(_ el: AXUIElement, _ attr: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
    }

    static func string(_ el: AXUIElement, _ attr: String) -> String? { value(el, attr) as? String }

    static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        guard let v = value(el, attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
        (value(el, attr) as? [AXUIElement]) ?? []
    }

    /// Element frame in AX global coordinates (top-left origin, y down).
    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let posV = value(el, kAXPositionAttribute as String),
              let sizeV = value(el, kAXSizeAttribute as String),
              CFGetTypeID(posV) == AXValueGetTypeID(),
              CFGetTypeID(sizeV) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(posV as! AXValue, .cgPoint, &p)
        AXValueGetValue(sizeV as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    /// Batch-fetch several attributes in ONE IPC round-trip. Returns a parallel
    /// array (nil where an attribute is missing/errored). Far cheaper than N reads.
    static func values(_ el: AXUIElement, _ attrs: [String]) -> [AnyObject?] {
        var out: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(el, attrs as CFArray, AXCopyMultipleAttributeOptions(), &out)
        guard err == .success, let arr = out as? [AnyObject], arr.count == attrs.count else {
            return Array(repeating: nil, count: attrs.count)
        }
        return arr.map { v in
            if CFGetTypeID(v) == AXValueGetTypeID(), AXValueGetType(v as! AXValue) == .axError { return nil }
            return v is NSNull ? nil : v
        }
    }

    static func cgPoint(_ v: AnyObject?) -> CGPoint? {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    static func cgSize(_ v: AnyObject?) -> CGSize? {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    static func rect(_ pos: AnyObject?, _ size: AnyObject?) -> CGRect? {
        guard let p = cgPoint(pos), let s = cgSize(size) else { return nil }
        return CGRect(origin: p, size: s)
    }

    static func actions(_ el: AXUIElement) -> Set<String> {
        var arr: CFArray?
        guard AXUIElementCopyActionNames(el, &arr) == .success, let a = arr as? [String] else { return [] }
        return Set(a)
    }

    // MARK: mutations
    @discardableResult
    static func perform(_ el: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(el, action as CFString) == .success
    }

    @discardableResult
    static func setValue(_ el: AXUIElement, _ attr: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(el, attr as CFString, value) == .success
    }

    static func setTimeout(_ el: AXUIElement, seconds: Float) {
        AXUIElementSetMessagingTimeout(el, seconds)
    }
}
