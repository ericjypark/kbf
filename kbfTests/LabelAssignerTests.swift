import ApplicationServices
import XCTest
@testable import kbf

final class LabelAssignerTests: XCTestCase {
    private func element(x: CGFloat, y: CGFloat, role: String = "AXButton") -> Element {
        Element(ax: AXUIElementCreateApplication(0), role: role,
                axFrame: CGRect(x: x, y: y, width: 40, height: 24), title: nil)
    }

    /// Spread-out fixtures (collisions vanishingly unlikely).
    private func grid(_ n: Int) -> [Element] {
        (0..<n).map { element(x: CGFloat($0 % 20) * 120, y: CGFloat($0 / 20) * 90) }
    }

    // MARK: pool

    func testPoolIsTwoCharUniqueAndUsesAlphabetOnly() {
        let pool = LabelAssigner.pool(alphabet: LabelAssigner.defaultAlphabet)
        XCTAssertGreaterThan(pool.count, 300)
        XCTAssertEqual(Set(pool).count, pool.count)
        let allowed = Set(LabelAssigner.defaultAlphabet)
        for label in pool {
            XCTAssertEqual(label.count, 2)
            XCTAssertTrue(label.allSatisfy { allowed.contains($0) })
        }
    }

    func testPoolCullsSameFingerReaches() {
        let pool = Set(LabelAssigner.pool(alphabet: LabelAssigner.defaultAlphabet))
        // f and r/t/g/v are all left index — slow reaches, must be culled.
        for bad in ["fr", "ft", "fg", "fv", "rf", "ki", "ol"] {
            XCTAssertFalse(pool.contains(bad), "\(bad) is a same-finger reach")
        }
        // Alternating-hand and double-tap combos must survive.
        for good in ["fj", "jf", "ff", "jj", "dk", "kd"] {
            XCTAssertTrue(pool.contains(good), "\(good) should be in the pool")
        }
    }

    func testHardReachKeysNeverAppearInThePool() {
        // q/p are pinky corners, z/x pinky-ring bottom, b a long center reach —
        // they must never appear in any 2-char label.
        let hard: Set<Character> = ["q", "p", "b", "x", "z"]
        for label in LabelAssigner.pool(alphabet: LabelAssigner.defaultAlphabet) {
            XCTAssertTrue(label.allSatisfy { !hard.contains($0) }, "\(label) uses a hard-reach key")
        }
    }

    func testPoolPrefersErgonomicPairsFirst() {
        let pool = LabelAssigner.pool(alphabet: LabelAssigner.defaultAlphabet)
        let top = pool.prefix(40)
        // The very best slots are resting-position index/middle alternations.
        XCTAssertTrue(top.contains("fj"))
        XCTAssertTrue(top.contains("jf"))
        XCTAssertTrue(top.contains("fk"))
        // Lateral/stretch keys come later than resting keys.
        XCTAssertFalse(top.contains("ty"))
        XCTAssertFalse(top.contains("wo"))
    }

    func testAssignmentsLandInTheHashWindow() {
        // Labels for realistic screens come only from the top of the ranking.
        let pool = LabelAssigner.pool(alphabet: LabelAssigner.defaultAlphabet)
        let window = Set(pool.prefix(256))
        let result = LabelAssigner.assign(grid(150), alphabet: LabelAssigner.defaultAlphabet)
        for r in result {
            XCTAssertTrue(window.contains(r.label), "\(r.label) is outside the top-256 window")
        }
    }

    func testPoolIsDeterministic() {
        XCTAssertEqual(LabelAssigner.pool(alphabet: LabelAssigner.defaultAlphabet),
                       LabelAssigner.pool(alphabet: LabelAssigner.defaultAlphabet))
    }

    // MARK: assignment

    func testAssignReturnsUniqueLabelsInInputOrder() {
        let els = grid(120)
        let result = LabelAssigner.assign(els, alphabet: LabelAssigner.defaultAlphabet)
        XCTAssertEqual(result.count, els.count)
        XCTAssertEqual(Set(result.map(\.label)).count, els.count)
        for (i, r) in result.enumerated() {
            XCTAssertEqual(r.element.axFrame, els[i].axFrame, "input order must be preserved")
        }
    }

    func testSamePositionGetsSameLabelAcrossRuns() {
        let els = grid(80)
        let a = LabelAssigner.assign(els, alphabet: LabelAssigner.defaultAlphabet)
        let b = LabelAssigner.assign(els, alphabet: LabelAssigner.defaultAlphabet)
        XCTAssertEqual(a.map(\.label), b.map(\.label))
    }

    func testLabelSurvivesReorderingAndOtherElementsChanging() {
        let els = grid(60)
        let full = LabelAssigner.assign(els, alphabet: LabelAssigner.defaultAlphabet)
        // Same elements, shuffled order → same label per position.
        let shuffledIdx = Array(els.indices.reversed())
        let shuffled = LabelAssigner.assign(shuffledIdx.map { els[$0] },
                                            alphabet: LabelAssigner.defaultAlphabet)
        for (pos, idx) in shuffledIdx.enumerated() {
            XCTAssertEqual(shuffled[pos].label, full[idx].label, "label must follow the position")
        }
        // Drop half the elements → survivors overwhelmingly keep their labels.
        // (A survivor that was hash-colliding with a removed element may re-home —
        // unavoidable for any unique-label scheme — but that must stay rare.)
        let survivors = els.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let half = LabelAssigner.assign(survivors, alphabet: LabelAssigner.defaultAlphabet)
        var kept = 0
        for (pos, survivor) in survivors.enumerated() {
            let original = full.first { $0.element.axFrame == survivor.axFrame }!
            if half[pos].label == original.label { kept += 1 }
        }
        XCTAssertGreaterThanOrEqual(Double(kept), Double(survivors.count) * 0.9,
                                    "only \(kept)/\(survivors.count) survivors kept their label")
    }

    func testSmallPositionDriftKeepsLabel() {
        let a = LabelAssigner.assign([element(x: 100, y: 100)], alphabet: LabelAssigner.defaultAlphabet)
        let b = LabelAssigner.assign([element(x: 104, y: 102)], alphabet: LabelAssigner.defaultAlphabet)
        XCTAssertEqual(a.first?.label, b.first?.label)
    }

    func testCollidingElementsGetDistinctLabelsDeterministically() {
        let els = [element(x: 100, y: 100), element(x: 100, y: 100)]
        let a = LabelAssigner.assign(els, alphabet: LabelAssigner.defaultAlphabet)
        XCTAssertEqual(Set(a.map(\.label)).count, 2)
        let b = LabelAssigner.assign(els, alphabet: LabelAssigner.defaultAlphabet)
        XCTAssertEqual(a.map(\.label), b.map(\.label))
    }

    func testOverflowStaysPrefixFreeAndUnique() {
        let els = grid(700)
        let labels = LabelAssigner.assign(els, alphabet: LabelAssigner.defaultAlphabet).map(\.label)
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
