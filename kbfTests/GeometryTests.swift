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
}
