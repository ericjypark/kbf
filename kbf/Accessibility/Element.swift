import ApplicationServices
import CoreGraphics

/// A normalized actionable UI element discovered in some app.
struct Element {
    let ax: AXUIElement
    let role: String
    /// Frame in AX global coordinates (top-left origin, y down). Convert with `Geometry` for AppKit.
    let axFrame: CGRect
    let title: String?

    /// Center point in AX global coordinates — used for cursor-warp clicking.
    var axCenter: CGPoint { CGPoint(x: axFrame.midX, y: axFrame.midY) }
}
