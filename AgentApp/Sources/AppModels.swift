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

    var statusText: String {
        switch status {
        case "available": return "Online"
        case "running": return "Busy"
        case "checking": return "Checking"
        case "disabled": return "Disabled"
        default: return "Offline"
        }
    }

    var isOnline: Bool {
        status == "available" || status == "running"
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
}

struct ChatHistoryResponse: Codable {
    let topics: [ChatTopic]
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
    let active: [String]?
    let items: [DevProgressItem]?
}

struct ChatSendResponse: Codable {
    let ok: Bool?
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

struct WorkflowStartResponse: Codable {
    let ok: Bool?
    let error: String?
}

struct WorkflowCoderDraft: Identifiable, Hashable {
    let id = UUID()
    var agentId: String = ""
    var task: String = ""
}

extension String {
    var asIsoDate: Date? {
        ISO8601DateFormatter().date(from: self)
    }
}
