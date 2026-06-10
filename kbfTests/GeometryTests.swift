import XCTest
@testable import kbf

final class GeometryTests: XCTestCase {
    func testAXCocoaRoundTrip() {
        let r = CGRect(x: 100, y: 200, width: 50, height: 30)
        let back = Geometry.cocoaToAX(Geometry.axToCocoa(r))
        XCTAssertEqual(back.origin.x, r.origin.x, accuracy: 0.01)
        XCTAssertEqual(back.origin.y, r.origin.y, accuracy: 0.01)
        XCTAssertEqual(back.width, r.width, accuracy: 0.01)
        XCTAssertEqual(back.height, r.height, accuracy: 0.01)
    }

    func testFlipPreservesWidthAndHeight() {
        let r = CGRect(x: 10, y: 20, width: 80, height: 40)
        let cocoa = Geometry.axToCocoa(r)
        XCTAssertEqual(cocoa.width, r.width, accuracy: 0.01)
        XCTAssertEqual(cocoa.height, r.height, accuracy: 0.01)
        XCTAssertEqual(cocoa.minX, r.minX, accuracy: 0.01)
    }

    func testCenterVisible() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        // Auto-hidden Dock tile: frame hangs almost entirely below the screen.
        XCTAssertFalse(Geometry.centerVisible(CGRect(x: 800, y: 1436, width: 64, height: 64), in: screen))
        // Visible Dock tile: bottom edge dips a few px past the screen edge.
        XCTAssertTrue(Geometry.centerVisible(CGRect(x: 800, y: 1380, width: 64, height: 64), in: screen))
        // Menu bar item: fully on-screen.
        XCTAssertTrue(Geometry.centerVisible(CGRect(x: 2000, y: 0, width: 30, height: 24), in: screen))
        // Fully off-screen.
        XCTAssertFalse(Geometry.centerVisible(CGRect(x: -200, y: 100, width: 50, height: 50), in: screen))
    }
}
