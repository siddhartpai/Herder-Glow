import AppKit

/// Reports mouse enter and exit even when the app is not active.
final class TrackingView: NSView {
    var onHover: (Bool) -> Void = { _ in }
    /// Area that reports hover; nil means the whole view.
    var hoverRect: NSRect?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        if hoverRect == nil { options.insert(.inVisibleRect) }
        addTrackingArea(NSTrackingArea(rect: hoverRect ?? .zero, options: options, owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    func embed(_ view: NSView) {
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }
}
