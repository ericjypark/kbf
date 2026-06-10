import CoreGraphics
import Foundation

/// Queries the window server for windows on the ACTIVE Space. Used to avoid
/// labeling a frontmost app whose focused window lives on another Space —
/// ⌘Tab can switch apps without (or before) switching Spaces, and painting
/// that window's labels over the current desktop is nonsense.
enum WindowList {
    struct Info { let pid: pid_t; let layer: Int; let bounds: CGRect }

    /// True when `pid` owns a normal-layer window on the active Space that
    /// intersects `frame` (top-left-origin global coords, same space as AX).
    static func hasOnScreenWindow(pid: pid_t, near frame: CGRect) -> Bool {
        hasOnScreenWindow(pid: pid, near: frame, in: onScreenWindows())
    }

    static func hasOnScreenWindow(pid: pid_t, near frame: CGRect, in windows: [Info]) -> Bool {
        windows.contains { $0.pid == pid && $0.layer == 0 && $0.bounds.intersects(frame) }
    }

    private static func onScreenWindows() -> [Info] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = w[kCGWindowLayer as String] as? Int,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return nil }
            return Info(pid: pid, layer: layer, bounds: bounds)
        }
    }
}
