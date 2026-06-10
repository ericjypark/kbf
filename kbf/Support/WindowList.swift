import CoreGraphics
import Foundation

/// Queries the window server for windows on the ACTIVE Space. Used to avoid
/// labeling a frontmost app whose focused window lives on another Space —
/// ⌘Tab can switch apps without (or before) switching Spaces, and painting
/// that window's labels over the current desktop is nonsense.
enum WindowList {
    struct Info {
        let pid: pid_t
        let layer: Int
        let bounds: CGRect
        var alpha: Double = 1
    }

    /// Windows smaller than this are menu-bar chrome (status-item icons are
    /// ~38×39), not real windows or popups.
    private static let minSize = CGSize(width: 50, height: 50)

    /// True when `pid` owns a real-sized window on the active Space that
    /// intersects `frame` (top-left-origin global coords, same space as AX).
    /// Any layer counts — Control Center-style popups are elevated windows.
    static func hasOnScreenWindow(pid: pid_t, near frame: CGRect) -> Bool {
        hasOnScreenWindow(pid: pid, near: frame, in: onScreenWindows())
    }

    static func hasOnScreenWindow(pid: pid_t, near frame: CGRect, in windows: [Info]) -> Bool {
        windows.contains {
            $0.pid == pid && $0.bounds.width >= minSize.width && $0.bounds.height >= minSize.height
                && $0.bounds.intersects(frame)
        }
    }

    /// Open popups on the active Space: visible windows ABOVE the normal layer
    /// with real size — Control Center popovers (battery, Wi-Fi, Now Playing),
    /// floating panels hung off status items.
    static func popupWindows(excludingPid own: pid_t) -> [Info] {
        popupWindows(in: onScreenWindows(), excludingPid: own)
    }

    static func popupWindows(in windows: [Info], excludingPid own: pid_t) -> [Info] {
        windows.filter {
            $0.pid != own && $0.layer > 0 && $0.alpha > 0
                && $0.bounds.width >= minSize.width && $0.bounds.height >= minSize.height
        }
    }

    private static func onScreenWindows() -> [Info] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = w[kCGWindowLayer as String] as? Int,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { return nil }
            return Info(pid: pid, layer: layer, bounds: bounds,
                        alpha: w[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }
}
