import Foundation
import SwiftUI

final class ServerSettings: ObservableObject {
    @Published var baseURLString: String {
        didSet {
            UserDefaults.standard.set(baseURLString, forKey: Self.storageKey)
        }
    }

    static let storageKey = "agentServerURL"
    static let defaultURL = "http://192.168.50.32:3456"

    init() {
        self.baseURLString = UserDefaults.standard.string(forKey: Self.storageKey) ?? Self.defaultURL
    }

    var normalizedBaseURL: URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: Self.defaultURL)!
    }
}
