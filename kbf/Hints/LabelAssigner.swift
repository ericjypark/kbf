import CoreGraphics

/// Assigns hint labels as a pure function of each element's position, so the
/// same click target keeps the same label across activations (and between
/// click and search mode), regardless of how many other elements appear.
///
/// Labels are uniform 2-char combos from an ergonomically scored pool:
/// same-finger reaches are culled; home row, strong fingers, hand alternation,
/// double-taps, and rolls are preferred; ties follow the user's hint-character
/// order. Each element hashes (quantized position + role, FNV-1a — stable
/// across launches) into the pool with deterministic collision probing.
/// Overflow past the pool gets 3-char labels behind a reserved prefix (the
/// alphabet's last char), keeping the whole set prefix-free.
enum LabelAssigner {
    static let defaultAlphabet = Array("fjdkslaghrueiwovbcnmtyqpxz")

    // MARK: pool

    private static var poolCache: (alphabet: String, pool: [String])?

    static func pool(alphabet: [Character]) -> [String] {
        let key = String(alphabet)
        if let c = poolCache, c.alphabet == key { return c.pool }
        // The last char is reserved as the overflow-tier prefix.
        let chars = alphabet.count > 3 ? Array(alphabet.dropLast()) : alphabet
        var scored: [(label: String, score: Int)] = []
        for (i, a) in chars.enumerated() {
            for (j, b) in chars.enumerated() {
                guard let s = pairScore(a, b) else { continue }
                // Fold the alphabet-order tie-break into the score.
                scored.append((String([a, b]), s * 10_000 - (i * chars.count + j)))
            }
        }
        let pool = scored.sorted { $0.score > $1.score }.map(\.label)
        poolCache = (key, pool)
        return pool
    }

    // MARK: QWERTY ergonomics

    private static let homeRow = Set("asdfghjkl")
    private static let topRow = Set("qwertyuiop")
    private static let leftHand = Set("qwertasdfgzxcvb")

    /// 0 pinky · 1 ring · 2 middle · 3 index (per hand).
    private static func finger(_ c: Character) -> Int {
        switch c {
        case "q", "a", "z", "p": return 0
        case "w", "s", "x", "o", "l": return 1
        case "e", "d", "c", "i", "k": return 2
        default: return 3
        }
    }

    private static func charScore(_ c: Character) -> Int {
        let row = homeRow.contains(c) ? 6 : (topRow.contains(c) ? 3 : 2)
        return row + [1, 2, 4, 4][finger(c)]
    }

    /// nil = culled (same-finger reach, e.g. "fr").
    static func pairScore(_ a: Character, _ b: Character) -> Int? {
        let sameHand = leftHand.contains(a) == leftHand.contains(b)
        if a != b, sameHand, finger(a) == finger(b) { return nil }
        var s = charScore(a) + charScore(b)
        if a == b { s += 4 }                                  // double-tap is fast
        else if !sameHand { s += 5 }                          // hand alternation
        else if abs(finger(a) - finger(b)) == 1 { s += 1 }    // adjacent-finger roll
        return s
    }

    // MARK: assignment

    static func assign(_ elements: [Element], alphabet: [Character])
        -> [(label: String, element: Element)] {
        let pool = pool(alphabet: alphabet)
        guard !pool.isEmpty else { return [] }
        // Deterministic processing order (reading order by quantized position),
        // so collision probing resolves the same way every time.
        let order = elements.indices.sorted { a, b in
            let ka = gridKey(elements[a]), kb = gridKey(elements[b])
            if ka.y != kb.y { return ka.y < kb.y }
            if ka.x != kb.x { return ka.x < kb.x }
            return a < b
        }
        var labelOf = [Int: String](minimumCapacity: elements.count)
        var used = Set<Int>()
        var overflow = 0
        for idx in order {
            var slot = Int(fnv(hashKey(elements[idx])) % UInt64(pool.count))
            var steps = 0
            while used.contains(slot), steps < pool.count {
                slot = (slot + 1) % pool.count
                steps += 1
            }
            if steps < pool.count {
                used.insert(slot)
                labelOf[idx] = pool[slot]
            } else if alphabet.count > 3, overflow < pool.count {
                labelOf[idx] = String(alphabet.last!) + pool[overflow]
                overflow += 1
            }   // beyond ~2× pool capacity: drop (never reached in practice)
        }
        return elements.indices.compactMap { i in labelOf[i].map { ($0, elements[i]) } }
    }

    private static func gridKey(_ e: Element) -> (x: Int, y: Int) {
        (Int((e.axFrame.midX / 16).rounded()), Int((e.axFrame.midY / 16).rounded()))
    }

    private static func hashKey(_ e: Element) -> String {
        let k = gridKey(e)
        return "\(e.role)|\(k.x)|\(k.y)"
    }

    /// FNV-1a — deterministic across launches (Swift's Hasher is per-process seeded).
    private static func fnv(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        return h
    }
}
