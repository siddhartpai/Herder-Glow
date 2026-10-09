import AppKit
import SwiftUI
import SidebarCore

/// Window on the right screen edge that shows the traffic light. It is wider and taller than
/// the light, so the attention glow has room; only the light itself reports hover.
final class EdgeLightWindow: NSPanel {
    static let size = NSSize(width: 44, height: 96)

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
        tracking.hoverRect = Self.pillRect
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

    /// The light's area inside the window, at the right edge and vertically centered.
    static var pillRect: NSRect {
        NSRect(x: size.width - LightView.pillWidth, y: (size.height - LightView.pillHeight) / 2,
               width: LightView.pillWidth, height: LightView.pillHeight)
    }

    /// The light's area on screen.
    var pillFrame: NSRect { Self.pillRect.offsetBy(dx: frame.minX, dy: frame.minY) }

    /// Vertical center of the right edge of the primary screen.
    func reposition() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        setFrameOrigin(NSPoint(x: frame.maxX - Self.size.width,
                               y: frame.midY - Self.size.height / 2))
    }
}

struct LightView: View {
    static let pillWidth: CGFloat = 14
    static let pillHeight: CGFloat = 48
    let store: AgentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var waiting: Int { store.blocked.count }
    private var needsAttention: Bool { waiting > 0 }

    var body: some View {
        ZStack(alignment: .trailing) {
            if needsAttention {
                AttentionGlow(still: reduceMotion).transition(.opacity)
            }
            pill
                .keyframeAnimator(initialValue: CGFloat(0), trigger: waiting) { view, offset in
                    view.offset(x: offset)
                } keyframes: { _ in
                    // Nudge out of the edge and spring back when another agent starts waiting.
                    KeyframeTrack {
                        if reduceMotion || !needsAttention {
                            LinearKeyframe(CGFloat(0), duration: 0.01)
                        } else {
                            SpringKeyframe(CGFloat(-6), duration: 0.14, spring: .snappy)
                            SpringKeyframe(CGFloat(0), duration: 0.5, spring: .bouncy)
                        }
                    }
                }
        }
        .frame(width: EdgeLightWindow.size.width, height: EdgeLightWindow.size.height, alignment: .trailing)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: needsAttention)
    }

    private var pill: some View {
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
        .frame(width: Self.pillWidth)
        .frame(minHeight: Self.pillHeight)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, style: .continuous)
                        .strokeBorder(needsAttention ? Color.red.opacity(0.55) : Color.white.opacity(0.12),
                                      lineWidth: needsAttention ? 1 : 0.5)
                )
        }
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
            } animation: { _ in .easeInOut(duration: 0.8) }
        } else {
            circle
        }
    }
}

/// Soft red halo behind the light that breathes while an agent waits.
private struct AttentionGlow: View {
    let still: Bool

    var body: some View {
        let halo = UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10, style: .continuous)
            .fill(Color.red)
            .frame(width: LightView.pillWidth + 8, height: LightView.pillHeight + 10)
            .blur(radius: 9)
        if still {
            halo.opacity(0.45)
        } else {
            halo.phaseAnimator([false, true]) { view, bright in
                view.opacity(bright ? 0.75 : 0.2).scaleEffect(bright ? 1.12 : 0.95, anchor: .trailing)
            } animation: { _ in .easeInOut(duration: 0.8) }
        }
    }
}
