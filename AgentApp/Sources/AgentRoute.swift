import Foundation

enum AgentRoute: String, CaseIterable, Identifiable {
    case dashboard, chat, workflow, bigscreen, history, lessons, upgrade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "\u{4eea}\u{8868}\u{76d8}"
        case .chat: return "\u{7fa4}\u{804a}"
        case .workflow: return "\u{5de5}\u{4f5c}\u{6d41}"
        case .bigscreen: return "\u{5927}\u{5c4f}"
        case .history: return "\u{8bb0}\u{5f55}"
        case .lessons: return "\u{590d}\u{76d8}"
        case .upgrade: return "\u{5347}\u{7ea7}"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: return "\u{667a}\u{80fd}\u{4f53}\u{3001}\u{6a21}\u{578b}\u{548c}\u{7814}\u{53d1}\u{8fdb}\u{5ea6}"
        case .chat: return "\u{516c}\u{5171}\u{534f}\u{4f5c}\u{548c}\u{7fa4}\u{804a}"
        case .workflow: return "\u{53d1}\u{8d77}\u{4efb}\u{52a1}\u{548c}\u{6d41}\u{6c34}\u{7ebf}"
        case .bigscreen: return "\u{4f1a}\u{8bae}\u{5ba4}\u{3001}\u{6d88}\u{606f}\u{6d41}\u{548c}\u{53ef}\u{89c6}\u{5316}"
        case .history: return "\u{641c}\u{7d22}\u{804a}\u{5929}\u{8bb0}\u{5f55}"
        case .lessons: return "\u{7ecf}\u{9a8c}\u{6559}\u{8bad}"
        case .upgrade: return "\u{7cfb}\u{7edf}\u{5347}\u{7ea7}\u{548c}\u{5907}\u{4efd}"
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
