import Foundation
import ApplicationServices

/// `kbf --self-test` — lightweight runtime checks for the pure logic
/// (complements the XCTest suite). Exits non-zero on failure.
enum SelfTest {
    static func run() -> Int32 {
        var failures = 0
        func check(_ cond: Bool, _ msg: String) {
            print((cond ? "  ok  " : "  FAIL ") + msg)
            if !cond { failures += 1 }
        }

        // LabelAssigner: unique, prefix-free, stable labels for any count.
        let alphabet = LabelAssigner.defaultAlphabet
        for n in [1, 5, 26, 50, 200, 600] {
            let els = (0..<n).map { dummyElement(x: CGFloat($0 % 20) * 120, y: CGFloat($0 / 20) * 90) }
            let labels = LabelAssigner.assign(els, alphabet: alphabet).map(\.label)
            check(labels.count == n, "LabelAssigner(\(n)) count == \(n)")
            check(Set(labels).count == n, "LabelAssigner(\(n)) all unique")
            check(prefixFree(labels), "LabelAssigner(\(n)) prefix-free")
            let again = LabelAssigner.assign(els, alphabet: alphabet).map(\.label)
            check(labels == again, "LabelAssigner(\(n)) stable across runs")
        }

        // HintMatcher narrowing / matching over assigned labels.
        let els = (0..<3).map { dummyElement(x: CGFloat($0) * 200, y: 100) }
        let assigned = LabelAssigner.assign(els, alphabet: alphabet)
        var matcher = HintMatcher(assigned.map { ($0.label, $0.element) })
        if let label = assigned.first?.label, label.count == 2 {
            let chars = Array(label)
            switch matcher.input(chars[0]) {
            case .narrowed, .matched: check(true, "HintMatcher accepts label start")
            case .noMatch: check(false, "HintMatcher accepts label start")
            }
            switch matcher.input(chars[1]) {
            case .matched: check(true, "HintMatcher full label match")
            case .narrowed, .noMatch: check(false, "HintMatcher full label match")
            }
        }
        var m2 = HintMatcher(assigned.map { ($0.label, $0.element) })
        check({ if case .noMatch = m2.input("\u{1}") { return true }; return false }(),
              "HintMatcher rejects non-label char")

        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        return failures == 0 ? 0 : 1
    }

    private static func prefixFree(_ labels: [String]) -> Bool {
        let set = Set(labels)
        for l in labels {
            var p = ""
            for c in l.dropLast() { p.append(c); if set.contains(p) { return false } }
        }
        return true
    }

    private static func dummyElement(x: CGFloat, y: CGFloat) -> Element {
        Element(ax: AXUIElementCreateApplication(0), role: "AXButton",
                axFrame: CGRect(x: x, y: y, width: 40, height: 24), title: nil)
    }
}
