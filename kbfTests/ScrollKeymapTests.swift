import XCTest
@testable import kbf

final class ScrollKeymapTests: XCTestCase {
    func testVimDirections() {
        XCTAssertEqual(ScrollKeymap.command(for: "h", shift: false), .scroll(dx: 1, dy: 0))
        XCTAssertEqual(ScrollKeymap.command(for: "j", shift: false), .scroll(dx: 0, dy: -1))
        XCTAssertEqual(ScrollKeymap.command(for: "k", shift: false), .scroll(dx: 0, dy: 1))
        XCTAssertEqual(ScrollKeymap.command(for: "l", shift: false), .scroll(dx: -1, dy: 0))
    }

    func testShiftIsDash() {
        XCTAssertEqual(ScrollKeymap.command(for: "j", shift: true), .dash(dx: 0, dy: -1))
        XCTAssertEqual(ScrollKeymap.command(for: "k", shift: true), .dash(dx: 0, dy: 1))
    }

    func testHalfPageAndEdges() {
        XCTAssertEqual(ScrollKeymap.command(for: "d", shift: false), .halfPage(down: true))
        XCTAssertEqual(ScrollKeymap.command(for: "u", shift: false), .halfPage(down: false))
        XCTAssertEqual(ScrollKeymap.command(for: "g", shift: false), .edge(top: true))
        XCTAssertEqual(ScrollKeymap.command(for: "g", shift: true), .edge(top: false))
    }

    func testAreaJumpDigits() {
        XCTAssertEqual(ScrollKeymap.command(for: "1", shift: false), .jumpArea(0))
        XCTAssertEqual(ScrollKeymap.command(for: "9", shift: false), .jumpArea(8))
        XCTAssertNil(ScrollKeymap.command(for: "0", shift: false))
    }

    func testUppercaseTreatedAsShifted() {
        // The tap delivers shifted chars uppercased; mapping must be case-insensitive.
        XCTAssertEqual(ScrollKeymap.command(for: "J", shift: true), .dash(dx: 0, dy: -1))
    }

    func testUnknownIsNil() {
        XCTAssertNil(ScrollKeymap.command(for: "z", shift: false))
        XCTAssertNil(ScrollKeymap.command(for: " ", shift: false))
    }
}
