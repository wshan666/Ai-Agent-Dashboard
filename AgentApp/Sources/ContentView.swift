import SwiftUI
import WebKit

struct ContentView: View {
    @State private var serverURL: String = UserDefaults.standard.string(forKey: "agentServerURL") ?? "http://192.168.50.32:3456"
    @State private var isLoading = true
    @State private var reloadTrigger = 0

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
                    isLoading = true
                    reloadTrigger += 1
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
                WebViewWrapper(serverURL: serverURL, reloadTrigger: reloadTrigger, isLoading: $isLoading)
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
    let reloadTrigger: Int
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator {
            DispatchQueue.main.async { self.isLoading = false }
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor.systemBackground
        loadContent(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadContent(in: webView)
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
        let onLoadFinish: () -> Void

        init(onLoadFinish: @escaping () -> Void) {
            self.onLoadFinish = onLoadFinish
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadFinish()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadFinish()
        }
    }
}

#Preview {
    ContentView()
}
