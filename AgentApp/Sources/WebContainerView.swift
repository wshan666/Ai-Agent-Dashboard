import SwiftUI
import WebKit
import AVFoundation

struct AgentWebContainer: View {
    @EnvironmentObject private var settings: ServerSettings
    let route: AgentRoute

    @State private var isLoading = true
    @State private var reloadToken = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.title)
                        .font(.headline)
                    Text(settings.normalizedBaseURL.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    isLoading = true
                    reloadToken = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            ZStack {
                RouteWebView(
                    baseURL: settings.normalizedBaseURL,
                    route: route,
                    reloadToken: reloadToken,
                    isLoading: $isLoading
                )

                if isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Opening \(route.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                }
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RouteWebView: UIViewRepresentable {
    let baseURL: URL
    let route: AgentRoute
    let reloadToken: UUID
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, reloadToken: reloadToken)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("Audio session setup failed: \(error.localizedDescription)")
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = UIColor.systemBackground
        webView.isOpaque = false
        load(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.reloadToken != reloadToken {
            context.coordinator.reloadToken = reloadToken
            isLoading = true
            load(in: webView, force: true)
        } else {
            load(in: webView)
        }
    }

    private func load(in webView: WKWebView, force: Bool = false) {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.fragment = route.rawValue
        guard let url = components?.url else { return }

        if !force, webView.url?.absoluteString == url.absoluteString {
            return
        }

        isLoading = true
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding private var isLoading: Bool
        var reloadToken: UUID

        init(isLoading: Binding<Bool>, reloadToken: UUID) {
            _isLoading = isLoading
            self.reloadToken = reloadToken
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading = false
            let html = """
            <html><body style="font-family:-apple-system;padding:24px;background:#0f1117;color:#f3f4f6">
            <h3>Page Load Failed</h3>
            <p>\(error.localizedDescription)</p>
            <p>Please verify the dashboard URL and LAN connectivity.</p>
            </body></html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}
