import AppKit
import SwiftUI
import SidebarCore

/// Thin window on the right screen edge that shows the traffic light.
final class EdgeLightWindow: NSPanel {
    static let size = NSSize(width: 14, height: 48)

    init(store: AgentStore, onHover: @escaping (Bool) -> Void) {
        super.init(contentRect: NSRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false

        let tracking = TrackingView(frame: NSRect(origin: .zero, size: Self.size))
        tracking.onHover = onHover
        tracking.embed(NSHostingView(rootView: LightView(store: store)))
        contentView = tracking

        reposition()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    /// Vertical center of the right edge of the primary screen.
    func reposition() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        setFrameOrigin(NSPoint(x: frame.maxX - Self.size.width,
                               y: frame.midY - Self.size.height / 2))
    }
}

struct LightView: View {
    let store: AgentStore

    var body: some View {
        VStack(spacing: 3) {
            lamp(.red, on: store.color == .red)
            lamp(.yellow, on: store.color == .yellow)
            lamp(.green, on: store.color == .green)
        }
        .frame(width: EdgeLightWindow.size.width, height: EdgeLightWindow.size.height)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 5))
    }

    private func lamp(_ color: Color, on: Bool) -> some View {
        Circle()
            .fill(on ? color : color.opacity(0.18))
            .frame(width: 9, height: 9)
    }
}
