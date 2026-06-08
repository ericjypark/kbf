import Foundation

/// Maps labels to elements and narrows them as the user types.
struct HintMatcher {
    enum Result {
        case narrowed([String])      // still ambiguous; these labels remain
        case matched(Element)        // exactly one label fully typed
        case noMatch                 // typed prefix matches nothing
    }

    private let table: [String: Element]
    private(set) var typed: String = ""

    init(_ assignments: [(label: String, element: Element)]) {
        var t: [String: Element] = [:]
        for a in assignments { t[a.label] = a.element }
        table = t
    }

    var allLabels: [String] { Array(table.keys) }

    /// Labels that still start with what's been typed.
    func candidates(for prefix: String) -> [String] {
        let p = prefix.lowercased()
        return p.isEmpty ? allLabels : allLabels.filter { $0.hasPrefix(p) }
    }

    mutating func input(_ character: Character) -> Result {
        let next = typed + String(character).lowercased()
        if let element = table[next] {
            typed = next
            return .matched(element)
        }
        let remaining = candidates(for: next)
        guard !remaining.isEmpty else { return .noMatch }
        typed = next
        return .narrowed(remaining)
    }

    mutating func deleteLast() -> [String] {
        if !typed.isEmpty { typed.removeLast() }
        return candidates(for: typed)
    }
}
