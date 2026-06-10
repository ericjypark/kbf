import XCTest
@testable import kbf

final class WindowListTests: XCTestCase {
    private let chrome = CGRect(x: 100, y: 100, width: 1200, height: 800)

    func testMatchingWindowOnActiveSpace() {
        let windows = [WindowList.Info(pid: 42, layer: 0, bounds: chrome)]
        XCTAssertTrue(WindowList.hasOnScreenWindow(pid: 42, near: chrome, in: windows))
    }

    func testOtherAppsWindowDoesNotCount() {
        let windows = [WindowList.Info(pid: 7, layer: 0, bounds: chrome)]
        XCTAssertFalse(WindowList.hasOnScreenWindow(pid: 42, near: chrome, in: windows))
    }

    func testElevatedPopupWindowCounts() {
        // Control Center's battery popover is an elevated-layer window.
        let popup = CGRect(x: 1617, y: 0, width: 570, height: 1246)
        let windows = [WindowList.Info(pid: 42, layer: 100, bounds: popup)]
        XCTAssertTrue(WindowList.hasOnScreenWindow(pid: 42, near: popup, in: windows))
    }

    func testTinyMenuBarWindowDoesNotCount() {
        // A status-item icon (~38×39) is menu-bar chrome, not a real window.
        let icon = CGRect(x: 1683, y: 0, width: 38, height: 39)
        let windows = [WindowList.Info(pid: 42, layer: 25, bounds: icon)]
        XCTAssertFalse(WindowList.hasOnScreenWindow(pid: 42, near: icon, in: windows))
    }

    func testNonIntersectingWindowDoesNotCount() {
        let elsewhere = CGRect(x: 5000, y: 100, width: 1200, height: 800)
        let windows = [WindowList.Info(pid: 42, layer: 0, bounds: elsewhere)]
        XCTAssertFalse(WindowList.hasOnScreenWindow(pid: 42, near: chrome, in: windows))
    }

    func testEmptyListMeansOffScreen() {
        XCTAssertFalse(WindowList.hasOnScreenWindow(pid: 42, near: chrome, in: []))
    }

    func testPopupWindowsFilter() {
        let windows = [
            WindowList.Info(pid: 620, layer: 100, bounds: CGRect(x: 1617, y: 0, width: 570, height: 1246)),  // CC popover
            WindowList.Info(pid: 620, layer: 25, bounds: CGRect(x: 1683, y: 0, width: 38, height: 39)),      // status icon
            WindowList.Info(pid: 620, layer: 500, bounds: CGRect(x: 1407, y: 0, width: 46, height: 39), alpha: 0),
            WindowList.Info(pid: 99, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1200, height: 800)),        // normal window
            WindowList.Info(pid: 7, layer: 101, bounds: CGRect(x: 50, y: 50, width: 300, height: 400)),      // own overlay
        ]
        let popups = WindowList.popupWindows(in: windows, excludingPid: 7)
        XCTAssertEqual(popups.count, 1)
        XCTAssertEqual(popups.first?.pid, 620)
        XCTAssertEqual(popups.first?.layer, 100)
    }
}
