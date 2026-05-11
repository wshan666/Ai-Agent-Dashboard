import SwiftUI

struct NativeChatView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedAgentIds: Set<String> = []
    @State private var privateAgentId = ""
    @State private var topic = ""
    @State private var draft = ""
    @State private var isSending = false
    @State private var showAgentPicker = false
    @State private var showPrivatePicker = false
    @State private var mode: ChatMode = .group
    @FocusState private var focusedField: ChatField?

    private enum ChatField { case topic, draft }
    private enum ChatMode: String, CaseIterable, Identifiable {
        case group, direct
        var id: String { rawValue }
        var title: String {
            self == .group ? "\u{7fa4}\u{804a}" : "\u{79c1}\u{804a}"
        }
    }

    private var selectedAgents: [AgentSummary] {
        store.agents.filter { selectedAgentIds.contains($0.id) }
    }

    private var privateAgent: AgentSummary? {
        store.agents.first(where: { $0.id == privateAgentId })
    }

    private var visibleMessages: [ChatMessage] {
        let base = Array(store.messages.suffix(220))
        guard mode == .direct, let agent = privateAgent else { return base }
        return base.filter { $0.isUser || $0.from == agent.id || $0.senderTitle.contains(agent.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            topicSection
            messageStream
            composer
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\u{534f}\u{4f5c}")
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .dismissKeyboardOnTap()
        .simultaneousGesture(
            DragGesture(minimumDistance: 18).onChanged { _ in
                focusedField = nil
                UIApplication.dismissKeyboard()
            }
        )
        .onDisappear {
            focusedField = nil
            UIApplication.dismissKeyboard()
        }
        .task {
            if store.agents.isEmpty { await store.refreshDashboard() }
            if store.messages.isEmpty { await store.refreshChat() }
            if selectedAgentIds.isEmpty {
                selectedAgentIds = Set(store.agents.filter(\.isOnline).prefix(2).map(\.id))
            }
            if privateAgentId.isEmpty {
                privateAgentId = store.agents.filter(\.isOnline).first?.id ?? ""
            }
        }
        .sheet(isPresented: $showAgentPicker) { groupAgentPicker }
        .sheet(isPresented: $showPrivatePicker) { privateAgentPicker }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\u{7fa4}\u{804a}\u{534f}\u{4f5c}")
                        .font(.title2.bold())
                    Text(mode == .group
                         ? (selectedAgents.isEmpty ? "\u{5148}\u{9009}\u{62e9}\u{7fa4}\u{804a}\u{667a}\u{80fd}\u{4f53}" : "\u{5df2}\u{9009}\u{62e9} \(selectedAgents.count) \u{4e2a}\u{667a}\u{80fd}\u{4f53}")
                         : (privateAgent == nil ? "\u{5148}\u{9009}\u{62e9}\u{79c1}\u{804a}\u{5bf9}\u{8c61}" : "\u{5f53}\u{524d}\u{79c1}\u{804a}\u{ff1a}\(privateAgent!.name)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(ChatMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 148)
            }

            if mode == .group {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button(selectedAgents.isEmpty ? "\u{9009}\u{62e9}\u{667a}\u{80fd}\u{4f53}" : "\u{7f16}\u{8f91}\u{6210}\u{5458}") {
                            showAgentPicker = true
                        }
                        .buttonStyle(.borderedProminent)

                        ForEach(selectedAgents) { agent in
                            HStack(spacing: 8) {
                                Text(agent.displayIcon)
                                Text(agent.name).font(.caption.weight(.semibold))
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
            } else {
                Button {
                    showPrivatePicker = true
                } label: {
                    HStack(spacing: 10) {
                        Text(privateAgent?.displayIcon ?? "\u{1F4AC}")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(privateAgent?.name ?? "\u{9009}\u{62e9}\u{79c1}\u{804a}\u{5bf9}\u{8c61}")
                                .font(.subheadline.weight(.semibold))
                            Text(privateAgent?.primaryModelText ?? "\u{70b9}\u{51fb}\u{9009}\u{62e9}")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(mode == .group ? "\u{8bdd}\u{9898}\u{ff08}\u{53ef}\u{9009}\u{ff09}" : "\u{79c1}\u{804a}\u{8bdd}\u{9898}\u{ff08}\u{53ef}\u{9009}\u{ff09}", text: $topic)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .topic)

            if !store.topics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.topics.prefix(10), id: \.self) { item in
                            Button(item.text) { topic = item.text }
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
                        messageRow(message).id(message.stableId)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.refreshChat() }
            .onAppear { scrollToBottom(proxy: proxy) }
            .onChange(of: store.messages.count) { _ in scrollToBottom(proxy: proxy) }
        }
    }

    private var composer: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(mode == .group ? "\u{8f93}\u{5165}\u{7fa4}\u{804a}\u{6d88}\u{606f}" : "\u{8f93}\u{5165}\u{79c1}\u{804a}\u{6d88}\u{606f}", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2 ... 6)
                    .focused($focusedField, equals: .draft)

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().tint(.white).frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "paperplane.fill").font(.headline)
                    }
                }
                .frame(width: 44, height: 44)
                .foregroundStyle(.white)
                .background(canSend ? Color.blue : Color.gray.opacity(0.45))
                .clipShape(Circle())
                .disabled(!canSend || isSending)
            }

            if mode == .direct, let agent = privateAgent {
                HStack(spacing: 8) {
                    Image(systemName: "lock.bubble")
                    Text("\u{6b63}\u{5728}\u{4e0e} \(agent.name) \u{79c1}\u{804a}")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.isUser { Spacer(minLength: 44) } else { avatarView(for: message.senderTitle) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if message.isUser { Spacer() }
                    Text(message.senderTitle).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(formatTime(message.timestamp)).font(.caption2).foregroundStyle(.tertiary)
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

            if message.isUser { avatarView(for: "\u{4f60}") } else { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }

    private var groupAgentPicker: some View {
        NavigationStack {
            List(store.agents) { agent in
                Button {
                    if selectedAgentIds.contains(agent.id) { selectedAgentIds.remove(agent.id) } else { selectedAgentIds.insert(agent.id) }
                } label: {
                    HStack(spacing: 12) {
                        Text(agent.displayIcon).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name).foregroundStyle(.primary)
                            Text("\(agent.hostGroup) · \(agent.statusText)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedAgentIds.contains(agent.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("\u{9009}\u{62e9}\u{7fa4}\u{804a}\u{667a}\u{80fd}\u{4f53}")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("\u{6e05}\u{7a7a}") { selectedAgentIds.removeAll() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("\u{5b8c}\u{6210}") { showAgentPicker = false }
                }
            }
        }
    }

    private var privateAgentPicker: some View {
        NavigationStack {
            List(store.agents.filter(\.isOnline)) { agent in
                Button {
                    privateAgentId = agent.id
                    showPrivatePicker = false
                } label: {
                    HStack(spacing: 12) {
                        Text(agent.displayIcon).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name).foregroundStyle(.primary)
                            Text(agent.primaryModelText).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if privateAgentId == agent.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("\u{9009}\u{62e9}\u{79c1}\u{804a}\u{5bf9}\u{8c61}")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("\u{5b8c}\u{6210}") { showPrivatePicker = false }
                }
            }
        }
    }

    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return mode == .group ? (hasText && !selectedAgentIds.isEmpty) : (hasText && !privateAgentId.isEmpty)
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
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomId = mode == .direct ? privateAgentId : nil
        let optimisticMessage = ChatMessage(
            id: UUID().uuidString,
            from: "user",
            fromName: "\u{4f60}",
            content: text,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            type: "chat",
            topic: trimmedTopic.isEmpty ? nil : trimmedTopic,
            room: roomId
        )

        isSending = true
        defer { isSending = false }

        let targetIds = mode == .group ? Array(selectedAgentIds) : [privateAgentId]
        guard !targetIds.isEmpty else { return }

        store.messages.append(optimisticMessage)
        store.messages.sort { ($0.timestamp?.asIsoDate ?? .distantPast) < ($1.timestamp?.asIsoDate ?? .distantPast) }
        draft = ""
        focusedField = nil
        UIApplication.dismissKeyboard()

        do {
            try await store.sendChat(agentIds: targetIds, message: text, topic: trimmedTopic, room: roomId)
        } catch {
            let text = error.localizedDescription.lowercased()
            if text.contains("timed out") || text.contains("超时") {
                store.lastError = "\u{6d88}\u{606f}\u{5df2}\u{53d1}\u{51fa}\u{ff0c}\u{6b63}\u{5728}\u{7b49}\u{5f85} agent \u{56de}\u{590d}\u{3002}\u{82e5}\u{8fdc}\u{7a0b}\u{8f83}\u{6162}\u{ff0c}\u{8bf7}\u{7a0d}\u{7b49}\u{5e76}\u{4e0b}\u{62c9}\u{5237}\u{65b0}\u{3002}"
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await store.refreshChat()
                }
            } else {
                store.messages.removeAll { $0.id == optimisticMessage.id }
                store.lastError = error.localizedDescription
            }
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
