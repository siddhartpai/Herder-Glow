import SwiftUI
import SidebarCore

private enum Motion {
    static let morph = Animation.spring(response: 0.38, dampingFraction: 0.82)
    /// No bounce, so the panel settles into the tab without overshoot.
    static let collapse = Animation.smooth(duration: HoverController.closeDuration)
    static let smooth = Animation.spring(response: 0.32, dampingFraction: 0.9)
    static let fade = Animation.easeOut(duration: 0.15)
}

/// The panel surface. It grows out of the tab on open and shrinks back into the tab's exact
/// shape and position on close, staying dark the whole time.
struct PanelRootView: View {
    let model: PanelModel
    let presentation: PanelPresentation
    let onHeight: (CGFloat) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let open = presentation.isOpen
        let height = min(max(presentation.contentHeight, LightView.pillHeight), HoverController.maxHeight)
        let shape = NotchShape(closedness: open ? 0 : 1)
        ZStack(alignment: .trailing) {
            GlassSurface(closedness: open ? 0 : 1)
            ScrollView {
                PanelContent(model: model, isOpen: open)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { onHeight($0) }
            }
            .scrollIndicators(.never)
            .frame(width: HoverController.width, height: height)
            // Text leaves first on close, and arrives after the shape has grown on open.
            .opacity(open ? 1 : 0)
            .animation(reduceMotion ? Motion.fade
                       : open ? .easeOut(duration: 0.2).delay(0.06) : .easeOut(duration: 0.08), value: open)
            // The orb appears as the shape lands, so the hand-off to the real tab is invisible.
            Orb(color: model.store.color.tint, breathing: false, fast: false)
                .padding(.trailing, 5)
                .opacity(open ? 0 : 1)
                .animation(open ? .easeOut(duration: 0.08) : .easeIn(duration: 0.12).delay(HoverController.closeDuration * 0.6),
                           value: open)
        }
        // Trailing, so the shrinking frame keeps the edge side (and the orb) in view.
        .frame(width: open ? HoverController.width : LightView.pillWidth,
               height: open ? height : LightView.pillHeight, alignment: .trailing)
        .clipShape(shape)
        .background(shape.fill(Color.black.opacity(open ? 0.35 : 0)).blur(radius: 14).offset(y: 6))
        // Closed, the shape sits on the tab even when the panel has moved since it opened.
        .offset(y: open ? 0 : presentation.anchorOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.leading, HoverController.shadowMargin)
        .padding(.vertical, HoverController.shadowMargin)
        .animation(reduceMotion ? Motion.fade : open ? Motion.morph : Motion.collapse, value: open)
        .environment(\.colorScheme, .dark)
    }
}

struct GlassSurface: View {
    let closedness: CGFloat

    var body: some View {
        // Closed, the fill and outline match the tab exactly, so the hand-off cannot be seen.
        let shape = NotchShape(closedness: closedness)
        shape.fill(.ultraThinMaterial).opacity(1 - closedness)
            .overlay(shape.fill(Color.black.opacity(0.66 + 0.19 * closedness)))
            .overlay(
                NotchShape(closedness: closedness, closed: false).stroke(
                    LinearGradient(colors: [.white.opacity(0.22 - 0.08 * closedness),
                                            .white.opacity(0.04 + 0.10 * closedness)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75 - 0.25 * closedness)
            )
    }
}

/// Blur-to-sharp entrance, staggered in reading order.
private struct Reveal: ViewModifier {
    let shown: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let still = shown || reduceMotion
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: still ? 0 : 6)
            .offset(y: still ? 0 : 6)
            .animation((reduceMotion ? Motion.fade : Motion.smooth)
                .delay(shown ? 0.08 + Double(index) * 0.035 : 0), value: shown)
    }
}

private extension View {
    func reveal(_ shown: Bool, _ index: Int) -> some View { modifier(Reveal(shown: shown, index: index)) }
}

struct PanelContent: View {
    let model: PanelModel
    let isOpen: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let store = model.store
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(store: store).reveal(isOpen, 0)
            if !store.connected {
                Text("herdr is not running").font(.callout).foregroundStyle(.secondary).reveal(isOpen, 1)
            } else if store.agents.isEmpty {
                Text("No agents").font(.callout).foregroundStyle(.secondary).reveal(isOpen, 1)
            }
            ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, agent in
                BlockedAgentCard(agent: agent, model: model)
                    .reveal(isOpen, index + 1)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97)),
                                            removal: .opacity.combined(with: .move(edge: .trailing))))
            }
            VStack(spacing: 2) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, agent in
                    AgentRow(agent: agent, model: model)
                        .reveal(isOpen, model.cards.count + index + 1)
                }
            }
        }
        .padding(14)
        .animation(reduceMotion ? Motion.fade : Motion.smooth, value: store.agents)
    }
}

struct PanelHeader: View {
    let store: AgentStore

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Agents").font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            HStack(spacing: 8) {
                count(store.blocked.count, "waiting", Palette.waiting)
                count(store.agents.filter { $0.status == .working }.count, "working", Palette.working)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func count(_ value: Int, _ label: String, _ color: Color) -> some View {
        if value > 0 {
            HStack(spacing: 3) {
                Text("\(value)").monospacedDigit().contentTransition(.numericText(value: Double(value)))
                Text(label)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
        }
    }
}

struct StatusChip: View {
    let status: AgentStatus

    var body: some View {
        Text(status == .blocked ? "waiting" : status.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(status.dotColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(status.dotColor.opacity(0.16), in: Capsule())
    }
}

struct BlockedAgentCard: View {
    let agent: Agent
    let model: PanelModel

    private var draft: Binding<String> {
        Binding(get: { model.drafts[agent.paneID] ?? "" },
                set: { model.drafts[agent.paneID] = $0 })
    }

    var body: some View {
        let busy = model.sending.contains(agent.paneID)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(Palette.waiting).frame(width: 7, height: 7)
                    .shadow(color: Palette.waiting.opacity(0.8), radius: 3)
                Text(agent.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if let hint = keyHint {
                    Text(hint)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                }
                StatusChip(status: agent.status)
            }
            Label(agent.cwd, systemImage: "folder")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.head)
            ScrollView([.horizontal, .vertical]) {
                Text(model.screens[agent.paneID].map(compact) ?? "Loading…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize()
                    .padding(8)
            }
            .defaultScrollAnchor(.bottomLeading)
            .scrollIndicators(.never)
            .frame(maxHeight: 150)
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
            VStack(spacing: 4) {
                ForEach(model.options(for: agent.paneID), id: \.number) { option in
                    OptionButton(option: option, isPending: model.pendingOption[agent.paneID] == option.number) {
                        Task { await model.choose(option.number, for: agent.paneID) }
                    }
                }
            }
            HStack(spacing: 6) {
                TextField("Type an answer", text: draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { send() }
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 17))
                }
                .buttonStyle(.plain)
                .foregroundStyle(draft.wrappedValue.isEmpty ? Color.white.opacity(0.25) : Color.accentColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            if let error = model.errors[agent.paneID] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .disabled(busy)
        .padding(12)
        .background(Palette.waiting.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Palette.waiting.opacity(0.22), lineWidth: 0.75))
        .overlay {
            if model.answered.contains(agent.paneID) {
                SentOverlay().transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.answered.contains(agent.paneID))
        .onHover { inside in
            if inside { model.hoveredCard = agent.paneID }
            else if model.hoveredCard == agent.paneID { model.hoveredCard = nil }
        }
        .task(id: agent) { await model.reload(agent.paneID) }
    }

    /// Drops blank lines so the prompt fits the small terminal area.
    private func compact(_ screen: String) -> String {
        screen.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    /// "Press 1–3" on the card that digit keys answer.
    private var keyHint: String? {
        let numbers = model.options(for: agent.paneID).map(\.number)
        guard let first = numbers.first, let last = numbers.last,
              model.shortcutTarget(for: first) == agent.paneID else { return nil }
        return "Press \(first)–\(min(last, 9))"
    }

    private func send() {
        Task { await model.reply(for: agent.paneID) }
    }
}

struct OptionButton: View {
    let option: PromptOption
    let isPending: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    if isPending {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("\(option.number)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                }
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.1), in: Circle())
                Text(option.label)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(hovering ? 0.13 : 0.06),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Check mark that draws itself after an answer is sent.
struct SentOverlay: View {
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            CheckShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 30, height: 30)
                .scaleEffect(drawn || reduceMotion ? 1 : 0.7)
            Text("Sent").font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6)) { drawn = true }
        }
    }
}

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.78))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.26))
        return path
    }
}

struct AgentRow: View {
    let agent: Agent
    let model: PanelModel
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { model.expanded == agent.paneID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Task { await model.toggleSummary(agent.paneID) }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(agent.status.dotColor).frame(width: 7, height: 7)
                        .shadow(color: agent.status == .working ? agent.status.dotColor.opacity(0.8) : .clear, radius: 3)
                    Text(agent.title).font(.system(size: 12.5)).lineLimit(1)
                    Spacer(minLength: 4)
                    StatusChip(status: agent.status)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded {
                SummaryView(agent: agent, model: model)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white.opacity(isExpanded ? 0.06 : hovering ? 0.08 : 0),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipped()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.9), value: isExpanded)
    }
}

/// What the agent did: from its Claude Code transcript, or its last screen lines.
struct SummaryView: View {
    let agent: Agent
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = model.summaries[agent.paneID], summary == TranscriptSummary() {
                Text("No work in this session yet").font(.system(size: 11.5)).foregroundStyle(.secondary)
            } else if let summary = model.summaries[agent.paneID] {
                if let title = summary.title {
                    Text(title).font(.system(size: 12, weight: .semibold))
                }
                if let request = summary.lastRequest {
                    section("Your last request", request, lines: 3)
                }
                stats(summary)
                if !summary.filesChanged.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        caption("Files changed")
                        ForEach(summary.filesChanged.suffix(5), id: \.self) { path in
                            Label((path as NSString).lastPathComponent, systemImage: "doc.text")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .help(path)
                        }
                    }
                }
                if let message = summary.lastMessage {
                    section("Last message", message, lines: 4)
                }
            } else if let screen = model.screens[agent.paneID] {
                caption("Last screen lines")
                Text(lastLines(screen))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(10)
            } else {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.focus(agent.paneID) }
            } label: {
                Label("Open in herdr", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: agent.status) {
            // A status change means new work; while working, follow the transcript as it grows.
            await model.refreshSummary(agent.paneID)
            while agent.status == .working && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await model.refreshSummary(agent.paneID)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
    }

    private func section(_ label: String, _ text: String, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            caption(label)
            Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(lines)
        }
    }

    private func stats(_ summary: TranscriptSummary) -> some View {
        HStack(spacing: 10) {
            Label("\(summary.filesChanged.count) files", systemImage: "pencil")
            Label("\(summary.commandCount) commands", systemImage: "terminal")
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private func lastLines(_ screen: String) -> String {
        screen.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .suffix(10).joined(separator: "\n")
    }
}

extension AgentStatus {
    var dotColor: Color {
        switch self {
        case .blocked: Palette.waiting
        case .working: Palette.working
        case .done: Palette.calm
        case .idle, .unknown: .gray
        }
    }
}
