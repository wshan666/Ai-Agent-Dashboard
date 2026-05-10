import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var agents: [AgentSummary] = []
    @Published var messages: [ChatMessage] = []
    @Published var topics: [ChatTopic] = []
    @Published var devProgress: [DevProgressItem] = []
    @Published var isLoadingDashboard = false
    @Published var isLoadingChat = false
    @Published var lastError: String?

    private let settings: ServerSettings

    init(settings: ServerSettings) {
        self.settings = settings
    }

    func refreshDashboard() async {
        isLoadingDashboard = true
        defer { isLoadingDashboard = false }

        do {
            async let agentsTask = fetchAgents()
            async let progressTask = fetchDevProgress()
            async let historyTask = fetchChatHistory()

            let agents = try await agentsTask
            let progress = try await progressTask
            let history = try await historyTask

            self.agents = agents
            self.devProgress = progress.items ?? []
            self.messages = sortedMessages(history.messages)
            self.topics = history.topics
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func refreshChat() async {
        isLoadingChat = true
        defer { isLoadingChat = false }

        do {
            let history = try await fetchChatHistory()
            self.messages = sortedMessages(history.messages)
            self.topics = history.topics
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func sendChat(agentIds: [String], message: String, topic: String) async throws {
        let payload: [String: Any] = [
            "agentIds": agentIds,
            "message": message,
            "mode": "chat",
            "topic": topic.isEmpty ? NSNull() : topic
        ]

        _ = try await postJSON(path: "/api/chat/send", payload: payload) as ChatSendResponse
        try await Task.sleep(nanoseconds: 350_000_000)
        await refreshChat()
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
        try await Task.sleep(nanoseconds: 350_000_000)
        await refreshDashboard()
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
        try await Task.sleep(nanoseconds: 350_000_000)
        await refreshDashboard()
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
        try await Task.sleep(nanoseconds: 350_000_000)
        await refreshDashboard()
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
        try await Task.sleep(nanoseconds: 350_000_000)
        await refreshDashboard()
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
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "AppStore",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: body.isEmpty ? "Request failed" : body]
            )
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func getData(path: String) async throws -> Data {
        let url = buildURL(path: path)
        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return data
    }

    private func buildURL(path: String) -> URL {
        URL(string: path, relativeTo: settings.normalizedBaseURL)!.absoluteURL
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
