# kbf

Keyboard-first control for macOS. Hit a hotkey, every clickable element on screen gets a short label — type it to click. Plus scroll mode and search mode. Drive your whole Mac without reaching for the mouse.

## Shortcuts
- **⌥Space** — Click mode: every clickable element gets a label; type it to click. Hold a modifier while finishing the label for a variant — **⌘** command-click, **⌃** right-click — or type the label twice for a double-click.
- **⌥⇧Space** — Scroll mode: every scroll area is outlined and numbered; the active one is highlighted. **h/j/k/l** scroll (vim directions), **⇧** dashes, **d/u** or **⌃D/⌃U** smooth half-page, **g/G** top/bottom, **Tab/⇧Tab/⌃N/⌃P/1–9** switch areas. Esc exits.
- **⌥/** — Search mode: type to fuzzy-find an element by its text. **↑/↓/Tab/⌃N/⌃P** select, or **⇧+label** to jump straight to a match. **⏎** clicks (**⏎⏎** double-clicks), **⇧⏎** right-clicks, **⌘⏎** command-clicks.

Each hotkey toggles its mode (press again to dismiss) and switches from any other. Everything is rebindable in **Preferences** (menu-bar ⌨︎ → Preferences, or ⌘,), along with hint characters, label theme + size, scroll/dash speed, click sound, and per-app exclusions.

## How it works
kbf is a non-sandboxed menu-bar agent. It uses the macOS Accessibility API to enumerate actionable elements in the frontmost app, overlays labels on them, and synthesizes the click. The fast path is a parameterized accessibility search query with a recursive tree-walk fallback; off-screen subtrees are pruned so cost scales with the *visible* elements, and per-element attributes are read in a single batched call. Elements are found on a background thread so activation stays responsive.

## Requirements
- macOS 13+
- Xcode 16+ (developed on Xcode 26)

## Build & run
```sh
./dev.sh    # builds and (re)launches; signs with a stable local identity if present
```
or plain:
```sh
xcodebuild -project kbf.xcodeproj -scheme kbf -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/kbf-*/Build/Products/Debug/kbf.app
```

kbf is a menu-bar agent (no Dock icon). On first launch, grant it Accessibility access in **System Settings → Privacy & Security → Accessibility** — required to read other apps' UI and synthesize clicks. Ad-hoc builds change signature on every rebuild and drop that grant; `dev.sh` signs with a stable self-signed identity so it persists across rebuilds (one-time setup documented in the script header).

## Tests
```sh
xcodebuild test -project kbf.xcodeproj -scheme kbf -destination 'platform=macOS'
```
Unit tests cover the pure logic (label generation, hint matching, fuzzy search, coordinate math). Quick runtime sanity check: `kbf --self-test`.

## Project layout
```
kbf/              app sources (file-system-synchronized Xcode target)
  App/            AppDelegate, MenuBarController
  Accessibility/  element finder (search query + recursive fallback)
  Hints/ Overlay/ labels, overlay, search bar
  Action/ Modes/  click/scroll, mode state machine
  Prefs/          settings + preferences UI
kbfTests/         unit tests
```

## License
MIT.
