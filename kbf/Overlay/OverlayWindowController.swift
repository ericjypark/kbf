import AppKit

/// Draws hint labels (and search boxes) as CALayers. Uses ONE borderless,
/// click-through panel per screen and routes each label to the display it belongs
/// on — a single window spanning all displays renders nothing on secondary screens.
/// Panels are rebuilt when the display arrangement changes.
final class OverlayWindowController {
    private struct ScreenPanel { let screen: NSScreen; let panel: NSPanel; let root: CALayer }
    private var screens: [ScreenPanel] = []
    private var hints: [(label: String, pill: CALayer, text: CATextLayer)] = []

    init() {
        rebuild()
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuild),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func rebuild() {
        screens.forEach { $0.panel.orderOut(nil) }
        screens = NSScreen.screens.map { screen in
            let panel = NSPanel(contentRect: screen.frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .popUpMenu
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            let root = CALayer()
            view.layer = root
            panel.contentView = view
            return ScreenPanel(screen: screen, panel: panel, root: root)
        }
    }

    /// Screen panel whose frame contains the global point (falls back to the first).
    private func screenPanel(at globalPoint: CGPoint) -> ScreenPanel? {
        screens.first { $0.screen.frame.contains(globalPoint) } ?? screens.first
    }

    func show(_ assignments: [(label: String, element: Element)]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clear()
        var placed: [CGRect] = []   // global Cocoa rects, for cross-screen de-overlap
        for a in assignments {
            let cocoa = Geometry.axToCocoa(a.element.axFrame)
            let center = Geometry.clampCocoa(CGPoint(x: cocoa.midX, y: cocoa.midY))
            let size = pillSize(a.label)
            var rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                              width: size.width, height: size.height)
            rect = deOverlap(rect, against: placed)
            placed.append(rect)
            guard let sp = screenPanel(at: CGPoint(x: rect.midX, y: rect.midY)) else { continue }
            let local = CGRect(x: rect.minX - sp.screen.frame.minX, y: rect.minY - sp.screen.frame.minY,
                               width: rect.width, height: rect.height)
            let (pill, text) = makePill(a.label, frame: local, scale: sp.screen.backingScaleFactor)
            sp.root.addSublayer(pill)
            hints.append((a.label.lowercased(), pill, text))
        }
        CATransaction.commit()
        screens.forEach { $0.panel.orderFrontRegardless() }
    }

    /// Hide labels that no longer match the typed prefix; dim the typed portion of the rest.
    func update(typed: String) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for h in hints {
            let match = typed.isEmpty || h.label.hasPrefix(typed)
            h.pill.isHidden = !match
            if match { h.text.string = styledLabel(h.label, typed: typed) }
        }
        CATransaction.commit()
    }

    /// Search mode: draw a box around each matched element, accenting the selected one.
    func showBoxes(_ elements: [Element], selected: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clear()
        for (i, e) in elements.enumerated() {
            let cocoa = Geometry.axToCocoa(e.axFrame)
            guard let sp = screenPanel(at: CGPoint(x: cocoa.midX, y: cocoa.midY)) else { continue }
            let box = CALayer()
            box.frame = CGRect(x: cocoa.minX - sp.screen.frame.minX, y: cocoa.minY - sp.screen.frame.minY,
                               width: cocoa.width, height: cocoa.height).insetBy(dx: -2, dy: -2)
            box.cornerRadius = 5
            let isSel = i == selected
            box.borderWidth = isSel ? 2.5 : 1
            box.borderColor = (isSel ? Theme.accent : NSColor.white.withAlphaComponent(0.35)).cgColor
            box.backgroundColor = isSel ? Theme.accent.withAlphaComponent(0.18).cgColor : nil
            sp.root.addSublayer(box)
        }
        CATransaction.commit()
        screens.forEach { $0.panel.orderFrontRegardless() }
    }

    func hide() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clear()
        CATransaction.commit()
        screens.forEach { $0.panel.orderOut(nil) }
    }

    // MARK: rendering

    private func clear() {
        screens.forEach { $0.root.sublayers?.forEach { $0.removeFromSuperlayer() } }
        hints.removeAll()
    }

    /// Nudge a pill downward until it no longer overlaps an already-placed one, so dense
    /// toolbars don't become an unreadable pile of labels.
    private func deOverlap(_ rect: CGRect, against placed: [CGRect]) -> CGRect {
        var r = rect
        let step = rect.height + 2
        var tries = 0
        while tries < 14, placed.contains(where: { $0.intersects(r) }) {
            r.origin.y -= step
            tries += 1
        }
        return r
    }

    private func pillSize(_ label: String) -> CGSize {
        let s = styledLabel(label, typed: "").size()
        return CGSize(width: ceil(s.width) + Theme.hintPadding.width * 2,
                      height: ceil(s.height) + Theme.hintPadding.height * 2)
    }

    private func makePill(_ label: String, frame: CGRect, scale: CGFloat) -> (CALayer, CATextLayer) {
        let str = styledLabel(label, typed: "")
        let pill = CALayer()
        pill.frame = frame
        pill.backgroundColor = Theme.accent.cgColor
        pill.cornerRadius = Theme.hintCornerRadius
        pill.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        pill.borderWidth = 0.5
        pill.shadowColor = NSColor.black.cgColor
        pill.shadowOpacity = 0.35
        pill.shadowRadius = 3
        pill.shadowOffset = CGSize(width: 0, height: -1)

        let text = CATextLayer()
        text.contentsScale = scale
        text.alignmentMode = .center
        text.string = str
        let th = str.size().height
        text.frame = CGRect(x: 0, y: (frame.height - th) / 2, width: frame.width, height: th)
        pill.addSublayer(text)
        return (pill, text)
    }

    private func styledLabel(_ label: String, typed: String) -> NSAttributedString {
        let s = NSMutableAttributedString(
            string: label.uppercased(),
            attributes: [.font: Theme.hintFont, .foregroundColor: Theme.hintText])
        if !typed.isEmpty {
            s.addAttribute(.foregroundColor, value: Theme.hintTypedText,
                           range: NSRange(location: 0, length: min(typed.count, label.count)))
        }
        return s
    }
}
