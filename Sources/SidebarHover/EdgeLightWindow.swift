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

/// A named set of status colors, plus a tint for the open glass.
struct Theme: Identifiable, Equatable {
    let name: String
    let waiting: Color
    let working: Color
    let calm: Color
    let glass: Color
    var id: String { name }

    static let all: [Theme] = [
        Theme(name: "Default",
              waiting: Color(red: 1.0, green: 0.29, blue: 0.35),
              working: Color(red: 0.26, green: 0.56, blue: 1.0),
              calm: Color(red: 0.22, green: 0.86, blue: 0.55),
              glass: .clear),
        Theme(name: "Pastel",
              waiting: Color(red: 1.0, green: 0.55, blue: 0.6),
              working: Color(red: 0.6, green: 0.75, blue: 1.0),
              calm: Color(red: 0.6, green: 0.92, blue: 0.75),
              glass: Color(red: 0.35, green: 0.3, blue: 0.5)),
        Theme(name: "Neon",
              waiting: Color(red: 1.0, green: 0.1, blue: 0.6),
              working: Color(red: 0.0, green: 0.9, blue: 1.0),
              calm: Color(red: 0.6, green: 1.0, blue: 0.1),
              glass: Color(red: 0.15, green: 0.0, blue: 0.3)),
        Theme(name: "Sunset",
              waiting: Color(red: 1.0, green: 0.36, blue: 0.2),
              working: Color(red: 1.0, green: 0.72, blue: 0.2),
              calm: Color(red: 0.95, green: 0.55, blue: 0.75),
              glass: Color(red: 0.4, green: 0.15, blue: 0.1)),
        Theme(name: "Ocean",
              waiting: Color(red: 1.0, green: 0.48, blue: 0.4),
              working: Color(red: 0.3, green: 0.7, blue: 0.95),
              calm: Color(red: 0.25, green: 0.85, blue: 0.8),
              glass: Color(red: 0.0, green: 0.2, blue: 0.35)),
        Theme(name: "Mono",
              waiting: Color(white: 1.0),
              working: Color(white: 0.75),
              calm: Color(white: 0.55),
              glass: .clear),
    ]
}

/// One palette for the light, the panel dots and the chips. The panel footer picks the theme.
@MainActor @Observable
final class Palette {
    static let shared = Palette()
    private static let key = "paletteTheme"

    var theme: Theme {
        didSet { UserDefaults.standard.set(theme.name, forKey: Self.key) }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        theme = Theme.all.first { $0.name == saved } ?? Theme.all[0]
    }

    static var waiting: Color { shared.theme.waiting }
    static var working: Color { shared.theme.working }
    static var calm: Color { shared.theme.calm }
    static var glass: Color { shared.theme.glass }
    static let offline = Color(white: 0.45)
}

extension LightColor {
    @MainActor var tint: Color {
        switch self {
        case .red: Palette.waiting
        case .blue: Palette.working
        case .green: Palette.calm
        case .grey: Palette.offline
        }
    }
}

/// A single glowing orb in a small dark capsule. Its color is the most urgent state.
struct LightView: View {
    static let pillWidth: CGFloat = 22
    static let pillHeight: CGFloat = 54
    let store: AgentStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var waiting: Int { store.blocked.count }
    private var needsAttention: Bool { waiting > 0 }

    var body: some View {
        ZStack(alignment: .trailing) {
            if needsAttention {
                AttentionGlow(still: reduceMotion).transition(.opacity)
            }
            capsule
                .overlay(alignment: .topTrailing) {
                    if waiting >= 2 {
                        CountBadge(count: waiting).offset(x: -2, y: -8).transition(.scale.combined(with: .opacity))
                    }
                }
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
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75), value: waiting)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: store.color)
    }

    private var capsule: some View {
        let shape = NotchShape()
        return Orb(color: store.color.tint, breathing: !reduceMotion && store.color != .grey,
                   fast: needsAttention)
            .padding(.trailing, 5)
            .frame(width: Self.pillWidth, height: Self.pillHeight, alignment: .trailing)
            .background(shape.fill(Color.black.opacity(0.85)))
            .overlay(NotchShape(closed: false).stroke(needsAttention ? Palette.waiting.opacity(0.55) : Color.white.opacity(0.14),
                                  lineWidth: needsAttention ? 1 : 0.5))
    }
}

/// Tab on the screen edge: slanted sides, a short flat face with round corners, and
/// concave fillets where it meets the edge so it sits flush. `closedness` blends it from the
/// open panel (0: a rectangle with round outer corners) to the tab (1), so the panel can
/// shrink into the tab. `closed: false` leaves out the edge side for outlines.
struct NotchShape: Shape {
    var closedness: CGFloat = 1
    var closed = true

    var animatableData: CGFloat {
        get { closedness }
        set { closedness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(max(closedness, 0), 1)
        let faceInset = 16 * t
        let cornerRadius = 18 + (5 - 18) * t
        let edgeDrop = 8 * t
        let fillet = 6 * t
        let edge = rect.maxX
        let faceTop = CGPoint(x: rect.minX, y: rect.minY + faceInset)
        let faceBottom = CGPoint(x: rect.minX, y: rect.maxY - faceInset)
        let edgeTop = CGPoint(x: edge, y: rect.minY + edgeDrop)
        let edgeBottom = CGPoint(x: edge, y: rect.maxY - edgeDrop)
        var path = Path()
        path.move(to: CGPoint(x: edge, y: rect.minY))
        if fillet > 0.5 {
            path.addArc(tangent1End: edgeTop, tangent2End: faceTop, radius: fillet)
        }
        path.addArc(tangent1End: faceTop, tangent2End: faceBottom, radius: cornerRadius)
        path.addArc(tangent1End: faceBottom, tangent2End: edgeBottom, radius: cornerRadius)
        if fillet > 0.5 {
            path.addArc(tangent1End: edgeBottom, tangent2End: CGPoint(x: edge, y: rect.maxY), radius: fillet)
        }
        path.addLine(to: CGPoint(x: edge, y: rect.maxY))
        if closed { path.closeSubpath() }
        return path
    }
}

/// Glass-like orb: a lit core, a soft rim and a glow in its own color.
struct Orb: View {
    let color: Color
    let breathing: Bool
    let fast: Bool

    var body: some View {
        let orb = Circle()
            .fill(RadialGradient(colors: [.white.opacity(0.95), color, color.opacity(0.75)],
                                 center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: 6.5))
            .frame(width: 10, height: 10)
            .shadow(color: color.opacity(0.9), radius: 4)
            .shadow(color: color.opacity(0.5), radius: 8)
        if breathing {
            orb.phaseAnimator([false, true]) { view, bright in
                view.scaleEffect(bright ? 1.0 : 0.86).opacity(bright ? 1 : 0.7)
            } animation: { _ in .easeInOut(duration: fast ? 0.8 : 1.8) }
        } else {
            orb
        }
    }
}

private struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 8.5, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .contentTransition(.numericText(value: Double(count)))
            .frame(minWidth: 13, minHeight: 13)
            .background(Palette.waiting, in: Circle())
            .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
    }
}

/// Soft red halo behind the orb that breathes while an agent waits.
private struct AttentionGlow: View {
    let still: Bool

    var body: some View {
        let halo = Circle()
            .fill(Palette.waiting)
            .frame(width: 30, height: 30)
            .blur(radius: 10)
            .offset(x: 4)
        if still {
            halo.opacity(0.45)
        } else {
            halo.phaseAnimator([false, true]) { view, bright in
                view.opacity(bright ? 0.8 : 0.2).scaleEffect(bright ? 1.2 : 0.9)
            } animation: { _ in .easeInOut(duration: 0.8) }
        }
    }
}
