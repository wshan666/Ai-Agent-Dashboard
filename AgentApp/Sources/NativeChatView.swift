import SwiftUI
import PhotosUI
import Speech
import AVFoundation

struct NativeChatView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var speechInput = SpeechInputController()

    @State private var selectedAgentIds: Set<String> = []
    @State private var privateAgentId = ""
    @State private var topic = ""
    @State private var draft = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var attachedImageData: Data?
    @State private var attachedImagePreview: UIImage?
    @State private var isSending = false
    @State private var isAutoRefreshing = false
    @State private var showAgentPicker = false
    @State private var showPrivatePicker = false
    @State private var mode: ChatMode = .group
    @FocusState private var focusedField: ChatField?

    private let refreshTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    private enum ChatField: Hashable { case topic, draft }
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

    private var activeMentionQuery: String? {
        guard mode == .group, focusedField == .draft else { return nil }
        guard let atIndex = draft.lastIndex(of: "@") else { return nil }
        let query = String(draft[draft.index(after: atIndex)...])
        if query.contains(where: { $0.isWhitespace || $0.isNewline }) { return nil }
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var mentionCandidates: [AgentSummary] {
        guard let query = activeMentionQuery else { return [] }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.agents
            .filter { !$0.disabled }
            .filter { agent in
                normalizedQuery.isEmpty
                    || agent.name.lowercased().contains(normalizedQuery)
                    || agent.id.lowercased().contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                let lhsSelected = selectedAgentIds.contains(lhs.id)
                let rhsSelected = selectedAgentIds.contains(rhs.id)
                if lhsSelected != rhsSelected { return lhsSelected && !rhsSelected }
                if lhs.isOnline != rhs.isOnline { return lhs.isOnline && !rhs.isOnline }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
            .prefix(10)
            .map { $0 }
    }

    private var visibleMessages: [ChatMessage] {
        let base = Array(store.messages.suffix(300))
        guard mode == .direct, let agent = privateAgent else { return base }
        return base.filter { message in
            if message.room == agent.id { return true }
            if message.from == agent.id { return true }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            topicSection
            messageStream
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\u{534f}\u{4f5c}")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
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
            if selectedAgentIds.isEmpty {
                selectedAgentIds = Set(store.agents.filter(\.isOnline).prefix(2).map(\.id))
            }
            if privateAgentId.isEmpty {
                privateAgentId = store.agents.filter(\.isOnline).first?.id ?? ""
            }
            await syncCurrentChat()
        }
        .onReceive(refreshTimer) { _ in
            Task { await syncCurrentChatSilently() }
        }
        .onChange(of: mode) { _ in
            Task { await syncCurrentChat() }
        }
        .onChange(of: privateAgentId) { _ in
            guard mode == .direct else { return }
            Task { await syncCurrentChat() }
        }
        .onChange(of: selectedPhotoItem) { item in
            Task { await loadSelectedImage(item) }
        }
        .onChange(of: speechInput.transcript) { text in
            guard speechInput.isRecording else { return }
            draft = text
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
                    Color.clear.frame(height: 1).id("chat-bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await syncCurrentChat() }
            .onAppear { scrollToBottom(proxy: proxy) }
            .onChange(of: store.messages.count) { _ in scrollToBottom(proxy: proxy) }
            .onChange(of: visibleMessages.last?.stableId) { _ in scrollToBottom(proxy: proxy) }
            .onChange(of: mode) { _ in scrollToBottom(proxy: proxy) }
            .onChange(of: privateAgentId) { _ in scrollToBottom(proxy: proxy) }
            .onChange(of: focusedField) { field in
                if field == .draft { scrollToBottom(proxy: proxy) }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 12) {
            mentionSuggestionBar
            attachmentPreview

            HStack(alignment: .bottom, spacing: 10) {
                if mode == .group {
                    Button {
                        showMentionCandidates()
                    } label: {
                        Image(systemName: "at")
                            .font(.headline)
                    }
                    .frame(width: 38, height: 38)
                    .foregroundStyle(Color.blue)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Circle())
                        .buttonStyle(.plain)
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .foregroundStyle(Color.blue)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Circle())
                }
                .disabled(isSending)

                Button {
                    toggleVoiceInput()
                } label: {
                    Image(systemName: speechInput.isRecording ? "stop.fill" : "mic.fill")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .foregroundStyle(speechInput.isRecording ? Color.white : Color.blue)
                        .background(speechInput.isRecording ? Color.red : Color.blue.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSending)

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

    @ViewBuilder
    private var attachmentPreview: some View {
        if let attachedImagePreview {
            HStack(spacing: 10) {
                Image(uiImage: attachedImagePreview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\u{5df2}\u{9009}\u{62e9}\u{56fe}\u{7247}")
                        .font(.caption.weight(.semibold))
                    Text("\u{53d1}\u{9001}\u{65f6}\u{4f1a}\u{81ea}\u{52a8}\u{4e0a}\u{4f20}\u{5e76}\u{9644}\u{5230}\u{6d88}\u{606f}\u{91cc}")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    clearAttachment()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }

        if speechInput.isRecording || !speechInput.statusText.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: speechInput.isRecording ? "waveform" : "mic")
                    .foregroundStyle(speechInput.isRecording ? Color.red : Color.secondary)
                Text(speechInput.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    private var mentionSuggestionBar: some View {
        if mode == .group, !mentionCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("\u{9009}\u{62e9}\u{8981} @ \u{7684}\u{667a}\u{80fd}\u{4f53}")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mentionCandidates) { agent in
                            Button {
                                insertMention(agent)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(agent.displayIcon)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(agent.name)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Text(agent.statusText)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if selectedAgentIds.contains(agent.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(Color.blue)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.isUser { Spacer(minLength: 44) } else { avatarView(for: avatarTitle(for: message)) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if message.isUser { Spacer() }
                    Text(displaySenderTitle(for: message)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(formatTime(message.timestamp)).font(.caption2).foregroundStyle(.tertiary)
                }
                Text(displayContent(for: message))
                    .font(.subheadline)
                    .foregroundStyle(message.isUser ? Color.white : Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(message.isUser ? Color.blue : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: message.isUser ? .trailing : .leading)
                    .textSelection(.enabled)

                let urls = imageUrls(in: displayContent(for: message))
                if !urls.isEmpty {
                    VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                        ForEach(urls, id: \.absoluteString) { url in
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 180, height: 130)
                                        .background(Color(.secondarySystemBackground))
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 180, height: 130)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                case .failure:
                                    Label("\u{56fe}\u{7247}\u{52a0}\u{8f7d}\u{5931}\u{8d25}", systemImage: "photo")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 180, height: 70)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: message.isUser ? .trailing : .leading)
                }
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
        let hasContent = hasText || attachedImageData != nil
        return mode == .group ? (hasContent && !selectedAgentIds.isEmpty) : (hasContent && !privateAgentId.isEmpty)
    }

    private func avatarView(for title: String) -> some View {
        let symbol = avatarInitial(title)
        return Text(symbol.isEmpty ? "A" : symbol)
            .font(.caption.bold())
            .foregroundStyle(.primary)
            .frame(width: 34, height: 34)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Circle())
    }

    private func avatarTitle(for message: ChatMessage) -> String {
        if let thinking = thinkingDisplay(for: message) {
            return thinking
        }
        if let from = message.from, let agent = store.agents.first(where: { $0.id == from }) {
            return agent.name
        }
        return message.senderTitle
    }

    private func displaySenderTitle(for message: ChatMessage) -> String {
        if let thinking = thinkingDisplay(for: message) {
            return thinking
        }
        return message.senderTitle
    }

    private func displayContent(for message: ChatMessage) -> String {
        guard let thinking = thinkingDisplay(for: message) else {
            return message.content ?? ""
        }
        return "\(thinking) \u{6b63}\u{5728}\u{601d}\u{8003}..."
    }

    private func thinkingDisplay(for message: ChatMessage) -> String? {
        guard message.from == "system",
              let content = message.content,
              content.contains("\u{6b63}\u{5728}\u{601d}\u{8003}") else {
            return nil
        }
        if let agent = store.agents.first(where: { agent in
            content.contains(agent.name) || content.contains(agent.id)
        }) {
            return agent.name
        }
        let marker = "\u{6b63}\u{5728}\u{601d}\u{8003}"
        let rawName = content.components(separatedBy: marker).first ?? content
        let cleaned = rawName
            .replacingOccurrences(of: "\u{23f3}", with: "")
            .replacingOccurrences(of: "\u{fffd}", with: "")
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleaned.split(separator: " ").last.map(String.init) ?? cleaned
        return name.isEmpty ? "\u{667a}\u{80fd}\u{4f53}" : name
    }

    private func avatarInitial(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(of: "\u{fe0f}", with: "")
        if let char = cleaned.first(where: { char in
            guard let value = char.unicodeScalars.first?.value else { return false }
            if value >= 0x4E00 && value <= 0x9FFF { return true }
            return (value >= 65 && value <= 90) || (value >= 97 && value <= 122) || (value >= 48 && value <= 57)
        }) {
            return String(char).uppercased()
        }
        return "A"
    }

    private func showMentionCandidates() {
        focusedField = .draft
        if draft.isEmpty || draft.last?.isWhitespace == true {
            draft += "@"
        } else if activeMentionQuery == nil {
            draft += " @"
        }
    }

    private func insertMention(_ agent: AgentSummary) {
        selectedAgentIds.insert(agent.id)
        focusedField = .draft

        if let atIndex = draft.lastIndex(of: "@") {
            let tail = String(draft[draft.index(after: atIndex)...])
            if !tail.contains(where: { $0.isWhitespace || $0.isNewline }) {
                draft.replaceSubrange(atIndex ..< draft.endIndex, with: "@\(agent.name) ")
                return
            }
        }

        if !draft.isEmpty, draft.last?.isWhitespace == false {
            draft += " "
        }
        draft += "@\(agent.name) "
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || attachedImageData != nil else { return }

        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomId = mode == .direct ? privateAgentId : nil
        let optimisticContent = text.isEmpty ? "\u{56fe}\u{7247}\u{6d88}\u{606f}\u{ff0c}\u{6b63}\u{5728}\u{4e0a}\u{4f20}..." : text
        let optimisticMessage = ChatMessage(
            id: UUID().uuidString,
            from: "user",
            fromName: "\u{4f60}",
            content: optimisticContent,
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
        let imageData = attachedImageData
        draft = ""
        clearAttachment()
        focusedField = nil
        UIApplication.dismissKeyboard()

        do {
            let finalText = try await messageWithUploadedImage(text: text, imageData: imageData)
            if mode == .group, targetIds.count >= 2 {
                try await store.startRoundtable(
                    agentIds: targetIds,
                    topic: trimmedTopic.isEmpty ? finalText : "\(trimmedTopic)\n\n\(finalText)",
                    rounds: 1,
                    mode: "roundtable"
                )
            } else {
                try await store.sendChat(agentIds: targetIds, message: finalText, topic: trimmedTopic, room: roomId)
            }
            await syncCurrentChat()
            Task { await followUpRefreshBurst() }
        } catch {
            let text = error.localizedDescription.lowercased()
            if text.contains("timed out") || text.contains("超时") {
                store.lastError = "\u{6d88}\u{606f}\u{5df2}\u{53d1}\u{51fa}\u{ff0c}\u{6b63}\u{5728}\u{7b49}\u{5f85} agent \u{56de}\u{590d}\u{3002}\u{82e5}\u{8fdc}\u{7a0b}\u{8f83}\u{6162}\u{ff0c}\u{8bf7}\u{7a0d}\u{7b49}\u{5e76}\u{4e0b}\u{62c9}\u{5237}\u{65b0}\u{3002}"
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await syncCurrentChat()
                }
            } else {
                store.messages.removeAll { $0.id == optimisticMessage.id }
                store.lastError = error.localizedDescription
            }
        }
    }

    private func syncCurrentChat() async {
        if mode == .direct, !privateAgentId.isEmpty {
            await store.refreshPrivateChat(agentId: privateAgentId)
        } else {
            await store.refreshChat()
        }
    }

    private func syncCurrentChatSilently() async {
        guard !isAutoRefreshing else { return }
        isAutoRefreshing = true
        defer { isAutoRefreshing = false }
        if mode == .direct, !privateAgentId.isEmpty {
            await store.refreshPrivateChatSilently(agentId: privateAgentId)
        } else {
            await store.refreshMessagesSilently(limit: 800)
        }
    }

    private func followUpRefreshBurst() async {
        for _ in 0 ..< 45 {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await syncCurrentChatSilently()
        }
    }

    private func messageWithUploadedImage(text: String, imageData: Data?) async throws -> String {
        guard let imageData else { return text }
        let url = try await store.uploadImage(data: imageData)
        let body = text.isEmpty ? "\u{8bf7}\u{5206}\u{6790}\u{8fd9}\u{5f20}\u{56fe}\u{7247}" : text
        return "\(body)\n\n![\u{56fe}\u{7247}](\(url))"
    }

    private func imageUrls(in content: String?) -> [URL] {
        let text = content ?? ""
        let pattern = #"https?://[^\s\])]+/uploads/[^\s\])]+\.(?:jpg|jpeg|png|gif|webp|bmp)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return store.downloadURL(for: String(text[swiftRange]))
        }
    }

    private func loadSelectedImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let compressed = compressedImageData(image) else {
                store.lastError = "\u{56fe}\u{7247}\u{8bfb}\u{53d6}\u{5931}\u{8d25}"
                return
            }
            attachedImageData = compressed
            attachedImagePreview = UIImage(data: compressed) ?? image
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func compressedImageData(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: 0.82)
    }

    private func clearAttachment() {
        selectedPhotoItem = nil
        attachedImageData = nil
        attachedImagePreview = nil
    }

    private func toggleVoiceInput() {
        if speechInput.isRecording {
            speechInput.stop()
        } else {
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                speechInput.seedTranscript(draft)
            }
            speechInput.start(localeIdentifier: "zh-CN")
        }
    }

    private func formatTime(_ iso: String?) -> String {
        guard let iso, let date = iso.asIsoDate else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard !visibleMessages.isEmpty else { return }
        DispatchQueue.main.async {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
    }
}

private final class SpeechInputController: ObservableObject {
    @Published var transcript = ""
    @Published var statusText = ""
    @Published var isRecording = false

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    func seedTranscript(_ text: String) {
        transcript = text
    }

    func start(localeIdentifier: String) {
        if isRecording { return }
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        guard recognizer?.isAvailable != false else {
            statusText = "\u{8bed}\u{97f3}\u{8bc6}\u{522b}\u{6682}\u{4e0d}\u{53ef}\u{7528}"
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            AVAudioSession.sharedInstance().requestRecordPermission { micGranted in
                Task { @MainActor in
                    guard let self else { return }
                    guard speechStatus == .authorized, micGranted else {
                        self.statusText = "\u{8bf7}\u{5728} iOS \u{8bbe}\u{7f6e}\u{91cc}\u{5141}\u{8bb8}\u{9ea6}\u{514b}\u{98ce}\u{548c}\u{8bed}\u{97f3}\u{8bc6}\u{522b}"
                        return
                    }
                    self.startRecording()
                }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        statusText = transcript.isEmpty ? "" : "\u{8bed}\u{97f3}\u{5df2}\u{8f6c}\u{6210}\u{6587}\u{5b57}"
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startRecording() {
        task?.cancel()
        task = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak request] buffer, _ in
                request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isRecording = true
            statusText = "\u{6b63}\u{5728}\u{542c}\u{5199}..."
            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                        self.transcript = text
                    }
                    if error != nil || result?.isFinal == true {
                        self.stop()
                    }
                }
            }
        } catch {
            statusText = "\u{8bed}\u{97f3}\u{542f}\u{52a8}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)"
            stop()
        }
    }
}
