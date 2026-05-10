import SwiftUI

@main
struct AgentApp: App {
    @StateObject private var settings: ServerSettings
    @StateObject private var store: AppStore

    init() {
        let settings = ServerSettings()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: AppStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
        }
    }
}
