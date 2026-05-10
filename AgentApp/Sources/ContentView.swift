import SwiftUI

struct ContentView: View {
    @StateObject private var settings = ServerSettings()
    @State private var selectedTab: RootTab = .collaboration

    var body: some View {
        TabView(selection: $selectedTab) {
            CollaborationHubView()
                .tabItem {
                    Label("Collab", systemImage: "person.3.fill")
                }
                .tag(RootTab.collaboration)

            NavigationStack {
                AgentWebContainer(route: .workflow)
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
        .environmentObject(settings)
    }
}

private enum RootTab {
    case collaboration
    case workflow
    case bigscreen
    case profile
}

private struct CollaborationHubView: View {
    @EnvironmentObject private var settings: ServerSettings

    private let primaryRoutes: [AgentRoute] = [.chat, .history, .lessons, .upgrade]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Agent Collaboration")
                            .font(.largeTitle.bold())
                        Text("Chat, workflows and big-screen views are now organized into an iPhone-first tab layout.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        ForEach(primaryRoutes) { route in
                            NavigationLink {
                                AgentWebContainer(route: route)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: route.systemImage)
                                        .font(.title3)
                                        .frame(width: 38, height: 38)
                                        .background(Color.blue.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(route.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(route.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(14)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Current Server")
                            .font(.headline)
                        Text(settings.normalizedBaseURL.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        NavigationLink {
                            AgentWebContainer(route: .dashboard)
                        } label: {
                            Label("Open Dashboard", systemImage: "rectangle.grid.2x2")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Collab")
        }
    }
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
