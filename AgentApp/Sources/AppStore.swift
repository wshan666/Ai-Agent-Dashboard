import Foundation
import SwiftUI
import AVFoundation

@MainActor
final class AppStore: ObservableObject {
    @Published var agents: [AgentSummary] = []
    @Published var messages: [ChatMessage] = []
    @Published var topics: [ChatTopic] = []
    @Published var devProgress: [DevProgressItem] = []
    @Published var isLoadingDashboard = false
    @Published var isLoadingChat = false
    @Published var isSearchingMusic = false
    @Published var musicSearchHint: String?
    @Published var musicSearchResults: [MusicTrack] = []
    @Published var musicFavorites: [MusicTrack] = []
    @Published var musicRecent: [MusicTrack] = []
    @Published var currentMusicTrack: MusicTrack?
    @Published var isMusicPlaying = false
    @Published var musicCurrentTime: Double = 0
    @Published var musicDuration: Double = 0
    @Published var lastError: String?
    @Published var lastCollaborationRun: CollaborationRun?
    @Published var apiRuns: [CollaborationRun] = []
    @Published var isLoadingRuns = false

    private let settings: ServerSettings
    private var musicPlayer: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserverToken: NSObjectProtocol?
    private var currentQueue: [MusicTrack] = []
    private var currentQueueIndex: Int = -1

    init(settings: ServerSettings) {
        self.settings = settings
        configureAudioSession()
    }

    func refreshDashboard() async {
        isLoadingDashboard = true
        defer { isLoadingDashboard = false }

        var errors: [String] = []

        do {
            agents = try await fetchAgents()
        } catch {
            errors.append("\u{667a}\u{80fd}\u{4f53}\u{5217}\u{8868}\u{52a0}\u{8f7d}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)")
        }

        if let progress = try? await fetchDevProgress() {
            devProgress = progress.items ?? progress.active ?? []
        }

        if let history = try? await fetchChatHistory(limit: 800) {
            messages = sortedMessages(history.messages)
            topics = history.topics
        }

        apiRuns = (try? await fetchApiRuns(limit: 20)) ?? apiRuns

        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    func refreshChat() async {
        isLoadingChat = true
        defer { isLoadingChat = false }

        do {
            let history = try await fetchChatHistory(limit: 800)
            messages = sortedMessages(history.messages)
            topics = history.topics
            lastError = nil
        } catch {
            lastError = "\u{804a}\u{5929}\u{8bb0}\u{5f55}\u{52a0}\u{8f7d}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)"
        }
    }

    func refreshPrivateChat(agentId: String) async {
        let trimmed = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoadingChat = true
        defer { isLoadingChat = false }

        do {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
            let history: PrivateChatHistoryResponse = try await getJSON(path: "/api/chat/private/\(encoded)")
            messages = sortedMessages(history.messages)
            lastError = nil
        } catch {
            lastError = "\u{79c1}\u{804a}\u{8bb0}\u{5f55}\u{52a0}\u{8f7d}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)"
        }
    }

    func sendChat(agentIds: [String], message: String, topic: String, room: String? = nil) async throws {
        var payload: [String: Any] = [
            "agentIds": agentIds,
            "message": message,
            "mode": "chat",
            "topic": topic.isEmpty ? NSNull() : topic
        ]
        if let room, !room.isEmpty {
            payload["room"] = room
        }

        let response: ChatSendResponse = try await postJSON(path: "/api/chat/send", payload: payload, timeout: 180)
        lastError = nil

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let room, !room.isEmpty {
                await self.refreshPrivateChat(agentId: room)
            } else {
                await self.refreshChat()
            }
        }

        if response.accepted == true && response.queued == true {
            return
        }
    }

    func refreshMessagesSilently(limit: Int = 800) async {
        guard let history = try? await fetchChatHistory(limit: limit) else { return }
        messages = sortedMessages(history.messages)
        topics = history.topics
    }

    func refreshRuns(status: String? = nil, limit: Int = 50) async {
        isLoadingRuns = true
        defer { isLoadingRuns = false }

        do {
            apiRuns = try await fetchApiRuns(status: status, limit: limit)
            lastError = nil
        } catch {
            lastError = "\u{8fd0}\u{884c}\u{8bb0}\u{5f55}\u{52a0}\u{8f7d}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)"
        }
    }

    func refreshRunDetail(id: String) async throws -> CollaborationRun {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let run: CollaborationRun = try await getJSON(path: "/api/v1/runs/\(encoded)?include_input=1")
        if let index = apiRuns.firstIndex(where: { $0.id == run.id }) {
            apiRuns[index] = run
        } else {
            apiRuns.insert(run, at: 0)
        }
        if run.kind == "collaboration" {
            lastCollaborationRun = run
        }
        return run
    }

    func cancelRun(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let run: CollaborationRun = try await postJSON(path: "/api/v1/runs/\(encoded)/cancel", payload: [:])
        if let index = apiRuns.firstIndex(where: { $0.id == run.id }) {
            apiRuns[index] = run
        }
        lastError = nil
    }

    func continueDoudizhu() async throws {
        let response: BasicAPIResponse = try await postJSON(path: "/api/doudizhu/continue", payload: ["async": true], timeout: 20)
        if response.ok == false {
            throw NSError(
                domain: "AppStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: response.error ?? "\u{7ee7}\u{7eed}\u{6597}\u{5730}\u{4e3b}\u{5931}\u{8d25}"]
            )
        }
        lastError = nil
        Task { await self.refreshDashboard() }
    }

    func startCollaboration(agentIds: [String], message: String, topic: String, mode: String = "parallel", summarizerId: String? = nil) async throws -> CollaborationRun {
        var payload: [String: Any] = [
            "agent_ids": agentIds,
            "input": message,
            "topic": topic.isEmpty ? (message.isEmpty ? "协作任务" : message) : topic,
            "mode": mode,
            "async": false
        ]
        if let summarizerId, !summarizerId.isEmpty {
            payload["summarizer_agent_id"] = summarizerId
        }

        let run: CollaborationRun = try await postJSON(path: "/api/v1/collaborations", payload: payload, timeout: 240)
        lastCollaborationRun = run
        if let index = apiRuns.firstIndex(where: { $0.id == run.id }) {
            apiRuns[index] = run
        } else {
            apiRuns.insert(run, at: 0)
        }
        lastError = nil

        let collaborationMessages = collaborationChatMessages(for: run, topic: topic)
        await refreshChat()
        mergeMessages(collaborationMessages)

        Task { await self.refreshRuns(limit: 20) }
        return run
    }

    func startRoundtable(agentIds: [String], topic: String, rounds: Int = 1, mode: String = "roundtable", summarizerId: String? = nil) async throws {
        var payload: [String: Any] = [
            "agentIds": agentIds,
            "topic": topic.isEmpty ? "圆桌会议" : topic,
            "rounds": max(1, min(5, rounds)),
            "mode": mode
        ]
        if let summarizerId, !summarizerId.isEmpty {
            payload["summarizerId"] = summarizerId
        }
        let response: BasicAPIResponse = try await postJSON(path: "/api/chat/roundtable", payload: payload, timeout: 600)
        if response.ok == false {
            throw NSError(
                domain: "AppStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: response.error ?? "圆桌会议启动失败"]
            )
        }
        lastError = nil
        await refreshChat()
        Task { await self.refreshRuns(limit: 20) }
    }

    func startCodeWorkflow(task: String, coders: [WorkflowCoderDraft], reviewerIds: [String], summarizerId: String?) async throws {
        let payload: [String: Any] = [
            "task": task,
            "coders": coders.map { ["id": $0.agentId, "task": $0.task] },
            "reviewerIds": reviewerIds,
            "summarizerId": summarizerId?.isEmpty == false ? summarizerId! : NSNull(),
            "passScore": 80,
            "maxRetries": 3
        ]

        _ = try await postJSON(path: "/api/workflow/start", payload: payload) as WorkflowStartResponse
        Task { await self.refreshDashboard() }
    }

    func startProjectWorkflow(_ draft: ProjectWorkflowDraft) async throws {
        let payload: [String: Any] = [
            "projectDir": draft.projectDir,
            "task": draft.task,
            "pmId": draft.pmId.isEmpty ? NSNull() : draft.pmId,
            "executorId": draft.executorId,
            "reviewerIds": Array(draft.reviewerIds),
            "testCommand": draft.testCommand,
            "passScore": draft.passScore,
            "maxRetries": draft.maxRetries,
            "feishuNotify": draft.feishuNotify
        ]

        _ = try await postJSON(path: "/api/workflow/project-pipeline", payload: payload) as WorkflowStartResponse
        Task { await self.refreshDashboard() }
    }

    func startContentWorkflow(_ draft: ContentWorkflowDraft) async throws {
        let payload: [String: Any] = [
            "platform": draft.platform,
            "topic": draft.topic,
            "copyAgentId": draft.copyAgentId,
            "imageAgentId": draft.imageAgentId,
            "integratorAgentId": draft.integratorAgentId,
            "reviewerAgentId": draft.reviewerAgentId.isEmpty ? NSNull() : draft.reviewerAgentId,
            "publishMode": draft.publishMode,
            "feishuNotify": draft.feishuNotify
        ]

        _ = try await postJSON(path: "/api/workflow/content-publish", payload: payload) as WorkflowStartResponse
        Task { await self.refreshDashboard() }
    }

    func startPptWorkflow(_ draft: PptWorkflowDraft) async throws -> WorkflowStartResponse {
        let payload: [String: Any] = [
            "topic": draft.topic,
            "audience": draft.audience,
            "goal": draft.goal,
            "slideCount": draft.slideCount,
            "style": draft.style,
            "outputFormat": draft.outputFormat,
            "outlineAgentId": draft.outlineAgentId,
            "makerAgentId": draft.makerAgentId,
            "reviewerAgentId": draft.reviewerAgentId,
            "finalizerAgentId": draft.finalizerAgentId.isEmpty ? NSNull() : draft.finalizerAgentId,
            "passScore": draft.passScore,
            "maxRetries": draft.maxRetries,
            "feishuNotify": draft.feishuNotify
        ]

        let response: WorkflowStartResponse = try await postJSON(path: "/api/workflow/ppt-review", payload: payload, timeout: 600)
        lastError = nil
        Task { await self.refreshDashboard() }
        return response
    }

    func startMusicWorkflow(_ draft: MusicWorkflowDraft) async throws -> MusicResult {
        let payload: [String: Any] = [
            "song": draft.song,
            "artist": draft.artist,
            "lyricsStyle": draft.lyricsStyle,
            "agentId": draft.agentId.isEmpty ? NSNull() : draft.agentId,
            "autoPlay": draft.autoPlay
        ]

        let response: MusicWorkflowResponse = try await postJSON(path: "/api/music/generate", payload: payload)
        Task { await self.refreshDashboard() }

        return MusicResult(
            title: response.title ?? draft.song,
            artist: response.artist ?? draft.artist,
            audioUrl: response.audioUrl ?? "",
            notesUrl: response.notesUrl ?? "",
            lyrics: response.lyrics ?? "",
            mode: response.mode ?? ""
        )
    }

    func searchMusic(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            musicSearchResults = []
            musicSearchHint = nil
            return
        }

        isSearchingMusic = true
        defer { isSearchingMusic = false }

        do {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let response: MusicSearchResponse = try await getJSON(path: "/api/music/search?q=\(encoded)")
            musicSearchResults = response.results ?? []
            musicSearchHint = response.hint
        } catch {
            musicSearchResults = []
            musicSearchHint = error.localizedDescription
            lastError = "\u{97f3}\u{4e50}\u{641c}\u{7d22}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)"
        }
    }

    func loadMusicLibrary() async {
        do {
            let library: MusicLibraryResponse = try await getJSON(path: "/api/music/library")
            musicFavorites = library.favorites ?? []
            musicRecent = library.recent ?? []
        } catch {
            lastError = "\u{97f3}\u{4e50}\u{5217}\u{8868}\u{52a0}\u{8f7d}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)"
        }
    }

    func toggleFavorite(track: MusicTrack) async {
        do {
            let response: MusicLibraryUpdateResponse = try await postJSON(path: "/api/music/library/favorites/toggle", payload: [
                "track": musicTrackPayload(track)
            ])
            musicFavorites = response.favorites ?? []
        } catch {
            lastError = "\u{6536}\u{85cf}\u{66f4}\u{65b0}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)"
        }
    }

    func isFavorite(track: MusicTrack) -> Bool {
        musicFavorites.contains(where: { $0.stableKey == track.stableKey })
    }

    func playMusic(track: MusicTrack, queue: [MusicTrack]? = nil) {
        if let queue {
            currentQueue = queue
            currentQueueIndex = queue.firstIndex(where: { $0.stableKey == track.stableKey }) ?? -1
        } else if currentQueue.isEmpty {
            currentQueue = [track]
            currentQueueIndex = 0
        } else if let existingIndex = currentQueue.firstIndex(where: { $0.stableKey == track.stableKey }) {
            currentQueueIndex = existingIndex
        } else {
            currentQueue = [track]
            currentQueueIndex = 0
        }

        let playable = normalizedPlayableURL(for: track)
        guard let url = playable else {
            lastError = "\u{97f3}\u{9891}\u{5730}\u{5740}\u{65e0}\u{6548}"
            return
        }

        currentMusicTrack = track
        let playerItem = AVPlayerItem(url: url)

        removeMusicObservers()
        if musicPlayer == nil {
            musicPlayer = AVPlayer(playerItem: playerItem)
        } else {
            musicPlayer?.replaceCurrentItem(with: playerItem)
        }

        bindMusicProgress()
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.playNextTrack()
            }
        }

        isMusicPlaying = true
        musicPlayer?.play()
        Task { await addRecent(track: track) }
    }

    func toggleMusicPlayback() {
        guard let player = musicPlayer else { return }
        if isMusicPlaying {
            player.pause()
            isMusicPlaying = false
        } else {
            player.play()
            isMusicPlaying = true
        }
    }

    func seekMusic(to seconds: Double) {
        guard let player = musicPlayer else { return }
        let clamped = min(max(0, seconds), musicDuration)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        musicCurrentTime = clamped
    }

    func playPreviousTrack() {
        guard !currentQueue.isEmpty else {
            seekMusic(to: 0)
            return
        }
        if currentQueueIndex > 0 {
            currentQueueIndex -= 1
            playMusic(track: currentQueue[currentQueueIndex], queue: currentQueue)
        } else {
            seekMusic(to: 0)
        }
    }

    func playNextTrack() {
        guard !currentQueue.isEmpty else { return }
        let nextIndex = currentQueueIndex + 1
        guard currentQueue.indices.contains(nextIndex) else {
            isMusicPlaying = false
            return
        }
        currentQueueIndex = nextIndex
        playMusic(track: currentQueue[nextIndex], queue: currentQueue)
    }

    func stopMusic() {
        musicPlayer?.pause()
        isMusicPlaying = false
        musicCurrentTime = 0
        musicDuration = 0
    }

    private func fetchAgents() async throws -> [AgentSummary] {
        do {
            let data = try await getData(path: "/api/v1/agents")
            return try parseAgents(data)
        } catch {
            let legacyData = try await getData(path: "/api/agents")
            return try parseAgents(legacyData)
        }
    }

    func downloadURL(for raw: String?) -> URL? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: trimmed, relativeTo: settings.normalizedBaseURL)?.absoluteURL
    }

    private func parseAgents(_ data: Data) throws -> [AgentSummary] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var items: [AgentSummary] = []
        if let data = json["data"] as? [[String: Any]] {
            for raw in data {
                items.append(agentSummary(from: raw, defaultGroup: raw["hostGroup"] as? String ?? "default"))
            }
            return sortedAgents(items)
        }

        for (group, value) in json where !group.hasPrefix("_") {
            guard let agents = value as? [[String: Any]] else { continue }
            for raw in agents {
                items.append(agentSummary(from: raw, defaultGroup: group))
            }
        }

        return sortedAgents(items)
    }

    private func fetchChatHistory(limit: Int? = nil) async throws -> ChatHistoryResponse {
        if let limit {
            return try await getJSON(path: "/api/chat/history?limit=\(max(1, min(1000, limit)))")
        }
        return try await getJSON(path: "/api/chat/history")
    }

    private func fetchDevProgress() async throws -> DevProgressResponse {
        try await getJSON(path: "/api/dev-progress")
    }

    private func fetchApiRuns(status: String? = nil, limit: Int = 50) async throws -> [CollaborationRun] {
        var query = "?limit=\(max(1, min(100, limit)))"
        if let status, !status.isEmpty, status != "all" {
            query += "&status=\(status.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? status)"
        }
        let response: ApiRunListResponse = try await getJSON(path: "/api/v1/runs\(query)")
        return response.data
    }

    private func getJSON<T: Decodable>(path: String) async throws -> T {
        let data = try await getData(path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postJSON<T: Decodable>(path: String, payload: [String: Any], timeout: TimeInterval = 90) async throws -> T {
        let url = buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw requestError(response: response, body: body)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func getData(path: String) async throws -> Data {
        let url = buildURL(path: path)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        applyAuth(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw requestError(response: response, body: body)
        }

        return data
    }

    private func buildURL(path: String) -> URL {
        URL(string: path, relativeTo: settings.normalizedBaseURL)!.absoluteURL
    }

    private func applyAuth(to request: inout URLRequest) {
        let token = settings.trimmedAPIToken
        guard !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func requestError(response: URLResponse, body: String) -> NSError {
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        let message: String
        if code == 401 {
            message = "\u{670d}\u{52a1}\u{5668}\u{9700}\u{8981}\u{6388}\u{6743}\u{ff0c}\u{8bf7}\u{5728}\u{6211}\u{7684} > API Token \u{586b}\u{5165} DASHBOARD_API_TOKEN\u{3002}"
        } else if code == 404 {
            message = "\u{63a5}\u{53e3}\u{4e0d}\u{5b58}\u{5728}\u{ff0c}\u{8bf7}\u{786e}\u{8ba4} Dashboard \u{670d}\u{52a1}\u{5df2}\u{542f}\u{52a8}\u{5e76}\u{662f}\u{6700}\u{65b0}\u{7248}\u{672c}\u{3002}"
        } else if !body.isEmpty {
            message = body
        } else {
            message = "\u{8bf7}\u{6c42}\u{5931}\u{8d25}\u{ff1a}HTTP \(code)"
        }
        return NSError(domain: "AppStore", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func agentSummary(from raw: [String: Any], defaultGroup: String) -> AgentSummary {
        AgentSummary(
            id: raw["id"] as? String ?? UUID().uuidString,
            name: raw["name"] as? String ?? "Agent",
            icon: raw["icon"] as? String ?? "",
            description: raw["description"] as? String ?? "",
            status: raw["status"] as? String ?? "offline",
            hostGroup: raw["hostGroup"] as? String ?? defaultGroup,
            modelLabel: raw["modelLabel"] as? String ?? "",
            engineLabel: raw["engineLabel"] as? String ?? "",
            disabled: raw["disabled"] as? Bool ?? false
        )
    }

    private func sortedAgents(_ items: [AgentSummary]) -> [AgentSummary] {
        items.sorted { lhs, rhs in
            if lhs.isOnline != rhs.isOnline {
                return lhs.isOnline && !rhs.isOnline
            }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    private func musicTrackPayload(_ track: MusicTrack) -> [String: Any] {
        [
            "id": track.id,
            "rawId": track.rawId,
            "title": track.title,
            "channel": track.channel,
            "type": track.streamType,
            "previewUrl": track.previewUrl,
            "url": track.url,
            "artwork": track.artwork,
            "duration": track.duration,
            "sourceLabel": track.sourceLabel,
            "source": track.source,
            "lyrics": track.lyrics,
            "local": track.local
        ]
    }

    private func addRecent(track: MusicTrack) async {
        do {
            let response: MusicLibraryUpdateResponse = try await postJSON(path: "/api/music/library/recent", payload: [
                "track": musicTrackPayload(track)
            ])
            musicRecent = response.recent ?? musicRecent
        } catch {}
    }

    private func normalizedPlayableURL(for track: MusicTrack) -> URL? {
        let raw: String
        if track.local, !track.url.isEmpty {
            raw = track.url
        } else if !track.previewUrl.isEmpty {
            raw = track.previewUrl
        } else if !track.url.isEmpty {
            raw = track.url
        } else {
            raw = "/api/music/stream?id=\(track.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track.id)&title=\(track.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track.title)"
        }

        let normalized = normalizeMusicURLString(raw)
        return URL(string: normalized, relativeTo: settings.normalizedBaseURL)?.absoluteURL
    }

    private func normalizeMusicURLString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.lowercased().hasPrefix("http://m"), trimmed.lowercased().contains(".music.126.net/") {
            return "https://" + trimmed.dropFirst("http://".count)
        }
        if trimmed.lowercased().hasPrefix("http://music.126.net/") {
            return "https://" + trimmed.dropFirst("http://".count)
        }
        return trimmed
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try session.setActive(true)
        } catch {}
    }

    private func bindMusicProgress() {
        guard let player = musicPlayer else { return }
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.musicCurrentTime = time.seconds.isFinite ? time.seconds : 0
                let duration = player.currentItem?.duration.seconds ?? 0
                self.musicDuration = duration.isFinite ? duration : 0
                self.isMusicPlaying = player.timeControlStatus == .playing
            }
        }
    }

    private func removeMusicObservers() {
        if let token = timeObserverToken {
            musicPlayer?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
    }

    private func collaborationChatMessages(for run: CollaborationRun, topic: String) -> [ChatMessage] {
        let timestamp = run.completedAt ?? run.updatedAt ?? ISO8601DateFormatter().string(from: Date())
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageTopic = run.topic?.isEmpty == false ? run.topic : (trimmedTopic.isEmpty ? nil : trimmedTopic)
        var items: [ChatMessage] = []

        let responses = run.responses ?? []
        for (index, response) in responses.enumerated() {
            let text = response.displayText
            guard !text.isEmpty || response.status == "failed" else { continue }

            items.append(ChatMessage(
                id: "ios-\(run.id)-\(response.agentId)-\(response.role ?? "member")-\(index)",
                from: response.agentId,
                fromName: response.agentName,
                content: text.isEmpty ? response.status : text,
                timestamp: timestamp,
                type: response.status == "failed" ? "error" : "api",
                topic: messageTopic,
                room: nil
            ))
        }

        let output = run.output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if responses.isEmpty, !output.isEmpty {
            items.append(ChatMessage(
                id: "ios-\(run.id)-summary",
                from: "api-collaboration",
                fromName: "\u{534f}\u{540c}\u{7ed3}\u{679c}",
                content: output,
                timestamp: timestamp,
                type: "api",
                topic: messageTopic,
                room: nil
            ))
        }

        return items
    }

    private func mergeMessages(_ incoming: [ChatMessage]) {
        guard !incoming.isEmpty else { return }
        var byId: [String: ChatMessage] = [:]
        for message in messages {
            byId[message.stableId] = message
        }
        for message in incoming {
            byId[message.stableId] = message
        }
        messages = sortedMessages(Array(byId.values))
    }

    private func sortedMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.enumerated().sorted { lhsItem, rhsItem in
            let lhs = lhsItem.element
            let rhs = rhsItem.element
            switch (lhs.timestamp?.asIsoDate, rhs.timestamp?.asIsoDate) {
            case let (l?, r?):
                return l == r ? lhsItem.offset < rhsItem.offset : l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhsItem.offset < rhsItem.offset
            }
        }.map(\.element)
    }
}
