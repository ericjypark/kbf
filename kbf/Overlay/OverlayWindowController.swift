import AppKit

/// A borderless, transparent, click-through panel spanning all screens that
/// draws hint labels as CALayers (fast for hundreds of labels).
final class OverlayWindowController {
    private let panel: NSPanel
    private let root: CALayer
    private var hints: [(label: String, pill: CALayer, text: CATextLayer)] = []

    init() {
        let frame = Geometry.screensBounds
        panel = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        let layer = CALayer()
        view.layer = layer
        panel.contentView = view
        root = layer
    }

    func show(_ assignments: [(label: String, element: Element)]) {
        // No implicit fade — hints must appear instantly.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clear()
        let origin = panel.frame.origin
        var placed: [CGRect] = []
        for a in assignments {
            let cocoa = Geometry.axToCocoa(a.element.axFrame)
            let center = CGPoint(x: cocoa.midX - origin.x, y: cocoa.midY - origin.y)
            let scale = OverlayWindowController.backingScale(at: CGPoint(x: cocoa.midX, y: cocoa.midY))
            let (pill, text) = makePill(a.label, center: center, scale: scale)
            pill.frame = deOverlap(pill.frame, against: placed)
            placed.append(pill.frame)
            root.addSublayer(pill)
            hints.append((a.label.lowercased(), pill, text))
        }
        CATransaction.commit()
        panel.orderFrontRegardless()
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
        let origin = panel.frame.origin
        for (i, e) in elements.enumerated() {
            let cocoa = Geometry.axToCocoa(e.axFrame)
            let box = CALayer()
            box.frame = CGRect(x: cocoa.minX - origin.x, y: cocoa.minY - origin.y,
                               width: cocoa.width, height: cocoa.height).insetBy(dx: -2, dy: -2)
            box.cornerRadius = 5
            let isSel = i == selected
            box.borderWidth = isSel ? 2.5 : 1
            box.borderColor = (isSel ? Theme.accent : NSColor.white.withAlphaComponent(0.35)).cgColor
            box.backgroundColor = isSel ? Theme.accent.withAlphaComponent(0.18).cgColor : nil
            root.addSublayer(box)
        }
        CATransaction.commit()
        panel.orderFrontRegardless()
    }

    func hide() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clear()
        CATransaction.commit()
        panel.orderOut(nil)
    }

    // MARK: rendering

    private func clear() {
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        hints.removeAll()
    }

    /// Nudge a pill downward until it no longer overlaps an already-placed one,
    /// so dense toolbars don't become an unreadable pile of labels.
    private func deOverlap(_ rect: CGRect, against placed: [CGRect]) -> CGRect {
        var r = rect
        let step = rect.height + 2
        var tries = 0
        while tries < 14, placed.contains(where: { $0.intersects(r) }) {
            r.origin.y -= step   // Cocoa coords: lower y moves the pill down on screen
            tries += 1
        }
        return r
    }

    /// Backing scale of the screen containing `globalPoint` (Cocoa coords), so hint
    /// text stays crisp on each display in a mixed-DPI multi-monitor setup.
    private static func backingScale(at globalPoint: CGPoint) -> CGFloat {
        for screen in NSScreen.screens where screen.frame.contains(globalPoint) {
            return screen.backingScaleFactor
        }
        return NSScreen.main?.backingScaleFactor ?? 2
    }

    private func makePill(_ label: String, center: CGPoint, scale: CGFloat) -> (CALayer, CATextLayer) {
        let str = styledLabel(label, typed: "")
        let textSize = str.size()
        let w = ceil(textSize.width) + Theme.hintPadding.width * 2
        let h = ceil(textSize.height) + Theme.hintPadding.height * 2

        let pill = CALayer()
        pill.frame = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
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
        text.frame = CGRect(x: 0, y: (h - textSize.height) / 2, width: w, height: textSize.height)
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
