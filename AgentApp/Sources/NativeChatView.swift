import SwiftUI
import PhotosUI
import Speech
import AVFoundation

struct NativeChatView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var speechInput = SpeechInputController()
    @StateObject private var voiceRecorder = VoiceMessageRecorder()

    @State private var selectedAgentIds: Set<String> = []
    @State private var privateAgentId = ""
    @State private var topic = ""
    @State private var draft = ""
    @State private var messageSearchText = ""
    @State private var replyTarget: ChatReplyContext?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var attachedImageData: Data?
    @State private var attachedImagePreview: UIImage?
    @State private var isSending = false
    @State private var isSendingVoice = false
    @State private var isAutoRefreshing = false
    @State private var showAgentPicker = false
    @State private var showPrivatePicker = false
    @State private var expandedMessageIds: Set<String> = []
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

    private var baseVisibleMessages: [ChatMessage] {
        let base = Array(store.messages.suffix(800))
        if mode == .group {
            return base.filter { ($0.room ?? "").isEmpty }
        }
        guard let agent = privateAgent else { return base }
        return base.filter { message in
            if message.room == agent.id { return true }
            if message.from == agent.id { return true }
            return false
        }
    }

    private var visibleMessages: [ChatMessage] {
        let search = messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !search.isEmpty else { return baseVisibleMessages }
        return baseVisibleMessages.filter { message in
            [
                message.content,
                message.fromName,
                message.from,
                message.topic,
                message.room,
                message.replyTo?.content,
                message.replyTo?.fromName,
                message.replyTo?.from
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(search) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            topicSection
            messageStream
        }
        .v2PageBackground()
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
            speechInput.stop()
            voiceRecorder.cancel()
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
            clearReplyTarget()
            Task { await syncCurrentChat() }
        }
        .onChange(of: privateAgentId) { _ in
            guard mode == .direct else { return }
            clearReplyTarget()
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
                            .background(V2Theme.cyan.opacity(0.12))
                            .overlay(Capsule().stroke(V2Theme.cyan.opacity(0.28), lineWidth: 1))
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
                    .v2Card(tint: V2Theme.cyan)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LinearGradient(colors: [V2Theme.cyan.opacity(0.45), V2Theme.mint.opacity(0.18)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
    }

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(mode == .group ? "\u{8bdd}\u{9898}\u{ff08}\u{53ef}\u{9009}\u{ff09}" : "\u{79c1}\u{804a}\u{8bdd}\u{9898}\u{ff08}\u{53ef}\u{9009}\u{ff09}", text: $topic)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .topic)

            TextField("\u{641c}\u{7d22}\u{6d88}\u{606f}\u{3001}\u{53d1}\u{4ef6}\u{4eba}\u{6216}\u{8bdd}\u{9898}", text: $messageSearchText)
                .textFieldStyle(.roundedBorder)

            if !messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 10) {
                    Text("\u{7b5b}\u{51fa} \(visibleMessages.count) / \(baseVisibleMessages.count) \u{6761}\u{6d88}\u{606f}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("\u{6e05}\u{9664}\u{641c}\u{7d22}") {
                        messageSearchText = ""
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(V2Theme.cyan)
                }
            }

            if mode == .group, !store.topics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.topics.prefix(10), id: \.self) { item in
                            Button(item.text) { topic = item.text }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(topic == item.text ? V2Theme.cyan.opacity(0.18) : Color(.secondarySystemBackground).opacity(0.72))
                                .overlay(Capsule().stroke(topic == item.text ? V2Theme.cyan.opacity(0.38) : Color.clear, lineWidth: 1))
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(V2Theme.cyan.opacity(0.18))
                .frame(height: 1)
        }
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
            replyPreview
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
                    .foregroundStyle(V2Theme.cyan)
                    .background(V2Theme.cyan.opacity(0.13))
                    .overlay(Circle().stroke(V2Theme.cyan.opacity(0.32), lineWidth: 1))
                    .clipShape(Circle())
                        .buttonStyle(.plain)
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .foregroundStyle(V2Theme.cyan)
                        .background(V2Theme.cyan.opacity(0.13))
                        .overlay(Circle().stroke(V2Theme.cyan.opacity(0.32), lineWidth: 1))
                        .clipShape(Circle())
                }
                .disabled(isSending)

                Button {
                    toggleVoiceInput()
                } label: {
                    Image(systemName: speechInput.isRecording ? "stop.fill" : "mic.fill")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .foregroundStyle(speechInput.isRecording ? Color.white : V2Theme.cyan)
                        .background(speechInput.isRecording ? V2Theme.red : V2Theme.cyan.opacity(0.13))
                        .overlay(Circle().stroke((speechInput.isRecording ? V2Theme.red : V2Theme.cyan).opacity(0.32), lineWidth: 1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSending)

                Button {
                    Task { await toggleVoiceMessageRecording() }
                } label: {
                    Image(systemName: voiceRecorder.isRecording ? "stop.circle.fill" : "waveform.circle")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .foregroundStyle(voiceRecorder.isRecording ? Color.white : V2Theme.mint)
                        .background(voiceRecorder.isRecording ? V2Theme.red : V2Theme.mint.opacity(0.15))
                        .overlay(Circle().stroke((voiceRecorder.isRecording ? V2Theme.red : V2Theme.mint).opacity(0.34), lineWidth: 1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSending || speechInput.isRecording || isSendingVoice)

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
                .background(canSend ? V2Theme.cyan : Color.gray.opacity(0.45))
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
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LinearGradient(colors: [V2Theme.cyan.opacity(0.45), V2Theme.mint.opacity(0.18)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var replyPreview: some View {
        if let replyTarget {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\u{56de}\u{590d} \(replyTarget.senderTitle)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(V2Theme.cyan)
                    Text(compactReplyText(replyTarget.content))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    clearReplyTarget()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .v2Card(tint: V2Theme.cyan)
        }
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if let attachedImagePreview {
            HStack(spacing: 10) {
                Image(uiImage: attachedImagePreview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            .v2Card(tint: V2Theme.cyan)
        }

        if voiceRecorder.isRecording || isSendingVoice || !voiceRecorder.statusText.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: voiceRecorder.isRecording ? "waveform.circle.fill" : "waveform")
                    .foregroundStyle(voiceRecorder.isRecording ? V2Theme.red : (isSendingVoice ? V2Theme.cyan : Color.secondary))
                Text(isSendingVoice ? "\u{6b63}\u{5728}\u{53d1}\u{9001}\u{8bed}\u{97f3}..." : voiceRecorder.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .v2Card(tint: V2Theme.mint)
        }

        if speechInput.isRecording || !speechInput.statusText.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: speechInput.isRecording ? "waveform" : "mic")
                    .foregroundStyle(speechInput.isRecording ? V2Theme.red : Color.secondary)
                Text(speechInput.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
            .v2Card(tint: V2Theme.cyan)
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
                                            .foregroundStyle(V2Theme.cyan)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(V2Theme.cyan.opacity(0.11))
                                .overlay(Capsule().stroke(V2Theme.cyan.opacity(0.22), lineWidth: 1))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(10)
            .v2Card(tint: V2Theme.cyan)
        }
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        let bodyText = displayContent(for: message)
        let lineCount = bodyText.components(separatedBy: .newlines).count
        let isLong = bodyText.count > 360 || lineCount > 10
        let isExpanded = expandedMessageIds.contains(message.stableId)
        let canReply = canReply(to: message)
        let audioLinks = audioUrls(in: message.content)

        return HStack(alignment: .bottom, spacing: 10) {
            if message.isUser { Spacer(minLength: 44) } else { avatarView(for: avatarTitle(for: message)) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if message.isUser { Spacer() }
                    Text(displaySenderTitle(for: message)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(formatTime(message.timestamp)).font(.caption2).foregroundStyle(.tertiary)
                    if canReply {
                        Button("\u{56de}\u{590d}") {
                            setReplyTarget(message)
                        }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(V2Theme.cyan)
                    }
                }
                if let reply = message.replyTo {
                    replyQuoteCard(reply, isUser: message.isUser)
                }
                Text(bodyText)
                    .font(.subheadline)
                    .foregroundStyle(message.isUser ? Color.white : Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .lineLimit(isLong && !isExpanded ? 10 : nil)
                    .background(message.isUser ? V2Theme.cyan : Color(.secondarySystemBackground).opacity(0.86))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(message.isUser ? V2Theme.mint.opacity(0.38) : V2Theme.cyan.opacity(0.18), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: message.isUser ? .trailing : .leading)
                    .textSelection(.enabled)

                if isLong {
                    Button {
                        if isExpanded {
                            expandedMessageIds.remove(message.stableId)
                        } else {
                            expandedMessageIds.insert(message.stableId)
                        }
                    } label: {
                        Label(isExpanded ? "\u{6536}\u{8d77}\u{957f}\u{6d88}\u{606f}" : "\u{5c55}\u{5f00}\u{5b8c}\u{6574}\u{5185}\u{5bb9}", systemImage: isExpanded ? "chevron.up.circle" : "chevron.down.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(V2Theme.cyan)
                }

                let urls = imageUrls(in: message.content)
                if !urls.isEmpty {
                    VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                        ForEach(urls, id: \.absoluteString) { url in
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 180, height: 130)
                                        .background(Color(.secondarySystemBackground).opacity(0.86))
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 180, height: 130)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                case .failure:
                                    Label("\u{56fe}\u{7247}\u{52a0}\u{8f7d}\u{5931}\u{8d25}", systemImage: "photo")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 180, height: 70)
                                        .background(Color(.secondarySystemBackground).opacity(0.86))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: message.isUser ? .trailing : .leading)
                }

                if !audioLinks.isEmpty {
                    VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                        ForEach(audioLinks, id: \.absoluteString) { url in
                            Link(destination: url) {
                                Label("\u{6253}\u{5f00}\u{8bed}\u{97f3}", systemImage: "waveform")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(message.isUser ? Color.white.opacity(0.16) : V2Theme.mint.opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke((message.isUser ? Color.white : V2Theme.mint).opacity(0.24), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    private func replyQuoteCard(_ reply: ChatReplyContext, isUser: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\u{56de}\u{590d} \(reply.senderTitle)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isUser ? Color.white.opacity(0.9) : V2Theme.cyan)
            Text(compactReplyText(reply.content))
                .font(.caption2)
                .foregroundStyle(isUser ? Color.white.opacity(0.76) : .secondary)
                .lineLimit(3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isUser ? Color.white.opacity(0.12) : Color(.tertiarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke((isUser ? Color.white : V2Theme.cyan).opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: UIScreen.main.bounds.width * 0.72, alignment: isUser ? .trailing : .leading)
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

    private func canReply(to message: ChatMessage) -> Bool {
        guard let from = message.from, !from.isEmpty else { return false }
        return !message.isUser && from != "system"
    }

    private func avatarView(for title: String) -> some View {
        let symbol = avatarInitial(title)
        return Text(symbol.isEmpty ? "A" : symbol)
            .font(.caption.bold())
            .foregroundStyle(.primary)
            .frame(width: 34, height: 34)
            .background(V2Theme.cyan.opacity(0.12))
            .overlay(Circle().stroke(V2Theme.cyan.opacity(0.34), lineWidth: 1))
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
            let cleaned = cleanAttachmentMarkup(message.content ?? "")
            if !cleaned.isEmpty { return cleaned }
            if !audioUrls(in: message.content).isEmpty { return "\u{8bed}\u{97f3}\u{6d88}\u{606f}" }
            if !imageUrls(in: message.content).isEmpty { return "\u{56fe}\u{7247}\u{6d88}\u{606f}" }
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

    private func compactReplyText(_ content: String?) -> String {
        let cleaned = cleanAttachmentMarkup(content ?? "")
        let source = cleaned.isEmpty ? (content ?? "") : cleaned
        return source
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(120)
            .description
    }

    private func cleanAttachmentMarkup(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("![") { return false }
                if trimmed.hasPrefix("[\u{56fe}\u{7247}URL]") { return false }
                if trimmed.hasPrefix("[\u{97f3}\u{9891}URL]") { return false }
                return true
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func setReplyTarget(_ message: ChatMessage) {
        guard canReply(to: message) else { return }
        replyTarget = ChatReplyContext(
            id: message.id,
            from: message.from,
            fromName: message.fromName ?? message.senderTitle,
            content: message.content,
            timestamp: message.timestamp
        )
        if mode == .group, let from = message.from, !from.isEmpty {
            selectedAgentIds = [from]
        } else if mode == .direct, let from = message.from, !from.isEmpty {
            privateAgentId = from
        }
        focusedField = .draft
    }

    private func clearReplyTarget() {
        replyTarget = nil
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || attachedImageData != nil else { return }

        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomId = mode == .direct ? privateAgentId : nil
        let currentReplyTarget = replyTarget
        let optimisticContent = text.isEmpty ? "\u{56fe}\u{7247}\u{6d88}\u{606f}\u{ff0c}\u{6b63}\u{5728}\u{4e0a}\u{4f20}..." : text
        let optimisticMessage = ChatMessage(
            id: UUID().uuidString,
            from: "user",
            fromName: "\u{4f60}",
            content: optimisticContent,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            type: "chat",
            topic: trimmedTopic.isEmpty ? nil : trimmedTopic,
            room: roomId,
            replyTo: currentReplyTarget
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
        clearReplyTarget()
        focusedField = nil
        UIApplication.dismissKeyboard()

        do {
            let finalText = try await messageWithUploadedImage(text: text, imageData: imageData)
            try await store.sendChat(
                agentIds: targetIds,
                message: finalText,
                topic: trimmedTopic,
                room: roomId,
                replyTo: currentReplyTarget
            )
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
                replyTarget = currentReplyTarget
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
        let urls = regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return store.downloadURL(for: String(text[swiftRange]))
        }
        return Array(Set(urls)).sorted { $0.absoluteString < $1.absoluteString }
    }

    private func audioUrls(in content: String?) -> [URL] {
        let text = content ?? ""
        let pattern = #"https?://[^\s\])]+/uploads/[^\s\])]+\.(?:m4a|mp3|wav|webm|aac|ogg|caf|mp4)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        let urls = regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return store.downloadURL(for: String(text[swiftRange]))
        }
        return Array(Set(urls)).sorted { $0.absoluteString < $1.absoluteString }
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

    private func toggleVoiceMessageRecording() async {
        if voiceRecorder.isRecording {
            guard let recording = voiceRecorder.stop() else { return }
            await sendVoiceMessage(recording)
        } else {
            speechInput.stop()
            voiceRecorder.start()
        }
    }

    private func sendVoiceMessage(_ recording: VoiceRecording) async {
        isSendingVoice = true
        defer { isSendingVoice = false }

        do {
            let data = try Data(contentsOf: recording.fileURL)
            let uploadURL = try await store.uploadAttachment(data: data, mime: recording.mimeType)
            let currentReplyTarget = replyTarget
            let voiceBody = [
                "[\u{8bed}\u{97f3}\u{6d88}\u{606f}]",
                "![audio](\(uploadURL))",
                "[\u{97f3}\u{9891}URL] \(uploadURL)"
            ].joined(separator: "\n")

            let targetIds = mode == .group ? Array(selectedAgentIds) : [privateAgentId]
            let hasTargets = !targetIds.isEmpty && !targetIds.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard hasTargets else {
                if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draft += "\n"
                }
                draft += voiceBody
                voiceRecorder.statusText = ""
                store.lastError = "\u{8bed}\u{97f3}\u{5df2}\u{9644}\u{52a0}\u{5230}\u{8f93}\u{5165}\u{6846}\u{ff0c}\u{8bf7}\u{5148}\u{9009}\u{62e9}\u{63a5}\u{6536}\u{7684} Agent \u{518d}\u{53d1}\u{9001}\u{3002}"
                return
            }

            let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
            let roomId = mode == .direct ? privateAgentId : nil
            let optimisticMessage = ChatMessage(
                id: UUID().uuidString,
                from: "user",
                fromName: "\u{4f60}",
                content: "[\u{8bed}\u{97f3}\u{6d88}\u{606f}]",
                timestamp: ISO8601DateFormatter().string(from: Date()),
                type: "chat",
                topic: trimmedTopic.isEmpty ? nil : trimmedTopic,
                room: roomId,
                replyTo: currentReplyTarget
            )

            store.messages.append(optimisticMessage)
            store.messages.sort { ($0.timestamp?.asIsoDate ?? .distantPast) < ($1.timestamp?.asIsoDate ?? .distantPast) }
            clearReplyTarget()
            try await store.sendChat(
                agentIds: targetIds,
                message: voiceBody,
                topic: trimmedTopic,
                room: roomId,
                replyTo: currentReplyTarget
            )
            voiceRecorder.statusText = ""
            await syncCurrentChat()
            Task { await followUpRefreshBurst() }
        } catch {
            if let optimistic = store.messages.last, optimistic.content == "[\u{8bed}\u{97f3}\u{6d88}\u{606f}]", optimistic.from == "user" {
                store.messages.removeAll { $0.stableId == optimistic.stableId }
            }
            store.lastError = "\u{8bed}\u{97f3}\u{53d1}\u{9001}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)"
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

private struct VoiceRecording {
    let fileURL: URL
    let mimeType: String
}

private final class VoiceMessageRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var statusText = ""

    private var recorder: AVAudioRecorder?
    private var currentFileURL: URL?

    func start() {
        guard !isRecording else { return }
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.statusText = "\u{8bf7}\u{5728} iOS \u{8bbe}\u{7f6e}\u{91cc}\u{5141}\u{8bb8}\u{9ea6}\u{514b}\u{98ce}"
                    return
                }
                self.beginRecording()
            }
        }
    }

    func stop() -> VoiceRecording? {
        guard isRecording, let fileURL = currentFileURL else { return nil }
        recorder?.stop()
        recorder = nil
        isRecording = false
        statusText = "\u{8bed}\u{97f3}\u{5df2}\u{5f55}\u{5236}\u{ff0c}\u{6b63}\u{5728}\u{53d1}\u{9001}..."
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        currentFileURL = nil
        return VoiceRecording(fileURL: fileURL, mimeType: "audio/m4a")
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        currentFileURL = nil
        statusText = ""
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("agent-voice-\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.prepareToRecord()
            recorder.record()

            self.recorder = recorder
            currentFileURL = url
            isRecording = true
            statusText = "\u{6b63}\u{5728}\u{5f55}\u{97f3}\u{ff0c}\u{518d}\u{70b9}\u{4e00}\u{6b21}\u{5373}\u{53ef}\u{76f4}\u{63a5}\u{53d1}\u{9001}"
        } catch {
            cancel()
            statusText = "\u{8bed}\u{97f3}\u{542f}\u{52a8}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)"
        }
    }
}
