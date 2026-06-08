import XCTest
@testable import kbf

final class LabelMakerTests: XCTestCase {
    func testCountAndUniqueness() {
        for n in [1, 5, 26, 50, 200, 999] {
            let labels = LabelMaker.labels(n)
            XCTAssertEqual(labels.count, n)
            XCTAssertEqual(Set(labels).count, n, "labels must be unique for n=\(n)")
        }
    }

    func testPrefixFree() {
        for n in [5, 50, 200, 999] {
            let labels = LabelMaker.labels(n)
            let set = Set(labels)
            for l in labels {
                var prefix = ""
                for c in l.dropLast() {
                    prefix.append(c)
                    XCTAssertFalse(set.contains(prefix), "\(prefix) is a prefix of \(l)")
                }
            }
        }
    }

    func testNoEmptyLabels() {
        XCTAssertTrue(LabelMaker.labels(100).allSatisfy { !$0.isEmpty })
    }

    func testCustomAlphabet() {
        let labels = LabelMaker.labels(4, alphabet: Array("ab"))
        XCTAssertEqual(labels.count, 4)
        XCTAssertTrue(labels.allSatisfy { $0.allSatisfy { "ab".contains($0) } })
    }

    func testZeroCount() {
        XCTAssertTrue(LabelMaker.labels(0).isEmpty)
    }
}
