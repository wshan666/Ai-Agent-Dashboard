import Foundation
import SwiftUI

final class ServerSettings: ObservableObject {
    @Published var baseURLString: String {
        didSet {
            UserDefaults.standard.set(baseURLString, forKey: Self.storageKey)
        }
    }
    @Published var apiToken: String {
        didSet {
            UserDefaults.standard.set(apiToken, forKey: Self.tokenStorageKey)
        }
    }

    static let storageKey = "agentServerURL"
    static let tokenStorageKey = "agentServerAPIToken"
    static let defaultURL = "http://192.168.1.100:3456"

    init() {
        self.baseURLString = UserDefaults.standard.string(forKey: Self.storageKey) ?? Self.defaultURL
        self.apiToken = UserDefaults.standard.string(forKey: Self.tokenStorageKey) ?? ""
    }

    var normalizedBaseURL: URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: Self.defaultURL)!
    }

    var trimmedAPIToken: String {
        apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
