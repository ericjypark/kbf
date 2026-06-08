import XCTest
@testable import kbf

final class FuzzyMatchTests: XCTestCase {
    func testEmptyQueryScoresZero() {
        XCTAssertEqual(FuzzyMatch.score("", in: "anything"), 0)
    }

    func testSubstringBeatsSubsequence() {
        let substring = FuzzyMatch.score("set", in: "Settings")
        let subsequence = FuzzyMatch.score("stg", in: "Settings")
        XCTAssertNotNil(substring)
        XCTAssertNotNil(subsequence)
        XCTAssertGreaterThan(substring!, subsequence!)
    }

    func testPrefixBeatsLaterMatch() {
        let early = FuzzyMatch.score("se", in: "Settings")
        let late = FuzzyMatch.score("ng", in: "Settings")
        XCTAssertGreaterThan(early!, late!)
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(FuzzyMatch.score("xyz", in: "Settings"))
    }

    func testCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatch.score("SET", in: "settings"))
    }
}
