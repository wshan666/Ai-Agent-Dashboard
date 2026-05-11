import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: ServerSettings
    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: RootTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { NativeDashboardView() }
                .tabItem { Label("\u{9996}\u{9875}", systemImage: "house") }
                .tag(RootTab.home)

            NavigationStack { NativeChatView() }
                .tabItem { Label("\u{534f}\u{4f5c}", systemImage: "person.3.fill") }
                .tag(RootTab.chat)

            NavigationStack { NativeWorkflowView() }
                .tabItem { Label("\u{5de5}\u{4f5c}\u{6d41}", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(RootTab.workflow)

            NavigationStack { AgentWebContainer(route: .bigscreen) }
                .tabItem { Label("\u{5927}\u{5c4f}", systemImage: "display.2") }
                .tag(RootTab.bigscreen)

            ProfileView()
                .tabItem { Label("\u{6211}\u{7684}", systemImage: "person.crop.circle") }
                .tag(RootTab.profile)
        }
        .tint(.blue)
        .onChange(of: selectedTab) { _ in UIApplication.dismissKeyboard() }
        .task {
            if store.agents.isEmpty {
                await store.refreshDashboard()
            }
        }
        .alert("\u{8bf7}\u{6c42}\u{9519}\u{8bef}", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("\u{77e5}\u{9053}\u{4e86}", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

private enum RootTab { case home, chat, workflow, bigscreen, profile }

private struct ProfileView: View {
    @EnvironmentObject private var settings: ServerSettings
    @State private var draftURL: String = ""
    @State private var testStatus: String = "\u{5c1a}\u{672a}\u{6d4b}\u{8bd5}"
    @State private var isTesting = false
    @FocusState private var urlFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("\u{670d}\u{52a1}\u{5668}\u{5730}\u{5740}") {
                    TextField("http://192.168.1.100:3456", text: $draftURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .focused($urlFocused)

                    Button("\u{4fdd}\u{5b58}\u{5e76}\u{4f7f}\u{7528}") {
                        urlFocused = false
                        UIApplication.dismissKeyboard()
                        settings.baseURLString = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    Button(isTesting ? "\u{6d4b}\u{8bd5}\u{4e2d}..." : "\u{6d4b}\u{8bd5}\u{8fde}\u{63a5}") {
                        urlFocused = false
                        UIApplication.dismissKeyboard()
                        testConnection()
                    }
                    .disabled(isTesting)

                    Text(testStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("\u{5feb}\u{6377}\u{5165}\u{53e3}") {
                    NavigationLink {
                        AgentWebContainer(route: .dashboard)
                    } label: {
                        Label("\u{4eea}\u{8868}\u{76d8}", systemImage: AgentRoute.dashboard.systemImage)
                    }

                    NavigationLink {
                        AgentWebContainer(route: .upgrade)
                    } label: {
                        Label("\u{7cfb}\u{7edf}\u{5347}\u{7ea7}", systemImage: AgentRoute.upgrade.systemImage)
                    }
                }
            }
            .navigationTitle("\u{6211}\u{7684}")
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap()
            .onDisappear {
                urlFocused = false
                UIApplication.dismissKeyboard()
            }
            .onAppear {
                draftURL = settings.baseURLString
            }
        }
    }

    private func testConnection() {
        let target = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: target), url.scheme != nil else {
            testStatus = "\u{5730}\u{5740}\u{683c}\u{5f0f}\u{4e0d}\u{6b63}\u{786e}"
            return
        }

        isTesting = true
        testStatus = "\u{6d4b}\u{8bd5}\u{4e2d}..."

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                isTesting = false
                if let error {
                    testStatus = "\u{8fde}\u{63a5}\u{5931}\u{8d25}\u{ff1a}\(error.localizedDescription)"
                } else if let http = response as? HTTPURLResponse {
                    testStatus = "\u{8fde}\u{63a5}\u{6210}\u{529f}\u{ff1a}HTTP \(http.statusCode)"
                } else {
                    testStatus = "\u{8fde}\u{63a5}\u{6210}\u{529f}"
                }
            }
        }.resume()
    }
}
