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
        // The panel draws its own shadow, so it can shrink and fade with the shape.
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }

    /// Lets a click in a text field give the panel keyboard focus.
    override var canBecomeKey: Bool { true }
}

/// State the SwiftUI panel animates from: open grows the light into the panel.
@MainActor @Observable
final class PanelPresentation {
    var isOpen = false
    var contentHeight: CGFloat = 0
    /// How far the tab's center is below the panel's center, in view points.
    var anchorOffset: CGFloat = 0
}

/// Opens the panel while the mouse is over the light or the panel; closes it 0.3 s after both are left.
@MainActor
final class HoverController {
    static let width: CGFloat = 380
    static let maxHeight: CGFloat = 560
    nonisolated static let closeDuration = 0.3
    /// Transparent space around the glass for its shadow.
    static let shadowMargin: CGFloat = 24

    var anchor: () -> NSRect = { .zero }
    /// The tab's window. It is hidden while the panel is on screen, so it cannot show through.
    weak var lightWindow: NSWindow?
    private let panel = HoverPanel()
    private let model: PanelModel
    private let presentation = PanelPresentation()
    private var inLight = false
    private var inPanel = false
    private var closeWork: DispatchWorkItem?
    private var keyMonitor: Any?

    init(model: PanelModel) {
        self.model = model
        let tracking = TrackingView()
        tracking.onHover = { [weak self] inside in
            guard let self else { return }
            inPanel = inside
            // The open panel covers the light, so the light never reports its own exit.
            if !inside { inLight = false }
            update()
        }
        tracking.embed(NSHostingView(rootView: PanelRootView(model: model, presentation: presentation) { [weak self] height in
            self?.resize(height: height)
        }))
        panel.contentView = tracking
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
    }

    /// Digit keys pick that option on a waiting card, unless the user is typing in a text box.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard panel.isKeyWindow, !(panel.firstResponder is NSTextView),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(digit),
              let pane = model.shortcutTarget(for: digit) else { return false }
        Task { await model.choose(digit, for: pane) }
        return true
    }

    /// Takes keyboard focus only while an agent waits, so digit keys reach the panel.
    private func takeKeysIfWaiting() {
        guard presentation.isOpen, !model.cards.isEmpty, !panel.isKeyWindow else { return }
        panel.makeKey()
        // SwiftUI may focus the first text box; clear it so digits pick options.
        panel.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak self] in self?.panel.makeFirstResponder(nil) }
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
        let work = DispatchWorkItem { [weak self] in self?.close() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func open() {
        guard !presentation.isOpen else { return }
        if !panel.isVisible {
            Task { await model.panelOpened() }
            position()
            panel.orderFrontRegardless()
            lightWindow?.alphaValue = 0
        }
        // Let the collapsed shape render once, so the spring grows from the light.
        DispatchQueue.main.async { [weak self] in
            self?.presentation.isOpen = true
            self?.takeKeysIfWaiting()
        }
    }

    private func close() {
        // The panel opens under a still cursor and gets no enter event, so check the real position.
        let mouse = NSEvent.mouseLocation
        if (presentation.isOpen && panel.frame.contains(mouse)) || anchor().contains(mouse) {
            inPanel = presentation.isOpen
            return
        }
        presentation.isOpen = false
        panel.resignKey()
        // Hide only after the collapse has fully settled into the tab.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDuration + 0.05) { [weak self] in
            guard let self, !self.presentation.isOpen else { return }
            self.lightWindow?.alphaValue = 1
            self.panel.orderOut(nil)
        }
    }

    private func resize(height: CGFloat) {
        presentation.contentHeight = height
        let top = presentation.isOpen && panel.isVisible ? panel.frame.maxY : nil
        let glassHeight = min(max(height, LightView.pillHeight), Self.maxHeight)
        panel.setContentSize(NSSize(width: Self.width + Self.shadowMargin,
                                    height: glassHeight + 2 * Self.shadowMargin))
        position(keepTop: top)
    }


    /// Right edge on the screen edge, vertically centered on the light, kept inside the screen.
    /// While open, the top edge stays still so rows do not move under the mouse.
    private func position(keepTop: CGFloat? = nil) {
        let light = anchor()
        let size = panel.frame.size
        var y = keepTop.map { $0 - size.height } ?? light.midY - size.height / 2
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(light) }) {
            let visible = screen.visibleFrame
            y = min(max(y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrameOrigin(NSPoint(x: light.maxX - size.width, y: y))
        // Screen y grows upward and view y grows downward.
        presentation.anchorOffset = (y + size.height / 2) - light.midY
    }
}
