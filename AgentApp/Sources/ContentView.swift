import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: ServerSettings
    @EnvironmentObject private var store: AppStore
    @State private var selectedTab: RootTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                NativeDashboardView()
            }
            .tabItem {
                Label("首页", systemImage: "house")
            }
            .tag(RootTab.home)

            NavigationStack {
                NativeChatView()
            }
            .tabItem {
                Label("协作", systemImage: "person.3.fill")
            }
            .tag(RootTab.chat)

            NavigationStack {
                NativeWorkflowView()
            }
            .tabItem {
                Label("工作流", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .tag(RootTab.workflow)

            NavigationStack {
                AgentWebContainer(route: .bigscreen)
            }
            .tabItem {
                Label("大屏", systemImage: "display.2")
            }
            .tag(RootTab.bigscreen)

            ProfileView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
                .tag(RootTab.profile)
        }
        .tint(.blue)
        .onChange(of: selectedTab) { _ in
            UIApplication.dismissKeyboard()
        }
        .task {
            if store.agents.isEmpty {
                await store.refreshDashboard()
            }
        }
        .alert("请求错误", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("知道了", role: .cancel) {
                store.lastError = nil
            }
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

private enum RootTab {
    case home
    case chat
    case workflow
    case bigscreen
    case profile
}

private struct ProfileView: View {
    @EnvironmentObject private var settings: ServerSettings
    @State private var draftURL: String = ""
    @State private var testStatus: String = "尚未测试"
    @State private var isTesting = false
    @FocusState private var urlFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器地址") {
                    TextField("http://192.168.50.32:3456", text: $draftURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .focused($urlFocused)

                    Button("保存并使用") {
                        urlFocused = false
                        UIApplication.dismissKeyboard()
                        settings.baseURLString = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    Button(isTesting ? "测试中..." : "测试连接") {
                        urlFocused = false
                        UIApplication.dismissKeyboard()
                        testConnection()
                    }
                    .disabled(isTesting)

                    Text(testStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("快捷入口") {
                    NavigationLink {
                        AgentWebContainer(route: .dashboard)
                    } label: {
                        Label("仪表盘", systemImage: AgentRoute.dashboard.systemImage)
                    }

                    NavigationLink {
                        AgentWebContainer(route: .upgrade)
                    } label: {
                        Label("系统升级", systemImage: AgentRoute.upgrade.systemImage)
                    }
                }
            }
            .navigationTitle("我的")
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
            testStatus = "地址格式不正确"
            return
        }

        isTesting = true
        testStatus = "测试中..."

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                isTesting = false
                if let error {
                    testStatus = "连接失败：\(error.localizedDescription)"
                } else if let http = response as? HTTPURLResponse {
                    testStatus = "连接成功：HTTP \(http.statusCode)"
                } else {
                    testStatus = "连接成功"
                }
            }
        }.resume()
    }
}
