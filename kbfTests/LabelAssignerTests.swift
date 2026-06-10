import ApplicationServices
import XCTest
@testable import kbf

final class LabelAssignerTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let alphabet = LabelAssigner.defaultAlphabet

    private func element(x: CGFloat, y: CGFloat, role: String = "AXButton") -> Element {
        Element(ax: AXUIElementCreateApplication(0), role: role,
                axFrame: CGRect(x: x, y: y, width: 40, height: 24), title: nil)
    }

    /// Spread-out fixtures (collisions unlikely), within `screen`.
    private func grid(_ n: Int) -> [Element] {
        (0..<n).map { element(x: CGFloat($0 % 20) * 120, y: CGFloat($0 / 20) * 90) }
    }

    private func assign(_ els: [Element]) -> [(label: String, element: Element)] {
        LabelAssigner.assign(els, alphabet: alphabet, bounds: screen)
    }

    // MARK: ergonomic model (pool feeds the overflow tier and validates scoring)

    func testPoolIsTwoCharUniqueAndUsesAlphabetOnly() {
        let pool = LabelAssigner.pool(alphabet: alphabet)
        XCTAssertGreaterThan(pool.count, 300)
        XCTAssertEqual(Set(pool).count, pool.count)
        let allowed = Set(alphabet)
        for label in pool {
            XCTAssertEqual(label.count, 2)
            XCTAssertTrue(label.allSatisfy { allowed.contains($0) })
        }
    }

    func testPoolCullsSameFingerReaches() {
        let pool = Set(LabelAssigner.pool(alphabet: alphabet))
        for bad in ["fr", "ft", "fg", "fv", "rf", "ki", "ol"] {
            XCTAssertFalse(pool.contains(bad), "\(bad) is a same-finger reach")
        }
        for good in ["fj", "jf", "ff", "jj", "dk", "kd"] {
            XCTAssertTrue(pool.contains(good), "\(good) should be in the pool")
        }
    }

    func testHardReachKeysNeverAppearInAnyLabel() {
        let hard: Set<Character> = ["q", "p", "b", "x", "z"]
        for label in LabelAssigner.pool(alphabet: alphabet) {
            XCTAssertTrue(label.allSatisfy { !hard.contains($0) }, "\(label) uses a hard-reach key")
        }
        for first in LabelAssigner.firstChars(alphabet) {
            XCTAssertFalse(hard.contains(first))
            for second in LabelAssigner.secondChars(for: first, alphabet: alphabet) {
                XCTAssertFalse(hard.contains(second))
            }
        }
    }

    func testSecondCharsPreferErgonomicPartners() {
        // For an 'f' band, the easiest partners are right-hand home keys.
        let seconds = LabelAssigner.secondChars(for: "f", alphabet: alphabet)
        XCTAssertEqual(seconds.first, "j")
        // Same-finger partners of f are culled outright.
        for culled in ["r", "t", "g", "v"] {
            XCTAssertFalse(seconds.contains(Character(culled)))
        }
    }

    // MARK: spatial pattern

    func testTopLeftStartsAtTheFirstLetter() {
        let labels = assign([element(x: 40, y: 30)])
        XCTAssertEqual(labels.first?.label.first, LabelAssigner.firstChars(alphabet).first)
        XCTAssertEqual(labels.first?.label.first, "a")
    }

    func testFirstCharGrowsAlphabeticallyRightAndDown() {
        let acrossTop = assign([element(x: 40, y: 30), element(x: 1300, y: 30), element(x: 2500, y: 30)])
            .map { $0.label.first! }
        XCTAssertTrue(acrossTop == acrossTop.sorted() && Set(acrossTop).count == 3,
                      "left→right must grow alphabetically: \(acrossTop)")
        let downLeft = assign([element(x: 40, y: 30), element(x: 40, y: 700), element(x: 40, y: 1400)])
            .map { $0.label.first! }
        XCTAssertTrue(downLeft == downLeft.sorted() && Set(downLeft).count == 3,
                      "top→bottom must grow alphabetically: \(downLeft)")
    }

    func testSameRegionSharesFirstChar() {
        let labels = assign([element(x: 40, y: 30), element(x: 120, y: 60)]).map(\.label)
        XCTAssertEqual(labels[0].first, labels[1].first)
        XCTAssertNotEqual(labels[0], labels[1])
    }

    // MARK: assignment

    func testAssignReturnsUniqueLabelsInInputOrder() {
        let els = grid(120)
        let result = assign(els)
        XCTAssertEqual(result.count, els.count)
        XCTAssertEqual(Set(result.map(\.label)).count, els.count)
        for (i, r) in result.enumerated() {
            XCTAssertEqual(r.element.axFrame, els[i].axFrame, "input order must be preserved")
        }
    }

    func testSamePositionGetsSameLabelAcrossRuns() {
        let els = grid(80)
        XCTAssertEqual(assign(els).map(\.label), assign(els).map(\.label))
    }

    func testLabelSurvivesReorderingAndOtherElementsChanging() {
        let els = grid(60)
        let full = assign(els)
        // Same elements, shuffled order → same label per position.
        let shuffledIdx = Array(els.indices.reversed())
        let shuffled = assign(shuffledIdx.map { els[$0] })
        for (pos, idx) in shuffledIdx.enumerated() {
            XCTAssertEqual(shuffled[pos].label, full[idx].label, "label must follow the position")
        }
        // Realistic drift — 10% of elements disappear → survivors overwhelmingly
        // keep their labels. (A survivor that was hash-colliding with a removed
        // element may re-home within its region — unavoidable for unique labels —
        // but must stay rare.)
        let survivors = els.enumerated().filter { $0.offset % 10 != 0 }.map(\.element)
        let drifted = assign(survivors)
        var kept = 0
        for (pos, survivor) in survivors.enumerated() {
            let original = full.first { $0.element.axFrame == survivor.axFrame }!
            if drifted[pos].label == original.label { kept += 1 }
        }
        XCTAssertGreaterThanOrEqual(Double(kept), Double(survivors.count) * 0.9,
                                    "only \(kept)/\(survivors.count) survivors kept their label")
    }

    func testSmallPositionDriftKeepsLabel() {
        let a = assign([element(x: 100, y: 100)])
        let b = assign([element(x: 104, y: 102)])
        XCTAssertEqual(a.first?.label, b.first?.label)
    }

    func testCollidingElementsGetDistinctLabelsDeterministically() {
        let els = [element(x: 100, y: 100), element(x: 100, y: 100)]
        let a = assign(els)
        XCTAssertEqual(Set(a.map(\.label)).count, 2)
        XCTAssertEqual(a.map(\.label), assign(els).map(\.label))
    }

    func testOverflowStaysPrefixFreeAndUnique() {
        let labels = assign(grid(700)).map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count)
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
