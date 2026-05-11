import Foundation

struct AgentSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let status: String
    let hostGroup: String
    let modelLabel: String
    let engineLabel: String
    let disabled: Bool

    var displayIcon: String { icon.isEmpty ? "AI" : icon }

    var statusText: String {
        switch status {
        case "available": return "\u{5728}\u{7ebf}"
        case "running": return "\u{5fd9}\u{788c}"
        case "checking": return "\u{68c0}\u{6d4b}\u{4e2d}"
        case "disabled": return "\u{5df2}\u{7981}\u{7528}"
        default: return "\u{79bb}\u{7ebf}"
        }
    }

    var isOnline: Bool {
        status == "available" || status == "running"
    }

    var primaryModelText: String {
        if !modelLabel.isEmpty { return modelLabel }
        if !engineLabel.isEmpty { return engineLabel }
        return "\u{672a}\u{77e5}\u{6a21}\u{578b}"
    }
}

struct ChatTopic: Codable, Hashable {
    let text: String
    let setAt: String?
}

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: String?
    let from: String?
    let fromName: String?
    let content: String?
    let timestamp: String?
    let type: String?
    let topic: String?
    let room: String?
    let gomoku: GomokuGameState?
    let doudizhu: DoudizhuGameState?

    init(
        id: String?,
        from: String?,
        fromName: String?,
        content: String?,
        timestamp: String?,
        type: String?,
        topic: String?,
        room: String?,
        gomoku: GomokuGameState? = nil,
        doudizhu: DoudizhuGameState? = nil
    ) {
        self.id = id
        self.from = from
        self.fromName = fromName
        self.content = content
        self.timestamp = timestamp
        self.type = type
        self.topic = topic
        self.room = room
        self.gomoku = gomoku
        self.doudizhu = doudizhu
    }

    var stableId: String {
        id ?? "\(fromName ?? from ?? "msg")-\(timestamp ?? UUID().uuidString)"
    }

    var isUser: Bool {
        from == "user" || fromName == "You" || fromName == "\u{4f60}"
    }

    var senderTitle: String {
        fromName ?? from ?? "\u{672a}\u{77e5}"
    }
}

struct GomokuGameState: Codable, Hashable {
    let status: String?
    let blackAgentId: String?
    let blackAgentName: String?
    let whiteAgentId: String?
    let whiteAgentName: String?
    let reporterAgentId: String?
    let reporterAgentName: String?
    let winnerAgentId: String?
    let winnerName: String?
    let size: Int?
    let maxMoves: Int?
    let waiting: GomokuWaiting?
    let move: GomokuMove?
    let moves: [GomokuMove]?
    let imageUrl: String?
    let reason: String?
}

struct GomokuWaiting: Codable, Hashable {
    let moveNo: Int?
    let agentId: String?
    let agentName: String?
    let stone: String?
}

struct GomokuMove: Codable, Identifiable, Hashable {
    let moveNo: Int?
    let agentId: String?
    let agentName: String?
    let row: Int?
    let col: Int?
    let stone: String?
    let source: String?

    var id: String {
        "\(moveNo ?? 0)-\(agentId ?? "")-\(row ?? 0)-\(col ?? 0)-\(stone ?? "")"
    }
}

struct DoudizhuGameState: Codable, Hashable {
    let status: String?
    let players: [DoudizhuPlayer]?
    let handCounts: [DoudizhuPlayer]?
    let bottomCount: Int?
    let landlordAgentId: String?
    let landlordName: String?
    let currentAgentId: String?
    let currentAgentName: String?
    let turnNo: Int?
    let lastPlay: DoudizhuPlay?
    let plays: [DoudizhuPlay]?
    let winnerAgentId: String?
    let winnerName: String?
    let winnerTeam: String?
    let reason: String?

    var displayPlayers: [DoudizhuPlayer] {
        handCounts?.isEmpty == false ? (handCounts ?? []) : (players ?? [])
    }
}

struct DoudizhuPlayer: Codable, Identifiable, Hashable {
    let agentId: String?
    let agentName: String?
    let role: String?
    let count: Int?
    let cards: [String]?

    var id: String { agentId ?? agentName ?? role ?? "player-\(count ?? 0)" }
}

struct DoudizhuPlay: Codable, Identifiable, Hashable {
    let turnNo: Int?
    let agentId: String?
    let agentName: String?
    let role: String?
    let cards: [String]?
    let type: String?
    let pass: Bool?

    var id: String {
        "\(turnNo ?? 0)-\(agentId ?? agentName ?? "")-\((cards ?? []).joined(separator: "-"))-\(pass == true ? "pass" : "play")"
    }
}

struct BasicAPIResponse: Codable {
    let ok: Bool?
    let error: String?
}

struct ChatHistoryResponse: Codable {
    let topics: [ChatTopic]
    let messages: [ChatMessage]
}

struct PrivateChatHistoryResponse: Codable {
    let agentId: String
    let messages: [ChatMessage]
}

struct DevProgressItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String?
    let status: String?
    let executor: String?
    let requirement: String?
    let backup: String?
    let updatedAt: String?
    let kind: String?
}

struct DevProgressResponse: Codable {
    let active: [DevProgressItem]?
    let items: [DevProgressItem]?
}

struct ChatSendResponse: Codable {
    let ok: Bool?
    let accepted: Bool?
    let queued: Bool?
    let responses: [AgentRunResponse]?
    let error: String?
}

struct AgentRunResponse: Codable, Hashable {
    let agentId: String?
    let agentName: String?
    let ok: Bool?
    let stdout: String?
    let stderr: String?
}

struct CollaborationRun: Codable, Identifiable, Hashable {
    let id: String
    let object: String?
    let kind: String?
    let status: String
    let agentId: String?
    let agentName: String?
    let agentIds: [String]?
    let summarizerAgentId: String?
    let topic: String?
    let output: String?
    let input: String?
    let inputPreview: String?
    let error: String?
    let responses: [CollaborationAgentResponse]?
    let latencyMs: Int?
    let createdAt: String?
    let updatedAt: String?
    let startedAt: String?
    let completedAt: String?
    let cancellationRequested: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, object, kind, status, topic, output, input, error, responses
        case agentId = "agent_id"
        case agentName = "agent_name"
        case agentIds = "agent_ids"
        case summarizerAgentId = "summarizer_agent_id"
        case inputPreview = "input_preview"
        case latencyMs = "latency_ms"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case cancellationRequested = "cancellation_requested"
    }

    var isCompleted: Bool {
        status == "completed"
    }

    var displayTitle: String {
        if let topic, !topic.isEmpty { return topic }
        if let agentName, !agentName.isEmpty { return agentName }
        return kind == "collaboration" ? "Collaboration" : "Agent Run"
    }

    var previewText: String {
        let value = output?.isEmpty == false ? output : (inputPreview?.isEmpty == false ? inputPreview : error)
        return (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var statusText: String {
        switch status {
        case "queued": return "\u{6392}\u{961f}\u{4e2d}"
        case "running": return "\u{8fd0}\u{884c}\u{4e2d}"
        case "completed": return "\u{5df2}\u{5b8c}\u{6210}"
        case "failed": return "\u{5931}\u{8d25}"
        case "cancelled": return "\u{5df2}\u{53d6}\u{6d88}"
        default: return status
        }
    }

    var isActive: Bool {
        status == "queued" || status == "running"
    }
}

struct CollaborationAgentResponse: Codable, Identifiable, Hashable {
    let agentId: String
    let agentName: String
    let status: String
    let output: String?
    let error: String?
    let latencyMs: Int?
    let role: String?

    private enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case agentName = "agent_name"
        case status, output, error, role
        case latencyMs = "latency_ms"
    }

    var id: String {
        "\(agentId)-\(role ?? "member")"
    }

    var displayText: String {
        let text = (output?.isEmpty == false ? output : error) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ApiRunListResponse: Codable {
    let object: String?
    let data: [CollaborationRun]
}

struct WorkflowStartResponse: Codable {
    let ok: Bool?
    let error: String?
    let passed: Bool?
    let status: String?
    let score: Int?
    let packageUrl: String?
    let previewUrl: String?
    let previewHtmlUrl: String?
    let previewError: String?
    let pdfUrl: String?
    let pdfError: String?
    let pyUrl: String?
}

struct MusicWorkflowResponse: Codable {
    let ok: Bool?
    let error: String?
    let id: String?
    let title: String?
    let artist: String?
    let lyrics: String?
    let audioUrl: String?
    let notesUrl: String?
    let mode: String?
    let autoPlay: Bool?
}

struct MusicTrack: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let channel: String
    let duration: String
    let source: String
    let sourceLabel: String
    let previewUrl: String
    let url: String
    let rawId: String
    let artwork: String
    let lyrics: String
    let local: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case channel
        case duration
        case source
        case sourceLabel
        case previewUrl
        case url
        case rawId
        case artwork
        case lyrics
        case local
    }

    init(
        id: String,
        title: String,
        channel: String,
        duration: String,
        source: String,
        sourceLabel: String,
        previewUrl: String,
        url: String,
        rawId: String,
        artwork: String,
        lyrics: String,
        local: Bool
    ) {
        self.id = id
        self.title = title
        self.channel = channel
        self.duration = duration
        self.source = source
        self.sourceLabel = sourceLabel
        self.previewUrl = previewUrl
        self.url = url
        self.rawId = rawId
        self.artwork = artwork
        self.lyrics = lyrics
        self.local = local
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        let title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        let rawId = try container.decodeIfPresent(String.self, forKey: .rawId) ?? ""
        let decodedId = try container.decodeIfPresent(String.self, forKey: .id) ?? ""

        self.id = decodedId.isEmpty ? (rawId.isEmpty ? title : rawId) : decodedId
        self.title = title
        self.channel = try container.decodeIfPresent(String.self, forKey: .channel) ?? ""
        self.duration = try container.decodeIfPresent(String.self, forKey: .duration) ?? ""
        self.source = source
        self.sourceLabel = try container.decodeIfPresent(String.self, forKey: .sourceLabel) ?? source
        self.previewUrl = try container.decodeIfPresent(String.self, forKey: .previewUrl) ?? ""
        self.url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        self.rawId = rawId
        self.artwork = try container.decodeIfPresent(String.self, forKey: .artwork) ?? ""
        self.lyrics = try container.decodeIfPresent(String.self, forKey: .lyrics) ?? ""
        self.local = try container.decodeIfPresent(Bool.self, forKey: .local) ?? false
    }

    var artistText: String {
        channel.isEmpty ? sourceLabel : channel
    }

    var streamType: String {
        if local { return "local" }
        if !previewUrl.isEmpty { return "preview" }
        return "stream"
    }

    var stableKey: String {
        let base = [source, rawId, id, title, channel]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
        return base.isEmpty ? "music-track" : base
    }

    static func == (lhs: MusicTrack, rhs: MusicTrack) -> Bool {
        lhs.stableKey == rhs.stableKey
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(stableKey)
    }
}

struct MusicSearchResponse: Codable {
    let ok: Bool?
    let results: [MusicTrack]?
    let hint: String?
    let searchError: String?
}

struct MusicLibraryResponse: Codable {
    let ok: Bool?
    let favorites: [MusicTrack]?
    let recent: [MusicTrack]?
}

struct MusicLibraryUpdateResponse: Codable {
    let ok: Bool?
    let active: Bool?
    let favorites: [MusicTrack]?
    let recent: [MusicTrack]?
}

struct WorkflowCoderDraft: Identifiable, Hashable {
    let id = UUID()
    var agentId: String = ""
    var task: String = ""
}

enum WorkflowTemplate: String, CaseIterable, Identifiable {
    case code
    case project
    case content
    case ppt
    case music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .code: return "\u{4ee3}\u{7801}\u{5ba1}\u{67e5}"
        case .project: return "\u{9879}\u{76ee}\u{6539}\u{9020}"
        case .content: return "\u{5185}\u{5bb9}\u{53d1}\u{5e03}"
        case .ppt: return "PPT\u{5236}\u{4f5c}"
        case .music: return "\u{97f3}\u{4e50}\u{5de5}\u{4f5c}\u{6d41}"
        }
    }

    var subtitle: String {
        switch self {
        case .code: return "\u{7a0b}\u{5e8f}\u{5458}\u{4e0e}\u{8bc4}\u{5ba1}\u{534f}\u{4f5c}\u{6d41}\u{6c34}\u{7ebf}"
        case .project: return "\u{6267}\u{884c}\u{3001}\u{8bc4}\u{5ba1}\u{3001}\u{6d4b}\u{8bd5}\u{4e00}\u{4f53}\u{5316}"
        case .content: return "\u{6587}\u{6848}\u{3001}\u{914d}\u{56fe}\u{3001}\u{6574}\u{5408}\u{3001}\u{5ba1}\u{6838}"
        case .ppt: return "\u{7b56}\u{5212}\u{3001}\u{5236}\u{4f5c}\u{3001}\u{5ba1}\u{6838}\u{3001}\u{4ea4}\u{4ed8}"
        case .music: return "\u{6b4c}\u{8bcd}\u{3001}\u{8bd5}\u{542c}\u{97f3}\u{9891}\u{3001}\u{8bf4}\u{660e}\u{6587}\u{6863}"
        }
    }

    var systemImage: String {
        switch self {
        case .code: return "curlybraces.square"
        case .project: return "shippingbox"
        case .content: return "megaphone"
        case .ppt: return "rectangle.on.rectangle"
        case .music: return "music.note.list"
        }
    }
}

struct ProjectWorkflowDraft {
    var projectDir: String = ""
    var task: String = ""
    var pmId: String = ""
    var executorId: String = ""
    var reviewerIds: Set<String> = []
    var testCommand: String = ""
    var passScore: Int = 80
    var maxRetries: Int = 2
    var feishuNotify: Bool = true
}

struct ContentWorkflowDraft {
    var platform: String = "xiaohongshu"
    var topic: String = ""
    var copyAgentId: String = ""
    var imageAgentId: String = ""
    var integratorAgentId: String = ""
    var reviewerAgentId: String = ""
    var publishMode: String = "draft"
    var feishuNotify: Bool = true
}

struct PptWorkflowDraft {
    var topic: String = ""
    var audience: String = ""
    var goal: String = ""
    var slideCount: Int = 10
    var style: String = "business"
    var outlineAgentId: String = ""
    var makerAgentId: String = ""
    var reviewerAgentId: String = ""
    var finalizerAgentId: String = ""
    var outputFormat: String = "markdown"
    var passScore: Int = 85
    var maxRetries: Int = 2
    var feishuNotify: Bool = true
}

struct MusicWorkflowDraft {
    var song: String = ""
    var artist: String = ""
    var lyricsStyle: String = "\u{6d41}\u{884c}\u{6292}\u{60c5}"
    var agentId: String = ""
    var autoPlay: Bool = true
}

struct MusicResult: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String
    let audioUrl: String
    let notesUrl: String
    let lyrics: String
    let mode: String
}

extension String {
    var asIsoDate: Date? {
        isoDateFormatterWithFractionalSeconds.date(from: self)
            ?? isoDateFormatter.date(from: self)
    }
}

private let isoDateFormatterWithFractionalSeconds: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let isoDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()
