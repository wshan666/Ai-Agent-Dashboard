import Foundation

enum AgentRoute: String, CaseIterable, Identifiable {
    case dashboard
    case chat
    case workflow
    case bigscreen
    case history
    case lessons
    case upgrade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .chat: return "Chat"
        case .workflow: return "Workflow"
        case .bigscreen: return "Big Screen"
        case .history: return "History"
        case .lessons: return "Lessons"
        case .upgrade: return "Upgrade"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: return "Agents, models and active dev progress"
        case .chat: return "Public collaboration, mentions and group chat"
        case .workflow: return "Create tasks and run review pipelines"
        case .bigscreen: return "Meeting room, live feed and visual scenes"
        case .history: return "Search chat history and key steps"
        case .lessons: return "Collect retrospectives and lessons learned"
        case .upgrade: return "System upgrade, backup and restore"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2"
        case .chat: return "person.3.fill"
        case .workflow: return "point.3.connected.trianglepath.dotted"
        case .bigscreen: return "display.2"
        case .history: return "clock.arrow.circlepath"
        case .lessons: return "book.closed"
        case .upgrade: return "arrow.triangle.2.circlepath"
        }
    }
}
