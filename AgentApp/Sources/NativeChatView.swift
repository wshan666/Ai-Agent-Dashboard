import SwiftUI

struct NativeChatView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedAgentIds: Set<String> = []
    @State private var topic = ""
    @State private var draft = ""
    @State private var isSending = false
    @State private var showAgentPicker = false

    private var selectedAgents: [AgentSummary] {
        store.agents.filter { selectedAgentIds.contains($0.id) }
    }

    private var visibleMessages: [ChatMessage] {
        Array(store.messages.suffix(160))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            topicSection
            messageStream
            composer
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Collab")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.messages.isEmpty {
                await store.refreshChat()
            }
            if selectedAgentIds.isEmpty {
                selectedAgentIds = Set(store.agents.filter(\.isOnline).prefix(1).map(\.id))
            }
        }
        .sheet(isPresented: $showAgentPicker) {
            agentPicker
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Team Chat")
                        .font(.title2.bold())
                    Text(selectedAgents.isEmpty ? "Select one or more agents to start" : "\(selectedAgents.count) agent(s) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showAgentPicker = true
                } label: {
                    Image(systemName: "plus.bubble.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 42, height: 42)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if selectedAgents.isEmpty {
                        Button("Choose Agents") {
                            showAgentPicker = true
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        ForEach(selectedAgents) { agent in
                            HStack(spacing: 8) {
                                Text(agent.displayIcon)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(agent.name)
                                        .font(.caption.weight(.semibold))
                                    Text(agent.primaryModelText)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    selectedAgentIds.remove(agent.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Topic (optional)", text: $topic)
                .textFieldStyle(.roundedBorder)

            if !store.topics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.topics.prefix(10), id: \.self) { item in
                            Button(item.text) {
                                topic = item.text
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(topic == item.text ? Color.blue.opacity(0.16) : Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var messageStream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(visibleMessages, id: \.stableId) { message in
                        messageRow(message)
                            .id(message.stableId)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await store.refreshChat()
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: store.messages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Type a message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2 ... 6)

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.headline)
                    }
                }
                .frame(width: 44, height: 44)
                .foregroundStyle(.white)
                .background(canSend ? Color.blue : Color.gray.opacity(0.45))
                .clipShape(Circle())
                .disabled(!canSend || isSending)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.isUser {
                Spacer(minLength: 44)
            } else {
                avatarView(for: message.senderTitle)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if message.isUser { Spacer() }
                    Text(message.senderTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(message.content ?? "")
                    .font(.subheadline)
                    .foregroundStyle(message.isUser ? Color.white : Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(message.isUser ? Color.blue : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: message.isUser ? .trailing : .leading)
                    .textSelection(.enabled)
            }

            if message.isUser {
                avatarView(for: "You")
            } else {
                Spacer(minLength: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }

    private var agentPicker: some View {
        NavigationStack {
            List(store.agents) { agent in
                Button {
                    if selectedAgentIds.contains(agent.id) {
                        selectedAgentIds.remove(agent.id)
                    } else {
                        selectedAgentIds.insert(agent.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(agent.displayIcon)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name)
                                .foregroundStyle(.primary)
                            Text("\(agent.hostGroup) · \(agent.statusText) · \(agent.primaryModelText)")
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
            .navigationTitle("Choose Agents")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        selectedAgentIds.removeAll()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showAgentPicker = false
                    }
                }
            }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedAgentIds.isEmpty
    }

    private func avatarView(for title: String) -> some View {
        let symbol = String(title.prefix(1)).uppercased()
        return Text(symbol.isEmpty ? "A" : symbol)
            .font(.caption.bold())
            .foregroundStyle(.primary)
            .frame(width: 34, height: 34)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Circle())
    }

    private func send() async {
        isSending = true
        defer { isSending = false }

        do {
            try await store.sendChat(
                agentIds: Array(selectedAgentIds),
                message: draft.trimmingCharacters(in: .whitespacesAndNewlines),
                topic: topic.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            draft = ""
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func formatTime(_ iso: String?) -> String {
        guard let iso, let date = iso.asIsoDate else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = visibleMessages.last else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.stableId, anchor: .bottom)
            }
        }
    }
}
