import SwiftUI

struct NativeChatView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedAgentIds: Set<String> = []
    @State private var topic = ""
    @State private var draft = ""
    @State private var isSending = false
    @State private var showAgentPicker = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        showAgentPicker = true
                    } label: {
                        Label(selectedAgentIds.isEmpty ? "Choose agents" : "\(selectedAgentIds.count) selected", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if store.isLoadingChat || isSending {
                        ProgressView()
                    }
                }

                TextField("Topic (optional)", text: $topic)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            List {
                ForEach(store.messages.prefix(80), id: \.self) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(message.fromName ?? message.from ?? "Unknown")
                                .font(.headline)
                            Spacer()
                            Text(formatTime(message.timestamp))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(message.content ?? "")
                            .font(.subheadline)
                            .textSelection(.enabled)
                        if let type = message.type, !type.isEmpty {
                            Text(type)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await store.refreshChat()
            }

            VStack(spacing: 10) {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                Button {
                    Task { await send() }
                } label: {
                    Text(isSending ? "Sending..." : "Send")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAgentIds.isEmpty)
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Chat")
        .task {
            if store.messages.isEmpty {
                await store.refreshChat()
            }
        }
        .sheet(isPresented: $showAgentPicker) {
            NavigationStack {
                List(store.agents) { agent in
                    Button {
                        if selectedAgentIds.contains(agent.id) {
                            selectedAgentIds.remove(agent.id)
                        } else {
                            selectedAgentIds.insert(agent.id)
                        }
                    } label: {
                        HStack {
                            Text(agent.icon)
                            VStack(alignment: .leading) {
                                Text(agent.name)
                                Text(agent.hostGroup)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedAgentIds.contains(agent.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .navigationTitle("Agents")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showAgentPicker = false }
                    }
                }
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            try await store.sendChat(agentIds: Array(selectedAgentIds), message: draft, topic: topic)
            draft = ""
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func formatTime(_ iso: String?) -> String {
        guard let iso, let date = iso.asIsoDate else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
