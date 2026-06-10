import AppKit

/// A floating, non-activating search bar (Raycast-style): dark translucent
/// rounded panel near the top-center showing the live query + match count.
/// Input is captured by the event tap, so this only displays.
final class SearchBar {
    private let panel: NSPanel
    private let queryField: NSTextField
    private let countField: NSTextField

    private let width: CGFloat = 560
    private let height: CGFloat = 58

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)

        // Blurred dark material + a slight dark tint for the Raycast depth.
        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        let tint = NSView(frame: blur.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        tint.autoresizingMask = [.width, .height]
        blur.addSubview(tint)

        let iconSize: CGFloat = 19
        let icon = NSImageView(frame: NSRect(x: 22, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 16, weight: .semibold)
        icon.contentTintColor = NSColor.white.withAlphaComponent(0.45)

        let fieldHeight: CGFloat = 26
        queryField = SearchBar.label(NSRect(x: 52, y: (height - fieldHeight) / 2 - 1,
                                            width: width - 52 - 64, height: fieldHeight))
        queryField.font = .systemFont(ofSize: 19, weight: .regular)

        countField = SearchBar.label(NSRect(x: width - 58, y: (height - 18) / 2 - 1, width: 42, height: 18))
        countField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        countField.alignment = .right
        countField.textColor = NSColor.white.withAlphaComponent(0.35)

        blur.addSubview(icon)
        blur.addSubview(queryField)
        blur.addSubview(countField)
        panel.contentView = blur
    }

    private static func label(_ frame: NSRect) -> NSTextField {
        let f = NSTextField(frame: frame)
        f.isEditable = false; f.isBordered = false; f.drawsBackground = false; f.isSelectable = false
        f.usesSingleLineMode = true
        f.cell?.lineBreakMode = .byTruncatingTail
        f.textColor = .white
        return f
    }

    func show() {
        if let screen = NSScreen.main {
            let x = (screen.frame.width - width) / 2 + screen.frame.minX
            let y = screen.frame.maxY - 170
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        // Re-assert before ordering in: a hidden panel can lose its all-Spaces
        // behavior and re-home to the Space it was last shown on.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.orderFrontRegardless()
    }

    func update(query: String, count: Int) {
        if query.isEmpty {
            queryField.stringValue = "Search for an element…"
            queryField.textColor = NSColor.white.withAlphaComponent(0.30)
            countField.stringValue = ""
        } else {
            queryField.stringValue = query
            queryField.textColor = .white
            countField.stringValue = "\(count)"
            countField.textColor = count == 0
                ? NSColor.systemRed.withAlphaComponent(0.7)
                : NSColor.white.withAlphaComponent(0.35)
        }
    }

    func hide() { panel.orderOut(nil) }
}
