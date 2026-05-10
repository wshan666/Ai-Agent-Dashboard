import SwiftUI
import WebKit

struct ContentView: View {
    @State private var serverURL: String = UserDefaults.standard.string(forKey: "agentServerURL") ?? "http://192.168.50.32:3456"
    @State private var isLoading = true
    @State private var needsReload = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("http://192.168.50.32:3456", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .font(.caption)

                Button {
                    UserDefaults.standard.set(serverURL, forKey: "agentServerURL")
                    needsReload = true
                    isLoading = true
                    NotificationCenter.default.post(name: .reloadWebView, object: serverURL)
                } label: {
                    Text("连接")
                        .font(.caption)
                        .bold()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(8)
            .background(Color(.systemGray6))

            ZStack {
                WebViewWrapper(serverURL: serverURL, isLoading: $isLoading, needsReload: $needsReload)
                    .edgesIgnoringSafeArea(.bottom)

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("连接中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                }
            }
        }
    }
}

struct WebViewWrapper: UIViewRepresentable {
    let serverURL: String
    @Binding var isLoading: Bool
    @Binding var needsReload: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor.systemBackground

        loadContent(in: webView)

        NotificationCenter.default.addObserver(
            forName: .reloadWebView,
            object: nil,
            queue: .main
        ) { notif in
            if let url = notif.object as? String {
                context.coordinator.parent.serverURL = url
            }
            loadContent(in: webView)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if needsReload {
            loadContent(in: webView)
            DispatchQueue.main.async {
                needsReload = false
            }
        }
    }

    private func loadContent(in webView: WKWebView) {
        guard let htmlPath = Bundle.main.path(forResource: "www/index", ofType: "html"),
              let htmlContent = try? String(contentsOfFile: htmlPath, encoding: .utf8) else {
            webView.loadHTMLString("<h2>Dashboard load failed</h2>", baseURL: nil)
            return
        }
        let baseURL = URL(string: serverURL) ?? URL(string: "http://192.168.50.32:3456")!
        webView.loadHTMLString(htmlContent, baseURL: baseURL)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewWrapper

        init(_ parent: WebViewWrapper) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                parent.isLoading = false
            }
        }
    }
}

extension Notification.Name {
    static let reloadWebView = Notification.Name("reloadWebView")
}

#Preview {
    ContentView()
}
