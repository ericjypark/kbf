import AppKit

/// Orchestrates the modes. Owns the single overlay + key-capture tap and routes
/// keys by current mode. Esc always cancels.
///
/// - click:      find → label → overlay → type label → click
/// - scroll:     find scroll areas → (pick if >1) → j/k/d/u/h/l/g/G scroll
final class ModeController {
    private enum Mode { case idle, finding, clickHints, scrollPick, scrolling, search }

    private let overlay = OverlayWindowController()
    private let searchBar = SearchBar()
    private let keyTap = KeyCaptureTap()
    private var mode: Mode = .idle
    private var matcher: HintMatcher?
    private var scrollTarget: Element?
    private var searchElements: [Element] = []
    private var searchQuery = ""
    private var searchMatches: [Element] = []
    private var searchSelected = 0
    private var generation = 0   // invalidates in-flight background finds on cancel

    private enum Key {
        static let escape: CGKeyCode = 53
        static let delete: CGKeyCode = 51
        static let `return`: CGKeyCode = 36
        static let tab: CGKeyCode = 48
        static let down: CGKeyCode = 125
        static let up: CGKeyCode = 126
    }

    var isActive: Bool { mode != .idle }

    init() {
        keyTap.onKeyDown = { [weak self] code, chars, flags in
            self?.handleKey(code, chars, flags) ?? false
        }
    }

    // MARK: entry points

    func toggleClick() { isActive ? cancel() : enterClick() }

    func enterClick() {
        guard let app = beginFinding() else { return }
        asyncFind({ ElementFinder.find(in: app) + ElementFinder.menuBarAndDock(frontApp: app) }) { [weak self] elements in
            guard let self else { return }
            guard !elements.isEmpty else { self.finishEmpty(); return }
            self.showHints(elements)
            self.mode = .clickHints
            self.keyTap.start()
        }
    }

    func enterScroll() {
        guard let app = beginFinding() else { return }
        asyncFind({ ElementFinder.scrollAreas(in: app) }) { [weak self] areas in
            guard let self else { return }
            guard !areas.isEmpty else { self.finishEmpty(); return }
            self.keyTap.start()
            if areas.count == 1 {
                self.startScrolling(areas[0])
            } else {
                self.showHints(areas)
                self.mode = .scrollPick
            }
        }
    }

    func enterSearch() {
        guard let app = beginFinding() else { return }
        asyncFind({
            ElementFinder.find(in: app).filter { !($0.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        }) { [weak self] titled in
            guard let self else { return }
            guard !titled.isEmpty else { self.finishEmpty(); return }
            self.searchElements = titled
            self.searchQuery = ""; self.searchMatches = []; self.searchSelected = 0
            self.searchBar.update(query: "", count: 0)
            self.searchBar.show()
            self.keyTap.start()
            self.mode = .search
        }
    }

    func cancel() {
        generation += 1   // discard any in-flight find
        keyTap.stop()
        overlay.hide()
        searchBar.hide()
        matcher = nil
        scrollTarget = nil
        searchElements = []
        searchMatches = []
        mode = .idle
    }

    // MARK: background find

    /// Claims the active state and returns the frontmost app, or nil if busy.
    private func beginFinding() -> NSRunningApplication? {
        guard mode == .idle, let app = NSWorkspace.shared.frontmostApplication else { return nil }
        mode = .finding   // blocks re-entry while the AX query runs off the main thread
        return app
    }

    /// Runs `work` off the main thread; delivers the result on the main thread only
    /// if the activation hasn't been superseded (generation unchanged, still finding).
    private func asyncFind<T>(_ work: @escaping () -> T, then completion: @escaping (T) -> Void) {
        generation += 1
        let g = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let result = work()
            DispatchQueue.main.async {
                guard self.generation == g, self.mode == .finding else { return }
                completion(result)
            }
        }
    }

    private func finishEmpty() { NSSound.beep(); mode = .idle }

    // MARK: helpers

    private func showHints(_ elements: [Element]) {
        let labels = LabelMaker.labels(elements.count, alphabet: AppSettings.shared.alphabetChars)
        let assignments = zip(labels, elements).map { (label: $0, element: $1) }
        matcher = HintMatcher(assignments.map { ($0.label, $0.element) })
        overlay.show(assignments)
        overlay.update(typed: "")
    }

    private func startScrolling(_ area: Element) {
        scrollTarget = area
        matcher = nil
        overlay.hide()
        mode = .scrolling
    }

    // MARK: key routing (runs on main run loop via the tap). Returns true to swallow.

    private func handleKey(_ code: CGKeyCode, _ chars: String, _ flags: CGEventFlags) -> Bool {
        switch mode {
        case .idle, .finding: return false
        case .clickHints: return handleHintKey(code, chars, flags) { [weak self] element, flags in
            self?.cancel()
            let action = ModeController.clickAction(for: flags)
            _ = Clicker.perform(action, on: element)
        }
        case .scrollPick: return handleHintKey(code, chars, flags) { [weak self] area, _ in
            self?.startScrolling(area)
        }
        case .scrolling: return handleScrollKey(code, chars, flags)
        case .search: return handleSearchKey(code, chars)
        }
    }

    private func handleSearchKey(_ code: CGKeyCode, _ chars: String) -> Bool {
        switch code {
        case Key.escape:
            cancel()
        case Key.return:
            if searchSelected < searchMatches.count {
                let element = searchMatches[searchSelected]
                DispatchQueue.main.async { self.cancel(); Clicker.perform(.left, on: element) }
            } else {
                cancel()
            }
        case Key.delete:
            if !searchQuery.isEmpty { searchQuery.removeLast(); refilterSearch() }
        case Key.down, Key.tab:
            if !searchMatches.isEmpty {
                searchSelected = (searchSelected + 1) % searchMatches.count
                overlay.showBoxes(searchMatches, selected: searchSelected)
            }
        case Key.up:
            if !searchMatches.isEmpty {
                searchSelected = (searchSelected - 1 + searchMatches.count) % searchMatches.count
                overlay.showBoxes(searchMatches, selected: searchSelected)
            }
        default:
            if let ch = chars.first, ch.isLetter || ch.isNumber || ch.isPunctuation || ch == " " {
                searchQuery.append(ch)
                refilterSearch()
            }
        }
        return true   // search mode is modal: swallow everything (Esc exits)
    }

    private func refilterSearch() {
        if searchQuery.isEmpty {
            searchMatches = []
            searchSelected = 0
            searchBar.update(query: "", count: 0)
            overlay.hide()
            searchBar.show()
            return
        }
        let scored = searchElements.compactMap { e -> (Element, Int)? in
            guard let title = e.title, let s = FuzzyMatch.score(searchQuery, in: title) else { return nil }
            return (e, s)
        }
        searchMatches = Array(scored.sorted { $0.1 > $1.1 }.map(\.0).prefix(60))
        searchSelected = 0
        searchBar.update(query: searchQuery, count: searchMatches.count)
        overlay.showBoxes(searchMatches, selected: searchSelected)
    }

    /// Shared hint-typing handler for click + scroll-pick. `onMatch` is deferred
    /// out of the tap callback (posting events from inside it gets them dropped).
    private func handleHintKey(_ code: CGKeyCode, _ chars: String, _ flags: CGEventFlags,
                               onMatch: @escaping (Element, CGEventFlags) -> Void) -> Bool {
        if code == Key.escape { cancel(); return true }
        if code == Key.delete {
            if matcher != nil { _ = matcher!.deleteLast(); overlay.update(typed: matcher!.typed) }
            return true
        }
        guard let ch = chars.first, ch.isLetter, matcher != nil else { return false }
        switch matcher!.input(ch) {
        case .matched(let element):
            DispatchQueue.main.async { onMatch(element, flags) }
        case .narrowed:
            overlay.update(typed: matcher!.typed)
        case .noMatch:
            NSSound.beep()
        }
        return true
    }

    /// Modifier held when the label completes chooses the click variant.
    /// ⌘ → command-click · ⌃ → right-click · ⌥ → double-click · none → left-click.
    private static func clickAction(for flags: CGEventFlags) -> Clicker.Action {
        if flags.contains(.maskCommand) { return .command }
        if flags.contains(.maskControl) { return .right }
        if flags.contains(.maskAlternate) { return .double }
        return .left
    }

    private func handleScrollKey(_ code: CGKeyCode, _ chars: String, _ flags: CGEventFlags) -> Bool {
        if code == Key.escape { cancel(); return true }
        guard let target = scrollTarget else { return false }
        let line: Int32 = 90, page: Int32 = 450, big: Int32 = 8000
        let shift = flags.contains(.maskShift)
        var dx: Int32 = 0, dy: Int32 = 0
        switch chars.lowercased().first {
        case "i": dy = line           // up        (IJKL arrows)
        case "k": dy = -line          // down
        case "j": dx = line           // left
        case "l": dx = -line          // right
        case "d": dy = -page          // half page down
        case "u": dy = page           // half page up
        case "g": dy = shift ? -big : big   // g = top, G = bottom
        default: return false          // not a scroll key — let it through
        }
        // Scroll at the center of the VISIBLE part of the area (a tall web area's
        // true center can be off-screen).
        let vr = target.axFrame.intersection(Geometry.screensBoundsAX)
        let point = vr.isNull ? target.axCenter : CGPoint(x: vr.midX, y: vr.midY)
        DispatchQueue.main.async { Scroller.scroll(at: point, dx: dx, dy: dy) }
        return true
    }
}
