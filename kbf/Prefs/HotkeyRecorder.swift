import SwiftUI
import Carbon.HIToolbox

/// A SwiftUI control that records a global hotkey: click it, then press the combo.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.hotkey = hotkey
        v.onChange = { hotkey = $0 }
        return v
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        if !view.isRecording { view.hotkey = hotkey }
    }
}

/// AppKit view that captures a key combo and draws a pill showing it.
final class RecorderView: NSView {
    var hotkey = Hotkey(keyCode: 49, modifiers: 0) { didSet { needsDisplay = true } }
    var onChange: ((Hotkey) -> Void)?
    private(set) var isRecording = false

    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 28) }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == UInt16(kVK_Escape) { isRecording = false; needsDisplay = true; return }
        let hk = Hotkey(event: event)
        hotkey = hk
        isRecording = false
        onChange?(hk)
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false; needsDisplay = true; return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.18)
                     : NSColor.white.withAlphaComponent(0.06)).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.14)).setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()

        let text = isRecording ? "Press keys…" : hotkey.display
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor
                : NSColor.white.withAlphaComponent(0.85),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2),
                                withAttributes: attrs)
    }
}
