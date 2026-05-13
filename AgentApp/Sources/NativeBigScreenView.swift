import SwiftUI

struct NativeBigScreenView: View {
    @EnvironmentObject private var store: AppStore

    @State private var selectedAgentIds: Set<String> = []
    @State private var topic = ""
    @State private var prompt = ""
    @State private var mode = "parallel"
    @State private var summarizerId = ""
    @State private var isRunning = false
    @State private var isContinuingDoudizhu = false
    @State private var activeRun: CollaborationRun?
    @FocusState private var focusedField: Field?

    private enum Field { case topic, prompt }

    private var selectedAgents: [AgentSummary] {
        store.agents.filter { selectedAgentIds.contains($0.id) }
    }

    private var onlineAgents: [AgentSummary] {
        store.agents.filter { !$0.disabled && $0.isOnline }
    }

    private var canRun: Bool {
        selectedAgentIds.count >= 2 &&
        (!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var latestGomokuMessage: ChatMessage? {
        store.messages.reversed().first { $0.gomoku != nil }
    }

    private var latestDoudizhuMessage: ChatMessage? {
        let indexed = store.messages.enumerated().filter { $0.element.doudizhu != nil }
        guard !indexed.isEmpty else { return nil }

        let lastFinishedIndex = indexed.last { $0.element.doudizhu?.status == "finished" }?.offset ?? -1
        let afterLastFinished = indexed.filter { $0.offset > lastFinishedIndex }
        let active = afterLastFinished.isEmpty ? indexed : afterLastFinished

        let latestGameId = active.reversed().compactMap { item -> String? in
            guard let gameId = item.element.doudizhu?.gameId, !gameId.isEmpty else { return nil }
            return gameId
        }.first
        let scoped = latestGameId == nil ? active : active.filter { $0.element.doudizhu?.gameId == latestGameId }

        if scoped.last(where: { $0.element.doudizhu?.status == "finished" }) != nil { return nil }
        let maxTurn = scoped.map { $0.element.doudizhu?.turnNo ?? -1 }.max() ?? -1
        return scoped.reversed().first { ($0.element.doudizhu?.turnNo ?? -1) >= maxTurn }?.element ?? scoped.last?.element
    }

    private var recentLiveMessages: [ChatMessage] {
        store.messages
            .filter { message in
                guard message.doudizhu == nil, message.gomoku == nil else { return false }
                guard let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else { return false }
                return ["roundtable", "debate", "chat", "api", "workflow"].contains(message.type ?? "chat")
            }
            .suffix(8)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                officeSection
                liveMessageWall
                liveGameSection
                commandCard
                agentBoard
                if let activeRun {
                    resultCard(activeRun)
                } else {
                    emptyState
                }
            }
            .padding(18)
        }
        .v2PageBackground()
        .navigationTitle("\u{6307}\u{6325}\u{5927}\u{5c4f}")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    NativeRunsView()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
            }
        }
        .refreshable { await store.refreshDashboard() }
        .dismissKeyboardOnTap()
        .task {
            if store.agents.isEmpty || store.messages.isEmpty { await store.refreshDashboard() }
            if selectedAgentIds.isEmpty {
                selectedAgentIds = Set(onlineAgents.prefix(3).map(\.id))
            }
            if activeRun == nil {
                activeRun = store.lastCollaborationRun
            }
            await refreshLivePanelsLoop()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            V2HeroHeader(
                eyebrow: "Live Ops",
                title: "\u{6307}\u{6325}\u{5927}\u{5c4f}",
                subtitle: "\u{52a8}\u{6001}\u{76d1}\u{63a7}\u{4f1a}\u{8bae}\u{53d1}\u{8a00}\u{3001}\u{6e38}\u{620f}\u{724c}\u{5c40}\u{548c}\u{591a} agent \u{534f}\u{540c}\u{4efb}\u{52a1}\u{3002}",
                systemImage: "display.2",
                tint: V2Theme.violet
            )

            HStack(spacing: 10) {
                metric("\u{5728}\u{7ebf}", "\(onlineAgents.count)", V2Theme.mint)
                metric("\u{5df2}\u{9009}", "\(selectedAgentIds.count)", V2Theme.cyan)
                metric("\u{6d88}\u{606f}", "\(store.messages.count)", V2Theme.violet)
            }
        }
    }

    private var liveGameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\u{6e38}\u{620f}\u{5b9e}\u{51b5}", systemImage: "gamecontroller")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.refreshDashboard() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.isLoadingDashboard)
            }

            if let message = latestGomokuMessage, let game = message.gomoku {
                gomokuPanel(game, message: message)
            } else {
                gamePlaceholder(
                    title: "\u{4e94}\u{5b50}\u{68cb}",
                    icon: "circle.grid.3x3.fill",
                    text: "\u{6682}\u{65e0}\u{68cb}\u{5c40}\u{3002}\u{5728}\u{7fa4}\u{804a}\u{91cc}\u{53d1}\u{8d77}\u{4e24}\u{4e2a} agent \u{4e94}\u{5b50}\u{68cb}\u{5bf9}\u{5f08}\u{540e}\u{ff0c}\u{8fd9}\u{91cc}\u{4f1a}\u{663e}\u{793a}\u{68cb}\u{76d8}\u{3002}"
                )
            }

            if let message = latestDoudizhuMessage, let game = message.doudizhu {
                doudizhuPanel(game, message: message)
            } else {
                gamePlaceholder(
                    title: "\u{6597}\u{5730}\u{4e3b}",
                    icon: "suit.club.fill",
                    text: "\u{6682}\u{65e0}\u{724c}\u{5c40}\u{3002}\u{4e09}\u{4e2a} agent \u{542f}\u{52a8}\u{6597}\u{5730}\u{4e3b}\u{540e}\u{ff0c}\u{8fd9}\u{91cc}\u{4f1a}\u{663e}\u{793a}\u{5730}\u{4e3b}\u{3001}\u{5269}\u{4f59}\u{624b}\u{724c}\u{548c}\u{684c}\u{9762}\u{51fa}\u{724c}\u{3002}"
                )
            }
        }
    }

    private var officeSection: some View {
        card {
            HStack {
                Label("\u{529e}\u{516c}\u{5ba4}\u{5927}\u{5c4f}", systemImage: "building.2")
                    .font(.headline)
                Spacer()
                Text("\u{539f}\u{751f}\u{7248}")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(groupedAgents, id: \.0) { group, agents in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(group)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                            Spacer()
                            Text("\(agents.filter(\.isOnline).count)/\(agents.count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 8)], spacing: 8) {
                            ForEach(agents) { agent in
                                VStack(spacing: 4) {
                                    Text(agent.displayIcon)
                                        .font(.caption)
                                        .frame(width: 34, height: 34)
                                        .background(statusColor(agent).opacity(0.16))
                                        .overlay(Circle().stroke(statusColor(agent).opacity(0.5), lineWidth: 1))
                                        .clipShape(Circle())
                                    Text(agent.name)
                                        .font(.system(size: 9, weight: .semibold))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground).opacity(0.68))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var liveMessageWall: some View {
        card {
            HStack {
                Label("\u{4f1a}\u{8bae}\u{53d1}\u{8a00}", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                Spacer()
                Text("\(recentLiveMessages.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if recentLiveMessages.isEmpty {
                Text("\u{5706}\u{684c}\u{4f1a}\u{8bae}\u{3001}\u{7fa4}\u{804a}\u{548c}\u{5de5}\u{4f5c}\u{6d41}\u{53d1}\u{8a00}\u{4f1a}\u{5728}\u{8fd9}\u{91cc}\u{6eda}\u{52a8}\u{51fa}\u{73b0}\u{3002}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    VStack(spacing: 10) {
                        ForEach(Array(recentLiveMessages.enumerated()), id: \.element.stableId) { index, message in
                            liveMessageBubble(message, index: index, time: time)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                                .zIndex(Double(index))
                        }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: recentLiveMessages.map(\.stableId))
            }
        }
    }

    private func gomokuPanel(_ game: GomokuGameState, message: ChatMessage) -> some View {
        card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\u{4e94}\u{5b50}\u{68cb}", systemImage: "circle.grid.3x3.fill")
                        .font(.headline)
                    Text(gomokuStatusText(game))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(game.status == "finished" ? Color.green : Color.orange)
                }
                Spacer()
                if let topic = message.topic, !topic.isEmpty {
                    Text(topic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                playerBadge(title: "\u{9ed1}\u{68cb}", name: gomokuAgentName(id: game.blackAgentId, fallback: game.blackAgentName, defaultName: "\u{9ed1}\u{65b9}"), color: .black)
                playerBadge(title: "\u{767d}\u{68cb}", name: gomokuAgentName(id: game.whiteAgentId, fallback: game.whiteAgentName, defaultName: "\u{767d}\u{65b9}"), color: .gray)
            }

            GomokuBoardView(game: game)
                .frame(height: min(UIScreen.main.bounds.width - 52, 360))

            VStack(alignment: .leading, spacing: 6) {
                if let waiting = game.waiting {
                    Text("\u{7b49}\u{5f85}\u{ff1a}\u{7b2c} \(waiting.moveNo ?? 0) \u{624b} \(waiting.agentName ?? "") \u{6267}\(waiting.stone == "W" ? "\u{767d}" : "\u{9ed1}")\u{843d}\u{5b50}")
                }
                if let last = latestGomokuMove(game) {
                    Text("\u{6700}\u{540e}\u{4e00}\u{624b}\u{ff1a}\u{7b2c} \(last.moveNo ?? 0) \u{624b} \(gomokuAgentName(id: last.agentId, fallback: last.agentName, defaultName: "")) \(gomokuCoord(last))")
                }
                if let reason = game.reason, !reason.isEmpty {
                    Text(reason)
                }
                if let url = store.downloadURL(for: game.imageUrl) {
                    Link(destination: url) {
                        Label("\u{6253}\u{5f00}\u{6700}\u{7ec8}\u{68cb}\u{76d8}\u{622a}\u{56fe}", systemImage: "photo")
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func doudizhuPanel(_ game: DoudizhuGameState, message: ChatMessage) -> some View {
        card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\u{6597}\u{5730}\u{4e3b}", systemImage: "suit.club.fill")
                        .font(.headline)
                    Text(doudizhuStatusText(game))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(game.status == "finished" ? Color.green : Color.orange)
                }
                Spacer()
                Button {
                    Task { await continueDoudizhuGame() }
                } label: {
                    if isContinuingDoudizhu {
                        ProgressView()
                    } else {
                        Label("\u{7ee7}\u{7eed}", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.bordered)
                .tint(V2Theme.cyan)
                .disabled(isContinuingDoudizhu || game.status == "finished")
            }

            if let lastPlay = effectiveLastPlay(game) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\u{684c}\u{9762}\u{51fa}\u{724c}\u{ff1a}\(lastPlay.agentName ?? "") \(lastPlay.pass == true ? "\u{8fc7}\u{724c}" : (lastPlay.type ?? "\u{51fa}\u{724c}"))")
                        .font(.caption.weight(.semibold))
                    CardRow(cards: lastPlay.cards ?? [])
                }
                .padding(12)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(spacing: 10) {
                ForEach(game.displayPlayers) { player in
                    doudizhuPlayerRow(player, game: game)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if let current = game.currentAgentName, !current.isEmpty, game.status != "finished" {
                    Text("\u{5f53}\u{524d}\u{7b49}\u{5f85}\u{ff1a}\(current)\u{ff0c}\u{7b2c} \(game.turnNo ?? 0) \u{624b}")
                }
                if let reason = game.reason, !reason.isEmpty {
                    Text(reason)
                } else if let landlord = game.landlordName, !landlord.isEmpty {
                    Text("\u{5730}\u{4e3b}\u{ff1a}\(landlord)")
                }
                if let topic = message.topic, !topic.isEmpty {
                    Text(topic)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var commandCard: some View {
        card {
            HStack {
                Label("\u{534f}\u{540c}\u{4efb}\u{52a1}", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Picker("", selection: $mode) {
                    Text("\u{5e76}\u{884c}").tag("parallel")
                    Text("\u{987a}\u{5e8f}").tag("sequential")
                    Text("\u{5706}\u{684c}").tag("roundtable")
                    Text("\u{8fa9}\u{8bba}").tag("debate")
                }
                .pickerStyle(.segmented)
                .frame(width: 232)
            }

            TextField("\u{8bdd}\u{9898}\u{ff0c}\u{4f8b}\u{5982}\u{ff1a}\u{5ba2}\u{6237}\u{4e0a}\u{7ebf}\u{65b9}\u{6848}", text: $topic)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .topic)

            TextField("\u{8f93}\u{5165}\u{8981}\u{4ea4}\u{7ed9}\u{591a}\u{4e2a} agent \u{534f}\u{4f5c}\u{7684}\u{4efb}\u{52a1}", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4 ... 8)
                .focused($focusedField, equals: .prompt)

            Picker("\u{603b}\u{7ed3} agent", selection: $summarizerId) {
                Text("\u{81ea}\u{52a8}\u{5408}\u{5e76}").tag("")
                ForEach(selectedAgents) { agent in
                    Text(agent.name).tag(agent.id)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Button("\u{9009}\u{62e9}\u{5728}\u{7ebf}\u{6210}\u{5458}") {
                    selectedAgentIds = Set(onlineAgents.prefix(4).map(\.id))
                }
                .buttonStyle(.bordered)
                .tint(V2Theme.cyan)

                Button("\u{6e05}\u{7a7a}") {
                    selectedAgentIds.removeAll()
                    summarizerId = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task { await runCollaboration() }
                } label: {
                    if isRunning {
                        ProgressView().tint(.white)
                    } else {
                        Label(mode == "roundtable" ? "\u{5f00}\u{4f1a}" : "\u{542f}\u{52a8}", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(V2Theme.cyan)
                .disabled(!canRun || isRunning)
            }
        }
    }

    private var agentBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\u{6210}\u{5458}")
                    .font(.headline)
                Spacer()
                Button(selectedAgentIds.count == onlineAgents.count ? "\u{53d6}\u{6d88}\u{5168}\u{9009}" : "\u{5168}\u{9009}\u{5728}\u{7ebf}") {
                    if selectedAgentIds.count == onlineAgents.count {
                        selectedAgentIds.removeAll()
                    } else {
                        selectedAgentIds = Set(onlineAgents.map(\.id))
                    }
                }
                .font(.caption.weight(.semibold))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(store.agents) { agent in
                    agentTile(agent)
                }
            }
        }
    }

    private func agentTile(_ agent: AgentSummary) -> some View {
        let selected = selectedAgentIds.contains(agent.id)
        return Button {
            if selected {
                selectedAgentIds.remove(agent.id)
                if summarizerId == agent.id { summarizerId = "" }
            } else if !agent.disabled {
                selectedAgentIds.insert(agent.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(agent.displayIcon)
                        .font(.title2)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.blue : Color.secondary)
                }
                Text(agent.name)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(agent.primaryModelText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack {
                    Circle()
                        .fill(agent.isOnline ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(agent.statusText)
                        .font(.caption2.weight(.semibold))
                    Spacer()
                    Text(agent.hostGroup)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .background(selected ? V2Theme.cyan.opacity(0.14) : Color(.secondarySystemBackground).opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? V2Theme.cyan.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(agent.disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(agent.disabled)
    }

    private func resultCard(_ run: CollaborationRun) -> some View {
        card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\u{534f}\u{540c}\u{7ed3}\u{679c}")
                        .font(.headline)
                    Text(run.statusText)
                        .font(.caption)
                        .foregroundStyle(run.isCompleted ? Color.green : Color.secondary)
                }
                Spacer()
                if isRunning { ProgressView() }
            }

            if let output = run.output, !output.isEmpty {
                Text(output)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let responses = run.responses, !responses.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\u{6210}\u{5458}\u{8f93}\u{51fa}")
                        .font(.subheadline.bold())
                    ForEach(responses) { response in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(response.agentName)
                                    .font(.caption.bold())
                                Spacer()
                                Text(response.status)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(response.status == "completed" ? Color.green : Color.orange)
                            }
                            Text(response.displayText.isEmpty ? "\u{65e0}\u{8f93}\u{51fa}" : response.displayText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\u{7b49}\u{5f85}\u{534f}\u{540c}\u{4efb}\u{52a1}", systemImage: "person.3.sequence")
                .font(.headline)
            Text("\u{8fd9}\u{91cc}\u{4f1a}\u{663e}\u{793a}\u{6700}\u{65b0}\u{4e00}\u{6b21}\u{539f}\u{751f}\u{534f}\u{540c}\u{6267}\u{884c}\u{7ed3}\u{679c}\u{548c}\u{6bcf}\u{4e2a}\u{6210}\u{5458}\u{7684}\u{8f93}\u{51fa}\u{3002}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .v2Card(tint: V2Theme.violet)
    }

    private func doudizhuPlayerRow(_ player: DoudizhuPlayer, game: DoudizhuGameState) -> some View {
        let isLandlord = player.agentId == game.landlordAgentId || player.role == "\u{5730}\u{4e3b}"
        let count = player.count ?? 0
        let progress = max(0.0, min(1.0, Double(count) / 20.0))

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(player.agentName ?? "\u{73a9}\u{5bb6}")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                if isLandlord {
                    Text("\u{5730}\u{4e3b}")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.16))
                        .foregroundStyle(Color.orange)
                        .clipShape(Capsule())
                } else if let role = player.role, !role.isEmpty {
                    Text(role)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(Color.blue)
                        .clipShape(Capsule())
                }
                Spacer()
                Text("\u{4f59} \(count) \u{5f20}")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(isLandlord ? .orange : .blue)

            if let cards = player.cards, !cards.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    CardRow(cards: cards)
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func gamePlaceholder(title: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .v2Card(tint: V2Theme.cyan)
    }

    private func playerBadge(title: String, name: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func liveMessageBubble(_ message: ChatMessage, index: Int, time: TimeInterval) -> some View {
        let isSystem = message.from == "system" || message.senderTitle.contains("\u{7cfb}\u{7edf}")
        let tint: Color = isSystem ? .orange : (message.type == "debate" ? .red : .blue)
        let wave = sin(time * 1.7 + Double(index) * 0.72)
        let drift = cos(time * 1.25 + Double(index) * 0.55)
        let side: Double = index.isMultiple(of: 2) ? 1 : -1
        return HStack(alignment: .top, spacing: 10) {
            avatarPill(message.senderTitle, tint: tint)
                .scaleEffect(1 + CGFloat(max(0, wave)) * 0.08)
                .shadow(color: tint.opacity(0.24 + max(0, wave) * 0.18), radius: 7 + max(0, wave) * 5)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(message.senderTitle)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    if let topic = message.topic, !topic.isEmpty {
                        Text(topic)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(message.content ?? "")
                    .font(.caption)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.18 + max(0, wave) * 0.18), lineWidth: 1)
            )
        }
        .offset(x: CGFloat(side * wave * 5), y: CGFloat(drift * 2))
        .scaleEffect(1 + CGFloat(wave) * 0.01)
        .opacity(0.92 + max(0, wave) * 0.08)
    }

    private func avatarPill(_ title: String, tint: Color) -> some View {
        let cleaned = title.replacingOccurrences(of: "\u{fe0f}", with: "")
        let letter = cleaned.first(where: { char in
            if char.isLetter || char.isNumber { return true }
            guard let value = char.unicodeScalars.first?.value else { return false }
            return value >= 0x4E00 && value <= 0x9FFF
        }).map { String($0).uppercased() } ?? "A"
        return Text(letter)
            .font(.caption.bold())
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.13))
            .clipShape(Circle())
    }

    private func gomokuAgentName(id: String?, fallback: String?, defaultName: String) -> String {
        if let fallback, !fallback.isEmpty { return fallback }
        guard let id, !id.isEmpty else { return defaultName }
        for message in store.messages.reversed() {
            guard let game = message.gomoku else { continue }
            if game.blackAgentId == id, let name = game.blackAgentName, !name.isEmpty { return name }
            if game.whiteAgentId == id, let name = game.whiteAgentName, !name.isEmpty { return name }
            if game.move?.agentId == id, let name = game.move?.agentName, !name.isEmpty { return name }
            if let move = game.moves?.first(where: { $0.agentId == id && $0.agentName?.isEmpty == false }),
               let name = move.agentName {
                return name
            }
        }
        return defaultName
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.13))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(color.opacity(0.28), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .v2Card(tint: V2Theme.violet)
    }

    private func runCollaboration() async {
        let task = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty || !trimmedTopic.isEmpty else { return }

        isRunning = true
        focusedField = nil
        UIApplication.dismissKeyboard()
        defer { isRunning = false }

        do {
            if mode == "roundtable" || mode == "debate" {
                try await store.startRoundtable(
                    agentIds: Array(selectedAgentIds),
                    topic: trimmedTopic.isEmpty ? task : trimmedTopic,
                    rounds: 1,
                    mode: mode,
                    summarizerId: summarizerId
                )
                await store.refreshMessagesSilently(limit: 800)
            } else {
                let run = try await store.startCollaboration(
                    agentIds: Array(selectedAgentIds),
                    message: task,
                    topic: trimmedTopic,
                    mode: mode,
                    summarizerId: summarizerId
                )
                activeRun = run
            }
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private var groupedAgents: [(String, [AgentSummary])] {
        Dictionary(grouping: store.agents, by: \.hostGroup)
            .map { ($0.key, $0.value.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) }
            .sorted { $0.0.localizedCompare($1.0) == .orderedAscending }
    }

    private func statusColor(_ agent: AgentSummary) -> Color {
        if agent.isOnline { return .green }
        if agent.isChecking { return .orange }
        return .red
    }

    private func refreshLivePanelsLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await store.refreshMessagesSilently(limit: 800)
        }
    }

    private var hasRunningGame: Bool {
        if let status = latestDoudizhuMessage?.doudizhu?.status, status != "finished" { return true }
        if let status = latestGomokuMessage?.gomoku?.status, status != "finished" { return true }
        return false
    }

    private func continueDoudizhuGame() async {
        isContinuingDoudizhu = true
        defer { isContinuingDoudizhu = false }
        do {
            try await store.continueDoudizhu()
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}

private struct GomokuBoardView: View {
    let game: GomokuGameState

    private var moves: [GomokuMove] {
        (game.moves ?? game.move.map { [$0] } ?? [])
            .filter { ($0.row ?? 0) > 0 && ($0.col ?? 0) > 0 }
            .sorted { ($0.moveNo ?? 0) < ($1.moveNo ?? 0) }
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let boardSize = max(3, game.size ?? 15)
            let padding: CGFloat = 20
            let span = side - padding * 2
            let cell = span / CGFloat(max(boardSize - 1, 1))
            let lastMoveNo = moves.last?.moveNo

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.78, green: 0.58, blue: 0.32))

                ForEach(0 ..< boardSize, id: \.self) { index in
                    Path { path in
                        let offset = padding + CGFloat(index) * cell
                        path.move(to: CGPoint(x: padding, y: offset))
                        path.addLine(to: CGPoint(x: side - padding, y: offset))
                        path.move(to: CGPoint(x: offset, y: padding))
                        path.addLine(to: CGPoint(x: offset, y: side - padding))
                    }
                    .stroke(Color.black.opacity(0.42), lineWidth: 0.8)
                }

                ForEach(Array(starPoints(size: boardSize).enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 5, height: 5)
                        .position(x: padding + CGFloat(point.1 - 1) * cell, y: padding + CGFloat(point.0 - 1) * cell)
                }

                ForEach(moves) { move in
                    let row = max(1, min(boardSize, move.row ?? 1))
                    let col = max(1, min(boardSize, move.col ?? 1))
                    let isWhite = move.stone == "W"
                    let isLast = move.moveNo == lastMoveNo

                    ZStack {
                        Circle()
                            .fill(isWhite ? Color.white : Color.black)
                            .shadow(color: Color.black.opacity(0.28), radius: 3, x: 0, y: 2)
                            .overlay(
                                Circle()
                                    .stroke(isLast ? Color.yellow : Color.clear, lineWidth: 3)
                            )
                        Text(move.moveNo.map(String.init) ?? "")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isWhite ? Color.black : Color.white)
                    }
                    .frame(width: max(18, cell * 0.72), height: max(18, cell * 0.72))
                    .position(x: padding + CGFloat(col - 1) * cell, y: padding + CGFloat(row - 1) * cell)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func starPoints(size: Int) -> [(Int, Int)] {
        if size >= 15 {
            return [(4, 4), (4, 8), (4, 12), (8, 4), (8, 8), (8, 12), (12, 4), (12, 8), (12, 12)]
        }
        let mid = max(2, (size + 1) / 2)
        return [(mid, mid)]
    }
}

private struct CardRow: View {
    let cards: [String]

    var body: some View {
        if cards.isEmpty {
            Text("\u{65e0}\u{51fa}\u{724c}")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 5) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    PlayingCardView(card: card)
                }
            }
        }
    }
}

private struct PlayingCardView: View {
    let card: String

    var body: some View {
        VStack(spacing: 1) {
            Text(rank)
                .font(.caption2.weight(.bold))
                .minimumScaleFactor(0.65)
            Text(suit)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(isRed ? Color.red : Color.primary)
        .frame(width: 28, height: 38)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var normalized: String {
        card.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var rank: String {
        if normalized == "SJ" { return "\u{5c0f}\u{738b}" }
        if normalized == "BJ" { return "\u{5927}\u{738b}" }
        return String(normalized.dropLast())
    }

    private var suit: String {
        switch normalized.last {
        case "S": return "\u{2660}"
        case "H": return "\u{2665}"
        case "C": return "\u{2663}"
        case "D": return "\u{2666}"
        default: return ""
        }
    }

    private var isRed: Bool {
        normalized.hasSuffix("H") || normalized.hasSuffix("D") || normalized == "BJ"
    }
}

private func latestGomokuMove(_ game: GomokuGameState) -> GomokuMove? {
    (game.moves ?? game.move.map { [$0] } ?? [])
        .filter { ($0.row ?? 0) > 0 && ($0.col ?? 0) > 0 }
        .sorted { ($0.moveNo ?? 0) < ($1.moveNo ?? 0) }
        .last
}

private func gomokuCoord(_ move: GomokuMove) -> String {
    let col = max(1, move.col ?? 1)
    let scalar = UnicodeScalar(64 + col)
    let colName = scalar.map { String(Character($0)) } ?? "\(col)"
    return "\(colName)\(move.row ?? 0)"
}

private func gomokuStatusText(_ game: GomokuGameState) -> String {
    if game.status == "finished" {
        if let winner = game.winnerName, !winner.isEmpty {
            return "\u{5df2}\u{7ed3}\u{675f}\u{ff1a}\(winner)\u{83b7}\u{80dc}"
        }
        return "\u{5df2}\u{7ed3}\u{675f}"
    }
    if let waiting = game.waiting {
        return "\u{7b49}\u{5f85}\u{7b2c} \(waiting.moveNo ?? 0) \u{624b}"
    }
    if let last = latestGomokuMove(game) {
        return "\u{8fdb}\u{884c}\u{4e2d}\u{ff1a}\u{7b2c} \(last.moveNo ?? 0) \u{624b}"
    }
    return "\u{5df2}\u{542f}\u{52a8}"
}

private func effectiveLastPlay(_ game: DoudizhuGameState) -> DoudizhuPlay? {
    if let last = game.plays?.last { return last }
    return game.lastPlay
}

private func doudizhuStatusText(_ game: DoudizhuGameState) -> String {
    if game.status == "finished" {
        if let team = game.winnerTeam, !team.isEmpty {
            return "\u{5df2}\u{7ed3}\u{675f}\u{ff1a}\(team)\u{83b7}\u{80dc}"
        }
        if let winner = game.winnerName, !winner.isEmpty {
            return "\u{5df2}\u{7ed3}\u{675f}\u{ff1a}\(winner)\u{83b7}\u{80dc}"
        }
        return "\u{5df2}\u{7ed3}\u{675f}"
    }
    if let current = game.currentAgentName, !current.isEmpty {
        return "\u{7b49}\u{5f85}\(current)\u{51fa}\u{724c}"
    }
    if let turn = game.turnNo, turn > 0 {
        return "\u{8fdb}\u{884c}\u{4e2d}\u{ff1a}\u{7b2c} \(turn) \u{624b}"
    }
    return "\u{5df2}\u{542f}\u{52a8}"
}

private func formatTime(_ iso: String?) -> String {
    guard let iso, let date = iso.asIsoDate else { return "" }
    return date.formatted(date: .omitted, time: .shortened)
}
