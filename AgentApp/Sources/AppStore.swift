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

        do {
            let progress = try await fetchDevProgress()
            devProgress = progress.items ?? progress.active ?? []
        } catch {
            errors.append("\u{7814}\u{53d1}\u{8fdb}\u{5ea6}\u{52a0}\u{8f7d}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)")
        }

        do {
            let history = try await fetchChatHistory()
            messages = sortedMessages(history.messages)
            topics = history.topics
        } catch {
            errors.append("\u{804a}\u{5929}\u{8bb0}\u{5f55}\u{52a0}\u{8f7d}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)")
        }

        lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    func refreshChat() async {
        isLoadingChat = true
        defer { isLoadingChat = false }

        do {
            let history = try await fetchChatHistory()
            messages = sortedMessages(history.messages)
            topics = history.topics
            lastError = nil
        } catch {
            lastError = "\u{804a}\u{5929}\u{8bb0}\u{5f55}\u{52a0}\u{8f7d}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)"
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

        _ = try await postJSON(path: "/api/chat/send", payload: payload) as ChatSendResponse
        lastError = nil

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await self.refreshChat()
        }
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

    func startPptWorkflow(_ draft: PptWorkflowDraft) async throws {
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

        _ = try await postJSON(path: "/api/workflow/ppt-review", payload: payload) as WorkflowStartResponse
        Task { await self.refreshDashboard() }
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
        let data = try await getData(path: "/api/agents")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var items: [AgentSummary] = []
        for (group, value) in json where !group.hasPrefix("_") {
            guard let agents = value as? [[String: Any]] else { continue }
            for raw in agents {
                items.append(
                    AgentSummary(
                        id: raw["id"] as? String ?? UUID().uuidString,
                        name: raw["name"] as? String ?? "Agent",
                        icon: raw["icon"] as? String ?? "",
                        description: raw["description"] as? String ?? "",
                        status: raw["status"] as? String ?? "offline",
                        hostGroup: raw["hostGroup"] as? String ?? group,
                        modelLabel: raw["modelLabel"] as? String ?? "",
                        engineLabel: raw["engineLabel"] as? String ?? "",
                        disabled: raw["disabled"] as? Bool ?? false
                    )
                )
            }
        }

        return items.sorted { lhs, rhs in
            if lhs.isOnline != rhs.isOnline {
                return lhs.isOnline && !rhs.isOnline
            }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    private func fetchChatHistory() async throws -> ChatHistoryResponse {
        try await getJSON(path: "/api/chat/history")
    }

    private func fetchDevProgress() async throws -> DevProgressResponse {
        try await getJSON(path: "/api/dev-progress")
    }

    private func getJSON<T: Decodable>(path: String) async throws -> T {
        let data = try await getData(path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postJSON<T: Decodable>(path: String, payload: [String: Any]) async throws -> T {
        let url = buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "AppStore",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: body.isEmpty ? "\u{8bf7}\u{6c42}\u{5931}\u{8d25}" : body]
            )
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func getData(path: String) async throws -> Data {
        let url = buildURL(path: path)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return data
    }

    private func buildURL(path: String) -> URL {
        URL(string: path, relativeTo: settings.normalizedBaseURL)!.absoluteURL
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

    private func sortedMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.sorted { lhs, rhs in
            switch (lhs.timestamp?.asIsoDate, rhs.timestamp?.asIsoDate) {
            case let (l?, r?):
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.stableId < rhs.stableId
            }
        }
    }
}
