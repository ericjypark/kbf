import Foundation

/// Scores how well a query matches a candidate string. Higher is better;
/// `nil` means no match. Substring matches beat subsequence matches; earlier
/// and word-boundary matches score higher.
enum FuzzyMatch {
    static func score(_ query: String, in text: String) -> Int? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return 0 }
        let t = text.lowercased()

        // Contiguous substring — strongest signal.
        if let r = t.range(of: q) {
            let start = t.distance(from: t.startIndex, to: r.lowerBound)
            let wordBoundary = start == 0 || t[t.index(before: r.lowerBound)] == " "
            return 10_000 - start + (wordBoundary ? 500 : 0)
        }

        // Subsequence — every query char appears in order.
        var idx = t.startIndex
        var firstAt = -1, gaps = 0, prev = -1
        for qc in q {
            guard let found = t[idx...].firstIndex(of: qc) else { return nil }
            let pos = t.distance(from: t.startIndex, to: found)
            if firstAt < 0 { firstAt = pos }
            if prev >= 0 { gaps += pos - prev - 1 }
            prev = pos
            idx = t.index(after: found)
        }
        return 5_000 - firstAt - gaps
    }
}
