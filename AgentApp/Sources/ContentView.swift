import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: ServerSettings
    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: RootTab = .collaboration

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                NativeDashboardView()
            }
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(RootTab.collaboration)

            NavigationStack {
                NativeChatView()
            }
            .tabItem {
                Label("Collab", systemImage: "person.3.fill")
            }
            .tag(RootTab.chat)

            NavigationStack {
                NativeWorkflowView()
            }
            .tabItem {
                Label("Workflow", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .tag(RootTab.workflow)

            NavigationStack {
                AgentWebContainer(route: .bigscreen)
            }
            .tabItem {
                Label("Big Screen", systemImage: "display.2")
            }
            .tag(RootTab.bigscreen)

            ProfileView()
                .tabItem {
                    Label("Me", systemImage: "person.crop.circle")
                }
                .tag(RootTab.profile)
        }
        .tint(.blue)
        .task {
            if store.agents.isEmpty {
                await store.refreshDashboard()
            }
        }
        .alert("Request Error", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

private enum RootTab {
    case collaboration
    case chat
    case workflow
    case bigscreen
    case profile
}

private struct ProfileView: View {
    @EnvironmentObject private var settings: ServerSettings
    @State private var draftURL: String = ""
    @State private var testStatus: String = "Not tested"
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server URL") {
                    TextField("http://192.168.50.32:3456", text: $draftURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()

                    Button("Save and Use") {
                        settings.baseURLString = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    Button(isTesting ? "Testing..." : "Test Connection") {
                        testConnection()
                    }
                    .disabled(isTesting)

                    Text(testStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Quick Access") {
                    NavigationLink {
                        AgentWebContainer(route: .dashboard)
                    } label: {
                        Label("Dashboard", systemImage: AgentRoute.dashboard.systemImage)
                    }

                    NavigationLink {
                        AgentWebContainer(route: .upgrade)
                    } label: {
                        Label("Upgrade", systemImage: AgentRoute.upgrade.systemImage)
                    }
                }
            }
            .navigationTitle("Me")
            .onAppear {
                draftURL = settings.baseURLString
            }
        }
    }

    private func testConnection() {
        let target = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: target), url.scheme != nil else {
            testStatus = "Invalid URL format"
            return
        }

        isTesting = true
        testStatus = "Testing..."

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                isTesting = false
                if let error {
                    testStatus = "Connection failed: \(error.localizedDescription)"
                } else if let http = response as? HTTPURLResponse {
                    testStatus = "Connected: HTTP \(http.statusCode)"
                } else {
                    testStatus = "Connected"
                }
            }
        }.resume()
    }
}
