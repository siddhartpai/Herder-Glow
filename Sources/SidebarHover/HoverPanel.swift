import AppKit
import SwiftUI
import SidebarCore

final class HoverPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: HoverController.width, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }

    /// Lets a click in a text field give the panel keyboard focus.
    override var canBecomeKey: Bool { true }
}

/// Opens the panel while the mouse is over the light or the panel; closes it 0.3 s after both are left.
@MainActor
final class HoverController {
    static let width: CGFloat = 380
    static let maxHeight: CGFloat = 560
    private static let gap: CGFloat = 6

    var anchor: () -> NSRect = { .zero }
    private let panel = HoverPanel()
    private let model: PanelModel
    private var inLight = false
    private var inPanel = false
    private var closeWork: DispatchWorkItem?

    init(model: PanelModel) {
        self.model = model
        let tracking = TrackingView()
        tracking.onHover = { [weak self] inside in
            self?.inPanel = inside
            self?.update()
        }
        tracking.embed(NSHostingView(rootView: PanelRootView(model: model) { [weak self] height in
            self?.resize(height: height)
        }))
        panel.contentView = tracking
    }

    func lightHover(_ inside: Bool) {
        inLight = inside
        update()
    }

    private func update() {
        closeWork?.cancel()
        if inLight || inPanel {
            open()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func open() {
        guard !panel.isVisible else { return }
        Task { await model.reloadBlocked() }
        position()
        panel.orderFrontRegardless()
    }

    private func resize(height: CGFloat) {
        panel.setContentSize(NSSize(width: Self.width, height: min(max(height, 1), Self.maxHeight)))
        position()
    }

    /// Left of the light, vertically centered on it, kept inside the screen.
    private func position() {
        let light = anchor()
        let size = panel.frame.size
        var y = light.midY - size.height / 2
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(light) }) {
            let visible = screen.visibleFrame
            y = min(max(y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrameOrigin(NSPoint(x: light.minX - size.width - Self.gap, y: y))
    }
}
