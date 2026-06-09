# Homerow Parity & Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the feature/quality gap between kbf and Homerow (homerow.app) — scroll-mode parity, search-mode click variants, full settings surface (hint chars, scroll speed, themes, sounds, excluded apps), and codebase hygiene.

**Architecture:** kbf is an AppKit menu-bar agent: `ModeController` (state machine) owns one `OverlayWindowController` (CALayer hint rendering, one panel per screen), a `KeyCaptureTap` (CGEventTap), and acts via `Clicker`/`Scroller` (CGEvents + AX actions). All new behavior follows that shape: pure logic in small testable enums, UI in the overlay/preferences layers, state in `ModeController`, persistence in `AppSettings`.

**Tech Stack:** Swift / AppKit / ApplicationServices (AX), SwiftUI for Preferences, XCTest.

---

## Part 1 — Gap analysis (Homerow feature inventory vs kbf today)

Sources: homerow.app (landing + FAQ), github.com/nchudleigh/homerow README (bindings reference), homerow.com/changelog (v1.0–v1.5.3).

| # | Homerow feature | kbf today | Action |
|---|---|---|---|
| 1 | Click frontmost window + menu bar + Dock | ✅ has | — |
| 2 | Left / right / double / command click | ✅ (⌃=right, ⌘=cmd, label-twice=double) | — |
| 3 | Search workflow: ⇧⌘Space, type text, Tab/↓/⌃N cycle, ⏎ click | Partial: fuzzy search, Tab/↑↓, ⏎ left-click only | M3: ⌃N/⌃P, ⏎ variants |
| 4 | ⇧⏎ right-click, ⌘⏎ command-click, ⏎×2 double-click (in search) | ❌ | M3 |
| 5 | Jump to search match by typed label (⇧+label) | ❌ (boxes only, no labels) | M3 |
| 6 | Scroll mode: HJKL vim directions | ❌ IJKL custom layout | M2 |
| 7 | Scroll dash (⇧+HJKL accelerated) | ❌ | M2 |
| 8 | Scroll: d/u half page, g(g)/G top/bottom | ✅ has | — |
| 9 | Switch scroll areas: Tab/⇧Tab/⌃N/⌃P, 1–9 jump | ❌ (one-shot hint pick) | M2 |
| 10 | Active scroll-area border highlight + numbered areas | ❌ (nothing shown while scrolling) | M2 |
| 11 | Scroll speed / dash speed adjustable | ❌ hardcoded 90/450px | M2 |
| 12 | Hint characters (label alphabet) setting | Setting exists, **no UI** | M4 |
| 13 | Label themes (Dark / Light / Original) | ❌ single indigo | M4 |
| 14 | Label size | ❌ fixed 12pt | M4 |
| 15 | Ignored applications list | ❌ | M4 |
| 16 | Click / warning sound effects (toggle) | ❌ (only no-match beep) | M4 |
| 17 | Activation shortcuts toggle active state (v1.1) | Click only; scroll/search hotkeys dead while active | M2/M3 |
| 18 | Launch at login | ✅ | — |
| 19 | Custom shortcuts (recorder UI) | ✅ | — |
| 20 | Multi-monitor | ✅ (per-screen panels) | — |
| 21 | Chromium/Electron AX wake (`AXManualAccessibility`) | ✅ | — |
| 22 | Tutor (`?` shows element's searchable properties) | ❌ | Future plan A |
| 23 | Mission Control navigation + auto-activate (v1.5) | ❌ | Future plan B |
| 24 | Click chain (multiple clicks per activation, v1.4) | Partial (double-arm only) | Future plan C |
| 25 | Modifier-only shortcuts / Hyper key (v1.1/1.2) | ❌ (Carbon hotkeys need a key) | Future plan C |
| 26 | Alternative keyboard layouts (Dvorak DHTN scroll) | ❌ | Future plan C |
| 27 | Onboarding (permission flow UI) | System prompt only | Future plan D |
| 28 | App icon, distribution (brew cask, updates) | ❌ | Future plan D |
| 29 | "Hide labels when nothing searched" option | N/A (kbf search already does this) | — |

**Code-quality issues found in analysis (fixed in M1):**
- `AX.searchPredicate` is dead (fast path removed in 4a91997); `Diagnostics.usedFastPath` is vestigial and always false; `let usedFast = false` in `ElementFinder.find`.
- `Clicker.Action.move` and `.double` cases are unreachable from any mode.
- README documents IJKL scroll keys that M2 replaces — must be updated (M5).

## Part 2 — Future plans (separate plan docs, not in this one)

- **Plan A — Tutor:** press `?` while hints are up → floating card showing the focused element's role, title, description, value (read via one `AX.values` batch). New `TutorPanel` + key route in `ModeController`.
- **Plan B — Mission Control:** detect Mission Control via `CGSSpace`/Dock AX tree, label window thumbnails (Dock exposes them as `AXButton`s under `AXGroup` during Exposé), optional auto-activate toggle.
- **Plan C — Input depth:** sticky/click-chain mode (stay active after click until Esc), modifier-only activation via `flagsChanged` event tap, keyboard-layout-aware scroll bindings (read `TISCopyCurrentKeyboardInputSource`).
- **Plan D — Distribution:** AppIcon asset, accessibility onboarding window (poll `AXIsProcessTrusted` timer, relaunch button), notarized release + Homebrew cask + GitHub Releases CI, Sparkle or built-in update check.

---

## Part 3 — Tasks (this plan)

### Task 0: Baseline — verify build + tests green

- [ ] Run: `xcodebuild test -project kbf.xcodeproj -scheme kbf -destination 'platform=macOS' -quiet`
- Expected: all existing tests pass. If not, fix before proceeding.

### Task 1 (M1): Remove dead fast-path remnants

**Files:**
- Modify: `kbf/Accessibility/AX.swift` (delete `searchPredicate`, lines ~85–106)
- Modify: `kbf/Accessibility/ElementFinder.swift:36,77,113` (drop `usedFastPath` from `Diagnostics`, delete `let usedFast = false`)
- Modify: `kbf/Debug/DebugDump.swift:33,36` (drop field from initializer + print)

- [ ] Delete `AX.searchPredicate` and its `// MARK: fast search predicate` comment block.
- [ ] `Diagnostics` becomes `struct Diagnostics { let rawCount: Int; let rawRoles: [String: Int]; let pressableCount: Int }`; update construction sites and the DebugDump print to say `via walk`.
- [ ] Update the file-header comment in `ElementFinder.swift` (it still describes the fast path as primary).
- [ ] Build: `xcodebuild -project kbf.xcodeproj -scheme kbf -configuration Debug build -quiet` → succeeds.
- [ ] Commit: `refactor: remove dead search-predicate fast path remnants`

### Task 2 (M2): ScrollKeymap — pure key→command logic (TDD)

**Files:**
- Create: `kbf/Modes/ScrollKeymap.swift`
- Test: `kbfTests/ScrollKeymapTests.swift`

- [ ] **Write the failing tests** (`kbfTests/ScrollKeymapTests.swift`):

```swift
import XCTest
@testable import kbf

final class ScrollKeymapTests: XCTestCase {
    func testVimDirections() {
        XCTAssertEqual(ScrollKeymap.command(for: "h", shift: false), .scroll(dx: 1, dy: 0))
        XCTAssertEqual(ScrollKeymap.command(for: "j", shift: false), .scroll(dx: 0, dy: -1))
        XCTAssertEqual(ScrollKeymap.command(for: "k", shift: false), .scroll(dx: 0, dy: 1))
        XCTAssertEqual(ScrollKeymap.command(for: "l", shift: false), .scroll(dx: -1, dy: 0))
    }
    func testShiftIsDash() {
        XCTAssertEqual(ScrollKeymap.command(for: "j", shift: true), .dash(dx: 0, dy: -1))
    }
    func testHalfPageAndEdges() {
        XCTAssertEqual(ScrollKeymap.command(for: "d", shift: false), .halfPage(down: true))
        XCTAssertEqual(ScrollKeymap.command(for: "u", shift: false), .halfPage(down: false))
        XCTAssertEqual(ScrollKeymap.command(for: "g", shift: false), .edge(top: true))
        XCTAssertEqual(ScrollKeymap.command(for: "g", shift: true), .edge(top: false))
    }
    func testAreaSwitching() {
        XCTAssertEqual(ScrollKeymap.command(for: "1", shift: false), .jumpArea(0))
        XCTAssertEqual(ScrollKeymap.command(for: "9", shift: false), .jumpArea(8))
        XCTAssertNil(ScrollKeymap.command(for: "0", shift: false))
    }
    func testUnknownIsNil() {
        XCTAssertNil(ScrollKeymap.command(for: "z", shift: false))
    }
}
```

- [ ] Run tests → FAIL (type doesn't exist).
- [ ] **Implement** (`kbf/Modes/ScrollKeymap.swift`):

```swift
/// Pure mapping from a typed character (+shift) to a scroll-mode command.
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

    static func command(for char: Character, shift: Bool) -> Command? {
        if let d = char.wholeNumberValue, (1...9).contains(d) { return .jumpArea(d - 1) }
        switch Character(char.lowercased()) {
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
```

- [ ] Run tests → PASS.
- [ ] Commit: `feat: vim-style scroll keymap (hjkl + shift-dash + 1-9 area jump)`

### Task 3 (M2): Scroll-area cycling + visible highlight

**Files:**
- Modify: `kbf/Overlay/OverlayWindowController.swift` (add `showScrollAreas`)
- Modify: `kbf/Modes/ModeController.swift` (replace scrollPick flow + `handleScrollKey`)

- [ ] Add to `OverlayWindowController`: `showScrollAreas(_ areas: [Element], active: Int)` — for each area draw a rounded border box (accent, width 2.5 for active; white@0.25, width 1 otherwise) and a small numbered pill badge (`1`…) at the box's top-left. Reuse `makePill`-style rendering with `Theme` tokens.
- [ ] `ModeController`: replace `.scrollPick` flow — `enterScroll` keeps ALL areas (`scrollAreas`), `activeArea` index starts 0, calls `overlay.showScrollAreas(areas, active: 0)` and goes straight to `.scrolling` (no hint-pick step; numbers/Tab switch areas). Remove `.scrollPick` case.
- [ ] `handleScrollKey` routes through `ScrollKeymap.command(for:shift:)`; Tab/⇧Tab (keycode 48) and ⌃N/⌃P map to `.nextArea`/`.prevArea`; switching areas re-renders `showScrollAreas` and re-targets the scroll point. Step sizes come from `AppSettings` (Task 4). `edge` keeps 8000px, `halfPage` = visible-height/2 of the active area (fallback 450).
- [ ] Toggle semantics: `toggleScroll()`/`toggleSearch()` mirror `toggleClick()`; a hotkey pressed while a *different* mode is active cancels then enters the new mode. Wire all three in `AppDelegate.registerHotkeys`.
- [ ] Build + run `--self-test` + unit tests → PASS.
- [ ] Commit: `feat: scroll-mode parity — area cycling (Tab/1-9), active-area highlight, dash scroll`

### Task 4 (M2): Scroll speed settings

**Files:**
- Modify: `kbf/Prefs/Settings.swift` (`scrollStep: Double` default 90, `scrollDash: Double` default 360)
- Modify: `kbf/Modes/ModeController.swift` (use them)
- Test: extend `kbfTests/ScrollKeymapTests.swift` is not needed (settings are storage); verify by build.

- [ ] Add `@Published var scrollStep` / `scrollDash` with `UserDefaults` persistence (`double(forKey:)`, 0 → default).
- [ ] `handleScrollKey`: `.scroll` scales by `Int32(scrollStep)`, `.dash` by `Int32(scrollDash)`.
- [ ] Commit together with Task 5 UI (single logical unit) or separately: `feat: adjustable scroll + dash speed`

### Task 5 (M3): Search mode — Return click variants + ⌃N/⌃P

**Files:**
- Modify: `kbf/Modes/ModeController.swift` (`handleSearchKey`, `armDouble` generalization)

- [ ] `handleSearchKey` Return: ⇧⏎ → `Clicker.perform(.right)`, ⌘⏎ → `.command`, plain ⏎ → `Clicker.leftClick(clickState: 1)` then arm a Return-double window (pressing ⏎ again within `NSEvent.doubleClickInterval` sends `leftClick(clickState: 2)`), reusing the `.doubleArmed` machinery with a stored element + trigger kind (`label(String)` vs `returnKey`).
- [ ] Add ⌃N/⌃P as next/prev selection (check `flags.contains(.maskControl)` + char n/p) in both search cycling and scroll-area cycling.
- [ ] Pass modifier `flags` into `handleSearchKey` (currently dropped).
- [ ] Build + tests → PASS.
- [ ] Commit: `feat: search mode click variants (⇧⏎ right, ⌘⏎ cmd, ⏎⏎ double) + ⌃N/⌃P`

### Task 6 (M3): Labels on search matches — type label to jump selection

**Files:**
- Modify: `kbf/Modes/ModeController.swift` (label assignment + shift-letter routing)
- Modify: `kbf/Overlay/OverlayWindowController.swift` (`showBoxes` gains optional labels)

- [ ] `refilterSearch` assigns `LabelMaker.labels(min(matches,60))` to matches; `showBoxes` draws each label as a mini-pill at the box's top-left corner.
- [ ] In search key handling: ⇧+letter is routed to a label matcher (`HintMatcher` over the current assignment) instead of the query; full label match moves `searchSelected` to that element (does not click — Homerow's "jump to element").
- [ ] Build + manual check via `--demo-search`; unit tests still PASS.
- [ ] Commit: `feat: hint labels on search matches — ⇧+label jumps selection`

### Task 7 (M4): Settings model — theme, size, sounds, excluded apps

**Files:**
- Modify: `kbf/Prefs/Settings.swift`
- Modify: `kbf/Theme/Theme.swift`
- Modify: `kbf/Modes/ModeController.swift`, `kbf/Overlay/OverlayWindowController.swift` (consume)
- Test: `kbfTests/SettingsTests.swift`

- [ ] Add to `AppSettings`: `labelTheme: LabelTheme` (`indigo|dark|light`, raw-value persisted), `hintScale: HintScale` (`small|medium|large` → font 10/12/14), `clickSound: Bool` (default false), `excludedApps: [String]` (bundle ids, JSON-persisted).
- [ ] `Theme` gains `static var current` computed from settings: `pill`, `text`, `typedText`, `font`, `padding` (light theme = near-white pill + black text; dark = #2A2A2E pill + white text; indigo = today's accent). Overlay reads `Theme.current` at `show` time.
- [ ] `beginFinding` returns nil (with beep) when `app.bundleIdentifier` is in `excludedApps`.
- [ ] Click paths play `NSSound(named: "Tink")` when `clickSound` is on.
- [ ] Tests: alphabet sanitization (already-shipped logic — lock it in), excluded-app matching, theme raw-value round-trip, label scale font mapping.
- [ ] Commit: `feat: label themes, hint size, click sound, excluded apps (model)`

### Task 8 (M4): Preferences UI for everything

**Files:**
- Modify: `kbf/Prefs/PreferencesView.swift` (+ window size in `PreferencesWindowController.swift`)

- [ ] New sections, same Raycast-style `section()` chrome:
  - SHORTCUTS (existing 3 rows)
  - CLICKING — hint characters text field (monospaced, sanitized via `alphabetChars`), label theme segmented picker, label size segmented picker, click-sound toggle
  - SCROLLING — speed slider (30…240 px) + dash slider (120…900 px)
  - EXCLUDED APPS — list of bundle ids with app names/icons when resolvable, "+" menu of running apps, "−" remove
  - GENERAL — launch at login (existing)
- [ ] Window grows to 520×640; content in `ScrollView` so it never clips.
- [ ] Build, open `--demo-prefs`, eyeball; tests PASS.
- [ ] Commit: `feat: full preferences UI — hint chars, theme, size, scroll speeds, sounds, excluded apps`

### Task 9 (M5): README + docs sync

**Files:**
- Modify: `README.md`

- [ ] Update Shortcuts section: scroll mode now `h/j/k/l` (+⇧ dash, Tab/1–9 area switch), search mode Return variants + ⇧label jump; new Preferences list.
- [ ] Commit: `docs: README sync for scroll/search parity + new preferences`

### Task 10: Final verification

- [ ] `xcodebuild test … -quiet` → all green.
- [ ] `./dev.sh` builds and relaunches the app; smoke-test click, scroll (hjkl, Tab, 1–9), search (⇧⏎/⌘⏎/⏎⏎), preferences round-trip.
- [ ] `git log --oneline` shows atomic conventional commits; working tree clean.

## Self-review notes

- Spec coverage: rows 3–17 of the gap table map to Tasks 2–9; rows 22–28 are explicitly deferred to Future Plans A–D (documented, intentional).
- Sign convention for `Scroller` (dy>0 = up) is preserved in `ScrollKeymap` tests — verified against `Scroller.scroll` docs.
- `.scrollPick` removal: `handleHintKey`'s scroll-pick branch and the `Mode.scrollPick` case both go; `showHints` remains used by click mode only.
- Naming locked: `showScrollAreas(_:active:)`, `ScrollKeymap.Command`, `AppSettings.excludedApps`, `Theme.current`.
