import SwiftUI
import SidebarCore

struct PanelRootView: View {
    let model: PanelModel
    let onHeight: (CGFloat) -> Void

    var body: some View {
        ScrollView {
            PanelContent(model: model)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { onHeight($0) }
        }
        .frame(width: HoverController.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PanelContent: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.store.connected {
                Text("herdr is not running").foregroundStyle(.secondary)
            } else if model.store.agents.isEmpty {
                Text("No agents").foregroundStyle(.secondary)
            }
            ForEach(model.store.blocked) { agent in
                BlockedAgentCard(agent: agent, model: model)
            }
            if !model.store.blocked.isEmpty && !model.store.others.isEmpty {
                Divider()
            }
            ForEach(model.store.others) { agent in
                AgentRow(agent: agent, model: model)
            }
        }
        .padding(12)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(agent.status.dotColor).frame(width: 8, height: 8)
                Text(agent.title).font(.headline).lineLimit(1)
            }
            Text(agent.cwd).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.head)
            ScrollView(.horizontal) {
                Text(model.screens[agent.paneID] ?? "Loading…")
                    .font(.system(size: 10, design: .monospaced))
                    .fixedSize()
                    .padding(6)
            }
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            ForEach(model.options(for: agent.paneID), id: \.number) { option in
                Button {
                    Task { await model.choose(option.number, for: agent.paneID) }
                } label: {
                    Text("\(option.number). \(option.label)")
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            HStack {
                TextField("Answer", text: draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.reply(for: agent.paneID) } }
                Button("Send") { Task { await model.reply(for: agent.paneID) } }
            }
            if let error = model.errors[agent.paneID] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .disabled(model.sending.contains(agent.paneID))
        .padding(10)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .task(id: agent) { await model.reload(agent.paneID) }
    }
}

struct AgentRow: View {
    let agent: Agent
    let model: PanelModel

    var body: some View {
        Button {
            Task { await model.focus(agent.paneID) }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(agent.status.dotColor).frame(width: 8, height: 8)
                Text(agent.title).lineLimit(1)
                Spacer()
                Text(agent.status.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension AgentStatus {
    var dotColor: Color {
        switch self {
        case .blocked: .red
        case .working: .yellow
        case .done: .green
        case .idle, .unknown: .gray
        }
    }
}
