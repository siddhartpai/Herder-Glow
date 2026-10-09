import AppKit
import SwiftUI
import SidebarCore

/// Thin window on the right screen edge that shows the traffic light.
final class EdgeLightWindow: NSPanel {
    static let size = NSSize(width: 14, height: 64)

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
    static let pillHeight: CGFloat = 48
    let store: AgentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var waiting: Int { store.blocked.count }

    var body: some View {
        VStack(spacing: 3) {
            lamp(.red, on: store.color == .red, pulse: !reduceMotion)
            lamp(.yellow, on: store.color == .yellow)
            lamp(.green, on: store.color == .green)
            if waiting >= 2 {
                Text("\(waiting)")
                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(waiting)))
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 6)
        .frame(width: EdgeLightWindow.size.width)
        .frame(minHeight: Self.pillHeight)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        }
        .frame(maxHeight: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: waiting)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: store.color)
    }

    @ViewBuilder
    private func lamp(_ color: Color, on: Bool, pulse: Bool = false) -> some View {
        let circle = Circle()
            .fill(on ? color : color.opacity(0.16))
            .frame(width: 8, height: 8)
            .shadow(color: on ? color.opacity(0.9) : .clear, radius: 3)
        if on && pulse {
            circle.phaseAnimator([1.0, 0.45]) { view, phase in
                view.opacity(phase)
            } animation: { _ in .easeInOut(duration: 0.9) }
        } else {
            circle
        }
    }
}
