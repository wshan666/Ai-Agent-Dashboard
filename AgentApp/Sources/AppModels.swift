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

    var displayIcon: String {
        icon.isEmpty ? "AI" : icon
    }

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

    var primaryModelText: String {
        if !modelLabel.isEmpty { return modelLabel }
        if !engineLabel.isEmpty { return engineLabel }
        return "Unknown model"
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

    var stableId: String {
        id ?? "\(fromName ?? from ?? "msg")-\(timestamp ?? UUID().uuidString)"
    }

    var isUser: Bool {
        from == "user" || fromName == "You"
    }

    var senderTitle: String {
        fromName ?? from ?? "Unknown"
    }
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
    let passed: Bool?
    let status: String?
    let packageUrl: String?
    let previewUrl: String?
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .code: return "Code Review"
        case .project: return "Project Upgrade"
        case .content: return "Content Publish"
        case .ppt: return "PPT Review"
        }
    }

    var subtitle: String {
        switch self {
        case .code: return "Coder + reviewer pipeline"
        case .project: return "Executor, reviewers and test command"
        case .content: return "Copy, image, integrator and reviewer"
        case .ppt: return "Outline, maker, reviewer and delivery"
        }
    }

    var systemImage: String {
        switch self {
        case .code: return "curlybraces.square"
        case .project: return "shippingbox"
        case .content: return "megaphone"
        case .ppt: return "rectangle.on.rectangle"
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

extension String {
    var asIsoDate: Date? {
        ISO8601DateFormatter().date(from: self)
    }
}
