import Foundation

/// Generates short, prefix-free hint labels from a home-row alphabet.
///
/// Prefix-free means no label is a prefix of another, so typing a complete label
/// is unambiguous. Uses the classic Vimium breadth-first expansion: labels grow
/// one character at a time and a label is only kept if it was never expanded.
enum LabelMaker {
    static let defaultAlphabet = Array("fjdkslaghrueiwovbcnmtyqpxz")

    static func labels(_ count: Int, alphabet: [Character] = defaultAlphabet) -> [String] {
        guard count > 0 else { return [] }
        guard alphabet.count >= 2 else { return (0..<count).map { String($0) } }

        var hints: [String] = [""]
        var offset = 0
        // Expand the frontier until enough *leaf* labels remain.
        while (hints.count - offset) < count || hints.count == 1 {
            let prefix = hints[offset]
            offset += 1
            for c in alphabet { hints.append(String(c) + prefix) }
        }
        // The labels we keep are the next `count` frontier entries (never expanded → prefix-free).
        let leaves = hints[offset ..< offset + count]
        // We built strings reversed (prepended chars); reverse back, then sort for stable order.
        return leaves.map { String($0.reversed()) }.sorted()
    }
}
