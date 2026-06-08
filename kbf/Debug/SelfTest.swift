import Foundation
import ApplicationServices

/// `kbf --self-test` — lightweight runtime checks for the pure logic
/// (no XCTest target yet). Exits non-zero on failure.
enum SelfTest {
    static func run() -> Int32 {
        var failures = 0
        func check(_ cond: Bool, _ msg: String) {
            print((cond ? "  ok  " : "  FAIL ") + msg)
            if !cond { failures += 1 }
        }

        // LabelMaker: correct count, unique, prefix-free.
        for n in [1, 5, 26, 50, 200, 999] {
            let labels = LabelMaker.labels(n)
            check(labels.count == n, "LabelMaker(\(n)) count == \(n)")
            check(Set(labels).count == n, "LabelMaker(\(n)) all unique")
            check(prefixFree(labels), "LabelMaker(\(n)) prefix-free")
            check(labels.allSatisfy { !$0.isEmpty }, "LabelMaker(\(n)) no empty labels")
        }

        // HintMatcher narrowing / matching.
        let mk = LabelMaker.labels(3)              // e.g. 3 single-char labels
        var matcher = HintMatcher(mk.map { ($0, dummyElement()) })
        if let first = mk.sorted().first, let ch = first.first {
            switch matcher.input(ch) {
            case .matched: check(true, "HintMatcher single-char match")
            case .narrowed, .noMatch: check(false, "HintMatcher single-char match")
            }
        }
        var m2 = HintMatcher(LabelMaker.labels(60).map { ($0, dummyElement()) })
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

    private static func dummyElement() -> Element {
        Element(ax: AXUIElementCreateApplication(0), role: "AXButton", axFrame: .zero, title: nil)
    }
}
