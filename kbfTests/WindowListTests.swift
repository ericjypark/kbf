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

    func testNonNormalLayerDoesNotCount() {
        // Status items / overlays live on non-zero layers.
        let windows = [WindowList.Info(pid: 42, layer: 25, bounds: chrome)]
        XCTAssertFalse(WindowList.hasOnScreenWindow(pid: 42, near: chrome, in: windows))
    }

    func testNonIntersectingWindowDoesNotCount() {
        let elsewhere = CGRect(x: 5000, y: 100, width: 1200, height: 800)
        let windows = [WindowList.Info(pid: 42, layer: 0, bounds: elsewhere)]
        XCTAssertFalse(WindowList.hasOnScreenWindow(pid: 42, near: chrome, in: windows))
    }

    func testEmptyListMeansOffScreen() {
        XCTAssertFalse(WindowList.hasOnScreenWindow(pid: 42, near: chrome, in: []))
    }
}
