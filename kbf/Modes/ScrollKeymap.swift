/// Pure mapping from a typed character (+shift) to a scroll-mode command.
/// Vim directions (h/j/k/l), Homerow-style: shift = dash (accelerated),
/// d/u half page, g/G top/bottom, 1–9 jump to a numbered scroll area.
/// Sign convention matches `Scroller`: dy > 0 scrolls up, dx > 0 scrolls left.
enum ScrollKeymap {
    enum Command: Equatable {
        case scroll(dx: Int, dy: Int)     // unit vector; caller scales by step
        case dash(dx: Int, dy: Int)       // unit vector; caller scales by dash step
        case halfPage(down: Bool)
        case edge(top: Bool)
        case nextArea, prevArea
        case jumpArea(Int)                // 0-based index
    }

    static func command(for char: Character, shift: Bool, control: Bool = false) -> Command? {
        if control {
            switch char.lowercased().first {
            case "d": return .halfPage(down: true)    // vim ⌃D
            case "u": return .halfPage(down: false)   // vim ⌃U
            case "n": return .nextArea
            case "p": return .prevArea
            default: return nil
            }
        }
        if let d = char.wholeNumberValue, (1...9).contains(d) { return .jumpArea(d - 1) }
        switch char.lowercased().first {
        case "h": return shift ? .dash(dx: 1, dy: 0) : .scroll(dx: 1, dy: 0)
        case "j": return shift ? .dash(dx: 0, dy: -1) : .scroll(dx: 0, dy: -1)
        case "k": return shift ? .dash(dx: 0, dy: 1) : .scroll(dx: 0, dy: 1)
        case "l": return shift ? .dash(dx: -1, dy: 0) : .scroll(dx: -1, dy: 0)
        case "d": return .halfPage(down: true)
        case "u": return .halfPage(down: false)
        case "g": return .edge(top: !shift)
        default: return nil
        }
    }
}
