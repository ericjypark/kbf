import AppKit

/// Orchestrates the modes. Owns the single overlay + key-capture tap and routes
/// keys by current mode. Esc always cancels; each activation hotkey toggles its
/// own mode and switches from any other.
///
/// - click:      find → label → overlay → type label → click
/// - scroll:     find scroll areas → outline + number them → h/j/k/l (⇧ dash),
///               d/u half page, g/G edges, Tab/⌃N/⌃P/1-9 switch area
final class ModeController {
    private enum Mode { case idle, finding, clickHints, scrolling, search, doubleArmed }
    private enum Kind { case click, scroll, search }

    private let overlay = OverlayWindowController()
    private let searchBar = SearchBar()
    private let keyTap = KeyCaptureTap()
    private var mode: Mode = .idle
    private var kind: Kind?                  // which activation owns the current mode
    private var matcher: HintMatcher?
    private var scrollAreas: [Element] = []
    private var scrollActive = 0
    private var armedMatcher: HintMatcher?   // post-click window: retype the label to double-click
    private var armWork: DispatchWorkItem?
    private var armedReturnElement: Element?  // post-click window: press ⏎ again to double-click
    private var searchElements: [Element] = []
    private var searchQuery = ""
    private var searchMatches: [Element] = []
    private var searchLabels: [String] = []
    private var searchLabelTyped = ""
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

    func toggleClick() { toggle(.click) }
    func toggleScroll() { toggle(.scroll) }
    func toggleSearch() { toggle(.search) }

    /// Activation hotkeys toggle their own mode off and switch from any other.
    private func toggle(_ k: Kind) {
        let wasActive = kind
        if mode != .idle { cancel() }
        guard wasActive != k else { return }
        switch k {
        case .click: enterClick()
        case .scroll: enterScroll()
        case .search: enterSearch()
        }
    }

    func enterClick() {
        guard let app = beginFinding(.click) else { return }
        asyncFind({
            ElementFinder.dedupByFrame(
                ElementFinder.find(in: app) + ElementFinder.menuBarAndDock(frontApp: app)
                    + ElementFinder.openMenuItems(frontApp: app) + ElementFinder.popupWindowItems())
        }) { [weak self] elements in
            guard let self else { return }
            guard !elements.isEmpty else { self.finishEmpty(); return }
            self.showHints(elements)
            self.mode = .clickHints
            self.keyTap.start()
        }
    }

    func enterScroll() {
        guard let app = beginFinding(.scroll) else { return }
        asyncFind({ ElementFinder.scrollAreas(in: app) }) { [weak self] areas in
            guard let self else { return }
            guard !areas.isEmpty else { self.finishEmpty(); return }
            self.keyTap.start()
            self.scrollAreas = Array(areas.prefix(9))   // 1–9 jump keys address them
            self.scrollActive = 0
            self.overlay.showScrollAreas(self.scrollAreas, active: 0)
            self.mode = .scrolling
        }
    }

    func enterSearch() {
        guard let app = beginFinding(.search) else { return }
        asyncFind({
            ElementFinder.dedupByFrame(
                ElementFinder.find(in: app) + ElementFinder.menuBarAndDock(frontApp: app)
                    + ElementFinder.openMenuItems(frontApp: app) + ElementFinder.popupWindowItems())
                .filter { !($0.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
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
        armWork?.cancel(); armWork = nil
        Scroller.stopAnimation()
        keyTap.stop()
        overlay.hide()
        searchBar.hide()
        matcher = nil
        armedMatcher = nil
        armedReturnElement = nil
        scrollAreas = []
        scrollActive = 0
        searchElements = []
        searchMatches = []
        searchLabels = []
        searchLabelTyped = ""
        mode = .idle
        kind = nil
    }

    // MARK: background find

    /// Claims the active state and returns the frontmost app, or nil if busy
    /// or the app is on the user's excluded list.
    private func beginFinding(_ k: Kind) -> NSRunningApplication? {
        guard mode == .idle, let app = NSWorkspace.shared.frontmostApplication else { return nil }
        guard !AppSettings.shared.isExcluded(app.bundleIdentifier) else { NSSound.beep(); return nil }
        mode = .finding   // blocks re-entry while the AX query runs off the main thread
        kind = k
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

    private func finishEmpty() { NSSound.beep(); mode = .idle; kind = nil }

    // MARK: helpers

    private func showHints(_ elements: [Element]) {
        let labels = LabelMaker.labels(elements.count, alphabet: AppSettings.shared.alphabetChars)
        let assignments = zip(labels, elements).map { (label: $0, element: $1) }
        matcher = HintMatcher(assignments.map { ($0.label, $0.element) })
        overlay.show(assignments)
        overlay.update(typed: "")
    }

    // MARK: key routing (runs on main run loop via the tap). Returns true to swallow.

    private func handleKey(_ code: CGKeyCode, _ chars: String, _ flags: CGEventFlags) -> Bool {
        switch mode {
        case .idle, .finding: return false
        case .clickHints: return handleHintKey(code, chars, flags) { [weak self] element, flags, label in
            guard let self else { return }
            let action = ModeController.clickAction(for: flags)
            if action == .left {
                // Single click now; keep listening so retyping the label double-clicks.
                self.overlay.hide()
                self.matcher = nil
                Clicker.leftClick(on: element, clickState: 1)
                self.armDouble(element: element, label: label)
            } else {
                self.cancel()
                _ = Clicker.perform(action, on: element)
            }
        }
        case .scrolling: return handleScrollKey(code, chars, flags)
        case .search: return handleSearchKey(code, chars, flags)
        case .doubleArmed: return handleDoubleArmedKey(code, chars)
        }
    }

    /// After a left click, listen briefly: repeating the trigger (the same label in
    /// click mode, ⏎ in search mode) within the system double-click interval sends
    /// a second click (state 2) → a real double-click.
    private func armDouble(element: Element, label: String) {
        armedMatcher = HintMatcher([(label, element)])
        mode = .doubleArmed
        scheduleDisarm()
    }

    private func armDoubleReturn(element: Element) {
        armedReturnElement = element
        mode = .doubleArmed
        scheduleDisarm()
    }

    private func scheduleDisarm() {
        let work = DispatchWorkItem { [weak self] in self?.cancel() }
        armWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(NSEvent.doubleClickInterval, 0.25), execute: work)
    }

    private func handleDoubleArmedKey(_ code: CGKeyCode, _ chars: String) -> Bool {
        if code == Key.escape { cancel(); return true }
        if let element = armedReturnElement {
            guard code == Key.return else { cancel(); return false }  // disarm, let it through
            armWork?.cancel()
            DispatchQueue.main.async { self.cancel(); Clicker.leftClick(on: element, clickState: 2) }
            return true
        }
        guard let ch = chars.first, ch.isLetter, armedMatcher != nil else {
            cancel(); return false   // not a retype — disarm and let the key through
        }
        switch armedMatcher!.input(ch) {
        case .matched(let element):
            armWork?.cancel()
            DispatchQueue.main.async { self.cancel(); Clicker.leftClick(on: element, clickState: 2) }
            return true
        case .narrowed:
            return true
        case .noMatch:
            cancel(); return false   // wrong key — disarm and let it through
        }
    }

    /// ⏎ left-click (⏎ again = double) · ⇧⏎ right-click · ⌘⏎ command-click ·
    /// Tab/↓/⌃N next · ⇧Tab/↑/⌃P previous · ⇧+label jump · letters refine the query.
    private func handleSearchKey(_ code: CGKeyCode, _ chars: String, _ flags: CGEventFlags) -> Bool {
        switch code {
        case Key.escape:
            cancel()
        case Key.return:
            guard searchSelected < searchMatches.count else { cancel(); return true }
            let element = searchMatches[searchSelected]
            if flags.contains(.maskCommand) {
                DispatchQueue.main.async { self.cancel(); Clicker.perform(.command, on: element) }
            } else if flags.contains(.maskShift) {
                DispatchQueue.main.async { self.cancel(); Clicker.perform(.right, on: element) }
            } else {
                // Single click now; pressing ⏎ again within the interval double-clicks.
                searchBar.hide()
                overlay.hide()
                DispatchQueue.main.async { Clicker.leftClick(on: element, clickState: 1) }
                armDoubleReturn(element: element)
            }
        case Key.delete:
            if !searchQuery.isEmpty { searchQuery.removeLast(); refilterSearch() }
        case Key.tab:
            if flags.contains(.maskCommand) { return false }   // ⌘Tab app switcher
            moveSearchSelection(by: flags.contains(.maskShift) ? -1 : 1)
        case Key.down:
            moveSearchSelection(by: 1)
        case Key.up:
            moveSearchSelection(by: -1)
        default:
            guard let ch = chars.first else { return true }
            if flags.contains(.maskControl) {
                if ch == "n" { moveSearchSelection(by: 1); return true }
                if ch == "p" { moveSearchSelection(by: -1); return true }
                return false   // unhandled ⌃-combo (e.g. input-source switch) — let the system have it
            }
            if !flags.intersection([.maskCommand, .maskAlternate]).isEmpty {
                return false   // ⌘/⌥ combos (Spotlight, kbf's own hotkeys) pass through
            }
            if ch.isUppercase, flags.contains(.maskShift) {
                jumpToLabel(ch)
            } else if ch.isLetter || ch.isNumber || ch.isPunctuation || ch == " " {
                searchQuery.append(ch)
                refilterSearch()
            }
        }
        return true   // otherwise modal: unmodified keys are query input (Esc exits)
    }

    private func moveSearchSelection(by delta: Int) {
        guard !searchMatches.isEmpty else { return }
        searchSelected = (searchSelected + delta + searchMatches.count) % searchMatches.count
        searchLabelTyped = ""
        overlay.showBoxes(searchMatches, selected: searchSelected, labels: searchLabels)
    }

    /// ⇧+letters type a match's hint label; a complete label jumps the selection
    /// to that element (labels are prefix-free, so a full match is unambiguous).
    private func jumpToLabel(_ ch: Character) {
        searchLabelTyped += ch.lowercased()
        if let hit = searchLabels.firstIndex(of: searchLabelTyped) {
            searchLabelTyped = ""
            searchSelected = hit
            overlay.showBoxes(searchMatches, selected: searchSelected, labels: searchLabels)
        } else if !searchLabels.contains(where: { $0.hasPrefix(searchLabelTyped) }) {
            searchLabelTyped = ""
            NSSound.beep()
        }
    }

    private func refilterSearch() {
        searchLabelTyped = ""
        if searchQuery.isEmpty {
            searchMatches = []
            searchLabels = []
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
        searchLabels = LabelMaker.labels(searchMatches.count, alphabet: AppSettings.shared.alphabetChars)
        searchSelected = 0
        searchBar.update(query: searchQuery, count: searchMatches.count)
        overlay.showBoxes(searchMatches, selected: searchSelected, labels: searchLabels)
    }

    /// Shared hint-typing handler for click + scroll-pick. `onMatch` is deferred
    /// out of the tap callback (posting events from inside it gets them dropped).
    private func handleHintKey(_ code: CGKeyCode, _ chars: String, _ flags: CGEventFlags,
                               onMatch: @escaping (Element, CGEventFlags, String) -> Void) -> Bool {
        if code == Key.escape { cancel(); return true }
        if code == Key.delete {
            if matcher != nil { _ = matcher!.deleteLast(); overlay.update(typed: matcher!.typed) }
            return true
        }
        guard let ch = chars.first, ch.isLetter, matcher != nil else { return false }
        switch matcher!.input(ch) {
        case .matched(let element):
            let label = matcher!.typed
            DispatchQueue.main.async { onMatch(element, flags, label) }
        case .narrowed:
            overlay.update(typed: matcher!.typed)
        case .noMatch:
            NSSound.beep()
        }
        return true
    }

    /// Modifier held when the label completes chooses the click variant.
    /// ⌘ → command-click · ⌃ → right-click · none → left-click.
    /// (Double-click is "type the label twice", not a modifier.)
    private static func clickAction(for flags: CGEventFlags) -> Clicker.Action {
        if flags.contains(.maskCommand) { return .command }
        if flags.contains(.maskControl) { return .right }
        return .left
    }

    private func handleScrollKey(_ code: CGKeyCode, _ chars: String, _ flags: CGEventFlags) -> Bool {
        if code == Key.escape { cancel(); return true }
        guard !scrollAreas.isEmpty else { return false }
        let shift = flags.contains(.maskShift)
        if code == Key.tab { switchArea(by: shift ? -1 : 1); return true }
        guard let ch = chars.first,
              let cmd = ScrollKeymap.command(for: ch, shift: shift,
                                             control: flags.contains(.maskControl)) else {
            return false   // not a scroll key — let it through
        }

        let area = scrollAreas[scrollActive]
        let big: Int32 = 8000
        var dx: Int32 = 0, dy: Int32 = 0
        var smooth = false   // big motions glide; single steps stay instant for key repeat
        switch cmd {
        case .scroll(let ux, let uy):
            let step = Int32(AppSettings.shared.scrollStep)
            dx = Int32(ux) * step; dy = Int32(uy) * step
        case .dash(let ux, let uy):
            let dash = Int32(AppSettings.shared.scrollDash)
            dx = Int32(ux) * dash; dy = Int32(uy) * dash
            smooth = true
        case .halfPage(let down):
            // Half the VISIBLE height of the active area, like a paging key.
            let vr = area.axFrame.intersection(Geometry.screensBoundsAX)
            let half = Int32(max((vr.isNull ? 900 : vr.height) / 2, 100))
            dy = down ? -half : half
            smooth = true
        case .edge(let top):
            dy = top ? big : -big
        case .nextArea: switchArea(by: 1); return true
        case .prevArea: switchArea(by: -1); return true
        case .jumpArea(let i):
            guard i < scrollAreas.count else { NSSound.beep(); return true }
            setActiveArea(i)
            return true
        }
        // Scroll at the center of the VISIBLE part of the area (a tall web area's
        // true center can be off-screen).
        let vr = area.axFrame.intersection(Geometry.screensBoundsAX)
        let point = vr.isNull ? area.axCenter : CGPoint(x: vr.midX, y: vr.midY)
        DispatchQueue.main.async {
            smooth ? Scroller.smoothScroll(at: point, dx: dx, dy: dy)
                   : Scroller.scroll(at: point, dx: dx, dy: dy)
        }
        return true
    }

    private func switchArea(by delta: Int) {
        guard scrollAreas.count > 1 else { return }
        setActiveArea((scrollActive + delta + scrollAreas.count) % scrollAreas.count)
    }

    private func setActiveArea(_ i: Int) {
        scrollActive = i
        overlay.showScrollAreas(scrollAreas, active: i)
    }
}
