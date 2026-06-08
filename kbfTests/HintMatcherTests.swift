import XCTest
import ApplicationServices
@testable import kbf

final class HintMatcherTests: XCTestCase {
    private func element() -> Element {
        Element(ax: AXUIElementCreateApplication(0), role: "AXButton", axFrame: .zero, title: nil)
    }

    func testSingleCharMatch() {
        var m = HintMatcher([("a", element()), ("b", element())])
        guard case .matched = m.input("a") else { return XCTFail("expected match") }
    }

    func testNarrowThenMatch() {
        var m = HintMatcher([("fa", element()), ("fb", element())])
        guard case .narrowed = m.input("f") else { return XCTFail("expected narrowed") }
        guard case .matched = m.input("a") else { return XCTFail("expected match") }
    }

    func testNoMatch() {
        var m = HintMatcher([("a", element())])
        guard case .noMatch = m.input("z") else { return XCTFail("expected noMatch") }
    }

    func testCaseInsensitive() {
        var m = HintMatcher([("a", element())])
        guard case .matched = m.input("A") else { return XCTFail("uppercase should match") }
    }

    func testDeleteLast() {
        var m = HintMatcher([("fa", element())])
        _ = m.input("f")
        XCTAssertEqual(m.typed, "f")
        _ = m.deleteLast()
        XCTAssertEqual(m.typed, "")
    }
}
